import CoreGraphics
import Foundation
import ImageIO
import SprungKit
import UniformTypeIdentifiers

/// A copied frame from a session, for writing PNGs and sanity checks.
struct FramebufferSnapshot {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: Data

    @MainActor
    init?(session: RDPSession) {
        guard let copy = session.withFramebuffer({ framebuffer in
            (framebuffer.width, framebuffer.height, framebuffer.bytesPerRow,
             Data(bytes: framebuffer.pixels, count: framebuffer.bytesPerRow * framebuffer.height))
        }) else { return nil }
        (width, height, bytesPerRow, pixels) = copy
    }

    /// Number of distinct colors on a sparse grid; a real desktop has many, a blank one few.
    var sampledColorCount: Int {
        var colors = Set<UInt32>()
        pixels.withUnsafeBytes { raw in
            for y in stride(from: 0, to: height, by: 7) {
                for x in stride(from: 0, to: width, by: 7) {
                    colors.insert(raw.load(fromByteOffset: y * bytesPerRow + x * 4, as: UInt32.self) & 0x00FF_FFFF)
                }
            }
        }
        return colors.count
    }

    /// Smallest and largest alpha byte, to learn what the decoders write there.
    var alphaRange: ClosedRange<UInt8> {
        pixels.withUnsafeBytes { raw in
            var low = UInt8.max, high = UInt8.min
            for y in stride(from: 0, to: height, by: 7) {
                for x in stride(from: 0, to: width, by: 7) {
                    let alpha = raw[y * bytesPerRow + x * 4 + 3]
                    low = min(low, alpha)
                    high = max(high, alpha)
                }
            }
            return low...high
        }
    }

    func writePNG(to url: URL) throws {
        try writeBGRAPNG(pixels, width: width, height: height, bytesPerRow: bytesPerRow, alpha: .noneSkipFirst, to: url)
    }
}

/// Writes BGRA32 pixels (little-endian ARGB words) as PNG.
func writeBGRAPNG(_ pixels: Data, width: Int, height: Int, bytesPerRow: Int, alpha: CGImageAlphaInfo, to url: URL) throws {
    let info = CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    guard let provider = CGDataProvider(data: pixels as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: info, provider: provider, decode: nil,
                              shouldInterpolate: false, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw SmokeFailure("cannot encode \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw SmokeFailure("cannot write \(url.path)") }
}
