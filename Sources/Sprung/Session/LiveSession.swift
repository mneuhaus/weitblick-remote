import AppKit
import KeyboardEngine
import SprungKit

/// One connection attempt of a session window: the RDP session with its keyboard and clipboard.
/// A retry (after the sign-in sheet or "Erneut verbinden") gets a new one; the window stays.
@MainActor
final class LiveSession {
    let session: RDPSession
    let keyboard: SessionKeyboard
    let clipboard: ClipboardSync
    /// Typed in the sign-in sheet with "im Schlüsselbund sichern": stored once the server accepts them.
    var credentialsToSave: Credentials?

    init?(configuration: SessionConfiguration, keyboardConfig: KeyboardConfig, clipboardEnabled: Bool,
          delegate: RDPSessionDelegate) {
        guard let session = RDPSession(configuration: configuration) else { return nil }
        self.session = session
        keyboard = SessionKeyboard(remote: session, config: keyboardConfig)
        // Created before connect(): it becomes the clipboard channel's delegate.
        clipboard = ClipboardSync(remote: session.clipboard, pasteboard: .general)
        clipboard.isEnabled = clipboardEnabled
        session.delegate = delegate
    }

    var isConnected: Bool { session.state == .connected }

    func connect() { session.connect() }

    /// Lets go of the session: no more input, the clipboard keeps what it can, the bridge shuts down.
    func end() {
        keyboard.stop()
        clipboard.stopWatching()
        clipboard.sessionWillEnd()
        session.delegate = nil
        session.close()
    }
}
