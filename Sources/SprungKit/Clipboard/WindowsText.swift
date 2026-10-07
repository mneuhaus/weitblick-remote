import Foundation

/// CF_UNICODETEXT: UTF-16LE, CRLF line ends, NUL-terminated.
enum WindowsText {
    /// Any line ending (LF, CR, CRLF) becomes CRLF.
    static func encode(_ text: String) -> Data {
        let windows = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        var data = windows.data(using: .utf16LittleEndian) ?? Data()
        data.append(contentsOf: [0, 0])
        return data
    }

    /// Reads up to the first NUL character; CRLF becomes LF.
    static func decode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var length = bytes.count & ~1
        for offset in stride(from: 0, to: length, by: 2) where bytes[offset] == 0 && bytes[offset + 1] == 0 {
            length = offset
            break
        }
        // Lenient: an unpaired surrogate becomes U+FFFD instead of failing the whole text.
        let units = stride(from: 0, to: length, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
        return String(decoding: units, as: UTF16.self).replacingOccurrences(of: "\r\n", with: "\n")
    }
}
