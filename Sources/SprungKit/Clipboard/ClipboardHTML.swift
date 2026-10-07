import Foundation

/// The Windows "HTML Format" (CF_HTML): a header with UTF-8 byte offsets, then the document with
/// the copied fragment between `<!--StartFragment-->` and `<!--EndFragment-->`.
enum ClipboardHTML {
    private static let startMarker = "<!--StartFragment-->"
    private static let endMarker = "<!--EndFragment-->"

    /// Wraps Mac HTML (a fragment or a whole document) into CF_HTML; the body is the fragment.
    static func encode(_ html: String) -> Data {
        let (prefix, fragment, suffix) = splitAtBody(html)
        let document = Array((prefix + startMarker).utf8) + Array(fragment.utf8) + Array((endMarker + suffix).utf8)
        let fragmentStart = (prefix + startMarker).utf8.count
        let fragmentEnd = fragmentStart + fragment.utf8.count

        func header(_ startHTML: Int, _ endHTML: Int, _ startFragment: Int, _ endFragment: Int) -> String {
            func field(_ name: String, _ value: Int) -> String { name + ":" + String(format: "%010d", value) + "\r\n" }
            return "Version:0.9\r\n" + field("StartHTML", startHTML) + field("EndHTML", endHTML)
                + field("StartFragment", startFragment) + field("EndFragment", endFragment)
        }
        let headerLength = header(0, 0, 0, 0).utf8.count // fixed width
        let final = header(headerLength, headerLength + document.count,
                           headerLength + fragmentStart, headerLength + fragmentEnd)
        var data = Data(final.utf8)
        data.append(contentsOf: document)
        data.append(0)
        return data
    }

    /// The HTML document of a CF_HTML blob (StartHTML…EndHTML, else the fragment, else everything
    /// after the header), with a UTF-8 charset declaration so Mac apps decode it correctly.
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix { $0 != 0 })
        let offsets = headerOffsets(bytes)
        let range: Range<Int>
        if let start = offsets["StartHTML"], let end = offsets["EndHTML"], 0 <= start, start < end, end <= bytes.count {
            range = start..<end
        } else if let start = offsets["StartFragment"], let end = offsets["EndFragment"], 0 <= start, start <= end,
                  end <= bytes.count {
            range = start..<end
        } else if let html = firstIndex(of: Array("<".utf8), in: bytes) {
            range = html..<bytes.count
        } else {
            return nil
        }
        return withUTF8Charset(String(decoding: bytes[range], as: UTF8.self))
    }

    // MARK: - Helpers

    private static func splitAtBody(_ html: String) -> (prefix: String, fragment: String, suffix: String) {
        if let bodyOpen = html.range(of: "<body", options: .caseInsensitive),
           let tagEnd = html.range(of: ">", range: bodyOpen.upperBound..<html.endIndex),
           let bodyClose = html.range(of: "</body", options: [.caseInsensitive, .backwards]),
           tagEnd.upperBound <= bodyClose.lowerBound {
            return (String(html[..<tagEnd.upperBound]), String(html[tagEnd.upperBound..<bodyClose.lowerBound]),
                    String(html[bodyClose.lowerBound...]))
        }
        return ("<html><body>", html, "</body></html>")
    }

    /// `Name:Value` lines before the document; values are byte offsets (-1 = absent).
    private static func headerOffsets(_ bytes: [UInt8]) -> [String: Int] {
        let headerEnd = firstIndex(of: Array("<".utf8), in: bytes) ?? bytes.count
        let header = String(decoding: bytes[0..<headerEnd], as: UTF8.self)
        var offsets: [String: Int] = [:]
        for line in header.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                offsets[String(parts[0])] = value
            }
        }
        return offsets
    }

    private static func firstIndex(of needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
        return (0...(bytes.count - needle.count)).first { bytes[$0..<$0 + needle.count].elementsEqual(needle) }
    }

    private static func withUTF8Charset(_ html: String) -> String {
        let meta = #"<meta charset="utf-8">"#
        guard html.range(of: "charset", options: .caseInsensitive) == nil else { return html }
        if let head = html.range(of: "<head", options: .caseInsensitive),
           let tagEnd = html.range(of: ">", range: head.upperBound..<html.endIndex) {
            return String(html[..<tagEnd.upperBound]) + meta + String(html[tagEnd.upperBound...])
        }
        return meta + html
    }
}
