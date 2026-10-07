import Foundation
import os
import SprungBridge

@MainActor
public protocol RDPSessionDelegate: AnyObject {
    func session(_ session: RDPSession, didReceive event: RDPSessionEvent)
}

/// One RDP connection. Main-actor API over SprungBridge; events arrive via the delegate.
@MainActor
public final class RDPSession {
    public enum State: Equatable, Sendable {
        case idle, connecting, connected, disconnected
    }

    public weak var delegate: RDPSessionDelegate?
    public private(set) var state: State = .idle
    /// Current remote desktop size in pixels.
    public private(set) var desktopSize: PixelSize
    public let configuration: SessionConfiguration
    /// The clipboard channel (inactive unless `configuration.clipboard`).
    public let clipboard: RemoteClipboard

    private let native: SessionHandle
    private var isClosed = false

    /// The bridge session, or nil once closed (the bridge treats NULL as a no-op).
    var rawSession: OpaquePointer? { isClosed ? nil : native.raw }

    /// The certificate policy runs on a FreeRDP thread and must decide immediately.
    public init?(
        configuration: SessionConfiguration,
        certificatePolicy: @escaping @Sendable (ServerCertificate) -> Bool = RDPSession.acceptAndLog
    ) {
        let clipboard = RemoteClipboard()
        let relay = EventRelay(clipboard: clipboard, certificatePolicy: certificatePolicy)
        var callbacks = relay.makeCallbacks()
        let values: [String] = [configuration.host, configuration.username, configuration.domain,
                                configuration.password, configuration.stateDirectory.path]
        let strings = values.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        try? FileManager.default.createDirectory(at: configuration.stateDirectory, withIntermediateDirectories: true)

        var config = SprungSessionConfig()
        config.host = UnsafePointer(strings[0])
        config.port = configuration.port
        config.username = UnsafePointer(strings[1])
        config.domain = UnsafePointer(strings[2])
        config.password = UnsafePointer(strings[3])
        config.width = UInt32(configuration.desktopSize.width)
        config.height = UInt32(configuration.desktopSize.height)
        config.desktopScaleFactor = configuration.scale.desktop
        config.deviceScaleFactor = configuration.scale.device
        config.keyboardLayout = configuration.keyboardLayout
        config.ignoreCertificate = configuration.ignoreCertificate
        config.audioPlayback = configuration.audioPlayback
        config.clipboard = configuration.clipboard
        config.stateDirectory = UnsafePointer(strings[4])

        guard let raw = sprung_session_create(&config, &callbacks) else { return nil }
        self.native = SessionHandle(raw: raw, relay: relay)
        self.configuration = configuration
        self.clipboard = clipboard
        clipboard.attach(raw)
        self.desktopSize = configuration.desktopSize
        relay.session = self
    }

    deinit {
        clipboard.detach()
        native.destroyInBackground()
    }

    public func connect() {
        guard state == .idle else { return }
        state = sprung_session_connect(rawSession) ? .connecting : .disconnected
    }

    /// Ends the session; `.disconnected` follows.
    public func disconnect() {
        sprung_session_disconnect(rawSession)
    }

    /// Starts disconnecting and freeing the session in the background. Idempotent; every
    /// other call is a no-op afterwards.
    public func close() {
        isClosed = true
        clipboard.detach()
        native.destroyInBackground()
    }

    /// Closes the session and waits until its bridge thread is gone.
    public func closeAndWait() async {
        close()
        await native.waitUntilDestroyed()
    }

    /// Blocks until every session created so far is torn down. Call before the process exits:
    /// FreeRDP's threads use global state (WLog) that `exit()` destroys under them.
    @discardableResult
    public nonisolated static func waitForAllSessionsToClose(timeout: TimeInterval) -> Bool {
        SessionHandle.alive.wait(timeout: .now() + timeout) == .success
    }

    public func setResolution(_ size: PixelSize, scale: RemoteScale) {
        sprung_session_set_resolution(rawSession, UInt32(size.width), UInt32(size.height), scale.desktop, scale.device)
    }

    /// Runs `body` with the framebuffer locked; nil if there is no framebuffer yet.
    /// Decoding waits while `body` runs, so keep it short.
    public func withFramebuffer<T>(_ body: (Framebuffer) throws -> T) rethrows -> T? {
        var raw = SprungFramebuffer()
        guard sprung_session_framebuffer_acquire(rawSession, &raw), let pixels = raw.pixels else { return nil }
        defer { sprung_session_framebuffer_release(rawSession) }
        return try body(Framebuffer(
            pixels: pixels, width: Int(raw.width), height: Int(raw.height), bytesPerRow: Int(raw.stride),
            dirtyRects: UnsafeBufferPointer(start: raw.dirtyRects, count: raw.dirtyRectCount)))
    }

    func handle(_ event: RDPSessionEvent) {
        switch event {
        case .connected: state = .connected
        case .disconnected: state = .disconnected
        case .desktopResized(let size): desktopSize = size
        case .frameReady, .pointer: break
        }
        delegate?.session(self, didReceive: event)
    }

    public nonisolated static func acceptAndLog(_ certificate: ServerCertificate) -> Bool {
        Logger.session.notice(
            "Accepting certificate of \(certificate.host, privacy: .public):\(certificate.port) (\(certificate.subject, privacy: .public)) sha256 \(certificate.fingerprint, privacy: .public)\(certificate.changed ? " [changed]" : "")")
        return true
    }
}

/// Locked view of the remote framebuffer (BGRA32, top-down). Valid only inside `withFramebuffer`.
public struct Framebuffer {
    public let pixels: UnsafePointer<UInt8>
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    /// Regions changed since the previous `withFramebuffer` call.
    public let dirtyRects: UnsafeBufferPointer<SprungRect>
}

extension Logger {
    static let session = Logger(subsystem: "nrw.neuhaus.sprung", category: "session")
}

/// Owns the C session and the relay its callbacks point to; destroys both exactly once.
private final class SessionHandle: Sendable {
    /// Entered by every session until its teardown has finished.
    static let alive = DispatchGroup()

    nonisolated(unsafe) let raw: OpaquePointer
    private let relay: EventRelay
    private let teardownStarted = OSAllocatedUnfairLock(initialState: false)
    private let teardown = DispatchGroup()

    init(raw: OpaquePointer, relay: EventRelay) {
        self.raw = raw
        self.relay = relay
        Self.alive.enter()
        teardown.enter()
    }

    /// Joining the bridge thread can take a moment (TLS shutdown), so never on the main thread.
    func destroyInBackground() {
        let alreadyStarted = teardownStarted.withLock { started in
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            sprung_session_destroy(self.raw)
            withExtendedLifetime(self.relay) {}
            self.teardown.leave()
            Self.alive.leave()
        }
    }

    func waitUntilDestroyed() async {
        await withCheckedContinuation { continuation in
            teardown.notify(queue: .global()) { continuation.resume() }
        }
    }
}
