/// Mac shortcut -> Windows key sequence (Mac-shortcut mode only).
///
/// JSON: `{"mac": "cmd+left", "windows": ["home"], "keepShift": true}`
public struct ShortcutRule: Hashable, Sendable {
    public var mac: MacChord
    /// Chords sent in order. A single chord with a key is held as long as the Mac key is held
    /// (and repeats); longer sequences and modifier taps are sent as taps.
    public var windows: [WindowsChord]
    /// The rule also matches with ⇧ added, and then adds Shift to every output chord (⌘⇧← -> ⇧Pos1).
    public var keepShift: Bool
    /// The output modifiers stay down until the rule's ⌘ (or ⌥) is released, and further keys pass
    /// through with them (⌘⇥⇥⇥ -> Alt held, Tab, Tab, Tab).
    public var holdUntilRelease: Bool
    /// Match the trigger by the character its key types with the held ⌥/⇧ in the current layout (as
    /// Jump does) instead of by the key's unmodified character or US position; ⌘ and ⌃ must match
    /// exactly. `cmd+[` is then ⌘[ on US and ⌘⌥5 on German, where ⌘Ü and ⌘+ keep the default rule.
    public var typedCharacter: Bool

    public init(
        mac: MacChord, windows: [WindowsChord], keepShift: Bool = false, holdUntilRelease: Bool = false,
        typedCharacter: Bool = false
    ) {
        self.mac = mac
        self.windows = windows
        self.keepShift = keepShift
        self.holdUntilRelease = holdUntilRelease
        self.typedCharacter = typedCharacter
    }

    /// Notation convenience for literals; traps on invalid notation.
    init(
        _ mac: String, _ windows: [String], keepShift: Bool = false, holdUntilRelease: Bool = false,
        typedCharacter: Bool = false
    ) {
        self.init(
            mac: try! MacChord(mac),
            windows: windows.map { try! WindowsChord($0) },
            keepShift: keepShift,
            holdUntilRelease: holdUntilRelease,
            typedCharacter: typedCharacter
        )
    }

    /// The defaults from the spec ("Sonderregeln").
    public static let defaults: [ShortcutRule] = [
        ShortcutRule("shift+cmd+z", ["ctrl+y"]),
        ShortcutRule("cmd+left", ["home"], keepShift: true),
        ShortcutRule("cmd+right", ["end"], keepShift: true),
        ShortcutRule("cmd+up", ["ctrl+home"], keepShift: true),
        ShortcutRule("cmd+down", ["ctrl+end"], keepShift: true),
        ShortcutRule("opt+left", ["ctrl+left"], keepShift: true),
        ShortcutRule("opt+right", ["ctrl+right"], keepShift: true),
        ShortcutRule("opt+up", ["ctrl+up"], keepShift: true),
        ShortcutRule("opt+down", ["ctrl+down"], keepShift: true),
        ShortcutRule("opt+backspace", ["ctrl+backspace"]),
        ShortcutRule("opt+delete", ["ctrl+delete"]),
        ShortcutRule("cmd+backspace", ["shift+home", "backspace"]),
        ShortcutRule("cmd+delete", ["shift+end", "delete"]),
        ShortcutRule("cmd+tab", ["alt+tab"], keepShift: true, holdUntilRelease: true),
        ShortcutRule("cmd+space", ["win"]),
        ShortcutRule("opt+cmd+escape", ["ctrl+shift+escape"]),
        // From Jump's default input profile. ⌘Q closes the remote window; the app quits via its menu
        // (or ⌘Q while no session has focus), so ⌘Q is deliberately not a reserved shortcut.
        ShortcutRule("cmd+q", ["alt+f4"]),
        ShortcutRule("cmd+[", ["alt+left"], typedCharacter: true),
        ShortcutRule("cmd+]", ["alt+right"], typedCharacter: true),
        ShortcutRule("ctrl+opt+backspace", ["ctrl+alt+delete"]),
        ShortcutRule("ctrl+opt+delete", ["ctrl+alt+delete"]),
    ]

    func matches(keyCode: UInt16, modifiers: MacModifiers, layout: any KeyboardLayoutProvider) -> Bool {
        guard typedCharacter else { return mac.matches(keyCode: keyCode, modifiers: modifiers, layout: layout) }
        guard case .character(let character) = mac.key, PhysicalKeyMap.keyClass(of: keyCode) == .character else {
            return false
        }
        let exact: MacModifiers = [.command, .control]
        guard modifiers.intersection(exact) == mac.modifiers.intersection(exact),
              modifiers.isSuperset(of: mac.modifiers)
        else { return false }
        var layoutModifiers: LayoutModifiers = []
        if modifiers.contains(.option) { layoutModifiers.insert(.option) }
        if modifiers.contains(.shift) { layoutModifiers.insert(.shift) }
        var deadKeyState: UInt32 = 0
        let typed = layout.translate(keyCode: keyCode, modifiers: layoutModifiers, deadKeyState: &deadKeyState)
        return typed == String(character)
    }
}

extension [ShortcutRule] {
    /// Exact modifier matches win over `keepShift` matches; otherwise table order.
    func match(keyCode: UInt16, modifiers: MacModifiers, layout: any KeyboardLayoutProvider) -> ShortcutRule? {
        if let exact = first(where: { $0.matches(keyCode: keyCode, modifiers: modifiers, layout: layout) }) {
            return exact
        }
        guard modifiers.contains(.shift) else { return nil }
        let withoutShift = modifiers.subtracting(.shift)
        return first { $0.keepShift && $0.matches(keyCode: keyCode, modifiers: withoutShift, layout: layout) }
    }
}

extension ShortcutRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case mac, windows, keepShift, holdUntilRelease, typedCharacter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mac: try container.decode(MacChord.self, forKey: .mac),
            windows: try container.decode([WindowsChord].self, forKey: .windows),
            keepShift: try container.decodeIfPresent(Bool.self, forKey: .keepShift) ?? false,
            holdUntilRelease: try container.decodeIfPresent(Bool.self, forKey: .holdUntilRelease) ?? false,
            typedCharacter: try container.decodeIfPresent(Bool.self, forKey: .typedCharacter) ?? false
        )
        if windows.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .windows, in: container, debugDescription: "empty")
        }
        if holdUntilRelease, windows.count != 1 || windows[0].key == nil
            || mac.modifiers.isDisjoint(with: [.command, .option]) {
            throw DecodingError.dataCorruptedError(
                forKey: .holdUntilRelease, in: container,
                debugDescription: "needs a ⌘ or ⌥ trigger and exactly one output chord with a key")
        }
        if typedCharacter {
            guard case .character = mac.key, !keepShift else {
                throw DecodingError.dataCorruptedError(
                    forKey: .typedCharacter, in: container,
                    debugDescription: "needs a character key and no keepShift (⇧ belongs to the typed character)")
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mac, forKey: .mac)
        try container.encode(windows, forKey: .windows)
        if keepShift { try container.encode(true, forKey: .keepShift) }
        if holdUntilRelease { try container.encode(true, forKey: .holdUntilRelease) }
        if typedCharacter { try container.encode(true, forKey: .typedCharacter) }
    }
}

extension MacChord: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let notation = try container.decode(String.self)
        do { try self.init(notation) } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension WindowsChord: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let notation = try container.decode(String.self)
        do { try self.init(notation) } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
