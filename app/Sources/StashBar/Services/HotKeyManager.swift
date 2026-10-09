import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts via Carbon's RegisterEventHotKey.
/// Unlike an NSEvent global monitor this needs no Accessibility permission and consumes the keystroke.
@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    public enum Action: UInt32 {
        case togglePopover = 1
        case stashClipboard = 2
    }

    private var refs: [Action: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    public var onAction: ((Action) -> Void)?

    private init() {}

    /// The user's "Open Stashbar" combo (default ⌥S).
    public var openCombo: KeyCombo {
        let d = UserDefaults.standard
        return KeyCombo(keyCode: UInt32(d.integer(forKey: PrefKey.hotKeyCode)),
                        modifiers: UInt32(d.integer(forKey: PrefKey.hotKeyModifiers)))
    }

    public func setOpenCombo(_ combo: KeyCombo) {
        UserDefaults.standard.set(Int(combo.keyCode), forKey: PrefKey.hotKeyCode)
        UserDefaults.standard.set(Int(combo.modifiers), forKey: PrefKey.hotKeyModifiers)
        registerAll()
    }

    public func registerAll() {
        installHandler()
        unregisterAll()
        let open = openCombo
        register(.togglePopover, open)
        // "Stash clipboard instantly" is the open combo plus Shift (⌥⇧S by default).
        register(.stashClipboard, KeyCombo(keyCode: open.keyCode, modifiers: open.modifiers | UInt32(shiftKey)))
    }

    public func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    /// Temporarily disable while the shortcut recorder is listening.
    public func suspend() { unregisterAll() }

    private func register(_ action: Action, _ combo: KeyCombo) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x53544252), id: action.rawValue) // 'STBR'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[action] = ref }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if let action = HotKeyManager.Action(rawValue: hotKeyID.id) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKeyManager.shared.onAction?(action) }
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

public struct KeyCombo: Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32  // Carbon modifier mask

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Builds a combo from an AppKit key event (used by the shortcut recorder).
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        // Require at least one of ⌘ ⌥ ⌃ so plain typing never triggers Stashbar.
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    public var modifierSymbols: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    public var keyName: String { KeyCombo.name(for: keyCode) }
    public var display: String { modifierSymbols + keyName }

    static func name(for keyCode: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Delete: "⌫", kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",",
            kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
            kVK_ANSI_Backslash: "\\", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        return map[Int(keyCode)] ?? "Key \(keyCode)"
    }
}
