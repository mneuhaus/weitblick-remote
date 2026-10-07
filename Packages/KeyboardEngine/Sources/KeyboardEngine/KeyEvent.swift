/// A macOS key event, reduced to what the engine needs. The app converts NSEvent/CGEvent into this.
public struct KeyEvent: Equatable, Sendable {
    public enum Kind: Sendable {
        case down
        case up
        /// A modifier key (⌘ ⌥ ⌃ ⇧, Caps Lock, fn) changed; `modifiers` holds the new state.
        case flagsChanged
    }

    public var kind: Kind
    /// macOS virtual key code (`kVK_*`, `NSEvent.keyCode`).
    public var keyCode: UInt16
    /// Modifier state after the event, device dependent (left/right distinguished).
    public var modifiers: ModifierFlags
    public var isRepeat: Bool
    /// Seconds, same clock as `NSEvent.timestamp`. Only differences are used.
    public var timestamp: Double
    /// Physical keyboard of the event (`CGEvent` field `keyboardEventKeyboardType`, converted with
    /// `PhysicalKeyboardType(macKeyboardType:)`). `nil` falls back to the layout provider's type.
    public var keyboardType: PhysicalKeyboardType?

    public init(
        kind: Kind,
        keyCode: UInt16,
        modifiers: ModifierFlags = [],
        isRepeat: Bool = false,
        timestamp: Double = 0,
        keyboardType: PhysicalKeyboardType? = nil
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.timestamp = timestamp
        self.keyboardType = keyboardType
    }
}

/// Device-dependent modifier state.
public struct ModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let leftShift = ModifierFlags(rawValue: 1 << 0)
    public static let rightShift = ModifierFlags(rawValue: 1 << 1)
    public static let leftControl = ModifierFlags(rawValue: 1 << 2)
    public static let rightControl = ModifierFlags(rawValue: 1 << 3)
    public static let leftOption = ModifierFlags(rawValue: 1 << 4)
    public static let rightOption = ModifierFlags(rawValue: 1 << 5)
    public static let leftCommand = ModifierFlags(rawValue: 1 << 6)
    public static let rightCommand = ModifierFlags(rawValue: 1 << 7)
    /// Caps Lock is a toggle: set while the lock is on.
    public static let capsLock = ModifierFlags(rawValue: 1 << 8)
    public static let function = ModifierFlags(rawValue: 1 << 9)

    public static let shift: ModifierFlags = [.leftShift, .rightShift]
    public static let control: ModifierFlags = [.leftControl, .rightControl]
    public static let option: ModifierFlags = [.leftOption, .rightOption]
    public static let command: ModifierFlags = [.leftCommand, .rightCommand]
    /// The eight physical modifier keys (no toggles, no fn).
    static let modifierKeys: ModifierFlags = [.shift, .control, .option, .command]

    /// Converts raw `NSEvent.ModifierFlags` / `CGEventFlags` bits, including the device-dependent
    /// `NX_DEVICE*KEYMASK` bits. A generic flag without side bits counts as the left key.
    public init(eventFlags raw: UInt64) {
        var flags: ModifierFlags = []
        func side(generic: UInt64, left: UInt64, right: UInt64, _ l: ModifierFlags, _ r: ModifierFlags) {
            guard raw & generic != 0 else { return }
            if raw & left != 0 { flags.insert(l) }
            if raw & right != 0 { flags.insert(r) }
            if raw & (left | right) == 0 { flags.insert(l) }
        }
        side(generic: 0x20000, left: 0x02, right: 0x04, .leftShift, .rightShift)
        side(generic: 0x40000, left: 0x01, right: 0x2000, .leftControl, .rightControl)
        side(generic: 0x80000, left: 0x20, right: 0x40, .leftOption, .rightOption)
        side(generic: 0x100000, left: 0x08, right: 0x10, .leftCommand, .rightCommand)
        if raw & 0x10000 != 0 { flags.insert(.capsLock) }
        if raw & 0x800000 != 0 { flags.insert(.function) }
        self = flags
    }
}
