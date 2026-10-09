import SwiftUI
import AppKit

/// 3b–3g — first run. 480×620 window.
struct OnboardingView: View {
    enum Step { case welcome, signIn, guestConfirm, restoring, shortcut, done }

    @State private var step: Step = .welcome
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var sync = SyncService.shared
    @AppStorage(PrefKey.watchClipboard) private var watchClipboard = true
    @AppStorage(PrefKey.stripTrackers) private var stripTrackers = true
    @AppStorage(PrefKey.launchAtLogin) private var launchAtLogin = true
    @State private var recording = false
    @State private var copied = false
    @State private var combo = HotKeyManager.shared.openCombo

    var body: some View {
        Group {
            switch step {
            case .welcome: welcome
            case .signIn: signIn
            case .guestConfirm: guestConfirm
            case .restoring: restoring
            case .shortcut: shortcut
            case .done: done
            }
        }
        .frame(width: 480, height: 620)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // 3b
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            AppIconView(.accent, size: 96)
            Text("Stop losing\ngood links.").headline(44).foregroundStyle(.white)
            Text("Stashbar lives in your menu bar. Copy a link anywhere, press ⌥S, and it's pinned — trackers stripped, ready to find.")
                .font(.mono(16)).lineSpacing(6).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                progressDots(0)
                Spacer()
                Button { step = .signIn } label: {
                    HStack(spacing: 8) { Text("Get started"); SymbolIcon(Icon.arrowRight, size: 16) }
                }
                .stashButton(.primary, height: 44, fontSize: 14)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 40).padding(.top, 60).padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x1A1919))
    }

    // 3c
    private var signIn: some View {
        page {
            VStack(alignment: .leading, spacing: 24) {
                SectionLabel("Step 2 of 4")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keep your links for good.").headline(36).foregroundStyle(Theme.ink)
                    Text("Sign in to back up your stash and sync it across Macs. Reinstall anytime — everything comes back.")
                        .font(.mono(14)).lineSpacing(5).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                SignInButtons(height: 50) { ok in if ok { startRestore() } }
                HStack(spacing: 12) {
                    Rectangle().fill(Theme.hairlineStrong).frame(height: 1)
                    Text("OR").font(.mono(12)).foregroundStyle(Theme.muted)
                    Rectangle().fill(Theme.hairlineStrong).frame(height: 1)
                }
                Button { step = .guestConfirm } label: {
                    HStack(spacing: 10) { SymbolIcon(Icon.user, size: 16); Text("Continue as guest").font(.mono(14)) }
                }
                .stashButton(.soft, height: 50, fullWidth: true)
                Spacer()
                HStack(alignment: .top, spacing: 8) {
                    SymbolIcon(Icon.lock, size: 14).opacity(0.6)
                    Text("We store the links you pin — never your browsing history.").font(.mono(13)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // 3d
    private var guestConfirm: some View {
        page {
            VStack(alignment: .leading, spacing: 22) {
                SectionLabel("Step 2 of 4 · Guest")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Guest links live on this Mac only.").headline(36).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Text("If you delete Stashbar, your links go with it. A fresh download starts empty.")
                        .font(.mono(14)).lineSpacing(5).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                CompareTable()
                Spacer()
                HStack(spacing: 10) {
                    Button("Stay a guest") {
                        Preferences.accountMode = "guest"
                        step = .shortcut
                    }
                    .stashButton(.outline, fullWidth: true)
                    Button("Sign in instead") { step = .signIn }.stashButton(.primary, fullWidth: true)
                }
            }
        }
    }

    // 3g
    private var restoring: some View {
        page {
            VStack(alignment: .leading, spacing: 22) {
                AvatarView(size: 56)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome back, \(auth.session?.name.components(separatedBy: " ").first ?? "there").")
                        .headline(36).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Text(sync.status == .syncing ? "Bringing your stash back from your account." : restoreSummary)
                        .font(.mono(14)).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Theme.paper)
                            RoundedRectangle(cornerRadius: 6).fill(Theme.charcoal)
                                .frame(width: geo.size.width * (sync.status == .syncing ? 0.6 : 1))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("\(sync.restoredCount) link\(sync.restoredCount == 1 ? "" : "s") · \(LinkStore.shared.allTags.count) tags")
                        Spacer()
                        Text(sync.status == .syncing ? "restoring…" : "done")
                    }
                    .font(.mono(12)).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 2) {
                    ForEach(Array(sync.restoredTitles.enumerated()), id: \.offset) { _, entry in
                        VStack(spacing: 0) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            HStack(spacing: 12) {
                                SiteLogo(host: entry.host, size: 14)
                                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9).fill(Theme.paper))
                                Text(entry.title).font(.mono(13)).lineLimit(1).foregroundStyle(Theme.ink)
                                Spacer()
                                SymbolIcon(Icon.check, size: 14).opacity(0.55)
                            }
                            .padding(.vertical, 9)
                        }
                    }
                }
                Spacer()
                HStack {
                    Text("Signed in with \(auth.session?.provider == "apple" ? "Apple" : "Google") · \(auth.session?.email ?? "")")
                        .font(.mono(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    Button { step = .shortcut } label: {
                        HStack(spacing: 8) { Text("Continue"); SymbolIcon(Icon.arrowRight, size: 16) }
                    }
                    .stashButton(.primary, height: 44, fontSize: 14)
                    .disabled(sync.status == .syncing)
                }
            }
        }
    }

    private var restoreSummary: String {
        sync.restoredCount == 0 ? "You're signed in. Links you stash will sync to every Mac." : "Your stash is back on this Mac."
    }

    // 3e
    private var shortcut: some View {
        page(topPadding: 8) {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("Step 3 of 4")
                Text("One shortcut to remember.").headline(36).foregroundStyle(Theme.ink)
                HStack(spacing: 12) {
                    bigKey(Text(combo.modifierSymbols).font(.monoMedium(22)))
                    bigKey(Text(combo.keyName).headline(22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording ? "Press a new combo…" : "Opens Stashbar").font(.mono(13)).foregroundStyle(Theme.ink)
                        Text("from any app").font(.mono(13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.leading, 8)
                    Spacer()
                    UnderlineLink(recording ? "Cancel" : "Change") { recording.toggle() }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
                .background(ShortcutRecorder(isRecording: $recording) { new in combo = new; HotKeyManager.shared.setOpenCombo(new) })

                VStack(spacing: 0) {
                    permRow(Icon.clipboard, "Watch clipboard for links", "Checked locally. Text never leaves your Mac.", $watchClipboard)
                    permRow(Icon.shield, "Strip tracking parameters", "utm_, fbclid, si and 40 more", $stripTrackers)
                    permRow("power", "Launch at login", "Always ready in the menu bar", $launchAtLogin)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        ClipboardWatcher.shared.start()
                        LoginItem.set(launchAtLogin)
                        step = .done
                    } label: {
                        HStack(spacing: 8) { Text("Continue"); SymbolIcon(Icon.arrowRight, size: 16) }
                    }
                    .stashButton(.primary, height: 44, fontSize: 14)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // 3f
    private var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    SymbolIcon(Icon.arrowUp, size: 20).foregroundStyle(Theme.ink)
                    Text("Stashbar lives here").font(.mono(12)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x1A1919)))
                }
            }
            .padding(.top, 36)
            Spacer().frame(height: 50)
            SectionLabel("Step 4 of 4")
            Text("You're set. Copy a link to try it.").headline(44).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                SymbolIcon(Icon.link, size: 15)
                Text(welcomeURL.replacingOccurrences(of: "https://", with: "")).font(.mono(13)).foregroundStyle(Theme.onAccent).lineLimit(1)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(welcomeURL, forType: .string)
                    copied = true
                } label: {
                    HStack(spacing: 4) { SymbolIcon(copied ? Icon.check : Icon.copy, size: 13); Text(copied ? "Copied" : "Copy").font(.mono(12)) }
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.accent))
            Spacer()
            HStack {
                Text("Then press").font(.mono(13)).foregroundStyle(Theme.muted)
                Spacer()
                Button { finish(openPopover: true) } label: {
                    HStack(spacing: 6) {
                        Text("Open Stashbar")
                        Text(combo.display).font(.monoMedium(14)).padding(.leading, 6)
                    }
                }
                .stashButton(.primary, height: 44, fontSize: 14)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 40).padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
    }

    private var welcomeURL: String { SupabaseConfig.websiteURL.appendingPathComponent("help").absoluteString }

    // MARK: Helpers

    private func page<C: View>(topPadding: CGFloat = 16, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 40).padding(.top, 44 + topPadding).padding(.bottom, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
    }

    private func progressDots(_ index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6).fill(i == index ? Theme.accent : Color(hex: 0x2A2828))
                    .frame(width: i == index ? 22 : 6, height: 6)
            }
        }
    }

    private func bigKey<V: View>(_ label: V) -> some View {
        label.foregroundStyle(Color(hex: 0x0C0A08))
            .frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Color(hex: 0xE5E7EB), lineWidth: 1))
            .shadow(color: Color(hex: 0xD3D3D3), radius: 0, x: 0, y: 3)
    }

    private func permRow(_ icon: String, _ label: String, _ hint: String, _ binding: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 14) {
                SymbolIcon(icon, size: 17).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.mono(13)).foregroundStyle(Theme.ink)
                    Text(hint).font(.mono(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                StashToggle(isOn: binding)
            }
            .padding(.vertical, 14)
        }
    }

    private func startRestore() {
        // SignInButtons already ran the first sync; this screen shows what came back.
        step = .restoring
    }

    private func finish(openPopover: Bool) {
        UserDefaults.standard.set(true, forKey: PrefKey.onboardingDone)
        if Preferences.accountMode == "none" { Preferences.accountMode = auth.isSignedIn ? "signedIn" : "guest" }
        WindowManager.shared.close(.onboarding)
        if openPopover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { StatusItemController.shared?.open() }
        }
    }
}

/// "Continue with Apple" (primary) + "Continue with Google" (outline).
struct SignInButtons: View {
    var height: CGFloat = 50
    var horizontal = false
    let completion: (Bool) -> Void
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
            layout {
                Button { go(.apple) } label: {
                    HStack(spacing: 10) { SiteLogo(host: "apple.com", size: 17, color: Theme.onAccent); Text("Continue with Apple").font(.monoMedium(14)) }
                }
                .stashButton(.primary, height: height, fullWidth: true)
                Button { go(.google) } label: {
                    HStack(spacing: 10) { SiteLogo(host: "google.com", size: 16); Text("Continue with Google").font(.mono(14)) }
                }
                .stashButton(.outline, height: height, fullWidth: true)
            }
            .disabled(auth.isWorking)
            if auth.isWorking {
                Text("Finish signing in in the window that opened…").font(.mono(12)).foregroundStyle(Theme.muted)
            } else if let error = auth.lastError {
                Text(error).font(.mono(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func go(_ provider: AuthProvider) {
        Task {
            let ok = await auth.signIn(with: provider)
            if ok {
                Preferences.accountMode = "signedIn"
                LinkStore.shared.markAllForSync()
                await SyncService.shared.syncNow()
                await ProfileStore.shared.refreshFromServer()
            }
            completion(ok)
        }
    }
}

/// The guest-vs-signed-in comparison grid from 3d.
struct CompareTable: View {
    private let rows: [(String, String, String, String, String, String)] = [
        (Icon.hardDrive, "Saved on this", "Mac only", Icon.cloud, "Backed up", "automatically"),
        (Icon.trash, "Gone if you", "delete the app", Icon.rotate, "Restored", "on reinstall"),
        (Icon.monitorOff, "No sync", "between Macs", Icon.laptop, "Synced across", "your Macs")
    ]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("Guest").font(.mono(13)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 14)
                HStack(spacing: 6) { Text("Signed in"); SymbolIcon(Icon.sparkles, size: 13) }.font(.mono(13))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Theme.surface).overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                GridRow {
                    cell(r.0, r.1, r.2, muted: true)
                    cell(r.3, r.4, r.5, muted: false)
                        .background(Theme.surface).overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
        .foregroundStyle(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func cell(_ icon: String, _ a: String, _ b: String, muted: Bool) -> some View {
        HStack(spacing: 10) {
            SymbolIcon(icon, size: 15).opacity(muted ? 0.55 : 1)
            Text("\(a)\n\(b)").font(.mono(13)).lineSpacing(2).foregroundStyle(muted ? Theme.muted : Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Listens for the next key combo while `isRecording` is true (Settings → Shortcuts, onboarding).
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: @MainActor (KeyCombo) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if isRecording { context.coordinator.start() } else { context.coordinator.stop() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator {
        var parent: ShortcutRecorder
        private var monitor: Any?
        init(parent: ShortcutRecorder) { self.parent = parent }

        func start() {
            guard monitor == nil else { return }
            HotKeyManager.shared.suspend()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode
                let combo = KeyCombo(event: event)
                let consumed: Bool = MainActor.assumeIsolated {
                    guard let self else { return false }
                    if keyCode == 53 { // Escape cancels
                        self.parent.isRecording = false
                        return true
                    }
                    if let combo {
                        self.parent.onRecord(combo)
                        self.parent.isRecording = false
                        return true
                    }
                    return false
                }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if monitor != nil { HotKeyManager.shared.registerAll() }
            monitor = nil
        }
    }
}
