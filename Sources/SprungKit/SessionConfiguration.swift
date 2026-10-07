import Foundation

/// Everything needed to open one RDP session.
public struct SessionConfiguration: Sendable {
    public var host: String
    public var port: UInt16 = 3389
    public var username: String
    public var domain: String = ""
    public var password: String
    /// Initial remote desktop size in pixels.
    public var desktopSize: PixelSize
    public var scale: RemoteScale = .standard
    /// Windows keyboard layout id (KLID), e.g. 0x0407 German. The app sets it from the Mac input source.
    public var keyboardLayout: UInt32 = 0x0407
    public var ignoreCertificate = false
    public var audioPlayback = true
    /// Clipboard redirection (cliprdr channel).
    public var clipboard = true
    /// FreeRDP's own state (license store; certificates are never stored there).
    public var stateDirectory = URL.applicationSupportDirectory.appending(path: "Sprung/FreeRDP", directoryHint: .isDirectory)

    public init(host: String, username: String, password: String, desktopSize: PixelSize) {
        self.host = host
        self.username = username
        self.password = password
        self.desktopSize = desktopSize
    }
}

public struct PixelSize: Equatable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width)x\(height)" }
}

/// Windows display scaling sent to the server (percent).
public struct RemoteScale: Equatable, Sendable {
    /// 100…500; 200 makes a Retina-sized desktop look like 100 % on a normal screen.
    public var desktop: UInt32
    /// 100, 140 or 180.
    public var device: UInt32

    public static let standard = RemoteScale(desktop: 100, device: 100)

    public init(desktop: UInt32, device: UInt32) {
        self.desktop = desktop
        self.device = device
    }
}
