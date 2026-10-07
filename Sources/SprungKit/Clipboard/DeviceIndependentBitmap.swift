import Accelerate
import CoreGraphics
import Foundation

/// CF_DIB / CF_DIBV5: a BITMAPINFOHEADER (40 bytes) or BITMAPV5HEADER (124 bytes), optional color
/// masks and palette, then bottom-up pixel rows padded to 4 bytes.
enum DeviceIndependentBitmap {
    private static let biRGB: UInt32 = 0
    private static let biBitfields: UInt32 = 3
    private static let biAlphaBitfields: UInt32 = 6
    private static let infoHeaderSize = 40
    private static let v5HeaderSize = 124

    // MARK: Encode

    /// CF_DIB for apps that know no transparency: 24 bpp, transparent areas flattened onto white.
    static func encodeDIB(_ image: CGImage) -> Data? {
        let width = image.width, height = image.height
        guard var bgrx = render(image, flattenOntoWhite: true) else { return nil }
        defer { bgrx.free() }
        let stride = (width * 3 + 3) & ~3
        var bgr = [UInt8](repeating: 0, count: stride * height)
        let converted = bgr.withUnsafeMutableBytes { bytes -> Bool in
            var destination = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(height),
                                            width: vImagePixelCount(width), rowBytes: stride)
            // Memory order B G R X: dropping the fourth byte leaves B G R.
            return vImageConvert_RGBA8888toRGB888(&bgrx, &destination, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        guard converted else { return nil }
        var data = infoHeader(width: width, height: height, bitCount: 24, compression: biRGB, imageSize: bgr.count)
        appendRowsBottomUp(bgr, stride: stride, height: height, to: &data)
        return data
    }

    /// CF_DIBV5 with straight alpha: 32 bpp BI_BITFIELDS (BGRA), sRGB.
    static func encodeDIBV5(_ image: CGImage) -> Data? {
        let width = image.width, height = image.height
        guard var bgra = render(image, flattenOntoWhite: false) else { return nil }
        defer { bgra.free() }
        // Alpha is the fourth byte (B G R A), as in RGBA8888.
        guard vImageUnpremultiplyData_RGBA8888(&bgra, &bgra, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        let stride = width * 4
        var header = infoHeader(width: width, height: height, bitCount: 32, compression: biBitfields,
                                imageSize: stride * height, headerSize: v5HeaderSize)
        header.append(uint32: 0x00FF_0000) // red mask
        header.append(uint32: 0x0000_FF00) // green mask
        header.append(uint32: 0x0000_00FF) // blue mask
        header.append(uint32: 0xFF00_0000) // alpha mask
        header.append(uint32: 0x7352_4742) // LCS_sRGB 'sRGB'
        header.append(Data(count: 36)) // CIEXYZTRIPLE endpoints, unused for sRGB
        header.append(Data(count: 12)) // gamma red/green/blue
        header.append(uint32: 4) // LCS_GM_IMAGES
        header.append(Data(count: 12)) // profile data, profile size, reserved
        let rows = UnsafeRawBufferPointer(start: bgra.data, count: bgra.rowBytes * height)
        appendRowsBottomUp(rows, stride: stride, rowBytes: bgra.rowBytes, height: height, to: &header)
        return header
    }

    /// Draws `image` into a BGRA buffer (premultiplied, top-down), optionally over white.
    private static func render(_ image: CGImage, flattenOntoWhite: Bool) -> vImage_Buffer? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = vImage_Buffer()
        guard vImageBuffer_Init(&buffer, vImagePixelCount(height), vImagePixelCount(width), 32,
                                vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return nil }
        let alpha: CGImageAlphaInfo = flattenOntoWhite ? .noneSkipFirst : .premultipliedFirst
        guard let context = CGContext(
            data: buffer.data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: buffer.rowBytes,
            space: sRGB, bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else {
            buffer.free()
            return nil
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if flattenOntoWhite {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
        } else {
            context.clear(bounds)
        }
        context.draw(image, in: bounds)
        return buffer
    }

    private static func infoHeader(width: Int, height: Int, bitCount: UInt16, compression: UInt32, imageSize: Int,
                                   headerSize: Int = infoHeaderSize) -> Data {
        var data = Data()
        data.append(uint32: UInt32(headerSize))
        data.append(uint32: UInt32(bitPattern: Int32(width)))
        data.append(uint32: UInt32(bitPattern: Int32(height))) // positive: bottom-up
        data.append(uint16: 1) // planes
        data.append(uint16: bitCount)
        data.append(uint32: compression)
        data.append(uint32: UInt32(imageSize))
        data.append(uint32: 2835) // 72 dpi in pixels per meter
        data.append(uint32: 2835)
        data.append(uint32: 0) // colors used
        data.append(uint32: 0) // important colors
        return data
    }

    private static func appendRowsBottomUp(_ rows: [UInt8], stride: Int, height: Int, to data: inout Data) {
        rows.withUnsafeBytes { appendRowsBottomUp($0, stride: stride, rowBytes: stride, height: height, to: &data) }
    }

    private static func appendRowsBottomUp(_ rows: UnsafeRawBufferPointer, stride: Int, rowBytes: Int, height: Int,
                                           to data: inout Data) {
        for row in (0..<height).reversed() {
            data.append(contentsOf: UnsafeRawBufferPointer(rebasing: rows[(row * rowBytes)..<(row * rowBytes + stride)]))
        }
    }

    // MARK: Decode

    /// 24 and 32 bpp are decoded here (Windows leaves the fourth byte of 32 bpp CF_DIB undefined,
    /// mostly 0, which ImageIO would read as fully transparent); everything else goes to ImageIO.
    static func decode(_ data: Data) -> CGImage? {
        let bytes = [UInt8](data)
        guard bytes.count >= infoHeaderSize else { return nil }
        let headerSize = Int(bytes.uint32(at: 0))
        let width = Int(Int32(bitPattern: bytes.uint32(at: 4)))
        let rawHeight = Int(Int32(bitPattern: bytes.uint32(at: 8)))
        let bitCount = Int(bytes.uint16(at: 14))
        let compression = bytes.uint32(at: 16)
        let colorsUsed = Int(bytes.uint32(at: 32))
        guard headerSize >= infoHeaderSize, headerSize <= bytes.count, width > 0, rawHeight != 0,
              width <= 32768, abs(rawHeight) <= 32768
        else { return nil }
        let height = abs(rawHeight)

        var maskBytes = 0
        if headerSize == infoHeaderSize {
            if compression == biBitfields { maskBytes = 12 }
            if compression == biAlphaBitfields { maskBytes = 16 }
        } else if compression == biBitfields, bytes.count >= headerSize + 12,
                  bytes[headerSize..<(headerSize + 12)].elementsEqual(bytes[40..<52]) {
            // Windows' synthesized CF_DIBV5 repeats the masks after the V5 header, like a color table.
            maskBytes = 12
        }
        let paletteEntries = bitCount <= 8 ? (colorsUsed == 0 ? 1 << bitCount : colorsUsed) : colorsUsed
        let pixelOffset = headerSize + maskBytes + paletteEntries * 4

        guard bitCount == 24 || bitCount == 32 else {
            return decodeWithImageIO(bytes, pixelOffset: pixelOffset)
        }
        var alphaMask: UInt32 = 0
        switch compression {
        case biRGB:
            alphaMask = bitCount == 32 ? 0xFF00_0000 : 0
        case biBitfields, biAlphaBitfields:
            // Masks follow a 40-byte header or sit at the same place inside V2…V5 headers.
            guard bitCount == 32, bytes.count >= 52, bytes.uint32(at: 40) == 0x00FF_0000,
                  bytes.uint32(at: 44) == 0x0000_FF00, bytes.uint32(at: 48) == 0x0000_00FF
            else { return decodeWithImageIO(bytes, pixelOffset: pixelOffset) }
            if (compression == biAlphaBitfields || headerSize >= 56), bytes.count >= 56 {
                alphaMask = bytes.uint32(at: 52)
            }
            guard alphaMask == 0 || alphaMask == 0xFF00_0000 else { return decodeWithImageIO(bytes, pixelOffset: pixelOffset) }
        default:
            return decodeWithImageIO(bytes, pixelOffset: pixelOffset)
        }

        let rowStride = (width * bitCount + 31) / 32 * 4
        let imageSize = rowStride * height
        // Some writers put extra masks or a profile in front of the bits; trust the total size then.
        let offset = pixelOffset + imageSize <= bytes.count ? pixelOffset : bytes.count - imageSize
        guard offset >= headerSize else { return nil }

        // Rows top-down, still in the source pixel format.
        var rows = [UInt8](repeating: 0, count: imageSize)
        for row in 0..<height {
            let source = offset + (rawHeight > 0 ? height - 1 - row : row) * rowStride
            rows.replaceSubrange((row * rowStride)..<((row + 1) * rowStride), with: bytes[source..<(source + rowStride)])
        }
        let bgra: [UInt8]
        var hasAlpha = false
        if bitCount == 32 {
            bgra = rows
            // An all-zero fourth byte means "no alpha", not "invisible".
            hasAlpha = alphaMask != 0 && stride(from: 3, to: bgra.count, by: 4).contains { bgra[$0] != 0 }
        } else {
            var converted = [UInt8](repeating: 0, count: width * height * 4)
            let ok = rows.withUnsafeMutableBytes { source in
                converted.withUnsafeMutableBytes { target in
                    var input = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(height),
                                              width: vImagePixelCount(width), rowBytes: rowStride)
                    var output = vImage_Buffer(data: target.baseAddress, height: vImagePixelCount(height),
                                               width: vImagePixelCount(width), rowBytes: width * 4)
                    // B G R -> B G R 255
                    return vImageConvert_RGB888toRGBA8888(&input, nil, 255, &output, false,
                                                          vImage_Flags(kvImageNoFlags)) == kvImageNoError
                }
            }
            guard ok else { return nil }
            bgra = converted
        }
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .first : .noneSkipFirst
        guard let provider = CGDataProvider(data: Data(bgra) as CFData), let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bitCount == 32 ? rowStride : width * 4,
            space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Palette, 16 bpp and RLE bitmaps: add a BITMAPFILEHEADER and let ImageIO read the BMP.
    private static func decodeWithImageIO(_ bytes: [UInt8], pixelOffset: Int) -> CGImage? {
        var file = Data([0x42, 0x4D]) // "BM"
        file.append(uint32: UInt32(14 + bytes.count))
        file.append(uint32: 0)
        file.append(uint32: UInt32(14 + pixelOffset))
        file.append(contentsOf: bytes)
        return ClipboardImage.decode(file)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}

private extension [UInt8] {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[offset + $1]) << ($1 * 8) }
    }
}
