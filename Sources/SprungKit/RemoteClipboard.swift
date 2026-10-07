import Foundation
import os
import SprungBridge

/// A clipboard format as the RDP clipboard channel lists it.
public struct RemoteClipboardFormat: Hashable, Sendable {
    public var id: UInt32
    /// nil for standard Windows formats (CF_UNICODETEXT, CF_DIB, …).
    public var name: String?

    public init(id: UInt32, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

/// Clipboard channel events. They arrive on the channel thread: return quickly and never wait
/// for the main thread there.
public protocol RemoteClipboardDelegate: AnyObject, Sendable {
    /// The channel is up and expects the local format list.
    func remoteClipboardDidBecomeReady(_ clipboard: RemoteClipboard)
    func remoteClipboard(_ clipboard: RemoteClipboard, didAnswerAnnouncement accepted: Bool)
    func remoteClipboard(_ clipboard: RemoteClipboard, didChangeFormats formats: [RemoteClipboardFormat])
    /// Answer exactly once with `respond(with:)`.
    func remoteClipboard(_ clipboard: RemoteClipboard, didRequestFormat id: UInt32)
    /// Answer to `request(formatID:)`; nil if the server failed.
    func remoteClipboard(_ clipboard: RemoteClipboard, didReceive data: Data?)
}

/// The clipboard channel of one session. Thread safe. Calls return false while the channel is down
/// and after the session was closed.
public final class RemoteClipboard: Sendable {
    private struct State {
        var session: OpaquePointer?
        weak var delegate: (any RemoteClipboardDelegate)?
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    init() {}

    public var delegate: (any RemoteClipboardDelegate)? {
        get { state.withLock { $0.delegate } }
        set { state.withLock { $0.delegate = newValue } }
    }

    @discardableResult
    public func announce(_ formats: [RemoteClipboardFormat]) -> Bool {
        withSession { session in
            let names = formats.map { $0.name.flatMap { strdup($0) } }
            defer { names.forEach { free($0) } }
            let list = zip(formats, names).map { format, name in
                SprungClipboardFormat(id: format.id, name: name.map { UnsafePointer($0) })
            }
            return list.withUnsafeBufferPointer { sprung_session_clipboard_announce(session, $0.baseAddress, $0.count) }
        }
    }

    /// Keep at most one request outstanding: answers carry no id.
    @discardableResult
    public func request(formatID: UInt32) -> Bool {
        withSession { sprung_session_clipboard_request($0, formatID) }
    }

    /// Answers a `didRequestFormat`; nil reports failure.
    @discardableResult
    public func respond(with data: Data?) -> Bool {
        withSession { session in
            guard let data else { return sprung_session_clipboard_respond(session, false, nil, 0) }
            return data.withUnsafeBytes { bytes in
                sprung_session_clipboard_respond(
                    session, true, bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
            }
        }
    }

    // MARK: Session side

    func attach(_ session: OpaquePointer) {
        state.withLockUnchecked { $0.session = session }
    }

    /// After this no call reaches the bridge, so the session can be destroyed.
    func detach() {
        state.withLock { $0.session = nil }
    }

    /// The lock is held during the bridge call so `detach` waits for calls in progress.
    private func withSession(_ body: (OpaquePointer) -> Bool) -> Bool {
        state.withLockUnchecked { state in
            guard let session = state.session else { return false }
            return body(session)
        }
    }

    func notify(_ event: (any RemoteClipboardDelegate) -> Void) {
        guard let delegate = state.withLock({ $0.delegate }) else { return }
        event(delegate)
    }
}
