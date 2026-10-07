import SprungBridge

/// Keyboard output of a session, the target of the keyboard handler (raw table in M1,
/// KeyboardEngine from M3 on). Scancodes are PC/AT set 1 make codes plus the E0 flag.
@MainActor
public protocol RemoteKeyboard: AnyObject {
    /// A down for a key that is already down is sent as a repeat; ups for keys that are not
    /// down are dropped. Pause is (0x46, extended).
    func sendScancode(_ code: UInt16, extended: Bool, down: Bool)
    /// UTF-16 code unit; send surrogate pairs as two units.
    func sendUnicode(_ codeUnit: UInt16, down: Bool)
    func sendSync(capsLock: Bool, numLock: Bool, scrollLock: Bool)
    /// Key-up for every scancode currently down.
    func releaseAllKeys()
}

public enum MouseButton: Sendable {
    case left, right, middle, back, forward

    var bridgeValue: SprungMouseButton {
        switch self {
        case .left: SprungMouseButtonLeft
        case .right: SprungMouseButtonRight
        case .middle: SprungMouseButtonMiddle
        case .back: SprungMouseButtonX1
        case .forward: SprungMouseButtonX2
        }
    }
}

/// A position on the remote desktop in pixels.
public struct RemotePoint: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

extension RDPSession: RemoteKeyboard {
    public func sendScancode(_ code: UInt16, extended: Bool, down: Bool) {
        sprung_session_send_scancode(rawSession, code, extended, down)
    }

    public func sendUnicode(_ codeUnit: UInt16, down: Bool) {
        sprung_session_send_unicode(rawSession, codeUnit, down)
    }

    public func sendSync(capsLock: Bool, numLock: Bool, scrollLock: Bool) {
        sprung_session_send_sync(rawSession, capsLock, numLock, scrollLock)
    }

    public func releaseAllKeys() {
        sprung_session_release_all_keys(rawSession)
    }
}

extension RDPSession {
    public func sendMouseMove(to point: RemotePoint) {
        sprung_session_send_mouse_move(rawSession, Int32(clamping: point.x), Int32(clamping: point.y))
    }

    public func sendMouseButton(_ button: MouseButton, down: Bool, at point: RemotePoint) {
        sprung_session_send_mouse_button(
            rawSession, button.bridgeValue, down, Int32(clamping: point.x), Int32(clamping: point.y))
    }

    /// Deltas in Windows wheel units (120 per notch). Positive vertical scrolls up,
    /// positive horizontal scrolls right.
    public func sendMouseWheel(vertical: Int, horizontal: Int, at point: RemotePoint) {
        sprung_session_send_mouse_wheel(
            rawSession, Int32(clamping: vertical), Int32(clamping: horizontal),
            Int32(clamping: point.x), Int32(clamping: point.y))
    }
}
