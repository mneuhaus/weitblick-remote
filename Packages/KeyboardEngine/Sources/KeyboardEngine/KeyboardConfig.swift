/// Per-connection keyboard settings, stored as JSON. Missing keys decode to their defaults.
public struct KeyboardConfig: Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        /// ⌘ shortcuts are translated (⌘C -> Ctrl+C, rules), ⌘ alone = Win.
        case macShortcuts
        /// ⌘ = Win, ⌥ = Alt, ⌃ = Ctrl, no rules ("Windows 1:1").
        case windowsDirect
    }

    /// What ⌥ + key does in Mac-shortcut mode when no rule matches.
    public enum OptionStrategy: String, Codable, Hashable, Sendable {
        /// Useful characters (@ € { } …) as Unicode, otherwise Alt + key.
        case smart
        /// Right ⌥ types characters, left ⌥ is Alt.
        case jumpStyle
        case alwaysAlt
        case alwaysCharacters
    }

    public var mode: Mode
    public var optionStrategy: OptionStrategy
    /// Send every printable character typed without ⌘/⌃ (and ⌥ in Windows-direct mode) as Unicode
    /// instead of scancodes, for a remote layout that differs from the Mac's.
    public var unicodeTextInput: Bool
    /// Shortcuts the app keeps (never sent to the remote). Exact modifiers, `*` = any key.
    public var reservedShortcuts: [MacChord]
    public var rules: [ShortcutRule]
    /// Forces the ISO/ANSI/JIS key placement instead of detecting it.
    public var keyboardTypeOverride: PhysicalKeyboardType?
    /// Windows keyboard layout for the session; nil = derived from the Mac input source.
    /// Not used by the engine itself; the app sends it at connect.
    public var layoutOverride: WindowsKeyboardLayoutID?
    /// A lone ⌘ (⌥) press longer than this does not send a Win (Alt) tap; <= 0 disables the limit.
    public var modifierTapTimeout: Double

    public init(
        mode: Mode = .macShortcuts,
        optionStrategy: OptionStrategy = .smart,
        unicodeTextInput: Bool = false,
        reservedShortcuts: [MacChord] = KeyboardConfig.defaultReservedShortcuts,
        rules: [ShortcutRule] = ShortcutRule.defaults,
        keyboardTypeOverride: PhysicalKeyboardType? = nil,
        layoutOverride: WindowsKeyboardLayoutID? = nil,
        modifierTapTimeout: Double = 0.5
    ) {
        self.mode = mode
        self.optionStrategy = optionStrategy
        self.unicodeTextInput = unicodeTextInput
        self.reservedShortcuts = reservedShortcuts
        self.rules = rules
        self.keyboardTypeOverride = keyboardTypeOverride
        self.layoutOverride = layoutOverride
        self.modifierTapTimeout = modifierTapTimeout
    }

    /// ⌘Q (quit), ⌃⌘F (full screen), everything with ⌃⌥⌘ (app shortcuts).
    public static let defaultReservedShortcuts: [MacChord] = [
        "cmd+q", "ctrl+cmd+f", "ctrl+opt+cmd+*", "ctrl+opt+shift+cmd+*",
    ].map { try! MacChord($0) }
}

extension KeyboardConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, optionStrategy, unicodeTextInput, reservedShortcuts, rules
        case keyboardTypeOverride, layoutOverride, modifierTapTimeout
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = KeyboardConfig()
        self.init(
            mode: try container.decodeIfPresent(Mode.self, forKey: .mode) ?? defaults.mode,
            optionStrategy: try container.decodeIfPresent(OptionStrategy.self, forKey: .optionStrategy)
                ?? defaults.optionStrategy,
            unicodeTextInput: try container.decodeIfPresent(Bool.self, forKey: .unicodeTextInput)
                ?? defaults.unicodeTextInput,
            reservedShortcuts: try container.decodeIfPresent([MacChord].self, forKey: .reservedShortcuts)
                ?? defaults.reservedShortcuts,
            rules: try container.decodeIfPresent([ShortcutRule].self, forKey: .rules) ?? defaults.rules,
            keyboardTypeOverride: try container.decodeIfPresent(PhysicalKeyboardType.self, forKey: .keyboardTypeOverride),
            layoutOverride: try container.decodeIfPresent(WindowsKeyboardLayoutID.self, forKey: .layoutOverride),
            modifierTapTimeout: try container.decodeIfPresent(Double.self, forKey: .modifierTapTimeout)
                ?? defaults.modifierTapTimeout
        )
    }
}
