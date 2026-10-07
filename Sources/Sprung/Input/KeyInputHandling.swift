import AppKit

/// Turns the session window's key events into remote keyboard input.
/// M1 ships a raw scancode pass-through; M3 swaps in the KeyboardEngine.
@MainActor
protocol KeyInputHandling: AnyObject {
    /// A keyDown, keyUp or flagsChanged event aimed at the session.
    func handle(_ event: NSEvent)
    /// The session window became key: resync the lock keys.
    func focusGained()
    /// The session window lost key status: release every key still held remotely.
    func focusLost()
}
