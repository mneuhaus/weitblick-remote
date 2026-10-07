import AppKit
import Carbon.HIToolbox
import os
import SprungKit

/// One session window: owns the RDP session, routes keyboard input to it and keeps the
/// remote resolution in sync with the window size.
@MainActor
final class SessionWindowController: NSWindowController, NSWindowDelegate, RDPSessionDelegate {
    private let session: RDPSession
    private let sessionView: SessionView
    private let keyInput: KeyInputHandling
    private let retina: Bool
    private var keyMonitor: Any?
    private var pendingResize: DispatchWorkItem?
    private var finished = false
    /// Called once the window has closed.
    var onClose: (() -> Void)?

    /// Waiting time after the last window size change before asking the server to resize.
    private static let resizeDebounce: TimeInterval = 0.3
    private static let logger = Logger(subsystem: "nrw.neuhaus.sprung", category: "window")

    /// `configuration.desktopSize` and `scale` are derived from the window; Retina asks for
    /// one remote pixel per screen pixel at 200 % Windows scaling.
    init?(configuration: SessionConfiguration, retina: Bool) {
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
        self.keyInput = RawKeyInputHandler(keyboard: session)
        super.init(window: window)

        window.contentView = sessionView
        window.delegate = self
        sessionView.session = session
        session.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func start() {
        showWindow(nil)
        window?.makeFirstResponder(sessionView)
        installKeyMonitor()
        window?.subtitle = "Verbinde…"
        session.connect()
    }

    // MARK: RDPSessionDelegate

    func session(_ session: RDPSession, didReceive event: RDPSessionEvent) {
        switch event {
        case .connected:
            window?.subtitle = ""
            if window?.isKeyWindow == true { keyInput.focusGained() }
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
        removeKeyMonitor()
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

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] incoming in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = incoming
            let consumed = MainActor.assumeIsolated { self?.forwardToSession(event) ?? false }
            return consumed ? nil : incoming
        }
    }

    /// Sends a key event of this window to the session unless it is a local shortcut.
    private func forwardToSession(_ event: NSEvent) -> Bool {
        guard event.window === window, session.state == .connected, !Self.isLocalShortcut(event) else { return false }
        keyInput.handle(event)
        return true
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Shortcuts that stay on the Mac: ⌃⌘F (full screen) and ⌘Q (quit).
    private static func isLocalShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch Int(event.keyCode) {
        case kVK_ANSI_F: return flags == [.command, .control]
        case kVK_ANSI_Q: return flags == [.command]
        default: return false
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if session.state == .connected { keyInput.focusGained() }
    }

    func windowDidResignKey(_ notification: Notification) {
        keyInput.focusLost()
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
        guard session.state == .connected, let window else { return }
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
        removeKeyMonitor()
        sessionView.tearDown()
        session.delegate = nil
        session.close()
        onClose?()
    }
}
