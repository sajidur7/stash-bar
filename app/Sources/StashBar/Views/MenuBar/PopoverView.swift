import SwiftUI
import AppKit
import SwiftData

/// 3h — the menu-bar popover: clipboard card, search + add, recent links, account footer.
struct PopoverView: View {
    @Query(filter: #Predicate<StashItem> { !$0.isArchived }, sort: \StashItem.createdAt, order: .reverse)
    private var items: [StashItem]

    @ObservedObject private var clipboard = ClipboardWatcher.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var sync = SyncService.shared
    @AppStorage(PrefKey.popoverCount) private var popoverCount = "10"
    @AppStorage(PrefKey.density) private var density = "Comfortable"
    @AppStorage(PrefKey.guestBannerDismissed) private var guestBannerDismissed = false

    @State private var query = ""
    @State private var selection = 0
    @State private var candidateTitle: String?
    @State private var copiedID: UUID?
    @FocusState private var searchFocused: Bool

    private var visible: [StashItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? items : items.filter { item in
            item.title.lowercased().contains(q) || item.url.lowercased().contains(q)
                || item.notes.lowercased().contains(q) || item.tags.contains { $0.lowercased().contains(q.replacingOccurrences(of: "#", with: "")) }
        }
        let sorted = base.filter(\.isPinned) + base.filter { !$0.isPinned }
        return Array(sorted.prefix(Int(popoverCount) ?? 10))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !auth.isSignedIn && Preferences.accountMode == "guest" && !guestBannerDismissed && clipboard.candidateUrl == nil {
                guestBanner
            }
            if sync.status == .offline { offlineBanner }
            if clipboard.candidateUrl != nil { clipboardCard }
            searchRow
            if items.isEmpty {
                emptyState
            } else if visible.isEmpty {
                noResults
            } else {
                Text("RECENT").caption11().frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == selection)
                            .onTapGesture { copy(item) }
                            .onHover { if $0 { selection = index } }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            footer
        }
        .frame(width: 380)
        .background(Theme.surface)
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidOpen)) { _ in
            query = ""
            selection = 0
            searchFocused = true
        }
        .onChange(of: clipboard.candidateUrl) { _, url in
            candidateTitle = nil
            guard let url else { return }
            Task { candidateTitle = await TitleFetcher.title(for: url) }
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .onExitCommand { StatusItemController.shared?.close() }
    }

    // MARK: Clipboard card

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SiteLogo(host: clipboard.candidateHost ?? "", size: 12, color: .white)
                Text("ON YOUR CLIPBOARD").font(.mono(11)).foregroundStyle(Theme.faint)
                Spacer()
                if !clipboard.removedTrackers.isEmpty {
                    SymbolIcon(Icon.shield, size: 12).foregroundStyle(.white).opacity(0.7)
                    Text("\(clipboard.removedTrackers.count) TRACKER\(clipboard.removedTrackers.count == 1 ? "" : "S") OFF")
                        .font(.mono(11)).foregroundStyle(Theme.faint)
                }
            }
            Text(candidateTitle ?? clipboard.candidateHost ?? "Link")
                .headline(18).foregroundStyle(.white).lineLimit(2)
            Text(displayURL(clipboard.candidateUrl ?? "")).font(.mono(12)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 8) {
                Button { Task { await clipboard.stashCandidate() } } label: {
                    HStack(spacing: 8) {
                        PinMark(color: Theme.onAccent).frame(width: 16, height: 16)
                        Text("Stash it")
                        SymbolIcon(Icon.returnKey, size: 13).opacity(0.55)
                    }
                }
                .stashButton(.primary, height: 40, fullWidth: true, radius: 10)

                Button { clipboard.dismissCandidate() } label: { SymbolIcon(Icon.close, size: 15) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x6D6C6B), lineWidth: 1))
                    .contentShape(Rectangle())
                    .help("Ignore this link")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).fill(Color(hex: 0x1A1919)))
        .padding(10)
    }

    // MARK: Search + add

    private var searchRow: some View {
        HStack(spacing: 8) {
            FieldBox(icon: Icon.search, height: 40) {
                TextField("Search \(items.count) link\(items.count == 1 ? "" : "s")", text: $query)
                    .stashField()
                    .focused($searchFocused)
                    .onSubmit { activateSelection(open: false) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        activateSelection(open: true)
                        return .handled
                    }
                HStack(spacing: 1) {
                    SymbolIcon(Icon.command, size: 10).opacity(0.6)
                    Text("E").font(.mono(11))
                }
                .foregroundStyle(Theme.muted)
                .help("⌘E opens the canvas")
            }
            Button { StatusItemController.shared?.close(); AppState.shared.presentAddLink() } label: {
                SymbolIcon(Icon.plus, size: 18).foregroundStyle(Theme.onAccent)
                    .frame(width: 56, height: 40)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .help("Add a link manually")
        }
        .padding(.horizontal, 10)
        .padding(.top, clipboard.candidateUrl == nil ? 10 : 0)
        .background {
            Button("") { WindowManager.shared.show(.canvas) }.keyboardShortcut("e", modifiers: .command).hidden()
        }
    }

    // MARK: Rows

    private func row(_ item: StashItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            SiteLogo(host: item.host, size: 15)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.paper))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.mono(13)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(copiedID == item.id ? "Copied" : "\(item.displayHost) · \(item.timeAgo)")
                    .font(.mono(11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isPinned { SymbolIcon(Icon.pinFill, size: 11).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, density == "Compact" ? 5 : 9)
        .background(RoundedRectangle(cornerRadius: Theme.rRow).fill(selected ? Theme.paper : .clear))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy link") { copy(item) }
            Button("Open") { LinkStore.shared.open(item) }
            Button(item.isPinned ? "Unpin" : "Pin to top") { LinkStore.shared.setPinned(item, !item.isPinned) }
            Button("Archive") { LinkStore.shared.archive(item) }
        }
    }

    // MARK: Empty, banners, footer

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            PinMark().frame(width: 24, height: 24)
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
            Text("Nothing stashed yet.").headline(22).foregroundStyle(Theme.ink)
            Text(auth.isSignedIn
                 ? "Copy any link and press ⌥S. It’ll be waiting here — and on every Mac you sign in to."
                 : "Copy any link and press ⌥S. Links you stash stay on this Mac. Sign in anytime to back them up.")
                .font(.mono(13)).lineSpacing(4).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { StatusItemController.shared?.close(); AppState.shared.presentAddLink() } label: {
                    Label { Text("Paste a URL") } icon: { SymbolIcon(Icon.link, size: 14) }
                }.stashButton(.primary, height: 42, fullWidth: true, radius: 10)
                Button { Task { _ = await BookmarkIO.runImport() } } label: { Text("Import") }
                    .stashButton(.outline, height: 42, fullWidth: true, radius: 10)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            SymbolIcon(Icon.searchX, size: 22).frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
            Text("No links match “\(query)”.").headline(18).foregroundStyle(Theme.ink)
            Text("Try a site name like figma.com, or a #tag.").font(.mono(13)).foregroundStyle(Theme.muted)
            Button { query = "" } label: { Label { Text("Clear search") } icon: { SymbolIcon(Icon.eraser, size: 14) } }
                .stashButton(.primary, height: 40, radius: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private var guestBanner: some View {
        HStack(spacing: 10) {
            SymbolIcon(Icon.hardDrive, size: 14).foregroundStyle(.white)
            Text("Guest · saved on this Mac only").font(.mono(12)).foregroundStyle(.white)
            Spacer()
            Button("Sign in") { AppState.shared.openSettings(.account) }.buttonStyle(.plain).font(.mono(12)).foregroundStyle(Theme.accent)
            Button { guestBannerDismissed = true } label: { SymbolIcon(Icon.close, size: 10) }.buttonStyle(.plain).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: 0x1A1919))
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            SymbolIcon(Icon.cloudOff, size: 14).foregroundStyle(.white)
            Text("Offline · changes sync when you’re back").font(.mono(12)).foregroundStyle(.white)
            Spacer()
            Button("Retry") { Task { await SyncService.shared.syncNow() } }.buttonStyle(.plain).font(.mono(12)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: 0x1A1919))
    }

    private var footer: some View {
        HStack {
            Button { AppState.shared.openSettings(.account) } label: {
                HStack(spacing: 8) {
                    AvatarView(size: 20)
                    Text(statusText).font(.mono(12)).foregroundStyle(Theme.muted)
                }
            }.buttonStyle(.plain)
            Spacer()
            HStack(spacing: 14) {
                Button { WindowManager.shared.show(.canvas) } label: { SymbolIcon(Icon.grid, size: 15) }
                    .buttonStyle(.plain).help("Open canvas (⌘E)")
                Button { AppState.shared.openSettings(.general) } label: { SymbolIcon(Icon.settings, size: 15) }
                    .buttonStyle(.plain).help("Settings (⌘,)")
            }
            .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var statusText: String {
        guard auth.isSignedIn else { return "Guest · this Mac" }
        switch sync.status {
        case .syncing: return "Syncing…"
        case .offline: return "Offline"
        case .error: return "Sync paused"
        case .idle: return "Synced"
        }
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        selection = max(0, min(visible.count - 1, selection + delta))
    }

    private func activateSelection(open: Bool) {
        if !open, clipboard.candidateUrl != nil, query.isEmpty {
            Task { await clipboard.stashCandidate() }
            return
        }
        guard visible.indices.contains(selection) else { return }
        let item = visible[selection]
        if open {
            LinkStore.shared.open(item)
            StatusItemController.shared?.close()
        } else {
            copy(item)
        }
    }

    private func copy(_ item: StashItem) {
        LinkStore.shared.copy(item)
        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { StatusItemController.shared?.close(); copiedID = nil }
    }

    private func displayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: "")
    }
}

/// Fetches just a page title for the clipboard card (first 50 KB, no images).
enum TitleFetcher {
    static func title(for urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let fetched = try? await URLSession.shared.bytes(for: request) else { return nil }
        let (bytes, response) = fetched
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 50_000 { break }
            }
        } catch { return nil }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var result = MetadataResult()
        MetadataParser.parseHead(html: html, baseURL: response.url ?? url, result: &result)
        return result.title
    }
}
