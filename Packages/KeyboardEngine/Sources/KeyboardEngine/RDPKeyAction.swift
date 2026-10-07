/// One RDP keyboard input event, in the order the app has to send them.
public enum RDPKeyAction: Hashable, Sendable {
    /// Set-1 make/break code; `extended` = E0 prefix (KBD_FLAGS_EXTENDED).
    case scancode(code: UInt8, extended: Bool, down: Bool)
    /// One UTF-16 code unit (non-BMP characters arrive as two surrogate units).
    case unicode(UInt16, down: Bool)
    /// Toggle-key synchronize event (send via `freerdp_input_send_focus_in_event`, like mstsc on focus).
    case sync(capsLock: Bool, numLock: Bool, scrollLock: Bool)
    /// The Pause key. It has no make/break pair; send `freerdp_input_send_keyboard_pause_event`
    /// (mstsc sequence: Ctrl with the E1 flag + NumLock make, then both breaks).
    case pause

    static func key(_ scancode: Scancode, down: Bool) -> RDPKeyAction {
        .scancode(code: scancode.code, extended: scancode.extended, down: down)
    }
}

/// A set-1 scancode with its E0 flag.
public struct Scancode: Hashable, Sendable, CustomStringConvertible {
    public var code: UInt8
    public var extended: Bool

    public init(_ code: UInt8, extended: Bool = false) {
        self.code = code
        self.extended = extended
    }

    static func e0(_ code: UInt8) -> Scancode { Scancode(code, extended: true) }

    public var description: String {
        (extended ? "E0 " : "") + hex(code)
    }
}

func hex(_ value: UInt8) -> String {
    let digits = Array("0123456789ABCDEF")
    return String([digits[Int(value >> 4)], digits[Int(value & 0xF)]])
}
