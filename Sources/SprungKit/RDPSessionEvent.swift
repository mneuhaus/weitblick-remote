import Foundation

/// Everything a session reports, delivered on the main actor in order.
public enum RDPSessionEvent: Sendable {
    case connected
    /// The session is over. `code` is FreeRDP's error code (0 when requested); `message` is German
    /// text for the user. `RDPSession.disconnectReason` says why.
    case disconnected(code: UInt32, message: String)
    /// The connection dropped and attempt `attempt` (1, 2, …) to get it back starts. Input is
    /// dropped until `.reconnected`; release local key state.
    case reconnecting(attempt: Int)
    /// Back in the same Windows session; every remote key is up again (send a sync).
    case reconnected
    /// New pixels are ready; read them with `RDPSession.withFramebuffer`.
    case frameReady
    case desktopResized(PixelSize)
    case pointer(RemotePointerEvent)
}

public enum RemotePointerEvent: Sendable {
    case new(RemotePointerImage)
    case free(id: UInt64)
    case set(id: UInt64)
    case hidden
    case systemDefault
    /// The server moved the cursor (remote pixels).
    case moved(x: Int, y: Int)
}

/// A server cursor shape in remote pixels.
public struct RemotePointerImage: Sendable {
    public let id: UInt64
    public let width: Int
    public let height: Int
    public let hotspotX: Int
    public let hotspotY: Int
    /// BGRA32, straight alpha, top-down, `width * 4` bytes per row.
    public let bgra: Data
}
