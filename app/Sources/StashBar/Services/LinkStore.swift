import Foundation
import SwiftData
import AppKit

/// Owns the SwiftData container and every mutation of links, so sync bookkeeping
/// (needsSync, tombstones) is handled in one place.
@MainActor
public final class LinkStore: ObservableObject {
    public static let shared = LinkStore()

    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    /// IDs deleted locally that still need to be deleted on the server.
    private let tombstoneKey = "pendingDeletes"

    private init() {
        let schema = Schema([StashItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A broken store shouldn't brick the app; fall back to memory and say so in the console.
            NSLog("Stashbar: could not open the link store (\(error)); using a temporary store.")
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
    }

    // MARK: - Queries

    public func all(includeArchived: Bool = true) -> [StashItem] {
        let descriptor = FetchDescriptor<StashItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let items = (try? context.fetch(descriptor)) ?? []
        return includeArchived ? items : items.filter { !$0.isArchived }
    }

    public func item(id: UUID) -> StashItem? {
        let descriptor = FetchDescriptor<StashItem>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    public func item(url: String) -> StashItem? {
        let descriptor = FetchDescriptor<StashItem>(predicate: #Predicate { $0.url == url })
        return (try? context.fetch(descriptor))?.first
    }

    public var count: Int { (try? context.fetchCount(FetchDescriptor<StashItem>())) ?? 0 }

    public var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in all(includeArchived: false) {
            for tag in item.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: - Mutations

    /// Stashes a URL. If it's already stashed, the existing link is brought back to the top instead.
    @discardableResult
    public func stash(rawURL: String, title: String? = nil, tags: [String] = [], notes: String = "") async -> StashItem? {
        var raw = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if Preferences.expandShortLinks, let expanded = await ShortLinkExpander.expand(raw) {
            raw = expanded
        }
        guard let clean = URLSanitizer.sanitizeWithPreferences(raw) else { return nil }

        if let existing = item(url: clean) {
            existing.isArchived = false
            existing.archivedAt = nil
            existing.createdAt = Date()
            if !tags.isEmpty { existing.tags = Array(Set(existing.tags + tags)).sorted() }
            existing.touch()
            save()
            feedback()
            return existing
        }

        let item = StashItem(url: clean, originalUrl: raw, title: title, tags: tags, notes: notes)
        context.insert(item)
        save()
        feedback()

        let id = item.id
        let context = self.context
        Task { await MetadataParser.resolveMetadata(for: id, urlString: clean, context: context) }
        return item
    }

    public func setPinned(_ item: StashItem, _ pinned: Bool) {
        item.isPinned = pinned
        item.touch()
        save()
    }

    public func archive(_ item: StashItem) {
        item.isArchived = true
        item.archivedAt = Date()
        item.touch()
        save()
    }

    public func restore(_ item: StashItem) {
        item.isArchived = false
        item.archivedAt = nil
        item.touch()
        save()
    }

    public func delete(_ item: StashItem) {
        addTombstone(item.id)
        context.delete(item)
        save()
    }

    public func markOpened(_ item: StashItem) {
        item.openedAt = Date()
        item.touch()
        save()
    }

    public func update(_ item: StashItem, _ change: (StashItem) -> Void) {
        change(item)
        item.touch()
        save()
    }

    public func open(_ item: StashItem) {
        if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
        markOpened(item)
    }

    public func copy(_ item: StashItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Preferences.copyCleanURL ? item.url : item.originalUrl, forType: .string)
        ClipboardWatcher.shared.ignoreCurrentPasteboard()
    }

    /// Removes every link from this Mac (used by sign-out "Remove from this Mac" and account deletion).
    public func wipeLocal() {
        for item in all() { context.delete(item) }
        UserDefaults.standard.removeObject(forKey: tombstoneKey)
        save()
    }

    /// Marks every link as needing upload — used when a guest signs in.
    public func markAllForSync() {
        for item in all() { item.needsSync = true }
        save()
    }

    public func clearPreviewCache() -> Int {
        var bytes = 0
        for item in all() {
            bytes += (item.ogImageData?.count ?? 0) + (item.faviconData?.count ?? 0)
            item.ogImageData = nil
            item.faviconData = nil
        }
        save()
        return bytes
    }

    public var previewCacheBytes: Int {
        all().reduce(0) { $0 + ($1.ogImageData?.count ?? 0) + ($1.faviconData?.count ?? 0) }
    }

    public func save() {
        try? context.save()
        objectWillChange.send()
        StatusItemController.shared?.refreshIcon()
        SyncService.shared.scheduleSync()
    }

    // MARK: - Tombstones

    public var pendingDeletes: [UUID] {
        (UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    private func addTombstone(_ id: UUID) {
        guard AuthService.shared.isSignedIn else { return }
        var ids = UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? []
        ids.append(id.uuidString)
        UserDefaults.standard.set(ids, forKey: tombstoneKey)
    }

    public func clearTombstones(_ ids: [UUID]) {
        let done = Set(ids.map(\.uuidString))
        let remaining = (UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? []).filter { !done.contains($0) }
        UserDefaults.standard.set(remaining, forKey: tombstoneKey)
    }

    // MARK: - Feedback

    private func feedback() {
        if Preferences.playSound { NSSound(named: "Tink")?.play() }
    }
}

/// Follows redirects for well-known link shorteners so the real address is saved.
public enum ShortLinkExpander {
    static let hosts: Set<String> = [
        "t.co", "bit.ly", "tinyurl.com", "ow.ly", "buff.ly", "lnkd.in", "goo.gl", "rebrand.ly",
        "is.gd", "t.ly", "shorturl.at", "cutt.ly", "rb.gy", "tiny.cc", "trib.al", "dlvr.it", "fb.me", "amzn.to"
    ]

    public static func expand(_ raw: String) async -> String? {
        guard let clean = URLSanitizer.sanitize(raw, stripping: []),
              let url = URL(string: clean), let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        guard let response = try? await URLSession.shared.data(for: request).1,
              let final = response.url, final.host?.lowercased() != host else { return nil }
        return final.absoluteString
    }
}
