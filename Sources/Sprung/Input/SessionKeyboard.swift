import AppKit
import Carbon.HIToolbox
import KeyboardEngine
import KeyboardEngineCarbon
import SprungKit

/// The keyboard of one session: Mac key events through the KeyboardEngine to the remote side.
/// Main thread only (the engine's layout provider uses Text Input Sources).
@MainActor
final class SessionKeyboard {
    private var engine: KeyboardEngine
    private unowned let remote: RemoteKeyboard
    private var inputSourceObserver: NSObjectProtocol?

    var config: KeyboardConfig { engine.config }

    init(remote: RemoteKeyboard, config: KeyboardConfig) {
        self.remote = remote
        engine = KeyboardEngine(config: config, layout: Self.currentLayout())
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLayout() }
        }
    }

    func stop() {
        if let inputSourceObserver { DistributedNotificationCenter.default().removeObserver(inputSourceObserver) }
        inputSourceObserver = nil
    }

    /// Sends the event to the session; false means it is an app shortcut for AppKit (⌃⌘F, ⌃⌥⌘…).
    func handle(_ event: KeyEvent) -> Bool {
        let output = engine.handle(event)
        remote.send(output.actions)
        return !output.passToApp
    }

    func isReserved(_ event: KeyEvent) -> Bool {
        engine.isReserved(event)
    }

    /// The session receives keys again (window became key, connected).
    func focusGained() {
        refreshLayout()
        remote.send(engine.focusGained(modifiers: .current))
    }

    /// The session stops receiving keys: nothing may stay pressed remotely.
    func focusLost() {
        remote.send(engine.focusLost())
        remote.releaseAllKeys()
    }

    /// Before a mouse button press or wheel event: ⌘-click becomes Ctrl-click.
    func prepareForPointerEvent() {
        remote.send(engine.prepareForPointerEvent())
    }

    func apply(_ config: KeyboardConfig) {
        remote.send(engine.apply(config))
    }

    /// Session menu commands such as Ctrl+Alt+Del.
    func tap(_ chord: WindowsChord) {
        remote.send(engine.tap(chord))
    }

    private func refreshLayout() {
        let layout = Self.currentLayout()
        guard layout.inputSourceID != (engine.layout as? UCKeyTranslateLayoutProvider)?.inputSourceID else { return }
        engine.layout = layout
    }

    private static func currentLayout() -> UCKeyTranslateLayoutProvider {
        if let current = UCKeyTranslateLayoutProvider.current() { return current }
        guard let us = UCKeyTranslateLayoutProvider(inputSourceID: "com.apple.keylayout.US") else {
            fatalError("No keyboard layout available")
        }
        return us
    }
}
