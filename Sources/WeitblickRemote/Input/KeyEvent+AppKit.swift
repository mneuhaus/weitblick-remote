import AppKit
import KeyboardEngine
import KeyboardEngineCarbon

extension KeyEvent {
    /// A keyDown, keyUp or flagsChanged event from AppKit.
    init?(_ event: NSEvent) {
        let kind: Kind
        switch event.type {
        case .keyDown: kind = .down
        case .keyUp: kind = .up
        case .flagsChanged: kind = .flagsChanged
        default: return nil
        }
        self.init(
            kind: kind, keyCode: event.keyCode,
            modifiers: ModifierFlags(eventFlags: UInt64(event.modifierFlags.rawValue)),
            isRepeat: kind == .down && event.isARepeat,
            timestamp: event.timestamp,
            keyboardType: event.cgEvent.map(Self.keyboardType))
    }

    /// A key event from the system shortcut tap (same fields, before AppKit sees it).
    init?(_ event: CGEvent) {
        let kind: Kind
        switch event.type {
        case .keyDown: kind = .down
        case .keyUp: kind = .up
        case .flagsChanged: kind = .flagsChanged
        default: return nil
        }
        self.init(
            kind: kind, keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: ModifierFlags(eventFlags: event.flags.rawValue),
            isRepeat: kind == .down && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            timestamp: Double(event.timestamp) / 1_000_000_000,
            keyboardType: Self.keyboardType(event))
    }

    private static func keyboardType(_ event: CGEvent) -> PhysicalKeyboardType {
        PhysicalKeyboardType(macKeyboardType: UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeyboardType)))
    }
}

extension ModifierFlags {
    /// The modifier keys held right now (device dependent, left/right distinguished).
    static var current: ModifierFlags {
        ModifierFlags(eventFlags: CGEventSource.flagsState(.combinedSessionState).rawValue)
    }
}
