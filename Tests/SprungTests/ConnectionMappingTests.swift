import ConnectionStore
import KeyboardEngine
import SprungKit
import XCTest

final class ConnectionMappingTests: XCTestCase {
    private let credentials = Credentials(username: "anna", domain: "BUERO", password: "geheim")
    private let desktop = RemoteDesktop(size: PixelSize(width: 2560, height: 1600), scale: RemoteScale(desktop: 200, device: 100))

    private func configuration(_ connection: Connection, layout: WindowsKeyboardLayoutID = .german) -> SessionConfiguration {
        SessionConfiguration(connection: connection, credentials: credentials, desktop: desktop, macKeyboardLayout: layout)
    }

    func testEndpointCredentialsAndDesktop() {
        let connection = Connection(name: "PC", host: "pc01.example", port: 13389, username: "ignored", domain: "ignored")
        let config = configuration(connection)
        XCTAssertEqual(config.host, "pc01.example")
        XCTAssertEqual(config.port, 13389)
        // The attempt's credentials win (they may come from the sign-in sheet).
        XCTAssertEqual(config.username, "anna")
        XCTAssertEqual(config.domain, "BUERO")
        XCTAssertEqual(config.password, "geheim")
        XCTAssertEqual(config.desktopSize, desktop.size)
        XCTAssertEqual(config.scale, desktop.scale)
        // FreeRDP's state lives in the app's single Application Support folder.
        XCTAssertEqual(config.stateDirectory.deletingLastPathComponent().standardizedFileURL,
                       ConnectionStore.applicationSupportDirectory.standardizedFileURL)
    }

    func testKeyboardLayoutFollowsTheMacUnlessOverridden() {
        var connection = Connection(name: "PC", host: "pc01.example")
        XCTAssertEqual(configuration(connection, layout: WindowsKeyboardLayoutID(0x0807)).keyboardLayout, 0x0807)
        connection.keyboard.layoutOverride = .usEnglish
        XCTAssertEqual(configuration(connection, layout: WindowsKeyboardLayoutID(0x0807)).keyboardLayout, 0x0409)
    }

    func testSecurityAndRedirection() {
        var connection = Connection(name: "PC", host: "pc01.example")
        connection.security.ignoreCertificateErrors = true
        connection.security.trustedCertificateFingerprints = ["AA:BB"]
        connection.redirection.audioPlayback = .remote
        connection.redirection.microphone = true
        connection.redirection.printers = false
        connection.redirection.clipboard = false
        let config = configuration(connection)
        XCTAssertTrue(config.ignoreCertificate)
        XCTAssertEqual(config.trustedCertificateFingerprints, ["AA:BB"])
        XCTAssertEqual(config.audio, .remote)
        XCTAssertTrue(config.microphone)
        XCTAssertFalse(config.printers)
        XCTAssertFalse(config.clipboard)
    }

    func testOnlyEnabledWritableDrivesAreSharedAndOnlyWithTheMasterSwitch() {
        var connection = Connection(name: "PC", host: "pc01.example")
        connection.redirection.drives = [
            DriveMapping(name: "Downloads", localPath: "~/Downloads"),
            DriveMapping(name: "Aus", localPath: "/tmp/off", enabled: false),
            DriveMapping(name: "Nur lesen", localPath: "/tmp/ro", readOnly: true),
        ]
        XCTAssertEqual(configuration(connection).drives, [], "master switch off")
        connection.redirection.driveRedirection = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(configuration(connection).drives,
                       [SharedDrive(name: "Downloads", localPath: URL(fileURLWithPath: "\(home)/Downloads"))])
    }

    func testDesktopFollowsTheWindow() {
        var display = DisplaySettings()
        display.retina = true
        let retina = display.desktop(forViewSize: CGSize(width: 1001, height: 700), backingScale: 2)
        XCTAssertEqual(retina.size, PixelSize(width: 2002, height: 1400))
        XCTAssertEqual(retina.scale, RemoteScale(desktop: 200, device: 100))
        display.retina = false
        let standard = display.desktop(forViewSize: CGSize(width: 1001, height: 700), backingScale: 2)
        XCTAssertEqual(standard.size, PixelSize(width: 1000, height: 700), "even width")
        XCTAssertEqual(standard.scale, RemoteScale(desktop: 100, device: 100))
        XCTAssertEqual(display.desktop(forViewSize: CGSize(width: 50, height: 9000), backingScale: 1).size,
                       PixelSize(width: 200, height: 8192), "clamped like the bridge")
        XCTAssertNil(display.contentSize(backingScale: 2))
    }

    func testFixedSizeAndScaleOverride() {
        var display = DisplaySettings()
        display.matchScreenResolution = false
        display.fixedWidth = 1600
        display.fixedHeight = 900
        display.retina = true
        display.desktopScaleFactor = 150
        let fixed = display.desktop(forViewSize: CGSize(width: 300, height: 300), backingScale: 2)
        XCTAssertEqual(fixed.size, PixelSize(width: 1600, height: 900))
        XCTAssertEqual(fixed.scale.desktop, 150)
        XCTAssertFalse(display.resizesWithWindow)
        XCTAssertEqual(display.contentSize(backingScale: 2), CGSize(width: 800, height: 450))
    }

    func testDynamicResolutionOnlyWhenFollowingTheWindow() {
        var display = DisplaySettings()
        XCTAssertTrue(display.resizesWithWindow)
        display.dynamicResolution = false
        XCTAssertFalse(display.resizesWithWindow)
        XCTAssertTrue(display.followsWindow)
    }
}
