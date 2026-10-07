import Foundation
import SprungKit

/// Records what a session reports so the smoke scenario can wait for it.
@MainActor
final class SmokeProbe: RDPSessionDelegate {
    let session: RDPSession
    private(set) var isConnected = false
    private(set) var ending: (code: UInt32, message: String)?
    private(set) var frameCount = 0
    private(set) var lastFrame = Date.distantPast
    private(set) var resizes: [PixelSize] = []
    private(set) var pointerImages: [UInt64: RemotePointerImage] = [:]
    private(set) var shownPointers: [UInt64] = []

    init?(configuration: SessionConfiguration) {
        guard let session = RDPSession(configuration: configuration) else { return nil }
        self.session = session
        session.delegate = self
    }

    func session(_ session: RDPSession, didReceive event: RDPSessionEvent) {
        switch event {
        case .connected:
            isConnected = true
        case .disconnected(let code, let message):
            ending = (code, message)
        case .frameReady:
            frameCount += 1
            lastFrame = Date()
            // Frame signals are coalesced until the framebuffer is read, so drain it.
            _ = session.withFramebuffer { _ in }
        case .desktopResized(let size):
            resizes.append(size)
        case .pointer(.new(let image)):
            pointerImages[image.id] = image
        case .pointer(.set(let id)):
            shownPointers.append(id)
        case .pointer:
            break
        }
    }

    /// Polls `condition` until it holds or `timeout` passes, failing early when the session ends.
    func wait(_ what: String, timeout: TimeInterval, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if let ending, what != "disconnect" {
                throw SmokeFailure("session ended while waiting for \(what): \(ending.message)")
            }
            if Date() > deadline { throw SmokeFailure("timed out after \(Int(timeout)) s waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Waits for the first frame, then until no new pixels arrived for `quiet` seconds.
    /// A desktop that keeps animating is not an error: after `settleLimit` the current frame counts.
    func waitForSettledFrame(quiet: TimeInterval = 1.5, settleLimit: TimeInterval = 10) async throws {
        try await wait("first frame", timeout: 30) { frameCount > 0 }
        let framesBefore = frameCount
        do {
            try await wait("frames to settle", timeout: settleLimit) { Date().timeIntervalSince(lastFrame) > quiet }
        } catch let failure as SmokeFailure where ending == nil {
            print("note: desktop still updating (\(frameCount - framesBefore) frames in \(Int(settleLimit)) s): \(failure)")
        }
    }
}

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
