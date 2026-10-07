/// A key in shortcut notation.
public enum KeyRef: Hashable, Sendable {
    /// The key that types this character in the current Mac layout (letters lowercase).
    case character(Character)
    case named(NamedKey)
    /// Any key (only in reserved shortcut patterns: `ctrl+opt+cmd+*`).
    case any
}

/// Keys without a character, by notation name.
public enum NamedKey: String, CaseIterable, Sendable {
    case escape, tab, space, `return`, backspace, delete, insert, home, end
    case pageUp = "pageup", pageDown = "pagedown", left, right, up, down
    case keypadEnter = "keypadenter", menu
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case f13, f14, f15, f16, f17, f18, f19, f20
    // Windows-only keys (outputs)
    case printScreen = "printscreen", scrollLock = "scrolllock", pause, numLock = "numlock"

    /// The Mac key for triggers; nil for keys a Mac keyboard does not have.
    var macKeyCode: UInt16? {
        switch self {
        case .escape: MacKeyCode.escape
        case .tab: MacKeyCode.tab
        case .space: MacKeyCode.space
        case .return: MacKeyCode.returnKey
        case .backspace: MacKeyCode.backspace
        case .delete: MacKeyCode.forwardDelete
        case .insert: MacKeyCode.help
        case .home: MacKeyCode.home
        case .end: MacKeyCode.end
        case .pageUp: MacKeyCode.pageUp
        case .pageDown: MacKeyCode.pageDown
        case .left: MacKeyCode.leftArrow
        case .right: MacKeyCode.rightArrow
        case .up: MacKeyCode.upArrow
        case .down: MacKeyCode.downArrow
        case .keypadEnter: MacKeyCode.keypadEnter
        case .menu: MacKeyCode.contextualMenu
        case .printScreen, .scrollLock, .pause, .numLock: nil
        default: functionKeyNumber.map { MacKeyCode.functionKeys[$0 - 1] }
        }
    }

    /// The PC key for outputs.
    var windowsTarget: KeyTarget {
        switch self {
        case .escape: .scancode(Scancode(0x01))
        case .tab: .scancode(PCScancode.tab)
        case .space: .scancode(PCScancode.space)
        case .return: .scancode(Scancode(0x1C))
        case .backspace: .scancode(Scancode(0x0E))
        case .delete: .scancode(.e0(0x53))
        case .insert: .scancode(.e0(0x52))
        case .home: .scancode(.e0(0x47))
        case .end: .scancode(.e0(0x4F))
        case .pageUp: .scancode(.e0(0x49))
        case .pageDown: .scancode(.e0(0x51))
        case .left: .scancode(.e0(0x4B))
        case .right: .scancode(.e0(0x4D))
        case .up: .scancode(.e0(0x48))
        case .down: .scancode(.e0(0x50))
        case .keypadEnter: .scancode(.e0(0x1C))
        case .menu: .scancode(.e0(0x5D))
        case .printScreen: .scancode(.e0(0x37))
        case .scrollLock: .scancode(PCScancode.scrollLock)
        case .pause: .pause
        case .numLock: .scancode(PCScancode.numLock)
        default: .scancode(PCScancode.functionKeys[functionKeyNumber! - 1])
        }
    }

    private var functionKeyNumber: Int? {
        guard rawValue.first == "f", let number = Int(rawValue.dropFirst()) else { return nil }
        return number
    }

    fileprivate static let aliases: [String: NamedKey] = [
        "esc": .escape, "enter": .return, "del": .delete, "forwarddelete": .delete,
        "help": .insert, "apps": .menu,
    ]
}

/// A Mac shortcut such as `cmd+shift+z`.
public struct MacChord: Hashable, Sendable, CustomStringConvertible {
    public var modifiers: MacModifiers
    public var key: KeyRef

    public init(_ modifiers: MacModifiers, _ key: KeyRef) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses `ctrl+opt+shift+cmd+<key>`; key is a single character, a `NamedKey` name, `plus` or `*`.
    public init(_ notation: String) throws(ChordNotationError) {
        let (names, key) = try splitChord(notation)
        guard let key else { throw ChordNotationError(notation, "missing key") }
        if case .named(let named) = key, named.macKeyCode == nil {
            throw ChordNotationError(notation, "'\(named.rawValue)' is not a Mac key")
        }
        var modifiers: MacModifiers = []
        for name in names {
            switch name {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "shift", "⇧": modifiers.insert(.shift)
            default: throw ChordNotationError(notation, "unknown Mac modifier '\(name)'")
            }
        }
        self.init(modifiers, key)
    }

    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return (parts + [key.notation]).joined(separator: "+")
    }

    func matches(keyCode: UInt16, modifiers: MacModifiers, layout: any KeyboardLayoutProvider) -> Bool {
        modifiers == self.modifiers && key.matches(keyCode: keyCode, layout: layout)
    }
}

/// A Windows key combination such as `ctrl+y`, or a modifier tap such as `win`.
public struct WindowsChord: Hashable, Sendable, CustomStringConvertible {
    public var modifiers: WindowsModifiers
    /// nil: the modifiers themselves are tapped.
    public var key: KeyRef?

    public init(_ modifiers: WindowsModifiers, _ key: KeyRef?) {
        self.modifiers = modifiers
        self.key = key
    }

    public init(_ notation: String) throws(ChordNotationError) {
        let (names, key) = try splitChord(notation)
        if key == .any { throw ChordNotationError(notation, "'*' is only allowed in reserved shortcuts") }
        var modifiers: WindowsModifiers = []
        for name in names {
            switch name {
            case "ctrl", "control": modifiers.insert(.control)
            case "alt": modifiers.insert(.alt)
            case "shift": modifiers.insert(.shift)
            case "win", "windows": modifiers.insert(.windows)
            default: throw ChordNotationError(notation, "unknown Windows modifier '\(name)'")
            }
        }
        if key == nil, modifiers.isEmpty { throw ChordNotationError(notation, "empty chord") }
        self.init(modifiers, key)
    }

    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.alt) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.windows) { parts.append("win") }
        if let key { parts.append(key.notation) }
        return parts.joined(separator: "+")
    }
}

public struct ChordNotationError: Error, Equatable, CustomStringConvertible {
    public var notation: String
    public var reason: String

    init(_ notation: String, _ reason: String) {
        self.notation = notation
        self.reason = reason
    }

    public var description: String { "Invalid shortcut '\(notation)': \(reason)" }
}

extension KeyRef {
    var notation: String {
        switch self {
        case .character("+"): "plus"
        case .character(let character): String(character)
        case .named(let named): named.rawValue
        case .any: "*"
        }
    }

    func matches(keyCode: UInt16, layout: any KeyboardLayoutProvider) -> Bool {
        switch self {
        case .any: true
        case .named(let named): named.macKeyCode == keyCode
        case .character(let character): layout.key(keyCode, types: character)
        }
    }
}

private let modifierNames: Set<String> = [
    "cmd", "command", "⌘", "opt", "option", "alt", "⌥", "ctrl", "control", "⌃", "shift", "⇧",
    "win", "windows",
]

/// Splits `a+b+key` into modifier names (lowercased) and the key; the key is nil when the last
/// token is a modifier name.
private func splitChord(_ notation: String) throws(ChordNotationError) -> ([String], KeyRef?) {
    let tokens = notation.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let last = tokens.last, !last.isEmpty, !tokens.dropLast().contains(where: \.isEmpty) else {
        throw ChordNotationError(notation, "empty part (write '+' as 'plus')")
    }
    let names = tokens.dropLast().map { $0.lowercased() }
    let lowered = last.lowercased()
    if modifierNames.contains(lowered) { return (names + [lowered], nil) }
    if last == "*" { return (names, .any) }
    if lowered == "plus" { return (names, .character("+")) }
    if let named = NamedKey(rawValue: lowered) ?? NamedKey.aliases[lowered] { return (names, .named(named)) }
    if last.count == 1, let character = last.lowercased().first { return (names, .character(character)) }
    throw ChordNotationError(notation, "unknown key '\(last)'")
}
