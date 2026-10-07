/// Physical keyboard kind; decides where the two "extra" ISO keys go.
public enum PhysicalKeyboardType: String, Codable, Hashable, Sendable {
    case ansi, iso, jis
}

/// What a physical key sends on the Windows side.
enum KeyTarget: Hashable {
    case scancode(Scancode)
    /// Pause key, see `RDPKeyAction.pause`.
    case pause
    /// Keys without a PC counterpart, sent as Unicode text (keypad `=`).
    case text(String)
}

/// How a key behaves for character translation and ⌥ handling.
enum KeyClass {
    /// Main block keys that type characters (letters, digits, punctuation, space, ISO/JIS extras).
    case character
    /// Numeric keypad keys that type characters.
    case keypad
    /// Everything else: Return, Tab, ⌫, Esc, F-keys, arrows, navigation cluster, keypad Enter/Clear.
    case function
}

/// macOS virtual key codes (`kVK_*` in HIToolbox/Events.h) the engine refers to by name.
enum MacKeyCode {
    static let isoSection: UInt16 = 0x0A
    static let ansiGrave: UInt16 = 0x32
    static let space: UInt16 = 0x31
    static let returnKey: UInt16 = 0x24
    static let tab: UInt16 = 0x30
    static let backspace: UInt16 = 0x33
    static let escape: UInt16 = 0x35
    static let forwardDelete: UInt16 = 0x75
    static let help: UInt16 = 0x72
    static let home: UInt16 = 0x73
    static let end: UInt16 = 0x77
    static let pageUp: UInt16 = 0x74
    static let pageDown: UInt16 = 0x79
    static let leftArrow: UInt16 = 0x7B
    static let rightArrow: UInt16 = 0x7C
    static let downArrow: UInt16 = 0x7D
    static let upArrow: UInt16 = 0x7E
    static let keypadEnter: UInt16 = 0x4C
    static let capsLock: UInt16 = 0x39
    static let function: UInt16 = 0x3F
    static let contextualMenu: UInt16 = 0x6E
    /// F1...F20 in order.
    static let functionKeys: [UInt16] = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]
}

/// Well-known set-1 scancodes.
enum PCScancode {
    static let tab = Scancode(0x0F)
    static let space = Scancode(0x39)
    static let capsLock = Scancode(0x3A)
    static let numLock = Scancode(0x45)
    static let scrollLock = Scancode(0x46)
    /// Ctrl+Pause on a PC keyboard.
    static let breakKey = Scancode.e0(0x46)
    /// F1...F24 (F13...F24 are the "extended function" codes Windows maps to VK_F13...VK_F24).
    static let functionKeys: [Scancode] = [
        0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58,
        0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x76,
    ].map { Scancode($0) }
}

/// macOS key code -> Windows scancode, the physical-position mapping of the spec.
enum PhysicalKeyMap {
    static func target(for keyCode: UInt16, keyboardType: PhysicalKeyboardType) -> KeyTarget? {
        // On ISO keyboards the key left of 1 reports kVK_ISO_Section and the extra key left of Z
        // reports kVK_ANSI_Grave (the layout data does not swap them). ANSI has only the Grave key,
        // left of 1. JIS behaves like ANSI here.
        switch (keyCode, keyboardType) {
        case (MacKeyCode.isoSection, .iso): return .scancode(Scancode(0x29))
        case (MacKeyCode.ansiGrave, .iso): return .scancode(Scancode(0x56))
        case (MacKeyCode.isoSection, _): return .scancode(Scancode(0x56))
        case (MacKeyCode.ansiGrave, _): return .scancode(Scancode(0x29))
        default: return entries[keyCode]?.target
        }
    }

    static func keyClass(of keyCode: UInt16) -> KeyClass? {
        if keyCode == MacKeyCode.isoSection || keyCode == MacKeyCode.ansiGrave { return .character }
        return entries[keyCode]?.keyClass
    }

    /// Every key code that has a mapping (excluding modifier keys, which are handled separately).
    static let mappedKeyCodes: [UInt16] = (Array(entries.keys) + [MacKeyCode.isoSection, MacKeyCode.ansiGrave]).sorted()

    private struct Entry {
        let target: KeyTarget
        let keyClass: KeyClass
    }

    private static func key(_ code: UInt8, _ keyClass: KeyClass = .character) -> Entry {
        Entry(target: .scancode(Scancode(code)), keyClass: keyClass)
    }

    private static func extended(_ code: UInt8, _ keyClass: KeyClass = .function) -> Entry {
        Entry(target: .scancode(.e0(code)), keyClass: keyClass)
    }

    private static func fn(_ number: Int) -> Entry {
        Entry(target: .scancode(PCScancode.functionKeys[number - 1]), keyClass: .function)
    }

    private static let entries: [UInt16: Entry] = [
        // Letters
        0x00: key(0x1E), 0x0B: key(0x30), 0x08: key(0x2E), 0x02: key(0x20), 0x0E: key(0x12),
        0x03: key(0x21), 0x05: key(0x22), 0x04: key(0x23), 0x22: key(0x17), 0x26: key(0x24),
        0x28: key(0x25), 0x25: key(0x26), 0x2E: key(0x32), 0x2D: key(0x31), 0x1F: key(0x18),
        0x23: key(0x19), 0x0C: key(0x10), 0x0F: key(0x13), 0x01: key(0x1F), 0x11: key(0x14),
        0x20: key(0x16), 0x09: key(0x2F), 0x0D: key(0x11), 0x07: key(0x2D), 0x10: key(0x15),
        0x06: key(0x2C),
        // Digit row
        0x12: key(0x02), 0x13: key(0x03), 0x14: key(0x04), 0x15: key(0x05), 0x17: key(0x06),
        0x16: key(0x07), 0x1A: key(0x08), 0x1C: key(0x09), 0x19: key(0x0A), 0x1D: key(0x0B),
        0x1B: key(0x0C), 0x18: key(0x0D),
        // Punctuation (named after the US legends)
        0x21: key(0x1A), 0x1E: key(0x1B), 0x29: key(0x27), 0x27: key(0x28), 0x2A: key(0x2B),
        0x2B: key(0x33), 0x2F: key(0x34), 0x2C: key(0x35), 0x31: key(0x39),
        // JIS main block
        0x5D: key(0x7D), 0x5E: key(0x73),
        // Editing and control
        0x24: key(0x1C, .function), 0x30: key(0x0F, .function), 0x33: key(0x0E, .function),
        0x35: key(0x01, .function),
        // Navigation cluster (Help sits where Insert is on PC keyboards)
        0x72: extended(0x52), 0x73: extended(0x47), 0x74: extended(0x49), 0x75: extended(0x53),
        0x77: extended(0x4F), 0x79: extended(0x51),
        0x7B: extended(0x4B), 0x7C: extended(0x4D), 0x7D: extended(0x50), 0x7E: extended(0x48),
        // Function keys; F13/F14/F15 take the PC's Print/Scroll/Pause positions.
        0x7A: fn(1), 0x78: fn(2), 0x63: fn(3), 0x76: fn(4), 0x60: fn(5), 0x61: fn(6),
        0x62: fn(7), 0x64: fn(8), 0x65: fn(9), 0x6D: fn(10), 0x67: fn(11), 0x6F: fn(12),
        0x69: extended(0x37), 0x6B: key(0x46, .function),
        0x71: Entry(target: .pause, keyClass: .function),
        0x6A: fn(16), 0x40: fn(17), 0x4F: fn(18), 0x50: fn(19), 0x5A: fn(20),
        // Keypad (Clear sits where NumLock is; Mac-only `=` goes as text)
        0x47: key(0x45, .function), 0x4C: extended(0x1C),
        0x4B: extended(0x35, .keypad), 0x43: key(0x37, .keypad), 0x4E: key(0x4A, .keypad),
        0x45: key(0x4E, .keypad), 0x41: key(0x53, .keypad), 0x5F: key(0x7E, .keypad),
        0x51: Entry(target: .text("="), keyClass: .keypad),
        0x52: key(0x52, .keypad), 0x53: key(0x4F, .keypad), 0x54: key(0x50, .keypad),
        0x55: key(0x51, .keypad), 0x56: key(0x4B, .keypad), 0x57: key(0x4C, .keypad),
        0x58: key(0x4D, .keypad), 0x59: key(0x47, .keypad), 0x5B: key(0x48, .keypad),
        0x5C: key(0x49, .keypad),
        // Media and language keys
        0x48: extended(0x30), 0x49: extended(0x2E), 0x4A: extended(0x20),
        0x6E: extended(0x5D),
        // JIS Eisu/Kana = HID LANG2/LANG1 -> VK_IME_OFF / VK_IME_ON on Windows JP layouts
        0x66: extended(0xF1), 0x68: extended(0xF2),
    ]
}
