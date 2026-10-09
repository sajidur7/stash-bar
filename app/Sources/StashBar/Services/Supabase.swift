import Foundation
import Security

/// Project URL + anon key, baked into Info.plist at build time (see app/scripts/build_app.sh).
/// Both values are public by design; row-level security protects the data.
public enum SupabaseConfig {
    public static var url: URL? {
        guard let s = value("StashbarSupabaseURL"), let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    public static var anonKey: String? { value("StashbarSupabaseAnonKey") }

    public static var isConfigured: Bool { url != nil && anonKey != nil }

    /// Where the website lives (help, feedback, privacy pages).
    public static var websiteURL: URL {
        URL(string: value("StashbarWebsiteURL") ?? "https://stash-bar.vercel.app")!
    }

    public static var githubRepo: String { value("StashbarGitHubRepo") ?? "sajidur7/stash-bar" }

    private static func value(_ key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty { return env }
        guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !s.isEmpty, !s.hasPrefix("$(") else { return nil }
        return s
    }
}

public enum SupabaseError: LocalizedError {
    case notConfigured
    case notSignedIn
    case offline
    case http(Int, String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Sign-in isn't set up in this build of Stashbar."
        case .notSignedIn: return "You're not signed in."
        case .offline: return "Can't reach your account. Check your connection."
        case .http(let code, let message): return message.isEmpty ? "Server error (\(code))." : message
        case .decoding: return "Unexpected response from the server."
        }
    }

    static func from(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .timedOut, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return SupabaseError.offline
            default: break
            }
        }
        return error
    }
}

/// Minimal REST client for Supabase Auth, PostgREST and Storage.
public struct SupabaseClient {
    public static func request(
        _ path: String,
        method: String = "GET",
        query: [(String, String)] = [],
        json: Any? = nil,
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        token: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let base = SupabaseConfig.url, let key = SupabaseConfig.anonKey else { throw SupabaseError.notConfigured }
        var urlString = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        if !query.isEmpty {
            urlString += "?" + query.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: urlString) else { throw SupabaseError.decoding }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token ?? key)", forHTTPHeaderField: "Authorization")
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            req.httpBody = body
            req.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw SupabaseError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(http.statusCode, errorMessage(from: data))
        }
        return (data, http)
    }

    /// Percent-encodes a query value, including "+" and ":" which PostgREST filters care about.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~,()*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func errorMessage(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        for key in ["error_description", "msg", "message", "error"] {
            if let s = obj[key] as? String { return s }
        }
        return ""
    }
}

/// ISO-8601 parsing that copes with Postgres' microsecond timestamps.
public enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func string(_ date: Date) -> String { withFraction.string(from: date) }

    public static func parse(_ value: Any?) -> Date? {
        guard var s = value as? String, !s.isEmpty else { return nil }
        if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
        // Trim fractional seconds to milliseconds: 2026-10-09T14:04:00.123456+00:00
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            var end = afterDot
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            let digits = String(s[afterDot..<end].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s = String(s[..<afterDot]) + digits + String(s[end...])
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

/// Tiny Keychain wrapper for the session tokens.
public enum Keychain {
    private static let service = "app.stashbar.session"

    public static func set(_ data: Data, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public static func get(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
