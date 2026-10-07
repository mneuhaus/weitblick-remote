import Foundation
import Testing
@testable import ConnectionStore

@Suite("RDP file interoperability")
struct RDPFileTests {
    @Test(arguments: [RDPFileEncoding.utf8, .utf16LittleEndian])
    func roundTripAllSupportedFields(_ encoding: RDPFileEncoding) throws {
        var c = Connection(name: "Synthetic", host: "PC0001.example", port: 13389, username: "testuser", domain: "EXAMPLE")
        c.display.fixedWidth = 1600
        c.display.fixedHeight = 900
        c.display.startFullscreen = true
        c.display.dynamicResolution = false
        c.display.useAllMonitors = true
        c.redirection.clipboard = false
        c.redirection.audioPlayback = .remote
        c.redirection.microphone = true
        c.redirection.printers = false
        c.advanced.rdpDriveStoreDirect = "C:;D:;"
        c.advanced.alternateShell = "C:\\Windows\\notepad.exe"
        c.advanced.workingDir = "C:\\Test"
        c.advanced.loadBalanceInfo = "synthetic:token"
        c.advanced.gatewayHostname = "gateway.example"
        c.security.authenticationLevel = 1
        c.security.promptForCredentials = false
        let data = try RDPFile.encode(c, encoding: encoding)
        if encoding == .utf16LittleEndian { #expect(data.starts(with: [0xFF, 0xFE])) }
        let decoded = try RDPFile.decode(data, name: c.name).connection
        c.id = decoded.id
        #expect(decoded == c)
    }

    @Test(arguments: [AudioPlaybackMode.local, .remote, .off])
    func audioCodeSpace(_ mode: AudioPlaybackMode) throws {
        var c = Connection(name: "Audio", host: "PC0001.example")
        c.redirection.audioPlayback = mode
        #expect(try RDPFile.decode(RDPFile.encode(c)).connection.redirection.audioPlayback == mode)
    }

    @Test func ipv6PortsUTF8BOMAndReadFile() throws {
        let temporary = try TemporaryDirectory()
        let text = "full address:s:[2001:db8::1]:3390\r\nusername:s:testuser\r\n"
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        let file = temporary.url.appendingPathComponent("Synthetic.rdp")
        try data.write(to: file)
        let imported = try RDPFile.read(file)
        #expect(imported.connection.host == "2001:db8::1")
        #expect(imported.connection.port == 3390)
        #expect(imported.connection.name == "Synthetic")
        let roundTrip = try RDPFile.decode(RDPFile.encode(imported.connection))
        #expect(roundTrip.connection.host == "2001:db8::1")
        #expect(try RDPFile.decode(Data("full address:s:PC0001.example\n".utf8)).connection.port == 3389)
        var vnc = imported.connection
        vnc.protocol = .vnc
        #expect(vnc.vncURL?.absoluteString == "vnc://[2001:db8::1]:3390")
    }

    @Test func unknownsDuplicatesAndSecretsAreReportedWithoutValues() throws {
        let text = """
        full address:s:PC0001.example:3389
        username:s:firstuser
        username:s:testuser
        password 51:b:SYNTHETIC-SECRET-DO-NOT-REPORT
        unknownfield:i:5
        malformed-line
        drivestoredirect:s:*
        authentication level:i:0
        """
        let imported = try RDPFile.decode(Data(text.utf8))
        #expect(imported.connection.username == "testuser")
        #expect(imported.connection.security.ignoreCertificateErrors)
        #expect(!imported.connection.redirection.driveRedirection)
        #expect(imported.connection.redirection.drives.isEmpty)
        #expect(imported.ignoredFields.map(\.field) == ["unknownfield"])
        #expect(imported.warnings.contains { $0.contains("Gespeichertes Passwort") })
        #expect(!imported.warnings.joined().contains("SYNTHETIC-SECRET"))
        let encoded = try RDPFile.encode(imported.connection, encoding: .utf8)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("password"))
    }

    @Test func invalidAddressTypesAndLineInjectionRejected() throws {
        for text in ["full address:s:PC0001.example:0", "full address:s:[bad", "full address:i:3389",
                     "full address:s:PC0001.example\naudiomode:i:9", "full address:s:PC0001.example\nredirectclipboard:i:2"] {
            #expect(throws: (any Error).self) { try RDPFile.decode(Data(text.utf8)) }
        }
        #expect(throws: RDPFileError.missingAddress) { try RDPFile.decode(Data("username:s:testuser".utf8)) }
        #expect(throws: RDPFileError.invalidEncoding) { try RDPFile.decode(Data([0xFF, 0xAB, 0xFE])) }
        var c = Connection(name: "Test", host: "PC0001.example")
        c.username = "testuser\nredirectclipboard:i:1"
        #expect(throws: RDPFileError.invalidValue("username")) { try RDPFile.encode(c) }
        c.protocol = .vnc
        #expect(throws: RDPFileError.unsupportedProtocol) { try RDPFile.encode(c) }
    }
}
