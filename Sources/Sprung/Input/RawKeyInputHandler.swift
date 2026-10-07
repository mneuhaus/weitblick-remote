import AppKit
import Carbon.HIToolbox
import SprungKit

/// M1 keyboard: every Mac key becomes the scancode at the same physical position
/// (⌘ = Win, ⌥ = Alt, ⌃ = Ctrl). No shortcut translation; that is the KeyboardEngine's job.
@MainActor
final class RawKeyInputHandler: KeyInputHandling {
    private unowned let keyboard: RemoteKeyboard

    init(keyboard: RemoteKeyboard) {
        self.keyboard = keyboard
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown: send(event.keyCode, down: true)
        case .keyUp: send(event.keyCode, down: false)
        case .flagsChanged: modifierChanged(event)
        default: break
        }
    }

    func focusGained() {
        // Macs have no Num Lock; keep it on so the keypad types digits.
        keyboard.sendSync(capsLock: NSEvent.modifierFlags.contains(.capsLock), numLock: true, scrollLock: false)
    }

    func focusLost() {
        keyboard.releaseAllKeys()
    }

    private func send(_ keyCode: UInt16, down: Bool) {
        guard let scancode = MacScancodeTable.scancode(forKeyCode: keyCode) else { return }
        keyboard.sendScancode(scancode.code, extended: scancode.extended, down: down)
    }

    private func modifierChanged(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        if keyCode == kVK_CapsLock {
            // macOS reports Caps Lock as a toggle, Windows wants a key press per toggle.
            send(event.keyCode, down: true)
            send(event.keyCode, down: false)
            return
        }
        guard let mask = Self.deviceMasks[keyCode] else { return }
        send(event.keyCode, down: event.modifierFlags.rawValue & mask != 0)
    }

    /// Device-dependent modifier bits (IOLLEvent.h NX_DEVICE*KEYMASK) tell left from right.
    private static let deviceMasks: [Int: UInt] = [
        kVK_Control: 0x0000_0001, kVK_RightControl: 0x0000_2000,
        kVK_Shift: 0x0000_0002, kVK_RightShift: 0x0000_0004,
        kVK_Command: 0x0000_0008, kVK_RightCommand: 0x0000_0010,
        kVK_Option: 0x0000_0020, kVK_RightOption: 0x0000_0040,
    ]
}
