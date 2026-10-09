import SwiftUI
import AppKit
import SwiftData

/// 3i / 3pa / 3pb / 3r / 3u — the full window (⌘E).
struct CanvasRootView: View {
    @Query(sort: \StashItem.createdAt, order: .reverse) private var allItems: [StashItem]
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var sync = SyncService.shared
    @AppStorage(PrefKey.guestBannerDismissed) private var guestBannerDismissed = false

    @State private var query = ""
    @State private var pendingDelete: StashItem?

    private var live: [StashItem] { allItems.filter { !$0.isArchived } }

    var body: some View {
        ZStack {
            if let id = state.selectedLinkID, let item = allItems.first(where: { $0.id == id }) {
                LinkDetailView(item: item, onBack: { state.selectedLinkID = nil }, onDelete: { pendingDelete = item })
            } else {
                HStack(spacing: 0) {
                    CanvasSidebar(items: allItems)
                        .frame(width: 220)
                    main
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Theme.surface)
        .ignoresSafeArea()
        .modalOverlay(state.showAddLink, onDismiss: { state.showAddLink = false }) {
            AddLinkSheet(prefill: state.addLinkPrefill) { state.showAddLink = false }
        }
        .modalOverlay(pendingDelete != nil, onDismiss: { pendingDelete = nil }) {
            if let item = pendingDelete { deleteDialog(item) }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Text(toast).font(.mono(13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1A1919)))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.showAddLink)
        .animation(.easeOut(duration: 0.2), value: state.toast)
    }

    // MARK: Main column

    private var main: some View {
        VStack(spacing: 0) {
            if !auth.isSignedIn && !guestBannerDismissed && !allItems.isEmpty { guestBanner }
            if auth.isSignedIn && sync.status == .offline { offlineBanner }
            topBar.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            FieldBox(icon: Icon.search, height: 42) {
                if case .tag(let t) = state.canvasView { token("#\(t)") }
                if state.canvasView == .pinned { token("pinned") }
                if state.canvasView == .archive { token("archive") }
                TextField(allItems.isEmpty ? "Nothing to search yet" : searchPlaceholder, text: $query).stashField()
                    .disabled(allItems.isEmpty)
            }
            .padding(.leading, 0)
            Menu {
                ForEach(BookmarkIO.Format.allCases, id: \.self) { f in
                    Button(f.rawValue) { BookmarkIO.export(f, items: allItems) }
                }
            } label: {
                Label { Text("Export") } icon: { SymbolIcon(Icon.share, size: 15) }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.mono(13))
            .padding(.horizontal, 16).frame(height: 42)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(allItems.isEmpty ? Theme.hairline : Theme.ink, lineWidth: 1.5))
            .disabled(allItems.isEmpty)
            .opacity(allItems.isEmpty ? 0.6 : 1)

            Button { state.presentAddLink() } label: {
                Label { Text("Add link") } icon: { SymbolIcon(Icon.plus, size: 15) }
            }
            .stashButton(.primary, height: 42)
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func token(_ text: String) -> some View {
        Text(text).font(.mono(12)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.charcoal))
            .onTapGesture { state.canvasView = .all }
            .help("Clear filter")
    }

    private var searchPlaceholder: String {
        switch state.canvasView {
        case .pinned: return "Search pinned"
        case .archive: return "Search archive"
        default: return "Search titles, sites, notes"
        }
    }

    private func matches(_ item: StashItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return item.title.lowercased().contains(q) || item.url.lowercased().contains(q)
            || item.notes.lowercased().contains(q) || item.tags.contains { $0.lowercased().contains(q) }
    }

    private var filtered: [StashItem] {
        let base: [StashItem]
        switch state.canvasView {
        case .all: base = live
        case .pinned: base = live.filter(\.isPinned)
        case .unopened: base = live.filter { $0.openedAt == nil }
        case .archive: base = allItems.filter(\.isArchived).sorted { ($0.archivedAt ?? $0.createdAt) > ($1.archivedAt ?? $1.createdAt) }
        case .tag(let t): base = live.filter { $0.tags.contains(t) }
        }
        let result = base.filter(matches)
        if state.canvasView == .all { return result.filter(\.isPinned) + result.filter { !$0.isPinned } }
        return result
    }

    @ViewBuilder
    private var content: some View {
        if allItems.isEmpty {
            if auth.isSignedIn { EmptyCanvasSignedIn() } else { EmptyCanvasGuest() }
        } else if filtered.isEmpty {
            emptyForView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if state.canvasView == .archive {
                        archiveList
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 14)], spacing: 14) {
                            ForEach(filtered) { item in
                                LinkCard(item: item, showPinBadge: state.canvasView == .pinned || item.isPinned,
                                         compactHeader: state.canvasView == .pinned,
                                         onOpen: { state.selectedLinkID = item.id },
                                         onDelete: { pendingDelete = item })
                            }
                        }
                        .padding(.horizontal, 24).padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            switch state.canvasView {
            case .all:
                Text("All links").headline(36)
                Spacer()
                Text("\(filtered.count) · newest first").font(.mono(12)).foregroundStyle(Theme.muted)
            case .pinned:
                Text("Pinned").headline(22)
                Text("Always on top").font(.mono(13)).foregroundStyle(Theme.muted)
                Spacer()
            case .unopened:
                Text("Unopened").headline(36)
                Spacer()
                Text("\(filtered.count) never opened").font(.mono(12)).foregroundStyle(Theme.muted)
            case .archive:
                Text("Archive").headline(22)
                Text("Hidden, not deleted").font(.mono(13)).foregroundStyle(Theme.muted)
                Spacer()
            case .tag(let t):
                Text("#\(t)").headline(36)
                Spacer()
                Text("\(filtered.count) link\(filtered.count == 1 ? "" : "s")").font(.mono(12)).foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
    }

    private var archiveList: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                SymbolIcon(Icon.info, size: 14)
                Text("Archived links are hidden from search and the popover. Restore puts them back in All links.")
                    .font(.mono(13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.rRow).fill(Theme.paper))

            ForEach(filtered) { item in
                HStack(spacing: 12) {
                    SiteLogo(host: item.host, size: 17)
                        .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 10).fill(Theme.paper))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.mono(13)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("\(item.displayHost) · archived \(RelativeTime.ago(item.archivedAt ?? item.updatedAt))")
                            .font(.mono(11)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Button { LinkStore.shared.restore(item) } label: {
                        Label { Text("Restore") } icon: { SymbolIcon(Icon.restore, size: 14) }
                    }
                    .stashButton(.primary, height: 36)
                    IconSquareButton(Icon.trash, size: 36, iconSize: 14, help: "Delete forever") { pendingDelete = item }
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { state.selectedLinkID = item.id }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    @ViewBuilder
    private var emptyForView: some View {
        if !query.isEmpty {
            EmptyStateCard(icon: Icon.searchX, title: "No links match “\(query)”.",
                           body: "Try a site name like figma.com, or include notes in your search.",
                           primary: ("Clear search", Icon.eraser, { query = "" }))
        } else {
            switch state.canvasView {
            case .pinned:
                EmptyStateCard(icon: Icon.pin, title: "No favourites pinned.",
                               body: "Press ⌘P on any link to keep it at the top of the popover.",
                               secondary: ("Show all links", { state.canvasView = .all }))
            case .archive:
                EmptyStateCard(icon: Icon.archive, title: "Archive is clear.",
                               body: "Links you archive rest here. Restore them anytime.",
                               secondary: ("Back to stash", { state.canvasView = .all }))
            case .tag(let t):
                EmptyStateCard(icon: Icon.hash, title: "Nothing tagged #\(t) yet.",
                               body: "Add tags while stashing, or from a link’s detail view.",
                               primary: ("Browse all links", Icon.library, { state.canvasView = .all }))
            case .unopened:
                EmptyStateCard(icon: Icon.check, title: "You’ve opened everything.",
                               body: "Links you stash but never open collect here.",
                               secondary: ("Show all links", { state.canvasView = .all }))
            case .all:
                EmptyStateCard(icon: Icon.archive, title: "Everything is archived.",
                               body: "Restore links from the Archive to see them here.",
                               secondary: ("Open archive", { state.canvasView = .archive }))
            }
        }
    }

    private var guestBanner: some View {
        HStack(spacing: 10) {
            SymbolIcon(Icon.hardDrive, size: 14)
            Text("Guest · saved on this Mac only").font(.mono(12))
            Spacer()
            Button("Sign in") { AppState.shared.openSettings(.account) }.buttonStyle(.plain).font(.mono(12)).foregroundStyle(Theme.accent)
            Button { guestBannerDismissed = true } label: { SymbolIcon(Icon.close, size: 10) }.buttonStyle(.plain).foregroundStyle(Theme.faint)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10).padding(.top, 22)
        .background(Color(hex: 0x1A1919))
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            SymbolIcon(Icon.cloudOff, size: 14)
            Text("Offline · changes sync when you’re back").font(.mono(12))
            Spacer()
            Button("Retry") { Task { await SyncService.shared.syncNow() } }.buttonStyle(.plain).font(.mono(12)).foregroundStyle(Theme.accent)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10).padding(.top, 22)
        .background(Color(hex: 0x1A1919))
    }

    private func deleteDialog(_ item: StashItem) -> some View {
        ModalCard {
            DialogIcon(Icon.trash)
            DialogTitle("Delete this link?", "“\(item.title)” will be removed\(auth.isSignedIn ? " from every Mac" : "") and can’t be restored. Archive it instead to hide it but keep it.")
            HStack(spacing: 10) {
                Button("Cancel") { pendingDelete = nil }.stashButton(.outline, fullWidth: true)
                if !item.isArchived {
                    Button("Archive") { LinkStore.shared.archive(item); pendingDelete = nil }.stashButton(.soft, fullWidth: true)
                }
                Button("Delete") {
                    if state.selectedLinkID == item.id { state.selectedLinkID = nil }
                    LinkStore.shared.delete(item)
                    pendingDelete = nil
                }
                .stashButton(.dark, fullWidth: true)
            }
        }
    }
}

// MARK: - Sidebar

struct CanvasSidebar: View {
    let items: [StashItem]
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var sync = SyncService.shared

    private var live: [StashItem] { items.filter { !$0.isArchived } }

    private var tags: [(String, Int)] {
        var counts: [String: Int] = [:]
        for i in live { for t in i.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(12).map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                PinMark(color: .white).frame(width: 20, height: 20)
                Text("Stashbar").headline(18)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.top, 34)

            VStack(spacing: 2) {
                navRow("All links", Icon.library, live.count, .all)
                navRow("Pinned", Icon.pin, live.filter(\.isPinned).count, .pinned)
                navRow("Unopened", Icon.unopened, live.filter { $0.openedAt == nil }.count, .unopened)
                navRow("Archive", Icon.archive, items.filter(\.isArchived).count, .archive)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TAGS").font(.mono(11)).foregroundStyle(Theme.faint).padding(.horizontal, 12).padding(.bottom, 6)
                if tags.isEmpty {
                    Text("Tags appear here once you add them.").font(.mono(13)).lineSpacing(4).foregroundStyle(Theme.faint)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(tags, id: \.0) { tag, count in
                        let on = state.canvasView == .tag(tag)
                        HStack(spacing: 10) {
                            SymbolIcon(Icon.hash, size: 13).opacity(on ? 1 : 0.6)
                            Text(tag).font(.mono(13)).lineLimit(1)
                            Spacer()
                            Text("\(count)").font(.mono(11)).foregroundStyle(on ? Theme.onAccent : Theme.faint)
                        }
                        .foregroundStyle(on ? Theme.onAccent : .white)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.accent : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { state.canvasView = .tag(tag); state.selectedLinkID = nil }
                    }
                }
            }

            Spacer(minLength: 0)
            accountCard
        }
        .padding(.horizontal, 12).padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x1A1919))
    }

    private func navRow(_ label: String, _ icon: String, _ count: Int, _ view: AppState.CanvasView) -> some View {
        let on = state.canvasView == view
        return HStack(spacing: 10) {
            SymbolIcon(icon, size: 15)
            Text(label).font(on ? .monoMedium(13) : .mono(13))
            Spacer()
            Text("\(count)").font(.mono(11)).opacity(0.7)
        }
        .foregroundStyle(on ? Theme.onAccent : .white)
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.accent : .clear))
        .contentShape(Rectangle())
        .onTapGesture { state.canvasView = view; state.selectedLinkID = nil }
    }

    @ViewBuilder
    private var accountCard: some View {
        if let s = auth.session {
            Button { AppState.shared.openSettings(.account) } label: {
                HStack(spacing: 10) {
                    AvatarView(size: 30, onCharcoal: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).font(.mono(13)).foregroundStyle(.white).lineLimit(1)
                        Text(syncLine).font(.mono(11)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Color(hex: 0x2A2828)))
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    AvatarView(size: 30, onCharcoal: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Guest").font(.mono(13)).foregroundStyle(.white)
                        Text("this Mac only").font(.mono(11)).foregroundStyle(Theme.faint)
                    }
                    Spacer(minLength: 0)
                }
                Button("Sign in to back up") { AppState.shared.openSettings(.account) }
                    .stashButton(.primary, height: 34, fullWidth: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Color(hex: 0x2A2828)))
        }
    }

    private var syncLine: String {
        switch sync.status {
        case .syncing: return "syncing…"
        case .offline: return "offline · will retry"
        case .error: return "sync paused"
        case .idle: return sync.lastSyncedAt.map { "synced · \(RelativeTime.ago($0))" } ?? "not synced yet"
        }
    }
}

// MARK: - Card

struct LinkCard: View {
    let item: StashItem
    var showPinBadge = false
    var compactHeader = false
    let onOpen: () -> Void
    let onDelete: () -> Void
    @AppStorage(PrefKey.showPreviews) private var showPreviews = true
    @AppStorage(PrefKey.density) private var density = "Comfortable"
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                preview
                    .frame(height: compactHeader ? 80 : (density == "Compact" ? 72 : 96))
                    .frame(maxWidth: .infinity)
                    .clipped()
                if showPinBadge {
                    SymbolIcon(Icon.pinFill, size: 12).foregroundStyle(Theme.onAccent)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.mono(13)).lineSpacing(2).foregroundStyle(Theme.ink)
                    .lineLimit(2).frame(minHeight: 34, alignment: .topLeading)
                HStack(spacing: 6) {
                    Text("\(item.displayHost) · \(item.timeAgo)").font(.mono(11)).foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    IconSquareButton(Icon.archive, help: "Archive") { LinkStore.shared.archive(item) }
                    IconSquareButton(Icon.trash, help: "Delete") { onDelete() }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
            .strokeBorder(hover ? Theme.ink.opacity(0.35) : Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Open in browser") { LinkStore.shared.open(item) }
            Button("Copy link") { LinkStore.shared.copy(item) }
            Button(item.isPinned ? "Unpin" : "Pin to top") { LinkStore.shared.setPinned(item, !item.isPinned) }
            Divider()
            Button("Archive") { LinkStore.shared.archive(item) }
            Button("Delete…") { onDelete() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if showPreviews, let data = item.ogImageData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                (item.host.count % 3 == 0 ? Theme.hairline : Theme.paper)
                SiteLogo(host: item.host, size: compactHeader ? 26 : 30)
            }
        }
    }
}

// MARK: - Empty states

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let body_: String
    var primary: (String, String, () -> Void)?
    var secondary: (String, () -> Void)?

    init(icon: String, title: String, body: String, primary: (String, String, () -> Void)? = nil, secondary: (String, () -> Void)? = nil) {
        self.icon = icon; self.title = title; self.body_ = body; self.primary = primary; self.secondary = secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SymbolIcon(icon, size: 24).foregroundStyle(Theme.ink)
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
            Text(title).headline(28).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text(body_).font(.mono(13)).lineSpacing(4).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let primary {
                    Button(action: primary.2) { Label { Text(primary.0) } icon: { SymbolIcon(primary.1, size: 14) } }
                        .stashButton(.primary, height: 42, radius: 10)
                }
                if let secondary {
                    Button(secondary.0, action: secondary.1).stashButton(.outline, height: 42, radius: 10)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

/// 3u — signed in, nothing stashed yet.
struct EmptyCanvasSignedIn: View {
    @ObservedObject private var auth = AuthService.shared
    var body: some View {
        VStack(spacing: 22) {
            AppIconView(.accent, size: 96)
            VStack(spacing: 10) {
                Text("No links stashed yet.").headline(36).foregroundStyle(Theme.ink)
                Text("Copy a link anywhere and press ⌥S. Links you stash on any Mac signed in as \(auth.session?.name.components(separatedBy: " ").first ?? "you") show up here.")
                    .font(.mono(16)).lineSpacing(6).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .frame(maxWidth: 460).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { AppState.shared.presentAddLink() } label: { Label { Text("Paste a URL") } icon: { SymbolIcon(Icon.link, size: 15) } }
                    .stashButton(.primary, height: 46, fontSize: 14).frame(width: 190)
                Button { Task { await runImport() } } label: { Label { Text("Import bookmarks") } icon: { SymbolIcon(Icon.importIcon, size: 15) } }
                    .stashButton(.outline, height: 46, fontSize: 14).frame(width: 190)
            }
            HStack(spacing: 8) {
                Text("Quick stash from any app").font(.mono(13)).foregroundStyle(Theme.muted)
                KeyCap("S", symbol: Icon.option, size: 24, fontSize: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .padding(.horizontal, 24).padding(.bottom, 24)
    }
}

/// 3r — guest, nothing stashed yet.
struct EmptyCanvasGuest: View {
    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 18) {
                PinMark().frame(width: 56, height: 56)
                Text("Your canvas is waiting.").headline(44).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text("Pinned links show up here as cards, sorted by when you saved them. Three ways to add your first:")
                    .font(.mono(14)).lineSpacing(5).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                way(Icon.copy, "Copy a link, then press ⌥S", "From any app — it’s pinned in one keystroke", "⌥S", Theme.paper) {
                    StatusItemController.shared?.open()
                }
                way(Icon.link, "Paste a URL", "Drop an address straight in", "⌘V", Theme.accent) {
                    AppState.shared.presentAddLink(prefill: NSPasteboard.general.string(forType: .string) ?? "")
                }
                way(Icon.importIcon, "Import bookmarks", "Safari, Chrome, Arc or an HTML file", "Import", Theme.hairline) {
                    Task { await runImport() }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func way(_ icon: String, _ title: String, _ hint: String, _ key: String, _ bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SymbolIcon(icon, size: 18).foregroundStyle(Color(hex: 0x0C0A08))
                    .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.mono(14)).foregroundStyle(bg == Theme.accent ? Theme.onAccent : Theme.ink)
                    Text(hint).font(.mono(13)).foregroundStyle(bg == Theme.accent ? Color(hex: 0x2A2828) : Theme.muted)
                }
                Spacer(minLength: 4)
                Text(key).font(.mono(12)).foregroundStyle(Color(hex: 0x0C0A08))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xE5E7EB), lineWidth: 1))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(bg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
func runImport() async {
    if let added = await BookmarkIO.runImport() {
        AppState.shared.showToast(added == 0 ? "No new links found in that file." : "Imported \(added) link\(added == 1 ? "" : "s").")
    }
}
