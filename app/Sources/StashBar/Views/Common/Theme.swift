import SwiftUI
import AppKit
import CoreText

// MARK: - Tokens (StashBar Redesign v13)
//
// Charcoal surfaces, warm paper fills, hairline borders and one highlighter yellow
// that only ever means "primary action / active". Every surface has a dark-mode twin.

public enum Theme {
    public static let accent = Color(hex: 0xE4F222)          // highlighter yellow — primary actions only
    public static let onAccent = Color(hex: 0x0C0A08)

    public static let ink = dynamic(light: 0x0C0A08, dark: 0xF4F2F0)        // primary text
    public static let body2 = dynamic(light: 0x2A2828, dark: 0xD3D3D3)      // secondary body
    public static let muted = dynamic(light: 0x6D6C6B, dark: 0xA3A2A1)      // captions, hints
    public static let faint = Color(hex: 0xA3A2A1)                           // text on charcoal
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x141313)    // windows, cards
    public static let paper = dynamic(light: 0xF4F2F0, dark: 0x201F1E)      // soft fills, inputs
    public static let hairline = dynamic(light: 0xE5E7EB, dark: 0x2E2C2B)   // borders
    public static let hairlineStrong = dynamic(light: 0xD3D3D3, dark: 0x3D3B3A)
    public static let charcoal = dynamic(light: 0x1A1919, dark: 0x0C0B0A)   // sidebars, dark cards
    public static let charcoal2 = dynamic(light: 0x2A2828, dark: 0x1F1E1D)  // raised on charcoal
    public static let charcoalLine = Color(hex: 0x3D3B3A)
    public static let scrim = Color.black.opacity(0.55)

    // Radii
    public static let rButton: CGFloat = 6
    public static let rInput: CGFloat = 10
    public static let rRow: CGFloat = 12
    public static let rCard: CGFloat = 16

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

public extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type (Geist Mono only; two weights)

public enum FontLoader {
    /// Registers the bundled Geist Mono files. Falls back to the system monospaced font if missing.
    public static func registerFonts() {
        for name in ["GeistMono-Regular", "GeistMono-Medium"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            if let url { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
        available = NSFont(name: "GeistMono-Regular", size: 12) != nil
    }
    static var available = false
}

public extension Font {
    /// Regular (400) Geist Mono.
    static func mono(_ size: CGFloat) -> Font {
        FontLoader.available ? .custom("GeistMono-Regular", fixedSize: size) : .system(size: size, design: .monospaced)
    }
    /// Medium (500) Geist Mono — headings, buttons and active states.
    static func monoMedium(_ size: CGFloat) -> Font {
        FontLoader.available ? .custom("GeistMono-Medium", fixedSize: size) : .system(size: size, weight: .medium, design: .monospaced)
    }
}

public extension View {
    /// Large headings: medium weight, −0.04em tracking, 1.05 line height.
    func headline(_ size: CGFloat) -> some View {
        self.font(.monoMedium(size)).tracking(-0.04 * size).lineSpacing(size * 0.05)
    }
    func caption11() -> some View {
        self.font(.mono(11)).foregroundStyle(Theme.muted)
    }
}

// MARK: - Icons (Lucide in the design → SF Symbols natively)

public enum Icon {
    public static let search = "magnifyingglass"
    public static let plus = "plus"
    public static let close = "xmark"
    public static let check = "checkmark"
    public static let arrowRight = "arrow.right"
    public static let arrowLeft = "arrow.left"
    public static let arrowUp = "arrow.up"
    public static let arrowUpRight = "arrow.up.right"
    public static let returnKey = "return"
    public static let command = "command"
    public static let option = "option"
    public static let link = "link"
    public static let copy = "doc.on.doc"
    public static let pin = "pin"
    public static let pinFill = "pin.fill"
    public static let archive = "archivebox"
    public static let restore = "arrow.uturn.backward"
    public static let trash = "trash"
    public static let library = "books.vertical"
    public static let unopened = "circle.dashed"
    public static let hash = "number"
    public static let share = "square.and.arrow.up"
    public static let importIcon = "square.and.arrow.down"
    public static let download = "arrow.down.to.line"
    public static let shield = "checkmark.shield"
    public static let user = "person"
    public static let lock = "lock"
    public static let sparkles = "sparkles"
    public static let hardDrive = "internaldrive"
    public static let cloud = "icloud"
    public static let cloudOff = "icloud.slash"
    public static let wifiOff = "wifi.slash"
    public static let rotate = "arrow.counterclockwise"
    public static let monitorOff = "display.trianglebadge.exclamationmark"
    public static let laptop = "laptopcomputer"
    public static let monitor = "desktopcomputer"
    public static let grid = "square.grid.2x2"
    public static let settings = "slider.horizontal.3"
    public static let logout = "rectangle.portrait.and.arrow.right"
    public static let alert = "exclamationmark.triangle"
    public static let camera = "camera"
    public static let upload = "square.and.arrow.up"
    public static let refresh = "arrow.clockwise"
    public static let info = "info.circle"
    public static let globe = "globe"
    public static let clipboard = "clipboard"
    public static let clipboardX = "doc.badge.ellipsis"
    public static let searchX = "magnifyingglass"
    public static let eraser = "eraser"
    public static let play = "play.fill"
    public static let book = "book"
    public static let message = "bubble.left"
    public static let file = "doc.text"
    public static let code = "chevron.left.forwardslash.chevron.right"
}

/// A Lucide-weight SF Symbol.
public struct SymbolIcon: View {
    let name: String
    var size: CGFloat = 15
    public init(_ name: String, size: CGFloat = 15) { self.name = name; self.size = size }
    public var body: some View {
        Image(systemName: name).font(.system(size: size * 0.92, weight: .regular)).frame(width: size, height: size)
    }
}

// MARK: - Brand mark

/// The Stashbar pushpin: a rounded head (ellipse + rim) and a tapered needle, tilted −28°.
/// Geometry matches assets/ramp/pin-mark-*.svg (viewBox 11.95 13.90 66.10 66.10).
public struct PinMark: View {
    var color: Color = Theme.ink
    public init(color: Color = Theme.ink) { self.color = color }

    public var body: some View {
        Canvas { ctx, size in
            ctx.concatenate(PinMark.transform(for: size))
            let stroke = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            ctx.stroke(PinMark.headPath(), with: .color(color), style: stroke)
            ctx.fill(PinMark.needlePath(), with: .color(color))
            ctx.stroke(PinMark.needlePath(), with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }

    static func transform(for size: CGSize) -> CGAffineTransform {
        let scale = min(size.width, size.height) / 66.10
        return CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: -11.95, y: -13.90)
            .translatedBy(x: 50, y: 50).rotated(by: -28 * .pi / 180).translatedBy(x: -50, y: -50)
    }

    static func headPath() -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 24, y: 19, width: 52, height: 26))
        // Rim: M24 32 v7 a26 13 0 0 0 52 0 v-7  (lower half of the ellipse shifted down 7)
        p.move(to: CGPoint(x: 24, y: 32))
        p.addLine(to: CGPoint(x: 24, y: 39))
        var rim = Path()
        rim.addArc(center: .zero, radius: 1, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addPath(rim, transform: CGAffineTransform(translationX: 50, y: 39).scaledBy(x: 26, y: 13))
        p.addLine(to: CGPoint(x: 76, y: 32))
        return p
    }

    static func needlePath() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 46, y: 52))
        p.addLine(to: CGPoint(x: 54, y: 52))
        p.addLine(to: CGPoint(x: 51.4, y: 79.5))
        p.addQuadCurve(to: CGPoint(x: 48.6, y: 79.5), control: CGPoint(x: 50, y: 81.2))
        p.closeSubpath()
        return p
    }

    /// Template image for the menu bar.
    public static func menuBarImage(size: CGFloat = 17) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.concatenate(PinMark.transform(for: rect.size))
            cg.setStrokeColor(NSColor.black.cgColor)
            cg.setFillColor(NSColor.black.cgColor)
            cg.setLineWidth(7)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(PinMark.headPath().cgPath)
            cg.strokePath()
            cg.addPath(PinMark.needlePath().cgPath)
            cg.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The app icon: rounded square (rx 23/100) with the pin, in accent / dark / light variants.
public struct AppIconView: View {
    public enum Variant { case accent, dark, light }
    var variant: Variant = .accent
    var size: CGFloat
    public init(_ variant: Variant = .accent, size: CGFloat) { self.variant = variant; self.size = size }

    public var body: some View {
        let bg: Color = variant == .accent ? Theme.accent : variant == .dark ? .black : .white
        let fg: Color = variant == .dark ? .white : .black
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(bg)
            .overlay(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .stroke(variant == .light ? Color(hex: 0xDCDCDC) : .clear, lineWidth: 1))
            .overlay(PinMark(color: fg).frame(width: size * 0.6, height: size * 0.6).offset(x: -size * 0.016))
            .frame(width: size, height: size)
    }
}

// MARK: - Site logos

/// Monochrome site logo (bundled Simple Icons), or a globe for unknown sites.
public struct SiteLogo: View {
    let host: String
    var size: CGFloat = 15
    var color: Color = Theme.ink

    public init(host: String, size: CGFloat = 15, color: Color = Theme.ink) {
        self.host = host; self.size = size; self.color = color
    }

    public var body: some View {
        if let image = SiteLogo.image(for: host) {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
                .foregroundStyle(color).frame(width: size, height: size)
        } else {
            Image(systemName: Icon.globe).font(.system(size: size * 0.9)).foregroundStyle(color).frame(width: size, height: size)
        }
    }

    static let slugs: [String: String] = [
        "x.com": "x", "twitter.com": "x", "youtube.com": "youtube", "youtu.be": "youtube", "github.com": "github",
        "apple.com": "apple", "figma.com": "figma", "stripe.com": "stripe", "reddit.com": "reddit",
        "medium.com": "medium", "notion.so": "notion", "notion.site": "notion", "arxiv.org": "arxiv",
        "nytimes.com": "newyorktimes", "google.com": "google", "instagram.com": "instagram",
        "facebook.com": "facebook", "spotify.com": "spotify", "wikipedia.org": "wikipedia",
        "stackoverflow.com": "stackoverflow", "ycombinator.com": "ycombinator", "producthunt.com": "producthunt",
        "dribbble.com": "dribbble", "behance.net": "behance", "substack.com": "substack", "vercel.com": "vercel",
        "twitch.tv": "twitch", "tiktok.com": "tiktok", "discord.com": "discord", "discord.gg": "discord",
        "netflix.com": "netflix", "threads.net": "threads", "bsky.app": "bluesky", "mastodon.social": "mastodon",
        "pinterest.com": "pinterest", "dropbox.com": "dropbox", "npmjs.com": "npm", "linear.app": "linear",
        "gitlab.com": "gitlab", "vimeo.com": "vimeo", "soundcloud.com": "soundcloud", "hashnode.com": "hashnode",
        "dev.to": "devdotto", "theguardian.com": "theguardian", "docs.google.com": "googledocs",
        "drive.google.com": "googledrive", "anthropic.com": "anthropic", "claude.ai": "anthropic"
    ]

    private static var cache: [String: NSImage] = [:]

    static func image(for host: String) -> NSImage? {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        var slug = slugs[h]
        if slug == nil {
            // Match subdomains: developer.apple.com → apple, open.spotify.com → spotify.
            var parts = h.split(separator: ".")
            while slug == nil, parts.count > 2 {
                parts.removeFirst()
                slug = slugs[parts.joined(separator: ".")]
            }
        }
        guard let slug else { return nil }
        if let cached = cache[slug] { return cached }
        let url = Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: "Logos")
            ?? Bundle.main.url(forResource: slug, withExtension: "png")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[slug] = img
        return img
    }
}
