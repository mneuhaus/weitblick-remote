/// Modifier state for a layout translation (Carbon `UCKeyTranslate` semantics).
public struct LayoutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = LayoutModifiers(rawValue: 1 << 0)
    public static let shift = LayoutModifiers(rawValue: 1 << 1)
    public static let capsLock = LayoutModifiers(rawValue: 1 << 2)
    public static let option = LayoutModifiers(rawValue: 1 << 3)
    public static let control = LayoutModifiers(rawValue: 1 << 4)
}

/// The Mac keyboard layout: what a key types with given modifiers.
public protocol KeyboardLayoutProvider: Sendable {
    /// Physical keyboard type used when an event does not carry one.
    var keyboardType: PhysicalKeyboardType { get }

    /// Text typed by `keyCode` with `modifiers`. `deadKeyState` is the compose state in and out:
    /// a dead key returns "" and a non-zero state; the next call composes with it.
    func translate(keyCode: UInt16, modifiers: LayoutModifiers, deadKeyState: inout UInt32) -> String
}

extension KeyboardLayoutProvider {
    /// What the key types without modifiers; for dead keys the standalone accent.
    func baseCharacter(of keyCode: UInt16) -> Character? {
        var state: UInt32 = 0
        var text = translate(keyCode: keyCode, modifiers: [], deadKeyState: &state)
        if text.isEmpty, state != 0 {
            text = translate(keyCode: MacKeyCode.space, modifiers: [], deadKeyState: &state)
        }
        return text.count == 1 ? text.first : nil
    }

    /// The main-block key that types `character` unmodified (case-insensitive). Characters the layout
    /// lacks (Latin letters on Cyrillic layouts) resolve to their US position, like Windows shortcuts.
    func keyCode(typing character: Character) -> UInt16? {
        let wanted = character.lowercased()
        for keyCode in PhysicalKeyMap.mappedKeyCodes where PhysicalKeyMap.keyClass(of: keyCode) == .character {
            if baseCharacter(of: keyCode)?.lowercased() == wanted { return keyCode }
        }
        return usKeyCodes[Character(wanted)]
    }

    /// Whether `keyCode` is the key for `character` in shortcut matching.
    func key(_ keyCode: UInt16, types character: Character) -> Bool {
        guard PhysicalKeyMap.keyClass(of: keyCode) != .function else { return false }
        if baseCharacter(of: keyCode)?.lowercased() == character.lowercased() { return true }
        return self.keyCode(typing: character) == keyCode
    }
}

/// US ANSI positions, the fallback for characters a layout does not have.
private let usKeyCodes: [Character: UInt16] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
    "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
    "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
]

/// True if every scalar is a visible character: no control characters, no private use (Apple logo).
func isPrintable(_ text: String) -> Bool {
    !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0xE000...0xF8FF, 0xF0000...: false
        default: true
        }
    }
}
