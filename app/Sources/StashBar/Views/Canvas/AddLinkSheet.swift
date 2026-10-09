import SwiftUI
import AppKit

/// 3z — "Add link" / "Paste a URL": live tracker preview, fetched title, tags.
struct AddLinkSheet: View {
    let prefill: String
    let onClose: () -> Void

    @State private var text = ""
    @State private var title: String?
    @State private var fetching = false
    @State private var selectedTags: Set<String> = []
    @State private var newTag = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    private var clean: String? { URLSanitizer.sanitizeWithPreferences(text) }
    private var removed: [String] {
        Preferences.stripTrackers ? URLSanitizer.removedParameters(from: text, parameters: URLSanitizer.activeParameters) : []
    }
    private var suggestions: [String] {
        let existing = LinkStore.shared.allTags.map(\.tag)
        let base = existing.isEmpty ? ["reading", "design", "tools"] : Array(existing.prefix(6))
        return Array(Set(base).union(selectedTags)).sorted()
    }

    var body: some View {
        ModalCard(width: 460) {
            HStack(alignment: .top) {
                Text("Add a link").headline(28).foregroundStyle(Theme.ink)
                Spacer()
                IconSquareButton(Icon.close, size: 32, iconSize: 14, filled: true, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("URL")
                HStack(spacing: 10) {
                    SymbolIcon(Icon.link, size: 14)
                    TextField("https://", text: $text).stashField().focused($focused)
                        .onSubmit { Task { await save() } }
                }
                .padding(.horizontal, 14).frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(Theme.ink, lineWidth: 1.5))
                if !text.isEmpty && clean == nil {
                    Text("That’s not a link. Stashbar only pins web addresses.").font(.mono(12)).foregroundStyle(Theme.muted)
                } else if !removed.isEmpty {
                    HStack(spacing: 6) {
                        SymbolIcon(Icon.shield, size: 13)
                        Text("\(removed.count) tracker\(removed.count == 1 ? "" : "s") will be removed: \(removed.joined(separator: ", "))")
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .font(.mono(12)).foregroundStyle(Theme.muted)
                }
            }

            if let clean {
                HStack(spacing: 12) {
                    SiteLogo(host: URLSanitizer.cleanHost(from: clean) ?? "", size: 17)
                        .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title ?? (fetching ? "Fetching title…" : URLSanitizer.cleanHost(from: clean) ?? clean))
                            .font(.mono(13)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("\(URLSanitizer.cleanHost(from: clean) ?? "") · \(title == nil ? (fetching ? "loading" : "title on save") : "title fetched")")
                            .font(.mono(11)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Tags")
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        TagChip(tag, selected: selectedTags.contains(tag))
                            .onTapGesture {
                                if selectedTags.contains(tag) { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                            }
                    }
                    TextField("+ tag", text: $newTag)
                        .textFieldStyle(.plain).font(.mono(13)).frame(width: 80)
                        .padding(.horizontal, 12).frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xA3A2A1), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .onSubmit {
                            let t = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").lowercased()
                            if !t.isEmpty { selectedTags.insert(t) }
                            newTag = ""
                        }
                }
            }

            if let error { Text(error).font(.mono(12)).foregroundStyle(Theme.muted) }

            HStack(spacing: 10) {
                Button("Cancel", action: onClose).stashButton(.outline, fullWidth: true)
                Button { Task { await save() } } label: {
                    HStack(spacing: 8) {
                        PinMark(color: Theme.onAccent).frame(width: 15, height: 15)
                        Text(saving ? "Stashing…" : "Stash it")
                    }
                }
                .stashButton(.primary, fullWidth: true)
                .disabled(clean == nil || saving)
                .opacity(clean == nil ? 0.5 : 1)
            }
            .padding(.top, 4)
        }
        .onAppear {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            text = !prefill.isEmpty ? prefill : (URLSanitizer.isValidUrl(clip) ? clip.trimmingCharacters(in: .whitespacesAndNewlines) : "")
            focused = true
        }
        .task(id: clean) {
            title = nil
            guard let clean else { return }
            fetching = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let fetched = await TitleFetcher.title(for: clean)
            if !Task.isCancelled { title = fetched }
            fetching = false
        }
    }

    private func save() async {
        guard clean != nil, !saving else { return }
        saving = true
        defer { saving = false }
        if let item = await LinkStore.shared.stash(rawURL: text, title: title, tags: Array(selectedTags).sorted()) {
            AppState.shared.showToast("Stashed “\(item.title)”")
            onClose()
        } else {
            error = "Couldn’t save that link."
        }
    }
}
