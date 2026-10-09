import Foundation
import SwiftData

/// Two-way sync between SwiftData and the `links` table.
/// Push: rows with needsSync, plus tombstones. Pull: rows changed on the server since the last cursor.
/// Conflicts resolve last-write-wins on `updated_at`.
@MainActor
public final class SyncService: ObservableObject {
    public static let shared = SyncService()

    public enum Status: Equatable {
        case idle, syncing, offline, error(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastSyncedAt: Date?
    @Published public private(set) var devices: [Device] = []
    /// Links received during the current pull (drives the "Welcome back" restore screen).
    @Published public private(set) var restoredCount = 0
    @Published public private(set) var restoredTitles: [(title: String, host: String)] = []

    public struct Device: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let lastSeen: Date
        public var isThisMac: Bool { id == Preferences.deviceId.uuidString.lowercased() }
    }

    private var timer: Timer?
    private var pending: Task<Void, Never>?
    private var running = false
    private var cursorKey: String { "syncCursor.\(AuthService.shared.session?.userId ?? "none")" }

    private init() {
        lastSyncedAt = UserDefaults.standard.object(forKey: "lastSyncedAt") as? Date
    }

    public func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                if Preferences.autoSync { await SyncService.shared.syncNow() }
            }
        }
        Task { await syncNow() }
    }

    /// Debounced sync after a local change.
    public func scheduleSync() {
        guard AuthService.shared.isSignedIn, Preferences.autoSync else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    public func resetCursor() {
        UserDefaults.standard.removeObject(forKey: cursorKey)
        lastSyncedAt = nil
        UserDefaults.standard.removeObject(forKey: "lastSyncedAt")
        devices = []
        status = .idle
    }

    public func syncNow() async {
        guard AuthService.shared.isSignedIn, !running else { return }
        running = true
        status = .syncing
        defer { running = false }
        do {
            let token = try await AuthService.shared.validAccessToken()
            try await registerDevice(token: token)
            try await pushDeletes(token: token)
            try await pushChanges(token: token)
            try await pull(token: token)
            try await fetchDevices(token: token)
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: "lastSyncedAt")
            status = .idle
        } catch SupabaseError.offline {
            status = .offline
        } catch SupabaseError.http(let code, _) where code == 401 {
            status = .error("Your session expired. Sign in again.")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Push

    private func pushDeletes(token: String) async throws {
        let ids = LinkStore.shared.pendingDeletes
        guard !ids.isEmpty else { return }
        let list = "(" + ids.map { $0.uuidString.lowercased() }.joined(separator: ",") + ")"
        _ = try await SupabaseClient.request(
            "/rest/v1/links", method: "PATCH", query: [("id", "in.\(list)")],
            json: ["is_deleted": true, "updated_at": ISODate.string(Date())],
            headers: ["Prefer": "return=minimal"], token: token)
        LinkStore.shared.clearTombstones(ids)
    }

    private func pushChanges(token: String) async throws {
        let dirty = LinkStore.shared.all().filter(\.needsSync)
        guard !dirty.isEmpty else { return }
        for batch in stride(from: 0, to: dirty.count, by: 200).map({ Array(dirty[$0..<min($0 + 200, dirty.count)]) }) {
            let snapshot = batch.map { ($0, $0.updatedAt) }
            let rows = batch.map(Self.row(from:))
            _ = try await SupabaseClient.request(
                "/rest/v1/links", method: "POST", query: [("on_conflict", "id")], json: rows,
                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"], token: token)
            for (item, stamp) in snapshot where item.updatedAt == stamp {
                item.needsSync = false
            }
        }
        try? LinkStore.shared.context.save()
    }

    static func row(from item: StashItem) -> [String: Any] {
        [
            "id": item.id.uuidString.lowercased(),
            "url": item.url,
            "original_url": item.originalUrl,
            "title": item.title,
            "host": item.host,
            "description": json(item.itemDescription),
            "favicon_url": json(item.faviconUrl),
            "og_image_url": json(item.ogImageUrl),
            "tags": item.tags,
            "notes": item.notes,
            "is_pinned": item.isPinned,
            "is_archived": item.isArchived,
            "is_deleted": false,
            "opened_at": json(item.openedAt.map { ISODate.string($0) }),
            "archived_at": json(item.archivedAt.map { ISODate.string($0) }),
            "created_at": ISODate.string(item.createdAt),
            "updated_at": ISODate.string(item.updatedAt)
        ]
    }

    private static func json(_ value: String?) -> Any {
        if let value { return value }
        return NSNull()
    }

    // MARK: - Pull

    private func pull(token: String) async throws {
        var cursor = UserDefaults.standard.string(forKey: cursorKey) ?? "1970-01-01T00:00:00Z"
        let firstPull = UserDefaults.standard.string(forKey: cursorKey) == nil
        if firstPull {
            restoredCount = 0
            restoredTitles = []
        }
        while true {
            let (data, _) = try await SupabaseClient.request(
                "/rest/v1/links", query: [
                    ("select", "*"),
                    ("server_updated_at", "gt.\(cursor)"),
                    ("order", "server_updated_at.asc"),
                    ("limit", "500")
                ], token: token)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw SupabaseError.decoding
            }
            for row in rows {
                apply(row: row, counting: firstPull)
                if let c = row["server_updated_at"] as? String { cursor = c }
            }
            try? LinkStore.shared.context.save()
            UserDefaults.standard.set(cursor, forKey: cursorKey)
            if rows.count < 500 { break }
        }
        LinkStore.shared.objectWillChange.send()
        StatusItemController.shared?.refreshIcon()
    }

    /// Applies one server row to the local store. Internal for tests.
    func apply(row: [String: Any], counting: Bool = false) {
        guard let idString = row["id"] as? String, let id = UUID(uuidString: idString) else { return }
        let store = LinkStore.shared
        let local = store.item(id: id)
        let remoteUpdated = ISODate.parse(row["updated_at"]) ?? .distantPast

        if (row["is_deleted"] as? Bool) == true {
            if let local { store.context.delete(local) }
            return
        }
        if let local, local.needsSync, local.updatedAt > remoteUpdated { return } // local edit wins; pushed next time
        if let local, !local.needsSync, local.updatedAt >= remoteUpdated, local.url == (row["url"] as? String) { return }

        guard let url = row["url"] as? String else { return }
        let item: StashItem
        if let local {
            item = local
        } else if let duplicate = store.item(url: url) {
            // The same link was stashed on two Macs before syncing; keep the server's copy.
            store.context.delete(duplicate)
            item = StashItem(id: id, url: url)
            store.context.insert(item)
        } else {
            item = StashItem(id: id, url: url)
            store.context.insert(item)
            if counting {
                restoredCount += 1
                if restoredTitles.count < 4 {
                    restoredTitles.append(((row["title"] as? String) ?? url, (row["host"] as? String) ?? ""))
                }
            }
        }
        item.url = url
        item.originalUrl = (row["original_url"] as? String) ?? url
        item.title = (row["title"] as? String) ?? item.title
        item.host = (row["host"] as? String) ?? item.host
        item.itemDescription = row["description"] as? String
        item.faviconUrl = row["favicon_url"] as? String
        if let og = row["og_image_url"] as? String, og != item.ogImageUrl {
            item.ogImageUrl = og
            item.ogImageData = nil
        }
        item.tags = (row["tags"] as? [String]) ?? []
        item.notes = (row["notes"] as? String) ?? ""
        item.isPinned = (row["is_pinned"] as? Bool) ?? false
        item.isArchived = (row["is_archived"] as? Bool) ?? false
        item.openedAt = ISODate.parse(row["opened_at"])
        item.archivedAt = ISODate.parse(row["archived_at"])
        item.createdAt = ISODate.parse(row["created_at"]) ?? item.createdAt
        item.updatedAt = remoteUpdated
        item.needsSync = false

        if item.faviconData == nil {
            let id = item.id, url = item.url, ctx = store.context
            Task { await MetadataParser.fillImages(for: id, urlString: url, context: ctx) }
        }
    }

    // MARK: - Devices

    private func registerDevice(token: String) async throws {
        let name = Host.current().localizedName ?? "This Mac"
        _ = try await SupabaseClient.request(
            "/rest/v1/devices", method: "POST", query: [("on_conflict", "id")],
            json: [["id": Preferences.deviceId.uuidString.lowercased(), "name": name, "last_seen_at": ISODate.string(Date())]],
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"], token: token)
    }

    private func fetchDevices(token: String) async throws {
        let (data, _) = try await SupabaseClient.request(
            "/rest/v1/devices", query: [("select", "id,name,last_seen_at"), ("order", "last_seen_at.desc")], token: token)
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        devices = rows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            return Device(id: id.lowercased(), name: name, lastSeen: ISODate.parse(row["last_seen_at"]) ?? Date())
        }
    }
}
