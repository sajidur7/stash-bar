import SwiftUI
import AppKit

/// Shared UI state that several windows care about.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum CanvasView: Hashable { case all, pinned, unopened, archive, tag(String) }
    enum SettingsSection: String, CaseIterable, Identifiable {
        case account, general, onboarding, shortcuts, cleaning, appearance, data, about
        var id: String { rawValue }
    }

    @Published var canvasView: CanvasView = .all
    @Published var selectedLinkID: UUID?
    @Published var showAddLink = false
    @Published var addLinkPrefill = ""
    @Published var settingsSection: SettingsSection = .account
    @Published var toast: String?

    func presentAddLink(prefill: String = "") {
        addLinkPrefill = prefill
        showAddLink = true
        WindowManager.shared.show(.canvas)
    }

    func openSettings(_ section: SettingsSection) {
        settingsSection = section
        WindowManager.shared.show(.settings)
    }

    func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.toast == text { self.toast = nil }
        }
    }

    /// ⌥⇧S — stash whatever link is on the clipboard without opening anything.
    func stashClipboardInstantly() async {
        ClipboardWatcher.shared.check(forced: true)
        if ClipboardWatcher.shared.candidateUrl != nil {
            await ClipboardWatcher.shared.stashCandidate()
            StatusItemController.shared?.flash()
        } else {
            NSSound.beep()
        }
    }
}

/// Creates and reuses the app's windows: canvas (⌘E), settings (⌘,) and onboarding.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    enum Kind: String { case canvas, settings, onboarding }

    private var windows: [Kind: NSWindow] = [:]

    func show(_ kind: Kind) {
        StatusItemController.shared?.close()
        let window = windows[kind] ?? makeWindow(kind)
        windows[kind] = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    private func makeWindow(_ kind: Kind) -> NSWindow {
        let container = LinkStore.shared.container
        let root: AnyView
        let size: NSSize
        let minSize: NSSize
        switch kind {
        case .canvas:
            root = AnyView(CanvasRootView().modelContainer(container))
            size = NSSize(width: 1100, height: 700); minSize = NSSize(width: 860, height: 560)
        case .settings:
            root = AnyView(SettingsView().modelContainer(container))
            size = NSSize(width: 1100, height: 760); minSize = NSSize(width: 900, height: 600)
        case .onboarding:
            root = AnyView(OnboardingView().modelContainer(container))
            size = NSSize(width: 480, height: 620); minSize = size
        }

        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if kind != .onboarding { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = kind == .canvas ? "Stashbar" : kind == .settings ? "Stashbar Settings" : "Welcome to Stashbar"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.contentView = NSHostingView(rootView: root)
        window.setFrameAutosaveName("Stashbar.\(kind.rawValue)")
        if kind == .onboarding || !window.setFrameUsingName("Stashbar.\(kind.rawValue)") {
            window.setContentSize(size)
            window.center()
        }
        window.delegate = self
        return window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Go back to being a menu-bar-only app once the last window closes.
            DispatchQueue.main.async {
                let anyVisible = self.windows.values.contains { $0.isVisible }
                if !anyVisible && !Preferences.showInDock {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

/// The menu-bar item and its popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static weak var shared: StatusItemController?

    private let item: NSStatusItem
    private let popover = NSPopover()

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        StatusItemController.shared = self

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView().modelContainer(LinkStore.shared.container))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
        }
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = item.button else { return }
        button.image = PinMark.menuBarImage()
        if UserDefaults.standard.string(forKey: PrefKey.menuBarIcon) == "Pin + count" {
            let count = LinkStore.shared.all(includeArchived: false).count
            button.title = " \(count)"
            button.font = NSFont(name: "GeistMono-Regular", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            button.title = ""
        }
    }

    @objc private func togglePopover(_ sender: Any?) { toggle() }

    func toggle() {
        if popover.isShown { close() } else { open() }
    }

    func open() {
        guard let button = item.button else { return }
        ClipboardWatcher.shared.check(forced: true)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .popoverDidOpen, object: nil)
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// Brief highlight after an instant stash.
    func flash() {
        item.button?.highlight(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.item.button?.highlight(false) }
    }
}

extension Notification.Name {
    static let popoverDidOpen = Notification.Name("StashbarPopoverDidOpen")
}
