import Darwin
import SprungKit
import XCTest

final class WakeOnLANTests: XCTestCase {
    func testParsesCommonMACNotations() {
        let expected: [UInt8] = [0x00, 0x1C, 0x42, 0xAB, 0xCD, 0xEF]
        for text in ["00:1c:42:ab:cd:ef", "00-1C-42-AB-CD-EF", "001c42abcdef", " 00:1C:42:AB:CD:EF "] {
            XCTAssertEqual(WakeOnLAN.macAddress(text), expected, text)
        }
        for text in ["", "00:1c:42:ab:cd", "00:1c:42:ab:cd:ef:01", "00:1c:42:ab:cd:eg"] {
            XCTAssertNil(WakeOnLAN.macAddress(text), text)
        }
    }

    func testMagicPacketIsSyncStreamAndSixteenCopies() {
        let mac: [UInt8] = [1, 2, 3, 4, 5, 6]
        let packet = [UInt8](WakeOnLAN.magicPacket(for: mac))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
        for copy in 0..<16 { XCTAssertEqual(Array(packet[(6 + copy * 6)..<(12 + copy * 6)]), mac) }
    }

    func testInvalidInputThrowsBeforeSending() {
        XCTAssertThrowsError(try WakeOnLAN.wake(["nope"], broadcastAddresses: ["127.0.0.1"])) {
            XCTAssertEqual($0 as? WakeOnLAN.Failure, .invalidMACAddress("nope"))
        }
        XCTAssertThrowsError(try WakeOnLAN.wake(["02:00:00:00:00:01"], broadcastAddresses: ["10.0.0"])) {
            XCTAssertEqual($0 as? WakeOnLAN.Failure, .invalidBroadcastAddress("10.0.0"))
        }
    }

    /// Over loopback, so no packet leaves the machine.
    func testSendsThePacketToTheGivenAddressAndPort() throws {
        let receiver = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(receiver, 0)
        defer { close(receiver) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(receiver, $0, length) == 0 && getsockname(receiver, $0, &length) == 0
            }
        }
        XCTAssertTrue(bound)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(receiver, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try WakeOnLAN.wake(["02:00:00:00:00:01"], broadcastAddresses: ["127.0.0.1"], port: UInt16(bigEndian: address.sin_port))

        var buffer = [UInt8](repeating: 0, count: 200)
        let received = recv(receiver, &buffer, buffer.count, 0)
        XCTAssertEqual(received, 102)
        XCTAssertEqual(Data(buffer.prefix(max(received, 0))), WakeOnLAN.magicPacket(for: [2, 0, 0, 0, 0, 1]))
    }
}
