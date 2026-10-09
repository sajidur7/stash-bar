import Foundation
import SwiftData

@Model
public final class StashItem {
    @Attribute(.unique) public var id: UUID
    public var url: String
    public var originalUrl: String
    public var title: String
    public var host: String
    public var itemDescription: String?
    public var faviconUrl: String?
    public var faviconData: Data?
    public var ogImageUrl: String?
    public var ogImageData: Data?
    public var createdAt: Date
    public var updatedAt: Date
    public var openedAt: Date?
    public var archivedAt: Date?
    public var isPinned: Bool
    public var isArchived: Bool
    public var tags: [String]
    public var notes: String
    /// True when this item has local changes that haven't reached the account yet.
    public var needsSync: Bool = true

    public init(
        id: UUID = UUID(),
        url: String,
        originalUrl: String? = nil,
        title: String? = nil,
        host: String? = nil,
        itemDescription: String? = nil,
        faviconUrl: String? = nil,
        ogImageUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        openedAt: Date? = nil,
        archivedAt: Date? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        tags: [String] = [],
        notes: String = "",
        needsSync: Bool = true
    ) {
        self.id = id
        self.url = url
        self.originalUrl = originalUrl ?? url

        let resolvedHost: String
        if let host = host, !host.isEmpty {
            resolvedHost = host
        } else if let parsed = URLSanitizer.cleanHost(from: url) {
            resolvedHost = parsed
        } else {
            resolvedHost = "link"
        }
        self.host = resolvedHost

        if let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.title = title
        } else {
            self.title = resolvedHost
        }

        self.itemDescription = itemDescription
        self.faviconUrl = faviconUrl
        self.ogImageUrl = ogImageUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.openedAt = openedAt
        self.archivedAt = archivedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.tags = tags
        self.notes = notes
        self.needsSync = needsSync
    }

    public var displayHost: String {
        host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var timeAgo: String { RelativeTime.short(createdAt) }

    /// Tracking parameters that were stripped from the original link.
    public var removedTrackers: [String] {
        URLSanitizer.removedParameters(from: originalUrl)
    }

    /// Records a user edit so it gets pushed on the next sync.
    public func touch() {
        updatedAt = Date()
        needsSync = true
    }
}

public enum RelativeTime {
    /// Compact labels used across the design: "38m", "2h", "Yday", "Tue", "3 Oct".
    public static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "\(Int(seconds / 3600))h" }
        if cal.isDateInYesterday(date) { return "Yday" }
        if seconds < 6 * 86400 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    /// Longer labels: "2m ago", "3 days ago", "just now".
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        let days = Int(seconds / 86400)
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 30 { return "\(days / 7)w ago" }
        return "\(days / 30)mo ago"
    }
}
