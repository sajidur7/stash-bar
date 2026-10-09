import SwiftUI
import AppKit

@main
struct StashBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All windows are AppKit-managed (see WindowManager) so the menu-bar popover,
        // the global hotkey and onboarding can open them from anywhere.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { WindowManager.shared.show(.settings) }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .newItem) {
                    Button("Open Canvas") { WindowManager.shared.show(.canvas) }
                        .keyboardShortcut("e", modifiers: .command)
                    Button("Add Link…") { AppState.shared.presentAddLink() }
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        FontLoader.registerFonts()
        ThemeController.apply()

        NSApp.setActivationPolicy(Preferences.showInDock ? .regular : .accessory)

        statusController = StatusItemController()
        HotKeyManager.shared.onAction = { action in
            switch action {
            case .togglePopover: StatusItemController.shared?.toggle()
            case .stashClipboard: Task { await AppState.shared.stashClipboardInstantly() }
            }
        }
        HotKeyManager.shared.registerAll()
        ClipboardWatcher.shared.start()
        SyncService.shared.start()
        if AuthService.shared.isSignedIn {
            Task { await ProfileStore.shared.refreshFromServer() }
        }

        if !UserDefaults.standard.bool(forKey: PrefKey.onboardingDone) {
            WindowManager.shared.show(.onboarding)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.show(.canvas) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
    }
}

/// Applies Settings → Appearance → Theme to the whole app.
@MainActor
enum ThemeController {
    static func apply() {
        switch UserDefaults.standard.string(forKey: PrefKey.theme) ?? "System" {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
