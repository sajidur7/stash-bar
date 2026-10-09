import AppKit
import Foundation

/// The user's avatar: one of four monogram styles, or an uploaded photo.
/// Stored locally for guests and in `profiles` + the `avatars` bucket when signed in.
@MainActor
public final class ProfileStore: ObservableObject {
    public static let shared = ProfileStore()

    @Published public private(set) var avatarStyle: Int
    @Published public private(set) var photo: NSImage?

    private let styleKey = "avatarStyle"
    private var photoFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stashbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("avatar.jpg")
    }

    private init() {
        avatarStyle = UserDefaults.standard.integer(forKey: "avatarStyle")
        photo = NSImage(contentsOf: photoFile)
    }

    public var initials: String {
        guard let name = AuthService.shared.session?.name, !name.isEmpty else { return "" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Saves a new avatar choice. Pass `photo` to set a photo, or nil to use the monogram style.
    public func save(style: Int, photo newPhoto: NSImage?) async {
        avatarStyle = style
        UserDefaults.standard.set(style, forKey: styleKey)

        var jpeg: Data?
        if let newPhoto {
            jpeg = Self.squareJPEG(newPhoto, size: 512)
            if let jpeg { try? jpeg.write(to: photoFile) }
            photo = newPhoto
        } else {
            try? FileManager.default.removeItem(at: photoFile)
            photo = nil
        }

        guard AuthService.shared.isSignedIn, let uid = AuthService.shared.session?.userId,
              let token = try? await AuthService.shared.validAccessToken() else { return }
        let path = "\(uid)/avatar.jpg"
        if let jpeg {
            _ = try? await SupabaseClient.request("/storage/v1/object/avatars/\(path)", method: "POST",
                                                  body: jpeg, contentType: "image/jpeg",
                                                  headers: ["x-upsert": "true"], token: token)
        } else {
            _ = try? await SupabaseClient.request("/storage/v1/object/avatars/\(path)", method: "DELETE", token: token)
        }
        _ = try? await SupabaseClient.request(
            "/rest/v1/profiles", method: "POST", query: [("on_conflict", "id")],
            json: [["id": uid, "avatar_style": style, "avatar_path": jpeg == nil ? NSNull() as Any : path as Any,
                    "display_name": AuthService.shared.session?.name ?? "", "updated_at": ISODate.string(Date())]],
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"], token: token)
    }

    /// Pulls the avatar from the account (after signing in on a new Mac).
    public func refreshFromServer() async {
        guard let uid = AuthService.shared.session?.userId,
              let token = try? await AuthService.shared.validAccessToken(),
              let result = try? await SupabaseClient.request(
                "/rest/v1/profiles", query: [("id", "eq.\(uid)"), ("select", "avatar_style,avatar_path")], token: token),
              let row = (try? JSONSerialization.jsonObject(with: result.0) as? [[String: Any]])?.first else { return }

        avatarStyle = (row["avatar_style"] as? Int) ?? 0
        UserDefaults.standard.set(avatarStyle, forKey: styleKey)
        if let path = row["avatar_path"] as? String, let base = SupabaseConfig.url {
            let url = base.appendingPathComponent("storage/v1/object/public/avatars/\(path)")
            if let img = try? await URLSession.shared.data(from: url).0, let image = NSImage(data: img) {
                try? img.write(to: photoFile)
                photo = image
            }
        } else {
            try? FileManager.default.removeItem(at: photoFile)
            photo = nil
        }
    }

    public func reset() {
        avatarStyle = 0
        UserDefaults.standard.removeObject(forKey: styleKey)
        try? FileManager.default.removeItem(at: photoFile)
        photo = nil
    }

    static func squareJPEG(_ image: NSImage, size: CGFloat) -> Data? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let crop = NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: crop, operation: .copy, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
