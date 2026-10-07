import AppKit
@testable import SprungKit
import XCTest

final class ClipboardFormatTests: XCTestCase {
    // MARK: CF_UNICODETEXT

    func testTextGetsCRLFAndATerminator() {
        let data = WindowsText.encode("a\nb\r\nc\rd😀")
        let units: [UInt16] = Array("a\r\nb\r\nc\r\nd😀".utf16) + [0]
        let expected: [UInt8] = units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        XCTAssertEqual([UInt8](data), expected)
    }

    func testTextStopsAtTheTerminatorAndGetsLF() {
        var data = Data("Grüße\r\nWelt 😀".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        data.append(contentsOf: [0, 0, 0x41, 0x00]) // garbage after NUL, as in GlobalAlloc padding
        XCTAssertEqual(WindowsText.decode(data), "Grüße\nWelt 😀")
    }

    // MARK: CF_HTML

    func testHTMLFragmentOffsetsPointAtTheFragment() throws {
        let fragment = "<b>Grüße</b> &amp; 😀"
        let data = ClipboardHTML.encode(fragment)
        let offsets = try XCTUnwrap(Self.offsets(data))
        let bytes = [UInt8](data)
        XCTAssertEqual(String(decoding: bytes[offsets.startFragment..<offsets.endFragment], as: UTF8.self), fragment)
        XCTAssertTrue(bytes[offsets.startHTML...].starts(with: Array("<html><body><!--StartFragment-->".utf8)))
        XCTAssertEqual(String(decoding: bytes[..<offsets.endHTML].suffix(7), as: UTF8.self), "</html>")
        XCTAssertEqual(bytes.last, 0)
    }

    func testHTMLDocumentKeepsItsHeadAndUsesTheBodyAsFragment() throws {
        let document = "<html><head><style>p{color:red}</style></head><BODY class=x><p>Hi</p></BODY></html>"
        let data = ClipboardHTML.encode(document)
        let offsets = try XCTUnwrap(Self.offsets(data))
        let bytes = [UInt8](data)
        XCTAssertEqual(String(decoding: bytes[offsets.startFragment..<offsets.endFragment], as: UTF8.self), "<p>Hi</p>")
        XCTAssertTrue(String(decoding: bytes[offsets.startHTML..<offsets.endHTML], as: UTF8.self).contains("<style>"))
    }

    func testHTMLFromWindowsGetsAUTF8CharsetAndRoundTrips() throws {
        let html = try XCTUnwrap(ClipboardHTML.decode(ClipboardHTML.encode("<i>Größe</i>")))
        XCTAssertTrue(html.hasPrefix(#"<meta charset="utf-8"><html><body><!--StartFragment--><i>Größe</i>"#), html)

        // Without StartHTML/EndHTML (-1) the fragment offsets are used.
        func header(_ start: Int, _ end: Int) -> String {
            "Version:0.9\r\nStartHTML:-1\r\nEndHTML:-1\r\nStartFragment:\(String(format: "%010d", start))\r\n"
                + "EndFragment:\(String(format: "%010d", end))\r\n"
        }
        let before = "<html><body><!--StartFragment-->"
        let start = header(0, 0).utf8.count + before.utf8.count
        let blob = header(start, start + "Grüße".utf8.count) + before + "Grüße<!--EndFragment--></body></html>"
        XCTAssertEqual(ClipboardHTML.decode(Data(blob.utf8)), #"<meta charset="utf-8">Grüße"#)
    }

    // MARK: CF_DIB / CF_DIBV5

    func testDIBIsBottomUp24BitOverWhite() throws {
        let image = try Self.image(width: 3, height: 2) { x, y in x == 0 ? (0, 0, 0, 0) : (UInt8(x * 50), UInt8(y * 90), 7, 255) }
        let dib = [UInt8](try XCTUnwrap(DeviceIndependentBitmap.encodeDIB(image)))
        XCTAssertEqual(dib[0], 40) // BITMAPINFOHEADER
        XCTAssertEqual(dib[14], 24) // bpp
        XCTAssertEqual(dib.count, 40 + 2 * 12) // rows of 9 bytes padded to 12
        // First stored row is the bottom one (y = 1); transparent pixel 0 became white; B G R order.
        XCTAssertEqual(Array(dib[40..<49]), [255, 255, 255, 7, 90, 50, 7, 90, 100])
    }

    func testDIBV5RoundTripKeepsPixelsAndAlpha() throws {
        let image = try Self.image(width: 5, height: 4) { x, y in (UInt8(x * 40), UInt8(y * 60), UInt8(x * y), x == 4 ? 128 : 255) }
        let dib = try XCTUnwrap(DeviceIndependentBitmap.encodeDIBV5(image))
        XCTAssertEqual(dib[0], 124)
        let decoded = try XCTUnwrap(DeviceIndependentBitmap.decode(dib))
        let pixels = Self.rgba(decoded)
        XCTAssertEqual(pixels[(1 * 5 + 2) * 4..<(1 * 5 + 2) * 4 + 4], [80, 60, 2, 255])
        XCTAssertEqual(pixels[(3 * 5 + 4) * 4 + 3], 128)
    }

    func testWindowsDIBV5WithRepeatedMasksDecodesAtTheRightOffset() throws {
        // Windows' synthesized CF_DIBV5 has the three BI_BITFIELDS masks again after the header.
        let image = try Self.image(width: 4, height: 3) { x, y in (UInt8(x * 60), UInt8(y * 80), 9, 255) }
        var dib = [UInt8](try XCTUnwrap(DeviceIndependentBitmap.encodeDIBV5(image)))
        dib.insert(contentsOf: dib[40..<52], at: 124)
        let decoded = try XCTUnwrap(DeviceIndependentBitmap.decode(Data(dib)))
        XCTAssertEqual(Self.rgba(decoded), Self.rgba(image))
    }

    func testThirtyTwoBitDIBWithoutAlphaIsOpaque() throws {
        // Windows leaves the fourth byte of a 32 bpp BI_RGB CF_DIB at 0; that must not mean invisible.
        var dib = Self.infoHeader(width: 2, height: -1, bitCount: 32)
        dib += [10, 20, 30, 0, 40, 50, 60, 0] // top-down: B G R X
        let decoded = try XCTUnwrap(DeviceIndependentBitmap.decode(Data(dib)))
        XCTAssertEqual(Self.rgba(decoded), [30, 20, 10, 255, 60, 50, 40, 255])
    }

    // MARK: Helpers

    static func offsets(_ data: Data) -> (startHTML: Int, endHTML: Int, startFragment: Int, endFragment: Int)? {
        let header = String(decoding: data.prefix(160), as: UTF8.self)
        func value(_ key: String) -> Int? {
            header.range(of: key + ":").flatMap { Int(header[$0.upperBound...].prefix(10)) }
        }
        guard let a = value("StartHTML"), let b = value("EndHTML"), let c = value("StartFragment"), let d = value("EndFragment")
        else { return nil }
        return (a, b, c, d)
    }

    static func image(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) throws -> CGImage {
        var rgba: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                rgba += [r, g, b, a]
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// Straight RGBA, top-down, as drawn into an sRGB context and un-premultiplied.
    static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 && pixels[i + 3] < 255 {
            for c in 0..<3 { pixels[i + c] = UInt8(min(255, (Int(pixels[i + c]) * 255 + Int(pixels[i + 3]) / 2) / Int(pixels[i + 3]))) }
        }
        return pixels
    }

    static func infoHeader(width: Int32, height: Int32, bitCount: UInt16) -> [UInt8] {
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) } }
        let size: [UInt8] = le32(40) + le32(UInt32(bitPattern: width)) + le32(UInt32(bitPattern: height))
        let format: [UInt8] = [1, 0, UInt8(bitCount), 0] + le32(0) + le32(0)
        return size + format + le32(2835) + le32(2835) + le32(0) + le32(0)
    }
}
