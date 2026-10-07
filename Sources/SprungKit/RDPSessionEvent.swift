import Foundation

/// Everything a session reports, delivered on the main actor in order.
public enum RDPSessionEvent: Sendable {
    case connected
    /// `code` is 0 for a clean, user-initiated disconnect.
    case disconnected(code: UInt32, message: String)
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

public struct ServerCertificate: Sendable {
    public let host: String
    public let port: UInt16
    public let commonName: String
    public let subject: String
    public let issuer: String
    public let fingerprint: String
    public let changed: Bool
}
