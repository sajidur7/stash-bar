import SwiftUI
import AppKit

/// 3y — opened from a canvas card: preview on the left, details on the right (400 wide).
struct LinkDetailView: View {
    @Bindable var item: StashItem
    let onBack: () -> Void
    let onDelete: () -> Void

    @AppStorage(PrefKey.showPreviews) private var showPreviews = true
    @State private var addingTag = false
    @State private var newTag = ""
    @State private var editingTitle = false
    @State private var copied = false
    @FocusState private var tagFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            previewPane
            detailPane.frame(width: 400)
        }
        .background(Theme.surface)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    SymbolIcon(Icon.arrowLeft, size: 14)
                    Text(item.isArchived ? "Archive" : "All links").font(.monoMedium(13))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .padding(.leading, 90).padding(.top, 14).padding(.bottom, 14)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).fill(Color(hex: 0x1A1919))
                if showPreviews, let data = item.ogImageData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SiteLogo(host: item.host, size: 56, color: .white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("page preview · \(item.displayHost)").font(.mono(12)).foregroundStyle(Theme.faint)
                    .padding(.leading, 18).padding(.bottom, 16)
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionLabel("Link detail")
                    Spacer()
                    IconSquareButton(item.isPinned ? Icon.pinFill : Icon.pin, size: 32, iconSize: 14, help: item.isPinned ? "Unpin (⌘P)" : "Pin to top (⌘P)") {
                        LinkStore.shared.setPinned(item, !item.isPinned)
                    }
                    .keyboardShortcut("p", modifiers: .command)
                    if item.isArchived {
                        IconSquareButton(Icon.restore, size: 32, iconSize: 14, help: "Restore") { LinkStore.shared.restore(item) }
                    } else {
                        IconSquareButton(Icon.archive, size: 32, iconSize: 14, help: "Archive (⌘⌫)") { LinkStore.shared.archive(item); onBack() }
                            .keyboardShortcut(.delete, modifiers: .command)
                    }
                    IconSquareButton(Icon.trash, size: 32, iconSize: 14, help: "Delete…", action: onDelete)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if editingTitle {
                        TextField("Title", text: Binding(get: { item.title }, set: { item.title = $0 }))
                            .textFieldStyle(.plain).headline(28)
                            .onSubmit { editingTitle = false; LinkStore.shared.update(item) { _ in } }
                    } else {
                        Text(item.title).headline(28).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            .onTapGesture(count: 2) { editingTitle = true }
                            .help("Double-click to rename")
                    }
                    HStack(spacing: 8) {
                        SiteLogo(host: item.host, size: 13)
                        Text("\(item.displayHost) · stashed \(RelativeTime.ago(item.createdAt))").font(.mono(13)).foregroundStyle(Theme.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel("Clean URL")
                        Spacer()
                        if !item.removedTrackers.isEmpty {
                            HStack(spacing: 5) {
                                SymbolIcon(Icon.shield, size: 12)
                                Text("\(item.removedTrackers.count) TRACKER\(item.removedTrackers.count == 1 ? "" : "S") REMOVED").font(.mono(11))
                            }
                            .foregroundStyle(Theme.muted)
                        }
                    }
                    Text(item.url).font(.mono(13)).lineSpacing(3).foregroundStyle(Theme.ink).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Theme.rRow).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(Theme.hairline, lineWidth: 1))
                    if !item.removedTrackers.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(item.removedTrackers, id: \.self) { t in
                                Text(t).font(.mono(11)).strikethrough().foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 9).frame(height: 24)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.paper))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Tags")
                    FlowLayout(spacing: 6) {
                        ForEach(item.tags, id: \.self) { tag in
                            TagChip(tag) { LinkStore.shared.update(item) { $0.tags.removeAll { $0 == tag } } }
                        }
                        if addingTag {
                            TextField("tag", text: $newTag)
                                .textFieldStyle(.plain).font(.mono(13)).frame(width: 100)
                                .padding(.horizontal, 12).frame(height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: 1.5))
                                .focused($tagFocused)
                                .onSubmit(commitTag)
                                .onExitCommand { addingTag = false; newTag = "" }
                        } else {
                            Button { addingTag = true; tagFocused = true } label: {
                                HStack(spacing: 4) { SymbolIcon(Icon.plus, size: 12); Text("Tag").font(.mono(13)) }
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 12).frame(height: 28)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xA3A2A1), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Note")
                    ZStack(alignment: .topLeading) {
                        if item.notes.isEmpty {
                            Text("Add a note…").font(.mono(13)).foregroundStyle(Theme.muted).padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        TextEditor(text: Binding(get: { item.notes }, set: { item.notes = $0; item.touch() }))
                            .font(.mono(13)).scrollContentBackground(.hidden)
                            .padding(.horizontal, 9).padding(.vertical, 8)
                            .frame(minHeight: 80)
                    }
                    .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(Theme.hairline, lineWidth: 1))
                }

                HStack(spacing: 10) {
                    Button {
                        LinkStore.shared.copy(item)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label { Text(copied ? "Copied" : "Copy link") } icon: { SymbolIcon(copied ? Icon.check : Icon.copy, size: 14) }
                    }
                    .stashButton(.primary, fullWidth: true)
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                    Button { LinkStore.shared.open(item) } label: {
                        Label { Text("Open") } icon: { SymbolIcon(Icon.arrowUpRight, size: 14) }
                    }
                    .stashButton(.outline, fullWidth: true)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 26).padding(.top, 38).padding(.bottom, 24)
        }
        .onDisappear { try? LinkStore.shared.context.save(); SyncService.shared.scheduleSync() }
    }

    private func commitTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").lowercased()
        if !tag.isEmpty, !item.tags.contains(tag) {
            LinkStore.shared.update(item) { $0.tags.append(tag) }
        }
        newTag = ""
        addingTag = false
    }
}
