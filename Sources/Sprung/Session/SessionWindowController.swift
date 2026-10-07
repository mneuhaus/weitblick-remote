import AppKit
import KeyboardEngine
import os
import SprungKit

/// One session window: owns the RDP session, routes keyboard and clipboard to it and keeps the
/// remote resolution in sync with the window size.
@MainActor
final class SessionWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, RDPSessionDelegate {
    private let session: RDPSession
    private let sessionView: SessionView
    private let keyboard: SessionKeyboard
    private let clipboard: ClipboardSync
    private var shortcutTap: SystemShortcutTap!
    private let retina: Bool
    private var keyMonitor: Any?
    private var appObservers: [NSObjectProtocol] = []
    private var pendingResize: DispatchWorkItem?
    private var finished = false
    /// Called once the window has closed.
    var onClose: (() -> Void)?

    /// Waiting time after the last window size change before asking the server to resize.
    private static let resizeDebounce: TimeInterval = 0.3
    private static let logger = Logger(subsystem: "nrw.neuhaus.sprung", category: "window")

    /// `configuration.desktopSize` and `scale` are derived from the window; Retina asks for
    /// one remote pixel per screen pixel at 200 % Windows scaling.
    init?(configuration: SessionConfiguration, keyboardConfig: KeyboardConfig, retina: Bool) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame.size
        let contentSize = NSSize(width: min(1440, visible.width * 0.85).rounded(), height: min(900, visible.height * 0.85).rounded())

        var configuration = configuration
        let backing = retina ? screen.backingScaleFactor : 1
        configuration.desktopSize = Self.pixelSize(for: contentSize, backingScale: backing)
        configuration.scale = Self.remoteScale(backingScale: backing)
        guard let session = RDPSession(configuration: configuration) else { return nil }

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = configuration.host
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.center()

        self.session = session
        self.retina = retina
        self.sessionView = SessionView(frame: NSRect(origin: .zero, size: contentSize))
        self.keyboard = SessionKeyboard(remote: session, config: keyboardConfig)
        self.clipboard = ClipboardSync(remote: session.clipboard, pasteboard: .general)
        super.init(window: window)
        shortcutTap = SystemShortcutTap { [unowned self] event in consumeCapturedKey(event) }

        window.contentView = sessionView
        window.delegate = self
        sessionView.session = session
        sessionView.willSendPointerPress = { [unowned self] in keyboard.prepareForPointerEvent() }
        session.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isConnected: Bool { session.state == .connected }

    func start() {
        showWindow(nil)
        window?.makeFirstResponder(sessionView)
        installKeyMonitor()
        observeApp()
        window?.subtitle = "Verbinde…"
        session.connect()
    }

    // MARK: RDPSessionDelegate

    func session(_ session: RDPSession, didReceive event: RDPSessionEvent) {
        switch event {
        case .connected:
            window?.subtitle = ""
            if window?.isKeyWindow == true { keyboard.focusGained() }
            if NSApp.isActive { clipboard.startWatching() }
            updateShortcutCapture()
            scheduleResolutionUpdate() // the window may have changed while connecting
        case .disconnected(let code, let message):
            sessionEnded(code: code, message: message)
        case .frameReady:
            sessionView.setNeedsPresent()
        case .desktopResized(let size):
            Self.logger.notice("desktop resized to \(size.description, privacy: .public)")
            sessionView.setNeedsPresent()
        case .pointer(let pointer):
            sessionView.apply(pointer)
        }
    }

    private func sessionEnded(code: UInt32, message: String) {
        guard !finished, let window else { return }
        finished = true
        stopInput()
        guard code != 0 else {
            window.close()
            return
        }
        Self.logger.error("session ended: \(message, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Verbindung zu \(session.configuration.host) beendet"
        alert.informativeText = message
        alert.beginSheetModal(for: window) { _ in window.close() }
    }

    /// Keyboard, shortcut tap and clipboard let go of the session.
    private func stopInput() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        appObservers.forEach(NotificationCenter.default.removeObserver)
        appObservers = []
        shortcutTap.stop()
        keyboard.stop()
        clipboard.sessionWillEnd()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        // A local monitor sees every key event of the app, including key-ups AppKit swallows
        // while ⌘ is held, before menus get key equivalents.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] incoming in
            nonisolated(unsafe) let event = incoming
            let consumed = MainActor.assumeIsolated { self?.forwardToSession(event) ?? false }
            return consumed ? nil : incoming
        }
    }

    /// Sends a key event of this window to the session unless the engine keeps it for the app.
    private func forwardToSession(_ event: NSEvent) -> Bool {
        guard event.window === window, isConnected, let keyEvent = KeyEvent(event) else { return false }
        return keyboard.handle(keyEvent)
    }

    /// Events from the shortcut tap. Reserved shortcuts pass on to AppKit through the monitor.
    private func consumeCapturedKey(_ event: CGEvent) -> Bool {
        guard shouldCaptureSystemShortcuts else {
            DispatchQueue.main.async { [weak self] in self?.updateShortcutCapture() }
            return false
        }
        guard let keyEvent = KeyEvent(event), !keyboard.isReserved(keyEvent) else { return false }
        return keyboard.handle(keyEvent)
    }

    private var shouldCaptureSystemShortcuts: Bool {
        guard isConnected, let window else { return false }
        return SystemShortcutCapture.setting.applies(
            sessionIsKey: window.isKeyWindow, appIsActive: NSApp.isActive,
            isFullScreen: window.styleMask.contains(.fullScreen))
    }

    private func updateShortcutCapture() {
        if shouldCaptureSystemShortcuts {
            if !shortcutTap.start() { Self.logger.notice("system shortcuts stay local: no Accessibility permission") }
        } else {
            shortcutTap.stop()
        }
    }

    private func observeApp() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification, .systemShortcutCaptureChanged,
        ]
        appObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let name = notification.name
                MainActor.assumeIsolated { self?.appStateChanged(name) }
            }
        }
    }

    private func appStateChanged(_ name: Notification.Name) {
        switch name {
        case NSApplication.didBecomeActiveNotification:
            guard isConnected else { break }
            clipboard.checkPasteboard()
            clipboard.startWatching()
        case NSApplication.didResignActiveNotification:
            clipboard.stopWatching()
        default:
            break
        }
        updateShortcutCapture()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard isConnected else { return }
        keyboard.focusGained()
        clipboard.checkPasteboard()
        updateShortcutCapture()
    }

    func windowDidResignKey(_ notification: Notification) {
        updateShortcutCapture()
        keyboard.focusLost()
    }

    func windowDidEnterFullScreen(_ notification: Notification) { updateShortcutCapture() }
    func windowDidExitFullScreen(_ notification: Notification) { updateShortcutCapture() }

    // MARK: Session menu

    private static let ctrlAltDelete = try! WindowsChord("ctrl+alt+delete")
    private static let windowsKey = try! WindowsChord("win")
    private static let altTab = try! WindowsChord("alt+tab")
    private static let printScreen = try! WindowsChord("printscreen")

    @objc func sendCtrlAltDelete(_ sender: Any?) { keyboard.tap(Self.ctrlAltDelete) }
    @objc func sendWindowsKey(_ sender: Any?) { keyboard.tap(Self.windowsKey) }
    @objc func sendAltTab(_ sender: Any?) { keyboard.tap(Self.altTab) }
    @objc func sendPrintScreen(_ sender: Any?) { keyboard.tap(Self.printScreen) }

    @objc func selectKeyboardMode(_ sender: NSMenuItem) {
        var config = keyboard.config
        config.mode = SessionMenu.keyboardModes[sender.tag]
        keyboard.apply(config)
    }

    @objc func selectOptionStrategy(_ sender: NSMenuItem) {
        var config = keyboard.config
        config.optionStrategy = SessionMenu.optionStrategies[sender.tag]
        keyboard.apply(config)
    }

    @objc func toggleClipboardSync(_ sender: Any?) {
        clipboard.isEnabled.toggle()
    }

    @objc func selectSystemShortcutCapture(_ sender: NSMenuItem) {
        SystemShortcutCapture.setting = SystemShortcutCapture.allCases[sender.tag]
        NotificationCenter.default.post(name: .systemShortcutCaptureChanged, object: nil)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectKeyboardMode(_:)):
            item.state = SessionMenu.keyboardModes[item.tag] == keyboard.config.mode ? .on : .off
        case #selector(selectOptionStrategy(_:)):
            item.state = SessionMenu.optionStrategies[item.tag] == keyboard.config.optionStrategy ? .on : .off
            return keyboard.config.mode == .macShortcuts
        case #selector(toggleClipboardSync(_:)):
            item.state = clipboard.isEnabled ? .on : .off
            return session.configuration.clipboard
        case #selector(selectSystemShortcutCapture(_:)):
            item.state = SystemShortcutCapture.allCases[item.tag] == SystemShortcutCapture.setting ? .on : .off
            return true
        default:
            break
        }
        return isConnected
    }

    // MARK: Resolution

    func windowDidResize(_ notification: Notification) { scheduleResolutionUpdate() }
    func windowDidChangeBackingProperties(_ notification: Notification) { scheduleResolutionUpdate() }

    private func scheduleResolutionUpdate() {
        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.sendResolution() }
        }
        pendingResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeDebounce, execute: work)
    }

    private func sendResolution() {
        guard isConnected, let window else { return }
        let backing = retina ? window.backingScaleFactor : 1
        let size = Self.pixelSize(for: sessionView.bounds.size, backingScale: backing)
        Self.logger.notice("requesting remote size \(size.description, privacy: .public)")
        session.setResolution(size, scale: Self.remoteScale(backingScale: backing))
    }

    private static func pixelSize(for points: NSSize, backingScale: CGFloat) -> PixelSize {
        // RDP wants an even width; the bridge clamps to 200…8192.
        let width = Int((points.width * backingScale).rounded()) & ~1
        return PixelSize(width: width, height: Int((points.height * backingScale).rounded()))
    }

    private static func remoteScale(backingScale: CGFloat) -> RemoteScale {
        RemoteScale(desktop: UInt32((backingScale * 100).rounded()), device: 100)
    }

    // MARK: Teardown

    func windowWillClose(_ notification: Notification) {
        pendingResize?.cancel()
        if !finished { stopInput() }
        sessionView.tearDown()
        session.delegate = nil
        session.close()
        onClose?()
    }
}

extension Notification.Name {
    static let systemShortcutCaptureChanged = Notification.Name("nrw.neuhaus.sprung.systemShortcutCaptureChanged")
}
