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

    public init(mac: MacChord, windows: [WindowsChord], keepShift: Bool = false, holdUntilRelease: Bool = false) {
        self.mac = mac
        self.windows = windows
        self.keepShift = keepShift
        self.holdUntilRelease = holdUntilRelease
    }

    /// Notation convenience for literals; traps on invalid notation.
    init(_ mac: String, _ windows: [String], keepShift: Bool = false, holdUntilRelease: Bool = false) {
        self.init(
            mac: try! MacChord(mac),
            windows: windows.map { try! WindowsChord($0) },
            keepShift: keepShift,
            holdUntilRelease: holdUntilRelease
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
        ShortcutRule("ctrl+opt+backspace", ["ctrl+alt+delete"]),
        ShortcutRule("ctrl+opt+delete", ["ctrl+alt+delete"]),
    ]
}

extension [ShortcutRule] {
    /// Exact modifier matches win over `keepShift` matches; otherwise table order.
    func match(keyCode: UInt16, modifiers: MacModifiers, layout: any KeyboardLayoutProvider) -> ShortcutRule? {
        if let exact = first(where: { $0.mac.matches(keyCode: keyCode, modifiers: modifiers, layout: layout) }) {
            return exact
        }
        guard modifiers.contains(.shift) else { return nil }
        let withoutShift = modifiers.subtracting(.shift)
        return first { $0.keepShift && $0.mac.matches(keyCode: keyCode, modifiers: withoutShift, layout: layout) }
    }
}

extension ShortcutRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case mac, windows, keepShift, holdUntilRelease
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mac: try container.decode(MacChord.self, forKey: .mac),
            windows: try container.decode([WindowsChord].self, forKey: .windows),
            keepShift: try container.decodeIfPresent(Bool.self, forKey: .keepShift) ?? false,
            holdUntilRelease: try container.decodeIfPresent(Bool.self, forKey: .holdUntilRelease) ?? false
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
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mac, forKey: .mac)
        try container.encode(windows, forKey: .windows)
        if keepShift { try container.encode(true, forKey: .keepShift) }
        if holdUntilRelease { try container.encode(true, forKey: .holdUntilRelease) }
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
