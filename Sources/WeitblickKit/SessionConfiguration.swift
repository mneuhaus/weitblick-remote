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
    /// Skips certificate checks entirely (Jump's "IgnoreCertificateErrors").
    public var ignoreCertificate = false
    /// SHA-256 fingerprints (colon-separated hex, any case) accepted without asking. A different
    /// certificate is reported as `ServerCertificate.changed`.
    public var trustedCertificateFingerprints: [String] = []
    /// Network Level Authentication. Off for old targets (Windows 7, IoT): TLS or standard RDP
    /// security, and Windows checks the credentials on its own logon screen inside the session (a
    /// wrong password then shows there instead of ending with `.logonFailed`).
    public var nla = true
    /// Connects to the console session (mstsc /admin).
    public var consoleSession = false
    /// Program started instead of the desktop ("" = desktop), and its working directory.
    public var alternateShell = ""
    public var workingDirectory = ""
    /// Load-balancer routing token (.rdp "loadbalanceinfo", e.g. "tsv://MS Terminal Services Plugin.1.Farm").
    public var loadBalanceInfo = ""
    public var audio: AudioPlayback = .local
    /// Microphone redirection; macOS asks for permission when a remote app first records.
    public var microphone = false
    /// Redirects the Mac's printers (CUPS).
    public var printers = false
    /// Local folders shown in the session as \\tsclient\<name>.
    public var drives: [SharedDrive] = []
    /// Clipboard redirection (cliprdr channel).
    public var clipboard = true
    /// Reconnects with backoff after a network drop (`.reconnecting` / `.reconnected`).
    public var autoReconnect = true
    /// FreeRDP's own state (license store; certificates are never stored there).
    public var stateDirectory = URL.applicationSupportDirectory
        .appending(path: AppIdentity.supportFolderName, directoryHint: .isDirectory)
        .appending(path: "FreeRDP", directoryHint: .isDirectory)

    public init(host: String, username: String, password: String, desktopSize: PixelSize) {
        self.host = host
        self.username = username
        self.password = password
        self.desktopSize = desktopSize
    }
}

public enum AudioPlayback: String, Sendable, CaseIterable {
    /// Played on the Mac.
    case local
    /// Played on the remote computer.
    case remote
    case off
}

/// A local folder redirected into the session.
public struct SharedDrive: Equatable, Sendable {
    /// Share name in the session (\\tsclient\<name>); "/" and "\" become "_".
    public var name: String
    public var localPath: URL

    public init(name: String, localPath: URL) {
        self.name = name
        self.localPath = localPath
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
