import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Straight RGBA pixels of a decoded image file, read without color management (the raw stored
/// values), so a lossless round trip must reproduce them exactly.
struct Pixels {
    let width: Int
    let height: Int
    private let rgba: [UInt8]

    init(width: Int, height: Int, _ pixel: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) {
        self.width = width
        self.height = height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y), i = (y * width + x) * 4
                (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]) = (p.r, p.g, p.b, p.a)
            }
        }
        self.rgba = rgba
    }

    init?(file data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.bitsPerComponent == 8,
              let raw = image.dataProvider?.data as Data?
        else { return nil }
        let channels = image.bitsPerPixel / 8
        guard channels == 3 || channels == 4 else { return nil }
        let alpha = image.alphaInfo
        let alphaFirst = [.first, .premultipliedFirst, .noneSkipFirst].contains(alpha)
        let hasAlpha = [.first, .last, .premultipliedFirst, .premultipliedLast].contains(alpha)
        let premultiplied = [.premultipliedFirst, .premultipliedLast].contains(alpha)
        let littleEndian = image.bitmapInfo.contains(.byteOrder32Little)
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let s = y * image.bytesPerRow + x * channels
                var px = Array(raw[s..<(s + channels)])
                if littleEndian, channels == 4 { px.reverse() }
                if channels == 4, alphaFirst { px = Array(px[1...]) + [px[0]] }
                var (r, g, b, a) = (px[0], px[1], px[2], channels == 4 && hasAlpha ? px[3] : 255)
                if premultiplied, a > 0, a < 255 {
                    func straight(_ c: UInt8) -> UInt8 { UInt8(min(255, (Int(c) * 255 + Int(a) / 2) / Int(a))) }
                    (r, g, b) = (straight(r), straight(g), straight(b))
                }
                let i = (y * image.width + x) * 4
                (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]) = (r, g, b, a)
            }
        }
        width = image.width
        height = image.height
        self.rgba = rgba
    }

    func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])
    }

    /// Pixels whose channels differ by more than `tolerance`; nil if the sizes differ.
    func mismatches(against expected: Pixels, tolerance: Int = 0, compareAlpha: Bool = true) -> Int? {
        guard width == expected.width, height == expected.height else { return nil }
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let a = pixel(x, y), e = expected.pixel(x, y)
                var deltas = [Int(a.r) - Int(e.r), Int(a.g) - Int(e.g), Int(a.b) - Int(e.b)]
                if compareAlpha { deltas.append(Int(a.a) - Int(e.a)) }
                if deltas.contains(where: { abs($0) > tolerance }) { count += 1 }
            }
        }
        return count
    }

    /// An sRGB PNG of these pixels (straight alpha).
    func png() -> Data? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
