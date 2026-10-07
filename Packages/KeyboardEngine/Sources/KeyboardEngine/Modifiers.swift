/// Side-agnostic Mac modifiers, as used in shortcut notation (`cmd+shift+z`).
public struct MacModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = MacModifiers(rawValue: 1 << 0)
    public static let option = MacModifiers(rawValue: 1 << 1)
    public static let control = MacModifiers(rawValue: 1 << 2)
    public static let shift = MacModifiers(rawValue: 1 << 3)

    init(_ flags: ModifierFlags) {
        self = []
        if !flags.isDisjoint(with: .command) { insert(.command) }
        if !flags.isDisjoint(with: .option) { insert(.option) }
        if !flags.isDisjoint(with: .control) { insert(.control) }
        if !flags.isDisjoint(with: .shift) { insert(.shift) }
    }
}

/// Side-agnostic Windows modifiers of an output chord.
public struct WindowsModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = WindowsModifiers(rawValue: 1 << 0)
    public static let alt = WindowsModifiers(rawValue: 1 << 1)
    public static let shift = WindowsModifiers(rawValue: 1 << 2)
    public static let windows = WindowsModifiers(rawValue: 1 << 3)
}

/// One of the eight physical modifier keys of a Mac keyboard.
enum PhysicalModifier: CaseIterable {
    case leftShift, rightShift, leftControl, rightControl
    case leftOption, rightOption, leftCommand, rightCommand

    init?(keyCode: UInt16) {
        switch keyCode {
        case 0x38: self = .leftShift
        case 0x3C: self = .rightShift
        case 0x3B: self = .leftControl
        case 0x3E: self = .rightControl
        case 0x3A: self = .leftOption
        case 0x3D: self = .rightOption
        case 0x37: self = .leftCommand
        case 0x36: self = .rightCommand
        default: return nil
        }
    }

    var flag: ModifierFlags {
        switch self {
        case .leftShift: .leftShift
        case .rightShift: .rightShift
        case .leftControl: .leftControl
        case .rightControl: .rightControl
        case .leftOption: .leftOption
        case .rightOption: .rightOption
        case .leftCommand: .leftCommand
        case .rightCommand: .rightCommand
        }
    }

    /// The same physical key on a PC keyboard (Windows-direct mode: ⌘ = Win, ⌥ = Alt).
    var windowsKey: RemoteModifier {
        switch self {
        case .leftShift: .leftShift
        case .rightShift: .rightShift
        case .leftControl: .leftControl
        case .rightControl: .rightControl
        case .leftOption: .leftAlt
        case .rightOption: .rightAlt
        case .leftCommand: .leftWindows
        case .rightCommand: .rightWindows
        }
    }
}

/// A modifier key on the remote (PC) keyboard.
enum RemoteModifier: CaseIterable {
    // Declaration order is the press order; releases go in reverse.
    case leftControl, rightControl, leftAlt, rightAlt, leftShift, rightShift, leftWindows, rightWindows

    var scancode: Scancode {
        switch self {
        case .leftControl: Scancode(0x1D)
        case .rightControl: .e0(0x1D)
        case .leftAlt: Scancode(0x38)
        case .rightAlt: .e0(0x38)
        case .leftShift: Scancode(0x2A)
        case .rightShift: Scancode(0x36)
        case .leftWindows: .e0(0x5B)
        case .rightWindows: .e0(0x5C)
        }
    }

    var kind: WindowsModifiers {
        switch self {
        case .leftControl, .rightControl: .control
        case .leftAlt, .rightAlt: .alt
        case .leftShift, .rightShift: .shift
        case .leftWindows, .rightWindows: .windows
        }
    }

    var isLeft: Bool {
        switch self {
        case .leftControl, .leftAlt, .leftShift, .leftWindows: true
        default: false
        }
    }

    init?(scancode: Scancode) {
        guard let match = Self.allCases.first(where: { $0.scancode == scancode }) else { return nil }
        self = match
    }
}
