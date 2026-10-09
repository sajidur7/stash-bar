import Foundation

public struct URLSanitizer {
    /// Common marketing, analytics and social tracking query parameter keys (lowercased).
    public static let defaultTrackingParameters: [String] = [
        // Google / Universal UTM
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_referrer", "utm_reader", "utm_viz_id", "utm_pubreferrer",
        // Meta / Facebook / Instagram
        "fbclid", "igshid", "igsh", "share_id", "mid",
        // Google Ads & Analytics
        "gclid", "gclsrc", "dclid", "wbraid", "gbraid", "gad_source", "gadid",
        // Microsoft / Bing
        "msclkid",
        // Twitter / X
        "twclid",
        // Email & CRM (Mailchimp, HubSpot, Marketo)
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok",
        // Social share trackers
        "si", "ref", "ref_src", "ref_url", "source", "feature",
        // Other ad & affiliate networks
        "wickedid", "yclid", "trk", "spm", "zanpid", "_ga", "_gl", "s_cid"
    ]

    /// The parameter list currently in effect (user-editable in Settings → Link cleaning).
    public static var activeParameters: Set<String> {
        Set(Preferences.trackerParameters.map { $0.lowercased() })
    }

    /// Kept for source compatibility with the original app and its tests.
    public static var trackingQueryParameters: Set<String> { Set(defaultTrackingParameters) }

    /// Sanitizes a URL string: normalises scheme/host and removes tracking parameters.
    /// Returns nil if the string can't be parsed into an HTTP(S) URL.
    public static func sanitize(_ urlString: String) -> String? {
        sanitize(urlString, stripping: Set(defaultTrackingParameters))
    }

    /// Sanitizes using the user's current preferences.
    public static func sanitizeWithPreferences(_ urlString: String) -> String? {
        sanitize(urlString, stripping: Preferences.stripTrackers ? activeParameters : [])
    }

    public static func sanitize(_ urlString: String, stripping parameters: Set<String>) -> String? {
        guard let components = parse(urlString) else { return nil }
        var cleaned = components
        cleaned.scheme = components.scheme?.lowercased()
        cleaned.host = components.host?.lowercased()

        if let queryItems = components.queryItems, !queryItems.isEmpty, !parameters.isEmpty {
            let kept = queryItems.filter { !isTracker($0.name, in: parameters) }
            cleaned.queryItems = kept.isEmpty ? nil : kept
        }

        if cleaned.path == "/" && cleaned.query == nil && cleaned.fragment == nil {
            cleaned.path = ""
        }
        return cleaned.url?.absoluteString
    }

    /// Names of tracking parameters present in the URL (in their original spelling).
    public static func removedParameters(from urlString: String, parameters: Set<String>? = nil) -> [String] {
        guard let components = parse(urlString), let items = components.queryItems else { return [] }
        let set = parameters ?? Set(defaultTrackingParameters)
        return items.map(\.name).filter { isTracker($0, in: set) }
    }

    public static func isValidUrl(_ candidate: String) -> Bool {
        sanitize(candidate) != nil
    }

    /// Host for display, without a leading "www.".
    public static func cleanHost(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Helpers

    private static func isTracker(_ name: String, in parameters: Set<String>) -> Bool {
        let key = name.lowercased()
        return parameters.contains(key) || (parameters.contains("utm_source") && key.hasPrefix("utm_"))
    }

    private static func parse(_ urlString: String) -> URLComponents? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }

        var candidate = trimmed
        let lower = candidate.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            // Accept bare domains like "github.com/apple/swift".
            guard candidate.contains("."), !candidate.contains(" "), !candidate.contains("://") else { return nil }
            candidate = "https://" + candidate
        }

        guard let components = URLComponents(string: candidate),
              let host = components.host, !host.isEmpty, host.contains(".") || host == "localhost",
              !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        return components
    }
}
