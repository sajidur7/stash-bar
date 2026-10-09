import SwiftUI
import AppKit

// MARK: - Buttons

public enum ButtonKind { case primary, outline, soft, dark, ghostOnDark, disabledOutline }

/// The v13 button family. Primary = highlighter yellow; outline = 1.5px ink; soft = paper fill.
public struct StashButtonStyle: ButtonStyle {
    var kind: ButtonKind = .primary
    var height: CGFloat = 46
    var fullWidth = false
    var radius: CGFloat = Theme.rButton
    var fontSize: CGFloat = 13

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .primary || kind == .dark ? .monoMedium(fontSize) : .mono(fontSize))
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height, maxHeight: height)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(background))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .soft: return Theme.paper
        case .dark: return Theme.charcoal
        default: return .clear
        }
    }
    private var foreground: Color {
        switch kind {
        case .primary: return Theme.onAccent
        case .dark, .ghostOnDark: return .white
        case .disabledOutline: return Theme.muted
        default: return Theme.ink
        }
    }
    private var border: Color {
        switch kind {
        case .primary: return Theme.accent
        case .outline: return Theme.ink
        case .dark: return Theme.charcoal
        case .ghostOnDark: return Color(hex: 0x6D6C6B)
        case .disabledOutline: return Theme.hairline
        case .soft: return .clear
        }
    }
}

public extension View {
    func stashButton(_ kind: ButtonKind = .primary, height: CGFloat = 46, fullWidth: Bool = false, radius: CGFloat = Theme.rButton, fontSize: CGFloat = 13) -> some View {
        buttonStyle(StashButtonStyle(kind: kind, height: height, fullWidth: fullWidth, radius: radius, fontSize: fontSize))
    }
}

/// Small square icon button (archive / delete on cards, close on sheets).
public struct IconSquareButton: View {
    let icon: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 13
    var filled = false
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    public init(_ icon: String, size: CGFloat = 28, iconSize: CGFloat = 13, filled: Bool = false, help: String = "", action: @escaping () -> Void) {
        self.icon = icon; self.size = size; self.iconSize = iconSize; self.filled = filled; self.help = help; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SymbolIcon(icon, size: iconSize)
                .foregroundStyle(hover ? Theme.onAccent : Theme.ink)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Theme.rButton).fill(hover ? Theme.accent : (filled ? Theme.paper : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: Theme.rButton).strokeBorder(hover ? Theme.accent : (filled ? .clear : Theme.hairline), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Toggle (42×24, radius 6; on = ink track + yellow knob)

public struct StashToggle: View {
    @Binding var isOn: Bool
    var disabled = false
    public init(isOn: Binding<Bool>, disabled: Bool = false) { _isOn = isOn; self.disabled = disabled }

    public var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 6).fill(isOn ? Theme.charcoal : Theme.hairlineStrong)
            Circle().fill(isOn ? Theme.accent : Color.white).frame(width: 18, height: 18).padding(3)
        }
        .frame(width: 42, height: 24)
        .opacity(disabled ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Segmented control

public struct Segmented: View {
    let options: [String]
    @Binding var selection: String
    public init(_ options: [String], selection: Binding<String>) { self.options = options; _selection = selection }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Text(o).font(.mono(12))
                    .padding(.horizontal, 12).frame(height: 28)
                    .foregroundStyle(selection == o ? Theme.surface : Theme.ink)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selection == o ? Theme.ink : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = o }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hairline))
    }
}

// MARK: - Key caps

public struct KeyCap: View {
    let label: String
    var symbol: String?
    var size: CGFloat = 30
    var fontSize: CGFloat = 13
    public init(_ label: String, symbol: String? = nil, size: CGFloat = 30, fontSize: CGFloat = 13) {
        self.label = label; self.symbol = symbol; self.size = size; self.fontSize = fontSize
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let symbol { SymbolIcon(symbol, size: fontSize) }
            if !label.isEmpty { Text(label).font(.monoMedium(fontSize)) }
        }
        .foregroundStyle(Color(hex: 0x0C0A08))
        .padding(.horizontal, 8)
        .frame(minWidth: size, minHeight: size, maxHeight: size)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xD3D3D3), lineWidth: 1))
        .shadow(color: Color(hex: 0xD3D3D3), radius: 0, x: 0, y: 2)
    }
}

// MARK: - Avatar

public struct AvatarView: View {
    @ObservedObject private var profile = ProfileStore.shared
    @ObservedObject private var auth = AuthService.shared
    var size: CGFloat = 30
    var styleOverride: Int?
    var photoOverride: NSImage??
    var onCharcoal = false

    public init(size: CGFloat = 30, style: Int? = nil, photo: NSImage?? = nil, onCharcoal: Bool = false) {
        self.size = size; self.styleOverride = style; self.photoOverride = photo; self.onCharcoal = onCharcoal
    }

    public var body: some View {
        if auth.isSignedIn {
            let photo = photoOverride ?? profile.photo
            if let photo {
                Image(nsImage: photo).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                monogram(style: styleOverride ?? profile.avatarStyle)
            }
        } else {
            Circle().strokeBorder(Color(hex: 0xA3A2A1), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .overlay(SymbolIcon(Icon.user, size: size * 0.45).foregroundStyle(onCharcoal ? .white : Theme.ink).opacity(0.8))
                .frame(width: size, height: size)
        }
    }

    func monogram(style: Int) -> some View {
        let (bg, fg, border): (Color, Color, Color) = {
            switch style {
            case 1: return (Theme.accent, Theme.onAccent, Theme.hairline)
            case 2: return (Theme.paper, Theme.ink, Theme.hairline)
            case 3: return (Theme.surface, Theme.ink, Theme.hairline)
            default: return (Color(hex: 0x1A1919), Theme.accent, onCharcoal ? Color(hex: 0x3D3B3A) : .clear)
            }
        }()
        return Circle().fill(bg)
            .overlay(Circle().strokeBorder(border, lineWidth: 1))
            .overlay(Text(profile.initials).font(.monoMedium(size * 0.32)).tracking(-0.04 * size * 0.32).foregroundStyle(fg))
            .frame(width: size, height: size)
    }
}

// MARK: - Inputs

/// Paper-filled field with a leading icon (search bars, URL inputs).
public struct FieldBox<Content: View>: View {
    var icon: String?
    var height: CGFloat = 40
    var radius: CGFloat = Theme.rInput
    var fill: Color = Theme.paper
    var border: Color = .clear
    @ViewBuilder var content: Content

    public init(icon: String? = Icon.search, height: CGFloat = 40, radius: CGFloat = Theme.rInput, fill: Color = Theme.paper, border: Color = .clear, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.height = height; self.radius = radius; self.fill = fill; self.border = border; self.content = content()
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon { SymbolIcon(icon, size: 15).foregroundStyle(Theme.ink).opacity(0.55) }
            content
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1.5))
    }
}

public extension TextField {
    func stashField(_ size: CGFloat = 13) -> some View {
        self.textFieldStyle(.plain).font(.mono(size)).foregroundStyle(Theme.ink)
    }
}

// MARK: - Chips & labels

public struct TagChip: View {
    let label: String
    var selected = true
    var onRemove: (() -> Void)?
    public init(_ label: String, selected: Bool = true, onRemove: (() -> Void)? = nil) {
        self.label = label; self.selected = selected; self.onRemove = onRemove
    }
    public var body: some View {
        HStack(spacing: 6) {
            Text(label).font(selected ? .monoMedium(13) : .mono(13))
            if let onRemove {
                Button(action: onRemove) { SymbolIcon(Icon.close, size: 9) }.buttonStyle(.plain).opacity(0.6)
            }
        }
        .padding(.horizontal, 12).frame(height: 28)
        .foregroundStyle(selected ? Color.white : Theme.ink)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.charcoal : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? .clear : Theme.hairline, lineWidth: 1))
    }
}

public struct SectionLabel: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text.uppercased()).font(.mono(11)).foregroundStyle(Theme.muted) }
}

/// Simple wrapping layout for tag chips.
public struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    public init(spacing: CGFloat = 6) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Modal overlay (scrim + white card, 440 wide)

public struct ModalCard<Content: View>: View {
    var width: CGFloat = 440
    @ViewBuilder var content: Content
    public init(width: CGFloat = 440, @ViewBuilder content: () -> Content) { self.width = width; self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(28)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).fill(Theme.surface))
            .shadow(color: .black.opacity(0.25), radius: 35, y: 30)
    }
}

public extension View {
    /// Presents `content` centered over a 55% black scrim inside this view.
    func modalOverlay<M: View>(_ isPresented: Bool, onDismiss: @escaping () -> Void = {}, @ViewBuilder content: () -> M) -> some View {
        overlay {
            if isPresented {
                ZStack {
                    Theme.scrim.ignoresSafeArea().onTapGesture(perform: onDismiss)
                    content()
                }
                .transition(.opacity)
            }
        }
    }
}

/// The 52px rounded icon tile at the top of dialogs.
public struct DialogIcon: View {
    let icon: String
    var dark = false
    var bordered = false
    public init(_ icon: String, dark: Bool = false, bordered: Bool = false) { self.icon = icon; self.dark = dark; self.bordered = bordered }
    public var body: some View {
        SymbolIcon(icon, size: 22)
            .foregroundStyle(dark ? Color.white : Theme.ink)
            .frame(width: 52, height: 52)
            .background(RoundedRectangle(cornerRadius: Theme.rCard).fill(dark ? Theme.charcoal : (bordered ? Theme.surface : Theme.paper)))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(bordered ? Theme.hairline : .clear, lineWidth: 1))
    }
}

public struct DialogTitle: View {
    let title: String
    let message: String
    public init(_ title: String, _ message: String) { self.title = title; self.message = message }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).headline(28).foregroundStyle(Theme.ink)
            Text(message).font(.mono(13)).lineSpacing(4).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row with leading icon tile, label, hint and trailing control — used across Settings.
public struct SettingRow<Trailing: View>: View {
    let icon: String?
    let label: String
    let hint: String
    @ViewBuilder var trailing: Trailing
    public init(_ icon: String?, _ label: String, _ hint: String, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon; self.label = label; self.hint = hint; self.trailing = trailing()
    }
    public var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 16) {
                if let icon {
                    SymbolIcon(icon, size: 16).foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.paper))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.mono(13)).foregroundStyle(Theme.ink)
                    Text(hint).font(.mono(13)).lineSpacing(3).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 14)
        }
    }
}

/// Underlined text link (yellow underline, as on the design's "Change" / "Export .json").
public struct UnderlineLink: View {
    let title: String
    var color: Color = Theme.ink
    var underline: Color = Theme.accent
    let action: () -> Void
    public init(_ title: String, color: Color = Theme.ink, underline: Color = Theme.accent, action: @escaping () -> Void) {
        self.title = title; self.color = color; self.underline = underline; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title).font(.mono(13)).foregroundStyle(color)
                .overlay(alignment: .bottom) { Rectangle().fill(underline).frame(height: 2).offset(y: 4) }
        }
        .buttonStyle(.plain)
    }
}

/// Visual-effect-free solid window background helper.
public struct WindowChrome: ViewModifier {
    public func body(content: Content) -> some View {
        content.background(Theme.surface).ignoresSafeArea()
    }
}
