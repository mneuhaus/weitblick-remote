import Foundation

/// One file or folder of a clipboard file list.
struct ClipboardFileEntry: Equatable, Sendable {
    /// Path relative to the copied items, components joined with "\" like Windows writes them.
    var path: String
    var isDirectory: Bool
    var size: UInt64
    var modified: Date?

    var components: [String] { path.split(separator: "\\").map(String.init) }
    var isTopLevel: Bool { !path.contains("\\") }
}

/// The "FileGroupDescriptorW" clipboard format: a count and one 592-byte FILEDESCRIPTORW per entry.
enum FileGroupDescriptor {
    static let format = WindowsClipboardFormat.registered("FileGroupDescriptorW")
    static let recordSize = 592
    /// cFileName holds 260 UTF-16 units including the terminator.
    static let maxPathLength = 259

    private static let attributesFlag: UInt32 = 0x04 // FD_ATTRIBUTES
    private static let writeTimeFlag: UInt32 = 0x20 // FD_WRITESTIME
    private static let fileSizeFlag: UInt32 = 0x40 // FD_FILESIZE
    private static let progressUIFlag: UInt32 = 0x4000 // FD_PROGRESSUI
    private static let unicodeFlag: UInt32 = 0x8000_0000 // FD_UNICODE
    private static let directoryAttribute: UInt32 = 0x10 // FILE_ATTRIBUTE_DIRECTORY
    private static let normalAttribute: UInt32 = 0x80 // FILE_ATTRIBUTE_NORMAL
    /// Seconds from 1601-01-01 (FILETIME epoch) to 1970-01-01.
    private static let fileTimeEpochOffset: TimeInterval = 11_644_473_600

    /// Entries with paths longer than `maxPathLength` must be filtered out before.
    static func encode(_ entries: [ClipboardFileEntry]) -> Data {
        var data = Data(capacity: 4 + entries.count * recordSize)
        data.appendLittleEndian(UInt32(entries.count))
        for entry in entries {
            var record = Data(count: recordSize)
            var flags = attributesFlag | fileSizeFlag | progressUIFlag | unicodeFlag
            if entry.modified != nil { flags |= writeTimeFlag }
            record.setLittleEndian(flags, at: 0)
            record.setLittleEndian(entry.isDirectory ? directoryAttribute : normalAttribute, at: 36)
            if let modified = entry.modified {
                let ticks = UInt64(max(0, (modified.timeIntervalSince1970 + fileTimeEpochOffset) * 10_000_000))
                record.setLittleEndian(ticks, at: 56)
            }
            let size = entry.isDirectory ? 0 : entry.size
            record.setLittleEndian(UInt32(size >> 32), at: 64)
            record.setLittleEndian(UInt32(size & 0xFFFF_FFFF), at: 68)
            for (index, unit) in entry.path.utf16.prefix(maxPathLength).enumerated() {
                record.setLittleEndian(unit, at: 72 + index * 2)
            }
            data.append(record)
        }
        return data
    }

    /// The entries, or nil if the data is malformed or names a path outside the copied items.
    static func decode(_ data: Data) -> [ClipboardFileEntry]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let count = Int(bytes.littleEndianUInt32(at: 0))
        guard count <= (bytes.count - 4) / recordSize else { return nil }
        var entries: [ClipboardFileEntry] = []
        for index in 0..<count {
            let base = 4 + index * recordSize
            let flags = bytes.littleEndianUInt32(at: base)
            let attributes = flags & attributesFlag != 0 ? bytes.littleEndianUInt32(at: base + 36) : 0
            let size = UInt64(bytes.littleEndianUInt32(at: base + 64)) << 32 | UInt64(bytes.littleEndianUInt32(at: base + 68))
            var units: [UInt16] = []
            for offset in stride(from: base + 72, to: base + recordSize, by: 2) {
                let unit = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                if unit == 0 { break }
                units.append(unit)
            }
            guard let path = safeRelativePath(String(decoding: units, as: UTF16.self)) else { return nil }
            var modified: Date?
            if flags & writeTimeFlag != 0 {
                let ticks = UInt64(bytes.littleEndianUInt32(at: base + 60)) << 32 | UInt64(bytes.littleEndianUInt32(at: base + 56))
                if ticks > 0 { modified = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - fileTimeEpochOffset) }
            }
            entries.append(ClipboardFileEntry(path: path, isDirectory: attributes & directoryAttribute != 0,
                                              size: flags & fileSizeFlag != 0 ? size : 0, modified: modified))
        }
        return entries
    }

    /// "a\b" from "a\b", "a/b" or "\a\b\"; nil for "..", empty, drive or device paths.
    static func safeRelativePath(_ path: String) -> String? {
        let parts = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).filter { $0 != "." }
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0.contains(":") || $0.contains("\0") }) else {
            return nil
        }
        return parts.joined(separator: "\\")
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func setLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        Swift.withUnsafeBytes(of: value.littleEndian) { replaceSubrange(offset..<offset + $0.count, with: $0) }
    }
}

private extension [UInt8] {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
