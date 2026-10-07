import Darwin
import Foundation

/// Wake-on-LAN: sends magic packets (6 × 0xFF, then the MAC address 16 times) as UDP broadcasts.
public enum WakeOnLAN {
    public enum Failure: Error, Equatable {
        case invalidMACAddress(String)
        case invalidBroadcastAddress(String)
        case socket(errno: Int32)
    }

    /// The limited broadcast. It leaves through the interface of the default route only; pass
    /// subnet broadcasts (e.g. "192.168.1.255") to reach other networks.
    public static let limitedBroadcast = "255.255.255.255"
    public static let defaultPort: UInt16 = 9

    /// Parses "00:11:22:33:44:55", "00-11-22-33-44-55" or "001122334455" (any case).
    public static func macAddress(_ text: String) -> [UInt8]? {
        let hex = text.trimmingCharacters(in: .whitespaces).filter { $0 != ":" && $0 != "-" && $0 != "." }
        guard hex.count == 12, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }

    public static func magicPacket(for mac: [UInt8]) -> Data {
        precondition(mac.count == 6, "a MAC address has 6 bytes")
        return Data(repeating: 0xFF, count: 6) + Data((0..<16).flatMap { _ in mac })
    }

    /// Sends one magic packet per MAC address to each broadcast address. Throws before sending
    /// anything if an address is invalid.
    public static func wake(_ macAddresses: [String], broadcastAddresses: [String] = [limitedBroadcast],
                            port: UInt16 = defaultPort) throws {
        let packets = try macAddresses.map { text in
            guard let mac = macAddress(text) else { throw Failure.invalidMACAddress(text) }
            return magicPacket(for: mac)
        }
        let destinations = try broadcastAddresses.map { try socketAddress($0, port: port) }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw Failure.socket(errno: errno) }
        defer { close(fd) }
        var enabled: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw Failure.socket(errno: errno)
        }
        for packet in packets {
            for var destination in destinations {
                let sent = packet.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &destination) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                guard sent == packet.count else { throw Failure.socket(errno: errno) }
            }
        }
    }

    private static func socketAddress(_ text: String, port: UInt16) throws -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, text, &address.sin_addr) == 1 else { throw Failure.invalidBroadcastAddress(text) }
        return address
    }
}
