import AppKit
import Combine

/// Watches the general pasteboard for web addresses. Nothing read here leaves the Mac.
@MainActor
public final class ClipboardWatcher: ObservableObject {
    public static let shared = ClipboardWatcher()

    /// The link as copied.
    @Published public private(set) var rawCandidate: String?
    /// The link after tracker stripping.
    @Published public private(set) var candidateUrl: String?
    @Published public private(set) var candidateHost: String?
    @Published public private(set) var removedTrackers: [String] = []
    /// True when the clipboard holds text that isn't a link (used for the "That's not a link" state).
    @Published public private(set) var clipboardHasNonLinkText = false

    private var lastChangeCount = -1
    private var ignoredChangeCount = -1
    private var dismissedUrl: String?
    private var timer: Timer?

    private init() {}

    public func start() {
        timer?.invalidate()
        guard Preferences.watchClipboard else {
            clear()
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in ClipboardWatcher.shared.check() }
        }
        check(forced: true)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        clear()
    }

    /// Ignore whatever is on the pasteboard right now (e.g. a link Stashbar itself copied).
    public func ignoreCurrentPasteboard() {
        ignoredChangeCount = NSPasteboard.general.changeCount
        clear()
    }

    public func check(forced: Bool = false) {
        let pasteboard = NSPasteboard.general
        let change = pasteboard.changeCount
        if !forced && change == lastChangeCount { return }
        lastChangeCount = change
        if change == ignoredChangeCount { return }

        var text: String?
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first, first.scheme?.hasPrefix("http") == true {
            text = first.absoluteString
        } else if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            text = string
        }

        guard let raw = text else {
            clear()
            return
        }
        guard let clean = URLSanitizer.sanitizeWithPreferences(raw) else {
            clear()
            clipboardHasNonLinkText = true
            return
        }
        if clean == dismissedUrl || LinkStore.shared.item(url: clean) != nil {
            clear()
            return
        }

        rawCandidate = raw
        candidateUrl = clean
        candidateHost = URLSanitizer.cleanHost(from: clean)
        removedTrackers = Preferences.stripTrackers
            ? URLSanitizer.removedParameters(from: raw, parameters: URLSanitizer.activeParameters)
            : []
        clipboardHasNonLinkText = false
    }

    @discardableResult
    public func stashCandidate() async -> StashItem? {
        guard let raw = rawCandidate else { return nil }
        let item = await LinkStore.shared.stash(rawURL: raw)
        clear()
        return item
    }

    public func dismissCandidate() {
        dismissedUrl = candidateUrl
        clear()
    }

    private func clear() {
        rawCandidate = nil
        candidateUrl = nil
        candidateHost = nil
        removedTrackers = []
        clipboardHasNonLinkText = false
    }
}
