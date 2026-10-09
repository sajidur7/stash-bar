import AppKit
import UniformTypeIdentifiers
import ServiceManagement

/// Import from browser bookmark files and export to JSON, Markdown or bookmarks HTML.
public enum BookmarkIO {
    public enum Format: String, CaseIterable {
        case json = "JSON", markdown = "Markdown", html = "Bookmarks HTML"
        var ext: String { self == .json ? "json" : self == .markdown ? "md" : "html" }
    }

    // MARK: Import

    /// Parses a Netscape bookmarks file (what Safari, Chrome, Arc and Firefox export) or a Stashbar JSON export.
    public static func parse(_ text: String) -> [(url: String, title: String?)] {
        if let data = text.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { row -> (url: String, title: String?)? in
                guard let url = row["url"] as? String else { return nil }
                return (url, row["title"] as? String)
            }
        }
        guard let regex = try? NSRegularExpression(
            pattern: "<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m -> (url: String, title: String?)? in
            let url = ns.substring(with: m.range(at: 1))
            guard url.lowercased().hasPrefix("http") else { return nil }
            let title = MetadataParser.decodeHTMLEntities(
                ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return (url, title.isEmpty ? nil : title)
        }
    }

    @MainActor
    public static func runImport() async -> Int? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html, .json, .plainText]
        panel.message = "Choose a bookmarks file exported from Safari, Chrome, Arc or Firefox"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var added = 0
        for entry in parse(text) {
            let before = LinkStore.shared.item(url: URLSanitizer.sanitizeWithPreferences(entry.url) ?? "")
            if before == nil, await LinkStore.shared.stash(rawURL: entry.url, title: entry.title) != nil { added += 1 }
        }
        return added
    }

    // MARK: Export

    @MainActor
    public static func export(_ format: Format, items: [StashItem]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Stashbar links.\(format.ext)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? render(format, items: items).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func render(_ format: Format, items: [StashItem]) -> String {
        switch format {
        case .json:
            let rows: [[String: Any]] = items.map { item in
                ["url": item.url, "title": item.title, "host": item.displayHost, "tags": item.tags, "notes": item.notes,
                 "pinned": item.isPinned, "archived": item.isArchived, "created_at": ISODate.string(item.createdAt)]
            }
            let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        case .markdown:
            var out = "# Stashbar links\n\n"
            for item in items {
                let tags = item.tags.isEmpty ? "" : " " + item.tags.map { "#\($0)" }.joined(separator: " ")
                out += "- [\(item.title.replacingOccurrences(of: "]", with: "\\]"))](\(item.url))\(tags)\n"
                if !item.notes.isEmpty { out += "  > \(item.notes.replacingOccurrences(of: "\n", with: " "))\n" }
            }
            return out
        case .html:
            var out = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
            <TITLE>Bookmarks</TITLE>
            <H1>Stashbar</H1>
            <DL><p>

            """
            for item in items {
                let t = item.title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                out += "    <DT><A HREF=\"\(item.url)\" ADD_DATE=\"\(Int(item.createdAt.timeIntervalSince1970))\" TAGS=\"\(item.tags.joined(separator: ","))\">\(t)</A>\n"
            }
            return out + "</DL><p>\n"
        }
    }
}

/// "Check for updates" compares this build with the latest GitHub release.
public enum UpdateChecker {
    public struct Result { public let latest: String; public let isNewer: Bool; public let url: URL }

    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    public static func check() async -> Result? {
        guard let api = URL(string: "https://api.github.com/repos/\(SupabaseConfig.githubRepo)/releases/latest"),
              let data = try? await URLSession.shared.data(from: api).0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return Result(latest: latest, isNewer: compare(latest, currentVersion) == .orderedDescending, url: page)
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

/// Launch at login through SMAppService (macOS 13+). Works once the app is in /Applications.
public enum LoginItem {
    public static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Stashbar: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
