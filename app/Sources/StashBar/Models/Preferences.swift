import Foundation

/// UserDefaults keys. Views read these with @AppStorage; services read them through `Preferences`.
public enum PrefKey {
    public static let onboardingDone = "onboardingDone"
    public static let accountMode = "accountMode"            // "none" | "guest" | "signedIn"
    public static let guestBannerDismissed = "guestBannerDismissed"

    // General
    public static let launchAtLogin = "launchAtLogin"
    public static let showInDock = "showInDock"
    public static let watchClipboard = "watchClipboard"
    public static let playSound = "playSound"
    public static let popoverCount = "popoverCount"          // "5" | "10" | "20"

    // Onboarding & tips
    public static let tourOnNewMacs = "tourOnNewMacs"
    public static let inlineTips = "inlineTips"
    public static let dismissedTips = "dismissedTips"

    // Cleaning
    public static let stripTrackers = "stripTrackers"
    public static let copyCleanURL = "copyCleanURL"
    public static let expandShortLinks = "expandShortLinks"
    public static let trackerParameters = "trackerParameters"

    // Appearance
    public static let theme = "theme"                        // "Light" | "Dark" | "System"
    public static let density = "density"                    // "Compact" | "Comfortable"
    public static let menuBarIcon = "menuBarIcon"            // "Pin" | "Pin + count"
    public static let showPreviews = "showPreviews"

    // Sync
    public static let autoSync = "autoSync"
    public static let syncPreviews = "syncPreviews"

    // Shortcuts (Carbon key code + modifier mask)
    public static let hotKeyCode = "hotKeyCode"
    public static let hotKeyModifiers = "hotKeyModifiers"

    // Internal
    public static let deviceId = "deviceId"
}

public enum Preferences {
    static let defaults = UserDefaults.standard

    public static func registerDefaults() {
        defaults.register(defaults: [
            PrefKey.onboardingDone: false,
            PrefKey.accountMode: "none",
            PrefKey.guestBannerDismissed: false,
            PrefKey.launchAtLogin: true,
            PrefKey.showInDock: false,
            PrefKey.watchClipboard: true,
            PrefKey.playSound: true,
            PrefKey.popoverCount: "10",
            PrefKey.tourOnNewMacs: true,
            PrefKey.inlineTips: true,
            PrefKey.stripTrackers: true,
            PrefKey.copyCleanURL: true,
            PrefKey.expandShortLinks: true,
            PrefKey.theme: "System",
            PrefKey.density: "Comfortable",
            PrefKey.menuBarIcon: "Pin",
            PrefKey.showPreviews: true,
            PrefKey.autoSync: true,
            PrefKey.syncPreviews: false,
            PrefKey.hotKeyCode: 1,          // kVK_ANSI_S
            PrefKey.hotKeyModifiers: 2048   // optionKey
        ])
    }

    public static var stripTrackers: Bool { defaults.bool(forKey: PrefKey.stripTrackers) }
    public static var copyCleanURL: Bool { defaults.bool(forKey: PrefKey.copyCleanURL) }
    public static var expandShortLinks: Bool { defaults.bool(forKey: PrefKey.expandShortLinks) }
    public static var watchClipboard: Bool { defaults.bool(forKey: PrefKey.watchClipboard) }
    public static var playSound: Bool { defaults.bool(forKey: PrefKey.playSound) }
    public static var autoSync: Bool { defaults.bool(forKey: PrefKey.autoSync) }
    public static var showInDock: Bool { defaults.bool(forKey: PrefKey.showInDock) }
    public static var popoverCount: Int { Int(defaults.string(forKey: PrefKey.popoverCount) ?? "10") ?? 10 }

    public static var trackerParameters: [String] {
        get { defaults.stringArray(forKey: PrefKey.trackerParameters) ?? URLSanitizer.defaultTrackingParameters }
        set { defaults.set(newValue, forKey: PrefKey.trackerParameters) }
    }

    public static var deviceId: UUID {
        if let s = defaults.string(forKey: PrefKey.deviceId), let id = UUID(uuidString: s) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: PrefKey.deviceId)
        return id
    }

    public static var accountMode: String {
        get { defaults.string(forKey: PrefKey.accountMode) ?? "none" }
        set { defaults.set(newValue, forKey: PrefKey.accountMode) }
    }
}
