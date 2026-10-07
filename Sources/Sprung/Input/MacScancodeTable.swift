import Carbon.HIToolbox

/// A PC/AT set 1 scancode with its E0 (extended) flag.
struct Scancode: Equatable {
    let code: UInt16
    let extended: Bool

    init(_ code: UInt16, extended: Bool = false) {
        self.code = code
        self.extended = extended
    }
}

/// Temporary M1 mapping from macOS virtual key codes to scancodes, by physical position.
/// The KeyboardEngine (M2) replaces this in M3.
enum MacScancodeTable {
    static func scancode(forKeyCode keyCode: UInt16, isISO: Bool = isISOKeyboard) -> Scancode? {
        switch Int(keyCode) {
        // On ISO keyboards macOS swaps these two codes relative to their ANSI positions.
        case kVK_ISO_Section: return Scancode(isISO ? 0x29 : 0x56)
        case kVK_ANSI_Grave: return Scancode(isISO ? 0x56 : 0x29)
        default: return table[Int(keyCode)]
        }
    }

    static var isISOKeyboard: Bool {
        KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO
    }

    private static let table: [Int: Scancode] = [
        kVK_ANSI_A: Scancode(0x1E), kVK_ANSI_S: Scancode(0x1F), kVK_ANSI_D: Scancode(0x20),
        kVK_ANSI_F: Scancode(0x21), kVK_ANSI_H: Scancode(0x23), kVK_ANSI_G: Scancode(0x22),
        kVK_ANSI_Z: Scancode(0x2C), kVK_ANSI_X: Scancode(0x2D), kVK_ANSI_C: Scancode(0x2E),
        kVK_ANSI_V: Scancode(0x2F), kVK_ANSI_B: Scancode(0x30), kVK_ANSI_Q: Scancode(0x10),
        kVK_ANSI_W: Scancode(0x11), kVK_ANSI_E: Scancode(0x12), kVK_ANSI_R: Scancode(0x13),
        kVK_ANSI_Y: Scancode(0x15), kVK_ANSI_T: Scancode(0x14), kVK_ANSI_1: Scancode(0x02),
        kVK_ANSI_2: Scancode(0x03), kVK_ANSI_3: Scancode(0x04), kVK_ANSI_4: Scancode(0x05),
        kVK_ANSI_6: Scancode(0x07), kVK_ANSI_5: Scancode(0x06), kVK_ANSI_Equal: Scancode(0x0D),
        kVK_ANSI_9: Scancode(0x0A), kVK_ANSI_7: Scancode(0x08), kVK_ANSI_Minus: Scancode(0x0C),
        kVK_ANSI_8: Scancode(0x09), kVK_ANSI_0: Scancode(0x0B), kVK_ANSI_RightBracket: Scancode(0x1B),
        kVK_ANSI_O: Scancode(0x18), kVK_ANSI_U: Scancode(0x16), kVK_ANSI_LeftBracket: Scancode(0x1A),
        kVK_ANSI_I: Scancode(0x17), kVK_ANSI_P: Scancode(0x19), kVK_Return: Scancode(0x1C),
        kVK_ANSI_L: Scancode(0x26), kVK_ANSI_J: Scancode(0x24), kVK_ANSI_Quote: Scancode(0x28),
        kVK_ANSI_K: Scancode(0x25), kVK_ANSI_Semicolon: Scancode(0x27), kVK_ANSI_Backslash: Scancode(0x2B),
        kVK_ANSI_Comma: Scancode(0x33), kVK_ANSI_Slash: Scancode(0x35), kVK_ANSI_N: Scancode(0x31),
        kVK_ANSI_M: Scancode(0x32), kVK_ANSI_Period: Scancode(0x34), kVK_Tab: Scancode(0x0F),
        kVK_Space: Scancode(0x39), kVK_Delete: Scancode(0x0E), kVK_Escape: Scancode(0x01),
        kVK_Command: Scancode(0x5B, extended: true), kVK_RightCommand: Scancode(0x5C, extended: true),
        kVK_Shift: Scancode(0x2A), kVK_RightShift: Scancode(0x36), kVK_CapsLock: Scancode(0x3A),
        kVK_Option: Scancode(0x38), kVK_RightOption: Scancode(0x38, extended: true),
        kVK_Control: Scancode(0x1D), kVK_RightControl: Scancode(0x1D, extended: true),
        kVK_F1: Scancode(0x3B), kVK_F2: Scancode(0x3C), kVK_F3: Scancode(0x3D), kVK_F4: Scancode(0x3E),
        kVK_F5: Scancode(0x3F), kVK_F6: Scancode(0x40), kVK_F7: Scancode(0x41), kVK_F8: Scancode(0x42),
        kVK_F9: Scancode(0x43), kVK_F10: Scancode(0x44), kVK_F11: Scancode(0x57), kVK_F12: Scancode(0x58),
        kVK_F13: Scancode(0x37, extended: true), // Print Screen
        kVK_F14: Scancode(0x46),                 // Scroll Lock
        kVK_F15: Scancode(0x46, extended: true), // Pause
        kVK_F16: Scancode(0x67), kVK_F17: Scancode(0x68), kVK_F18: Scancode(0x69),
        kVK_F19: Scancode(0x6A), kVK_F20: Scancode(0x6B),
        kVK_Help: Scancode(0x52, extended: true), // Insert
        kVK_Home: Scancode(0x47, extended: true), kVK_End: Scancode(0x4F, extended: true),
        kVK_PageUp: Scancode(0x49, extended: true), kVK_PageDown: Scancode(0x51, extended: true),
        kVK_ForwardDelete: Scancode(0x53, extended: true),
        kVK_LeftArrow: Scancode(0x4B, extended: true), kVK_RightArrow: Scancode(0x4D, extended: true),
        kVK_DownArrow: Scancode(0x50, extended: true), kVK_UpArrow: Scancode(0x48, extended: true),
        kVK_ANSI_KeypadDecimal: Scancode(0x53), kVK_ANSI_KeypadMultiply: Scancode(0x37),
        kVK_ANSI_KeypadPlus: Scancode(0x4E), kVK_ANSI_KeypadClear: Scancode(0x45), // Num Lock
        kVK_ANSI_KeypadDivide: Scancode(0x35, extended: true), kVK_ANSI_KeypadEnter: Scancode(0x1C, extended: true),
        kVK_ANSI_KeypadMinus: Scancode(0x4A), kVK_ANSI_KeypadEquals: Scancode(0x59),
        kVK_ANSI_Keypad0: Scancode(0x52), kVK_ANSI_Keypad1: Scancode(0x4F), kVK_ANSI_Keypad2: Scancode(0x50),
        kVK_ANSI_Keypad3: Scancode(0x51), kVK_ANSI_Keypad4: Scancode(0x4B), kVK_ANSI_Keypad5: Scancode(0x4C),
        kVK_ANSI_Keypad6: Scancode(0x4D), kVK_ANSI_Keypad7: Scancode(0x47), kVK_ANSI_Keypad8: Scancode(0x48),
        kVK_ANSI_Keypad9: Scancode(0x49),
        kVK_ContextualMenu: Scancode(0x5D, extended: true),
        kVK_JIS_Yen: Scancode(0x7D), kVK_JIS_Underscore: Scancode(0x73), kVK_JIS_KeypadComma: Scancode(0x7E),
        kVK_JIS_Eisu: Scancode(0x7B), kVK_JIS_Kana: Scancode(0x70),
    ]
}
