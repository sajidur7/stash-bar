import Foundation
import AppKit
import AuthenticationServices
import CryptoKit

public struct UserSession: Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userId: String
    public var email: String
    public var name: String
    public var provider: String      // "apple" | "google"
    public var avatarURL: String?
}

public enum AuthProvider: String {
    case apple, google
    public var label: String { self == .apple ? "Apple" : "Google" }
}

/// Supabase Auth over plain REST: OAuth with PKCE through ASWebAuthenticationSession,
/// tokens in the Keychain, refresh on demand.
@MainActor
public final class AuthService: NSObject, ObservableObject {
    public static let shared = AuthService()

    @Published public private(set) var session: UserSession?
    @Published public private(set) var isWorking = false
    @Published public var lastError: String?

    static let callbackScheme = "stashbar"
    static let redirectURL = "stashbar://auth-callback"
    private static let keychainAccount = "session"

    private var webSession: ASWebAuthenticationSession?

    public var isSignedIn: Bool { session != nil }

    private override init() {
        super.init()
        if let data = Keychain.get(Self.keychainAccount),
           let saved = try? JSONDecoder().decode(UserSession.self, from: data) {
            session = saved
        }
    }

    // MARK: - Sign in

    /// Opens the provider's sign-in page. Returns true when a session was created.
    @discardableResult
    public func signIn(with provider: AuthProvider) async -> Bool {
        lastError = nil
        guard let base = SupabaseConfig.url, SupabaseConfig.isConfigured else {
            lastError = SupabaseError.notConfigured.localizedDescription
            return false
        }
        isWorking = true
        defer { isWorking = false }

        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        var comps = URLComponents(url: base.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: Self.redirectURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let authURL = comps.url else { return false }

        do {
            let callback = try await openWebSession(authURL)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let err = items.first(where: { $0.name == "error_description" })?.value {
                lastError = err
                return false
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                lastError = "Sign-in didn't finish. Please try again."
                return false
            }
            let (data, _) = try await SupabaseClient.request(
                "/auth/v1/token", method: "POST", query: [("grant_type", "pkce")],
                json: ["auth_code": code, "code_verifier": verifier])
            try store(tokenResponse: data, fallbackProvider: provider.rawValue)
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func openWebSession(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? SupabaseError.decoding)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            NSApp.activate(ignoringOtherApps: true)
            if !session.start() {
                continuation.resume(throwing: SupabaseError.decoding)
            }
        }
    }

    // MARK: - Tokens

    /// A valid access token, refreshing it first if it's about to expire.
    public func validAccessToken() async throws -> String {
        guard let s = session else { throw SupabaseError.notSignedIn }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        let (data, _) = try await SupabaseClient.request(
            "/auth/v1/token", method: "POST", query: [("grant_type", "refresh_token")],
            json: ["refresh_token": s.refreshToken])
        try store(tokenResponse: data, fallbackProvider: s.provider)
        return session?.accessToken ?? s.accessToken
    }

    private func store(tokenResponse data: Data, fallbackProvider: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String,
              let user = obj["user"] as? [String: Any],
              let userId = user["id"] as? String else { throw SupabaseError.decoding }

        let expiresIn = (obj["expires_in"] as? Double) ?? 3600
        let meta = user["user_metadata"] as? [String: Any] ?? [:]
        let appMeta = user["app_metadata"] as? [String: Any] ?? [:]
        let email = (user["email"] as? String) ?? (meta["email"] as? String) ?? ""
        let name = (meta["full_name"] as? String) ?? (meta["name"] as? String)
            ?? session?.name ?? email.components(separatedBy: "@").first?.capitalized ?? "You"
        let avatar = (meta["avatar_url"] as? String) ?? (meta["picture"] as? String)

        let new = UserSession(accessToken: access, refreshToken: refresh,
                              expiresAt: Date().addingTimeInterval(expiresIn),
                              userId: userId, email: email, name: name,
                              provider: (appMeta["provider"] as? String) ?? fallbackProvider,
                              avatarURL: avatar)
        session = new
        if let encoded = try? JSONEncoder().encode(new) { Keychain.set(encoded, for: Self.keychainAccount) }
        Preferences.accountMode = "signedIn"
    }

    public func updateDisplayName(_ name: String) {
        guard var s = session else { return }
        s.name = name
        session = s
        if let encoded = try? JSONEncoder().encode(s) { Keychain.set(encoded, for: Self.keychainAccount) }
    }

    // MARK: - Sign out / delete

    /// Signs out. With keepLocal the links stay on this Mac and the user continues as a guest.
    public func signOut(keepLocal: Bool) async {
        if let token = session?.accessToken {
            _ = try? await SupabaseClient.request("/auth/v1/logout", method: "POST", token: token)
        }
        clearSession()
        SyncService.shared.resetCursor()
        if keepLocal {
            LinkStore.shared.markAllForSync()
        } else {
            LinkStore.shared.wipeLocal()
        }
        Preferences.accountMode = "guest"
    }

    /// Permanently deletes the account on the server, then wipes this Mac.
    public func deleteAccount() async throws {
        let token = try await validAccessToken()
        if let uid = session?.userId {
            _ = try? await SupabaseClient.request("/storage/v1/object/avatars/\(uid)/avatar.jpg", method: "DELETE", token: token)
        }
        _ = try await SupabaseClient.request("/rest/v1/rpc/delete_account", method: "POST", json: [String: String](), token: token)
        clearSession()
        SyncService.shared.resetCursor()
        LinkStore.shared.wipeLocal()
        ProfileStore.shared.reset()
        Preferences.accountMode = "none"
    }

    private func clearSession() {
        session = nil
        Keychain.delete(Self.keychainAccount)
    }

    // MARK: - PKCE

    nonisolated static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    nonisolated static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow()
        }
    }
}
