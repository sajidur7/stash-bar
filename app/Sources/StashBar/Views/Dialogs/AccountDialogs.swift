import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 3w — "Sign out of Stashbar?" with keep/remove choice.
struct SignOutDialog: View {
    @Binding var dialog: SettingsView.AccountDialog?
    @State private var keepLocal = true
    @State private var working = false

    var body: some View {
        let count = LinkStore.shared.count
        ModalCard {
            DialogIcon(Icon.logout)
            DialogTitle("Sign out of Stashbar?", "Your \(count) links are safe in your account. Choose what stays on this Mac:")
            VStack(spacing: 8) {
                option("Keep a local copy", "Continue as a guest with these links", selected: keepLocal) { keepLocal = true }
                option("Remove from this Mac", "Start empty. Sign in again to restore everything", selected: !keepLocal) { keepLocal = false }
            }
            HStack(spacing: 10) {
                Button("Cancel") { dialog = nil }.stashButton(.outline, fullWidth: true)
                Button(working ? "Signing out…" : "Sign out") {
                    working = true
                    Task {
                        await SyncService.shared.syncNow() // push anything pending first
                        await AuthService.shared.signOut(keepLocal: keepLocal)
                        ProfileStore.shared.reset()
                        dialog = .signedOut(keepLocal ? count : 0)
                    }
                }
                .stashButton(.primary, fullWidth: true)
                .disabled(working)
            }
        }
    }

    private func option(_ title: String, _ hint: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(selected ? Theme.ink : Color(hex: 0xA3A2A1), lineWidth: 1.5)
                    .overlay(Circle().fill(selected ? Theme.ink : .clear).padding(4.5))
                    .frame(width: 18, height: 18).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.mono(13)).foregroundStyle(Theme.ink)
                    Text(hint).font(.mono(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(selected ? Theme.paper : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(selected ? Theme.ink : Theme.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 3wa — after sign-out.
struct SignedOutDialog: View {
    let count: Int
    @Binding var dialog: SettingsView.AccountDialog?

    var body: some View {
        ModalCard {
            DialogIcon(Icon.check, bordered: true)
            DialogTitle("You’re signed out.", count > 0
                        ? "Your \(count) links stayed on this Mac. You’re now using Stashbar as a guest."
                        : "Links were removed from this Mac. Sign in again to bring them back.")
            HStack(spacing: 12) {
                SymbolIcon(Icon.hardDrive, size: 16)
                Text("Guest mode: links aren’t backed up until you sign in again.").font(.mono(13)).lineSpacing(3)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))
            HStack(spacing: 10) {
                Button("Sign in again") { dialog = nil; AppState.shared.settingsSection = .account }.stashButton(.outline, fullWidth: true)
                Button("Done") { dialog = nil }.stashButton(.primary, fullWidth: true)
            }
        }
    }
}

/// 3wb — delete account safety check.
struct DeleteAccountDialog: View {
    @Binding var dialog: SettingsView.AccountDialog?
    @ObservedObject private var sync = SyncService.shared
    @State private var understood = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        let count = LinkStore.shared.count
        let macs = max(sync.devices.count, 1)
        ModalCard {
            DialogIcon(Icon.alert, dark: true)
            DialogTitle("Delete your account?", "This permanently removes your account and all \(count) links from every Mac. It can’t be undone.")
            VStack(alignment: .leading, spacing: 6) {
                bullet("Links, tags and notes")
                bullet("Sync on \(macs) Mac\(macs == 1 ? "" : "s")")
                bullet("Your Apple / Google sign-in link")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(Theme.paper))

            Button { BookmarkIO.export(.json, items: LinkStore.shared.all()) } label: {
                HStack(spacing: 8) {
                    SymbolIcon(Icon.download, size: 14)
                    Text("Export my links first").font(.mono(13)).underline()
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button { understood.toggle() } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(understood ? Theme.charcoal : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: 1.5))
                        .overlay(SymbolIcon(Icon.check, size: 13).foregroundStyle(.white).opacity(understood ? 1 : 0))
                        .frame(width: 20, height: 20)
                    Text("I understand this is permanent").font(.mono(13)).foregroundStyle(Theme.ink)
                }
            }
            .buttonStyle(.plain)

            if let error { Text(error).font(.mono(12)).foregroundStyle(Theme.muted) }

            HStack(spacing: 10) {
                Button("Cancel") { dialog = nil }.stashButton(.outline, fullWidth: true)
                Button(working ? "Deleting…" : "Delete account") {
                    working = true
                    Task {
                        do {
                            try await AuthService.shared.deleteAccount()
                            dialog = .accountDeleted
                        } catch {
                            self.error = error.localizedDescription
                        }
                        working = false
                    }
                }
                .stashButton(.dark, fullWidth: true)
                .disabled(!understood || working)
                .opacity(understood ? 1 : 0.45)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(spacing: 8) { SymbolIcon(Icon.close, size: 13); Text(text).font(.mono(13)) }.foregroundStyle(Theme.ink)
    }
}

/// 3wc — account deleted.
struct AccountDeletedDialog: View {
    @Binding var dialog: SettingsView.AccountDialog?

    var body: some View {
        ModalCard {
            DialogIcon(Icon.trash)
            DialogTitle("Account deleted.", "Everything is gone from our servers and your other Macs. Thanks for trying Stashbar.")
            Button("Start over") {
                dialog = nil
                UserDefaults.standard.set(false, forKey: PrefKey.onboardingDone)
                WindowManager.shared.close(.settings)
                WindowManager.shared.show(.onboarding)
            }
            .stashButton(.primary, fullWidth: true)
        }
    }
}

/// 3wd — profile photo: upload or pick one of four monograms.
struct ProfilePhotoDialog: View {
    @Binding var dialog: SettingsView.AccountDialog?
    @ObservedObject private var profile = ProfileStore.shared
    @State private var style = ProfileStore.shared.avatarStyle
    @State private var photo: NSImage? = ProfileStore.shared.photo
    @State private var saving = false

    var body: some View {
        ModalCard {
            HStack(alignment: .top) {
                Text("Profile photo").headline(28).foregroundStyle(Theme.ink)
                Spacer()
                IconSquareButton(Icon.close, size: 32, iconSize: 14, filled: true) { dialog = nil }
            }
            HStack { Spacer(); AvatarView(size: 120, style: style, photo: .some(photo)); Spacer() }.padding(.vertical, 6)
            Button { pickPhoto() } label: {
                HStack(spacing: 8) { SymbolIcon(Icon.upload, size: 15); Text("Upload a photo") }
            }
            .stashButton(.outline, fullWidth: true)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Or pick a monogram")
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        Button { style = i; photo = nil } label: {
                            AvatarView(size: 40, style: i, photo: .some(nil))
                                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: photo == nil && style == i ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("JPG or PNG, square works best. Shown on every Mac you sign in to.").font(.mono(12)).lineSpacing(3).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Button("Remove photo") { photo = nil }.stashButton(.outline, fullWidth: true).disabled(photo == nil)
                Button(saving ? "Saving…" : "Save") {
                    saving = true
                    Task {
                        await profile.save(style: style, photo: photo)
                        saving = false
                        dialog = nil
                    }
                }
                .stashButton(.primary, fullWidth: true)
            }
        }
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            photo = image
        }
    }
}
