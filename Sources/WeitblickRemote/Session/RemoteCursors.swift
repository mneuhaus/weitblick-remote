import AppKit
import WeitblickKit

/// Server cursor shapes as NSCursors, sized to match the scaled desktop.
@MainActor
final class RemoteCursors {
    private enum Shape: Equatable {
        case system
        case hidden
        case image(UInt64)
    }

    private var images: [UInt64: RemotePointerImage] = [:]
    private var shape: Shape = .system
    private(set) var current: NSCursor = .arrow

    /// View points per remote pixel; cursors are rebuilt when it changes.
    var pointsPerPixel: CGFloat = 1 {
        didSet { if oldValue != pointsPerPixel { rebuild() } }
    }

    /// Applies a pointer event. Returns true if `current` changed.
    func apply(_ event: RemotePointerEvent) -> Bool {
        switch event {
        case .new(let image):
            images[image.id] = image
            return false
        case .free(let id):
            images[id] = nil
            return false
        case .set(let id):
            return setShape(.image(id))
        case .hidden:
            return setShape(.hidden)
        case .systemDefault:
            return setShape(.system)
        case .moved:
            return false
        }
    }

    private func setShape(_ newShape: Shape) -> Bool {
        shape = newShape
        rebuild()
        return true
    }

    private func rebuild() {
        switch shape {
        case .system:
            current = .arrow
        case .hidden:
            current = Self.invisible
        case .image(let id):
            current = images[id].flatMap { makeCursor($0) } ?? .arrow
        }
    }

    private func makeCursor(_ image: RemotePointerImage) -> NSCursor? {
        guard image.width > 0, image.height > 0,
              let provider = CGDataProvider(data: image.bgra as CFData),
              let cgImage = CGImage(
                  width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let scale = pointsPerPixel
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let hotspot = NSPoint(x: CGFloat(image.hotspotX) * scale, y: CGFloat(image.hotspotY) * scale)
        return NSCursor(image: NSImage(cgImage: cgImage, size: size), hotSpot: hotspot)
    }

    private static let invisible = NSCursor(
        image: NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }, hotSpot: .zero)
}
