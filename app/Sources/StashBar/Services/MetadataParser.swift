import Foundation
import SwiftData

public struct MetadataResult: Sendable {
    public var title: String?
    public var itemDescription: String?
    public var faviconUrl: String?
    public var faviconData: Data?
    public var ogImageUrl: String?
    public var ogImageData: Data?
}

public actor MetadataParser {
    private static let maxHeadBytes = 50 * 1024 // 50 KB cap for <head> scraping
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Scrapes metadata from the first 50KB of a web page and downloads favicon / OG image.
    public static func fetchMetadata(for urlString: String) async -> MetadataResult {
        guard let url = URL(string: urlString) else {
            return MetadataResult()
        }

        var result = MetadataResult()

        // 1. Partial stream fetch of HTML head
        do {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 8.0

            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            var collectedData = Data()
            collectedData.reserveCapacity(maxHeadBytes)

            for try await byte in bytes {
                collectedData.append(byte)
                if collectedData.count >= maxHeadBytes {
                    break
                }
            }

            let effectiveURL = response.url ?? url
            if let html = String(data: collectedData, encoding: .utf8) ?? String(data: collectedData, encoding: .ascii) {
                parseHead(html: html, baseURL: effectiveURL, result: &result)
            }
        } catch {
            // Ignore network stream error; will attempt fallback icon
        }

        // 2. Favicon resolution fallback if not found in HTML
        if result.faviconUrl == nil, let host = url.host {
            result.faviconUrl = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        }

        // 3. Download and cache favicon data (lightweight)
        if let iconUrlStr = result.faviconUrl, let iconUrl = URL(string: iconUrlStr) {
            do {
                var iconReq = URLRequest(url: iconUrl)
                iconReq.timeoutInterval = 5.0
                let (data, _) = try await URLSession.shared.data(for: iconReq)
                if !data.isEmpty {
                    result.faviconData = data
                }
            } catch {
                // Favicon download failed; fallback to SF Symbol
            }
        }

        // 4. Download and cache OG image data (capped at 1MB)
        if let ogUrlStr = result.ogImageUrl, let ogUrl = URL(string: ogUrlStr) {
            do {
                var ogReq = URLRequest(url: ogUrl)
                ogReq.timeoutInterval = 6.0
                let (data, _) = try await URLSession.shared.data(for: ogReq)
                if !data.isEmpty && data.count < 1_048_576 { // 1 MB cap
                    result.ogImageData = data
                }
            } catch {
                // OG image failed
            }
        }

        return result
    }

    /// Resolves metadata and updates the SwiftData StashItem on the MainActor
    @MainActor
    public static func resolveMetadata(for itemId: UUID, urlString: String, context: ModelContext) async {
        let metadata = await Task.detached(priority: .userInitiated) {
            await fetchMetadata(for: urlString)
        }.value

        let descriptor = FetchDescriptor<StashItem>(
            predicate: #Predicate { $0.id == itemId }
        )
        guard let item = (try? context.fetch(descriptor))?.first else { return }

        // Only replace placeholder titles (the host) so we never overwrite a title the user set.
        if let title = metadata.title, !title.isEmpty, item.title == item.host || item.title == item.displayHost || item.title.isEmpty {
            item.title = title
        }
        if let desc = metadata.itemDescription, !desc.isEmpty {
            item.itemDescription = desc
        }
        if let favUrl = metadata.faviconUrl {
            item.faviconUrl = favUrl
        }
        if let favData = metadata.faviconData {
            item.faviconData = favData
        }
        if let ogUrl = metadata.ogImageUrl {
            item.ogImageUrl = ogUrl
        }
        if let ogData = metadata.ogImageData {
            item.ogImageData = ogData
        }
        item.touch()

        try? context.save()
        SyncService.shared.scheduleSync()
    }

    /// Downloads only the favicon and preview image for a link that arrived through sync.
    /// Doesn't mark the link as edited, so it won't be pushed back.
    @MainActor
    public static func fillImages(for itemId: UUID, urlString: String, context: ModelContext) async {
        let metadata = await Task.detached(priority: .utility) {
            await fetchMetadata(for: urlString)
        }.value
        let descriptor = FetchDescriptor<StashItem>(predicate: #Predicate { $0.id == itemId })
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        if let favData = metadata.faviconData { item.faviconData = favData }
        if let ogData = metadata.ogImageData { item.ogImageData = ogData }
        try? context.save()
    }

    // MARK: - HTML Parsing Helpers

    public static func parseHead(html: String, baseURL: URL, result: inout MetadataResult) {
        // Extract <title>
        if let titleMatch = extractFirstMatch(pattern: "<title[^>]*>(.*?)</title>", in: html) {
            result.title = decodeHTMLEntities(titleMatch.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Extract og:title or twitter:title
        if let ogTitle = extractMetaContent(forProperty: "og:title", in: html) ?? extractMetaContent(forProperty: "twitter:title", in: html) {
            if result.title == nil || result.title?.isEmpty == true {
                result.title = decodeHTMLEntities(ogTitle)
            }
        }

        // Extract og:description or name="description"
        if let desc = extractMetaContent(forProperty: "og:description", in: html) 
            ?? extractMetaContent(forName: "description", in: html)
            ?? extractMetaContent(forProperty: "twitter:description", in: html) {
            result.itemDescription = decodeHTMLEntities(desc)
        }

        // Extract og:image
        if let ogImage = extractMetaContent(forProperty: "og:image", in: html) ?? extractMetaContent(forProperty: "twitter:image", in: html) {
            result.ogImageUrl = resolveRelativeUrl(ogImage, relativeTo: baseURL)
        }

        // Extract favicon
        if let faviconHref = extractFaviconHref(in: html) {
            result.faviconUrl = resolveRelativeUrl(faviconHref, relativeTo: baseURL)
        }
    }

    public static func extractMetaContent(forProperty property: String, in html: String) -> String? {
        let pattern1 = "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"
        let pattern2 = "<meta[^>]*content=[\"'](.*?)[\"'][^>]*property=[\"']\(property)[\"'][^>]*>"
        return extractFirstMatch(pattern: pattern1, in: html) ?? extractFirstMatch(pattern: pattern2, in: html)
    }

    public static func extractMetaContent(forName name: String, in html: String) -> String? {
        let pattern1 = "<meta[^>]*name=[\"']\(name)[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"
        let pattern2 = "<meta[^>]*content=[\"'](.*?)[\"'][^>]*name=[\"']\(name)[\"'][^>]*>"
        return extractFirstMatch(pattern: pattern1, in: html) ?? extractFirstMatch(pattern: pattern2, in: html)
    }

    public static func extractFaviconHref(in html: String) -> String? {
        let pattern1 = "<link[^>]*rel=[\"'][^\"']*(?:icon|shortcut icon|apple-touch-icon)[^\"']*[\"'][^>]*href=[\"'](.*?)[\"'][^>]*>"
        let pattern2 = "<link[^>]*href=[\"'](.*?)[\"'][^>]*rel=[\"'][^\"']*(?:icon|shortcut icon|apple-touch-icon)[^\"']*[\"'][^>]*>"
        return extractFirstMatch(pattern: pattern1, in: html) ?? extractFirstMatch(pattern: pattern2, in: html)
    }

    public static func extractFirstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        let range = match.range(at: 1)
        if range.location != NSNotFound {
            return nsString.substring(with: range)
        }
        return nil
    }

    public static func resolveRelativeUrl(_ path: String, relativeTo base: URL) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if let resolved = URL(string: trimmed, relativeTo: base) {
            return resolved.absoluteString
        }
        return trimmed
    }

    public static func decodeHTMLEntities(_ text: String) -> String {
        var str = text
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&#8217;": "’",
            "&#8216;": "‘",
            "&#8220;": "“",
            "&#8221;": "”",
            "&#8211;": "–",
            "&#8212;": "—"
        ]
        for (entity, replacement) in entities {
            str = str.replacingOccurrences(of: entity, with: replacement)
        }
        return str
    }
}
