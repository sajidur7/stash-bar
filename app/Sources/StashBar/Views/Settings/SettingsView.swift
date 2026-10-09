import SwiftUI
import AppKit
import SwiftData

/// 3v — Settings (⌘,). Sidebar with profile + sections; panes on the right.
struct SettingsView: View {
    typealias Section = AppState.SettingsSection

    @ObservedObject private var state = AppState.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var search = ""
    @State private var dialog: AccountDialog?

    enum AccountDialog: Identifiable {
        case signOut, signedOut(Int), deleteAccount, accountDeleted, profilePhoto
        var id: String {
            switch self {
            case .signOut: return "signOut"
            case .signedOut: return "signedOut"
            case .deleteAccount: return "deleteAccount"
            case .accountDeleted: return "accountDeleted"
            case .profilePhoto: return "profilePhoto"
            }
        }
    }

    static let meta: [Section: (label: String, icon: String, sub: String)] = [
        .account: ("Account", "person.crop.circle", "Your profile, sync and sign-out"),
        .general: ("General", "slider.horizontal.3", "How Stashbar starts and behaves"),
        .onboarding: ("Onboarding & tips", "graduationcap", "Welcome tour and hints"),
        .shortcuts: ("Shortcuts", "keyboard", "Keys that work from anywhere"),
        .cleaning: ("Link cleaning", "checkmark.shield", "What gets stripped before a link is saved"),
        .appearance: ("Appearance", "paintpalette", "Theme, density and the menu-bar icon"),
        .data: ("Data & privacy", "cylinder.split.1x2", "Import, export and what leaves your Mac"),
        .about: ("About", "info.circle", "Version, updates and help")
    ]

    private var sections: [Section] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Section.allCases }
        return Section.allCases.filter { s in
            let m = Self.meta[s]!
            return m.label.lowercased().contains(q) || m.sub.lowercased().contains(q) || SettingsView.keywords(s).contains { $0.contains(q) }
        }
    }

    static func keywords(_ s: Section) -> [String] {
        switch s {
        case .account: return ["sign in", "sign out", "sync", "devices", "photo", "delete"]
        case .general: return ["login", "dock", "clipboard", "sound", "popover"]
        case .onboarding: return ["tour", "tips", "welcome"]
        case .shortcuts: return ["hotkey", "keyboard", "option"]
        case .cleaning: return ["tracker", "utm", "parameter", "short"]
        case .appearance: return ["theme", "dark", "light", "density", "icon", "preview"]
        case .data: return ["import", "export", "cache", "privacy", "bookmarks"]
        case .about: return ["version", "update", "help", "feedback", "github"]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.meta[state.settingsSection]!.label).headline(36).foregroundStyle(Theme.ink)
                        Text(Self.meta[state.settingsSection]!.sub).font(.mono(14)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 48).padding(.top, 48).padding(.bottom, 20)
                    pane.padding(.horizontal, 48).padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.surface)
        }
        .frame(minWidth: 900, minHeight: 600)
        .ignoresSafeArea()
        .modalOverlay(dialog != nil, onDismiss: { if case .accountDeleted? = dialog {} else { dialog = nil } }) {
            if let dialog { dialogView(dialog) }
        }
        .animation(.easeOut(duration: 0.15), value: dialog?.id)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AvatarView(size: 40, onCharcoal: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.session?.name ?? "Guest").font(.mono(13)).foregroundStyle(.white).lineLimit(1)
                    Text(auth.session?.email ?? "this Mac only").font(.mono(11)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Color(hex: 0x2A2828)))
            .padding(.top, 34)

            HStack(spacing: 8) {
                SymbolIcon(Icon.search, size: 14).foregroundStyle(.white).opacity(0.6)
                TextField("Search settings", text: $search).textFieldStyle(.plain).font(.mono(13)).foregroundStyle(.white)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2828)))

            VStack(spacing: 2) {
                ForEach(sections) { s in
                    let on = state.settingsSection == s
                    HStack(spacing: 10) {
                        SymbolIcon(Self.meta[s]!.icon, size: 15)
                        Text(Self.meta[s]!.label).font(on ? .monoMedium(13) : .mono(13))
                        Spacer()
                        if s == .account && !auth.isSignedIn {
                            Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        }
                    }
                    .foregroundStyle(on ? Theme.onAccent : .white)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.accent : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { state.settingsSection = s }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                PinMark(color: .white).frame(width: 13, height: 13).opacity(0.7)
                Text("Stashbar \(UpdateChecker.currentVersion)").font(.mono(11)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 12).padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x1A1919))
    }

    // MARK: Panes

    @ViewBuilder
    private var pane: some View {
        switch state.settingsSection {
        case .account: AccountPane(dialog: $dialog)
        case .general: GeneralPane()
        case .onboarding: OnboardingPane()
        case .shortcuts: ShortcutsPane()
        case .cleaning: CleaningPane()
        case .appearance: AppearancePane()
        case .data: DataPane()
        case .about: AboutPane()
        }
    }

    // MARK: Dialogs

    @ViewBuilder
    private func dialogView(_ d: AccountDialog) -> some View {
        switch d {
        case .signOut: SignOutDialog(dialog: $dialog)
        case .signedOut(let count): SignedOutDialog(count: count, dialog: $dialog)
        case .deleteAccount: DeleteAccountDialog(dialog: $dialog)
        case .accountDeleted: AccountDeletedDialog(dialog: $dialog)
        case .profilePhoto: ProfilePhotoDialog(dialog: $dialog)
        }
    }
}

// MARK: - Account (3s / 3t)

struct AccountPane: View {
    @Binding var dialog: SettingsView.AccountDialog?
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var sync = SyncService.shared
    @ObservedObject private var store = LinkStore.shared
    @AppStorage(PrefKey.autoSync) private var autoSync = true
    @Query private var items: [StashItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let s = auth.session { signedIn(s) } else { guest }
        }
    }

    private func signedIn(_ s: UserSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                Button { dialog = .profilePhoto } label: {
                    AvatarView(size: 64)
                        .overlay(alignment: .bottomTrailing) {
                            SymbolIcon(Icon.camera, size: 12).foregroundStyle(Theme.onAccent)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Theme.accent))
                                .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                }
                .buttonStyle(.plain)
                .help("Change profile photo")
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name).headline(22).foregroundStyle(Theme.ink)
                    Text("\(s.email) · Signed in with \(s.provider == "apple" ? "Apple" : "Google")").font(.mono(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                HStack(spacing: 6) {
                    SymbolIcon(sync.status == .offline ? Icon.cloudOff : Icon.cloud, size: 13)
                    Text(syncChip).font(.monoMedium(12))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))

            HStack(spacing: 10) {
                stat("\(items.count)", "links")
                stat("\(store.allTags.count)", "tags")
                stat("\(max(sync.devices.count, 1))", sync.devices.count == 1 ? "Mac" : "Macs")
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Sync").padding(.bottom, 8)
                SettingRow(nil, "Sync automatically", "Keep every signed-in Mac up to date") { StashToggle(isOn: $autoSync) }
                SettingRow(nil, "Sync now", syncDetail) {
                    Button("Sync now") { Task { await SyncService.shared.syncNow() } }
                        .stashButton(.outline, height: 36).disabled(sync.status == .syncing)
                }
            }

            if !sync.devices.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Devices").padding(.bottom, 8)
                    ForEach(sync.devices) { d in
                        VStack(spacing: 0) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            HStack(spacing: 12) {
                                SymbolIcon(d.name.lowercased().contains("book") ? Icon.laptop : Icon.monitor, size: 17)
                                Text(d.isThisMac ? "\(d.name) — this Mac" : d.name).font(.mono(13))
                                Spacer()
                                Text(d.isThisMac ? "now" : RelativeTime.ago(d.lastSeen)).font(.mono(12)).foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign out of Stashbar").font(.mono(13)).foregroundStyle(Theme.ink)
                    Text("A copy of your \(items.count) links can stay on this Mac. Sign back in anytime.").font(.mono(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { dialog = .signOut } label: {
                    HStack(spacing: 8) { SymbolIcon(Icon.logout, size: 14); Text("Sign out") }
                }
                .stashButton(.outline, height: 42)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.hairline, lineWidth: 1))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete account and all links").font(.mono(13)).foregroundStyle(Theme.ink)
                    Text("Removes everything from our servers and every Mac. Can't be undone.").font(.mono(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                UnderlineLink("Delete account", underline: Theme.ink) { dialog = .deleteAccount }
            }
            .padding(.top, 4)
        }
    }

    private var guest: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                AvatarView(size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Guest").headline(22).foregroundStyle(Theme.ink)
                    Text("Stored on this \(Host.current().localizedName ?? "Mac") only").font(.mono(13)).foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SymbolIcon(Icon.alert, size: 13)
                    Text("GUEST · NOT BACKED UP").font(.mono(11))
                }
                .foregroundStyle(Theme.accent)
                Text(items.isEmpty ? "Nothing to lose yet." : "\(items.count) link\(items.count == 1 ? "" : "s") live only on this Mac.")
                    .headline(28).foregroundStyle(.white)
                Text("If you delete Stashbar they're gone, and a new install starts empty. Sign in to move them all to your account.")
                    .font(.mono(13)).lineSpacing(4).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Color(hex: 0x1A1919)))

            SignInButtons(height: 48, horizontal: true) { _ in }

            HStack(spacing: 10) {
                SymbolIcon("externaldrive.badge.checkmark", size: 16)
                Text("Rather stay a guest? Keep a manual backup.").font(.mono(13)).foregroundStyle(Theme.muted)
                Spacer()
                UnderlineLink("Export .json") { BookmarkIO.export(.json, items: items) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
        }
    }

    private func stat(_ v: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).headline(28).foregroundStyle(Theme.ink)
            Text(k).font(.mono(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var syncChip: String {
        switch sync.status {
        case .syncing: return "Syncing…"
        case .offline: return "Offline"
        case .error: return "Sync paused"
        case .idle: return sync.lastSyncedAt.map { "Synced \(RelativeTime.ago($0))" } ?? "Not synced yet"
        }
    }

    private var syncDetail: String {
        if case .error(let message) = sync.status { return message }
        return sync.lastSyncedAt.map { "Last synced \(RelativeTime.ago($0))" } ?? "Not synced yet"
    }
}

// MARK: - General

struct GeneralPane: View {
    @AppStorage(PrefKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(PrefKey.showInDock) private var showInDock = false
    @AppStorage(PrefKey.watchClipboard) private var watchClipboard = true
    @AppStorage(PrefKey.playSound) private var playSound = true
    @AppStorage(PrefKey.popoverCount) private var popoverCount = "10"

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            group("Startup") {
                SettingRow("power", "Launch at login", "Keep Stashbar ready in the menu bar") { StashToggle(isOn: $launchAtLogin) }
                SettingRow("macwindow", "Show in Dock", "Off keeps Stashbar menu-bar only") { StashToggle(isOn: $showInDock) }
            }
            group("Behaviour") {
                SettingRow(Icon.clipboard, "Watch clipboard for links", "Offers to stash links you copy. Checked on this Mac only.") { StashToggle(isOn: $watchClipboard) }
                SettingRow("speaker.wave.2", "Play sound when stashed", "A soft click confirms each stash") { StashToggle(isOn: $playSound) }
                SettingRow("list.bullet", "Popover shows", "Most recent links in the menu-bar popover") { Segmented(["5", "10", "20"], selection: $popoverCount) }
            }
        }
        .onChange(of: launchAtLogin) { _, v in LoginItem.set(v) }
        .onChange(of: showInDock) { _, v in if v { NSApp.setActivationPolicy(.regular) } }
        .onChange(of: watchClipboard) { _, v in if v { ClipboardWatcher.shared.start() } else { ClipboardWatcher.shared.stop() } }
    }
}

// MARK: - Onboarding & tips

struct OnboardingPane: View {
    @AppStorage(PrefKey.inlineTips) private var inlineTips = true
    @AppStorage(PrefKey.guestBannerDismissed) private var guestBannerDismissed = false
    @State private var resetDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            group("Tips") {
                SettingRow("lightbulb", "Inline tips", "Small hints like the guest reminder banner") { StashToggle(isOn: $inlineTips) }
                SettingRow(Icon.rotate, "Reset dismissed tips", resetDone ? "Done — every hint is back." : "Bring back every hint you closed") {
                    Button("Reset tips") { guestBannerDismissed = false; resetDone = true }.stashButton(.outline, height: 36)
                }
            }
            HStack(spacing: 18) {
                AppIconView(.accent, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Replay the welcome tour").headline(18).foregroundStyle(.white)
                    Text("Walk through setup again. Your links and account aren't touched.").font(.mono(13)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Button {
                    UserDefaults.standard.set(false, forKey: PrefKey.onboardingDone)
                    WindowManager.shared.close(.settings)
                    WindowManager.shared.show(.onboarding)
                } label: { HStack(spacing: 8) { SymbolIcon(Icon.play, size: 14); Text("Start tour") } }
                .stashButton(.primary, height: 42)
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Color(hex: 0x1A1919)))
        }
        .onChange(of: inlineTips) { _, v in guestBannerDismissed = !v }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @State private var recording = false
    @State private var combo = HotKeyManager.shared.openCombo

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            group("Global") {
                SettingRow("rectangle.topthird.inset.filled", "Open Stashbar", recording ? "Press the new shortcut, or Esc to cancel" : "From any app · click the keys to change") {
                    Button { recording.toggle() } label: {
                        KeyCap(recording ? "…" : combo.display, size: 30)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(recording ? Theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .background(ShortcutRecorder(isRecording: $recording) { new in
                        combo = new
                        HotKeyManager.shared.setOpenCombo(new)
                    })
                }
                SettingRow("doc.on.clipboard", "Stash clipboard instantly", "Skips the popover") {
                    KeyCap(KeyCombo(keyCode: combo.keyCode, modifiers: combo.modifiers | 512).display)
                }
            }
            group("In Stashbar") {
                SettingRow(Icon.grid, "Open canvas", "Full window with every link") { KeyCap("E", symbol: Icon.command) }
                SettingRow(Icon.plus, "Add a link", "Opens the Add link sheet") { KeyCap("N", symbol: Icon.command) }
                SettingRow(Icon.pin, "Pin to top", "In a link’s detail view") { KeyCap("P", symbol: Icon.command) }
                SettingRow(Icon.archive, "Archive link", "In a link’s detail view") { KeyCap("⌫", symbol: Icon.command) }
                SettingRow(Icon.copy, "Copy clean URL", "In a link’s detail view") { KeyCap("⇧C", symbol: Icon.command) }
                SettingRow("arrow.up.right.square", "Open in browser", "Popover or detail view") { KeyCap("↩", symbol: Icon.command) }
                SettingRow(Icon.settings, "Settings", "This window") { KeyCap(",", symbol: Icon.command) }
            }
        }
    }
}

// MARK: - Link cleaning

struct CleaningPane: View {
    @AppStorage(PrefKey.stripTrackers) private var strip = true
    @AppStorage(PrefKey.copyCleanURL) private var copyClean = true
    @AppStorage(PrefKey.expandShortLinks) private var expand = true
    @State private var params = Preferences.trackerParameters
    @State private var newParam = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            group("Cleaning") {
                SettingRow(Icon.shield, "Strip tracking parameters", "utm_, fbclid, si and \(max(params.count - 3, 0)) more") { StashToggle(isOn: $strip) }
                SettingRow(Icon.copy, "Copy the clean URL", "Otherwise copies the original link") { StashToggle(isOn: $copyClean) }
                SettingRow("arrow.up.left.and.arrow.down.right", "Expand short links", "t.co, bit.ly and friends become the real address") { StashToggle(isOn: $expand) }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Always strip these parameters")
                    Spacer()
                    UnderlineLink("Reset to defaults", color: Theme.muted, underline: Theme.hairlineStrong) {
                        params = URLSanitizer.defaultTrackingParameters
                        Preferences.trackerParameters = params
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(params, id: \.self) { p in
                        HStack(spacing: 6) {
                            Text(p).font(.mono(12))
                            Button { params.removeAll { $0 == p }; Preferences.trackerParameters = params } label: {
                                SymbolIcon(Icon.close, size: 9).opacity(0.5)
                            }.buttonStyle(.plain)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.leading, 12).padding(.trailing, 8).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.paper))
                    }
                    if adding {
                        TextField("param", text: $newParam).textFieldStyle(.plain).font(.mono(12)).frame(width: 110)
                            .padding(.horizontal, 12).frame(height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: 1.5))
                            .onSubmit {
                                let p = newParam.trimmingCharacters(in: .whitespaces).lowercased()
                                if !p.isEmpty, !params.contains(p) { params.append(p); Preferences.trackerParameters = params }
                                newParam = ""; adding = false
                            }
                    } else {
                        Button { adding = true } label: {
                            HStack(spacing: 6) { SymbolIcon(Icon.plus, size: 11); Text("Add parameter").font(.mono(12)) }
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 12).frame(height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xA3A2A1), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @AppStorage(PrefKey.theme) private var theme = "System"
    @AppStorage(PrefKey.density) private var density = "Comfortable"
    @AppStorage(PrefKey.menuBarIcon) private var menuBarIcon = "Pin"
    @AppStorage(PrefKey.showPreviews) private var showPreviews = true

    var body: some View {
        group("Look") {
            SettingRow("circle.lefthalf.filled", "Theme", "Follows macOS by default") { Segmented(["Light", "Dark", "System"], selection: $theme) }
            SettingRow("rectangle.grid.1x2", "Density", "Row height in lists") { Segmented(["Compact", "Comfortable"], selection: $density) }
            SettingRow(Icon.pin, "Menu-bar icon", "What appears next to the clock") { Segmented(["Pin", "Pin + count"], selection: $menuBarIcon) }
            SettingRow("photo", "Show link previews", "Load page images in the canvas") { StashToggle(isOn: $showPreviews) }
        }
        .onChange(of: theme) { _, _ in ThemeController.apply() }
        .onChange(of: menuBarIcon) { _, _ in StatusItemController.shared?.refreshIcon() }
    }
}

// MARK: - Data & privacy

struct DataPane: View {
    @Query(sort: \StashItem.createdAt, order: .reverse) private var items: [StashItem]
    @State private var cacheBytes = LinkStore.shared.previewCacheBytes

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            group("Your links") {
                SettingRow(Icon.importIcon, "Import bookmarks", "Safari, Chrome, Arc or Firefox bookmark files, or a Stashbar .json") {
                    Button("Import…") { Task { await runImport() } }.stashButton(.outline, height: 36)
                }
                SettingRow(Icon.download, "Export everything", "JSON, Markdown or browser bookmarks") {
                    Menu {
                        ForEach(BookmarkIO.Format.allCases, id: \.self) { f in
                            Button(f.rawValue) { BookmarkIO.export(f, items: items) }
                        }
                    } label: { Text("Export…").font(.monoMedium(13)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                    .foregroundStyle(Theme.onAccent)
                }
            }
            group("Privacy") {
                SettingRow("hand.raised", "No analytics, no crash reports", "This version of Stashbar collects neither. Guests never touch our servers.") { EmptyView() }
                SettingRow(Icon.trash, "Clear local cache", "Frees \(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)) of previews. Links are kept.") {
                    Button("Clear cache") { _ = LinkStore.shared.clearPreviewCache(); cacheBytes = 0 }
                        .stashButton(.outline, height: 36).disabled(cacheBytes == 0)
                }
            }
        }
    }
}

// MARK: - About

struct AboutPane: View {
    @State private var updateText = "Check for updates"
    @State private var updateURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 22) {
                AppIconView(.dark, size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stashbar").headline(28).foregroundStyle(Theme.ink)
                    Text("Version \(UpdateChecker.currentVersion) (\(UpdateChecker.build))").font(.mono(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    if let updateURL { NSWorkspace.shared.open(updateURL); return }
                    updateText = "Checking…"
                    Task {
                        if let r = await UpdateChecker.check() {
                            updateText = r.isNewer ? "Get \(r.latest)" : "Up to date"
                            updateURL = r.isNewer ? SupabaseConfig.websiteURL.appendingPathComponent("download") : nil
                        } else {
                            updateText = "Couldn’t check"
                        }
                    }
                } label: { HStack(spacing: 8) { SymbolIcon(Icon.refresh, size: 13); Text(updateText) } }
                .stashButton(updateURL == nil ? .outline : .primary, height: 40)
            }
            .padding(26)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))

            VStack(spacing: 0) {
                link(Icon.book, "Help & keyboard guide", SupabaseConfig.websiteURL.appendingPathComponent("help"))
                link(Icon.message, "Send feedback", SupabaseConfig.websiteURL.appendingPathComponent("feedback"))
                link(Icon.file, "Privacy policy", SupabaseConfig.websiteURL.appendingPathComponent("privacy"))
                link(Icon.code, "Source on GitHub", URL(string: "https://github.com/\(SupabaseConfig.githubRepo)")!)
            }
        }
    }

    private func link(_ icon: String, _ label: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 14) {
                    SymbolIcon(icon, size: 16)
                    Text(label).font(.mono(13))
                    Spacer()
                    SymbolIcon(Icon.arrowUpRight, size: 14).opacity(0.5)
                }
                .foregroundStyle(Theme.ink)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// Section label + rows.
@ViewBuilder
func group<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        SectionLabel(title).padding(.bottom, 8)
        rows()
    }
}
