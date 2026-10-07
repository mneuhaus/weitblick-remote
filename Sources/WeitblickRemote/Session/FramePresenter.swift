import AppKit
import IOSurface
import QuartzCore
import WeitblickKit

/// Shows the remote framebuffer in a CALayer through a small pool of IOSurfaces.
///
/// Each present copies only the regions that changed into a surface the window server is
/// not reading, then swaps it in as the layer contents. That avoids tearing (we never write
/// to the visible surface) and full-frame copies (each surface tracks what it is missing).
@MainActor
final class FramePresenter {
    let layer = CALayer()
    private var pool: [PooledSurface] = []
    private var shown: PooledSurface?
    private static let poolSize = 3

    init() {
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true
        layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    /// Size of the surfaces, i.e. of the last presented framebuffer.
    var pixelSize: PixelSize? {
        pool.first.map { PixelSize(width: $0.width, height: $0.height) }
    }

    /// Copies what changed since the last call and swaps it in. Returns false if there was
    /// nothing new to show.
    @discardableResult
    func present(from session: RDPSession) -> Bool {
        let next: PooledSurface?? = session.withFramebuffer { framebuffer in
            if pool.first.map({ $0.width != framebuffer.width || $0.height != framebuffer.height }) ?? true {
                rebuildPool(width: framebuffer.width, height: framebuffer.height)
            }
            let changed = framebuffer.dirtyRects.map {
                CGRect(x: Int($0.x), y: Int($0.y), width: Int($0.width), height: Int($0.height))
            }
            guard !changed.isEmpty || shown == nil else { return nil }
            pool.forEach { $0.markDirty(changed) }

            let candidates = pool.filter { $0 !== shown }
            let target = candidates.first { !$0.surface.isInUse } ?? candidates[0]
            target.copyPending(from: framebuffer)
            return target
        }
        guard let target = next ?? nil else { return false }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = target.surface
        CATransaction.commit()
        shown = target
        return true
    }

    private func rebuildPool(width: Int, height: Int) {
        pool = (0..<Self.poolSize).compactMap { _ in PooledSurface(width: width, height: height) }
        shown = nil
    }
}

/// One IOSurface plus the regions it has not received yet.
@MainActor
private final class PooledSurface {
    let surface: IOSurface
    let width: Int
    let height: Int
    private var pending: [CGRect]
    private static let maxPendingRects = 32

    init?(width: Int, height: Int) {
        let bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4)
        let properties: [IOSurfacePropertyKey: any Sendable] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        guard let surface = IOSurface(properties: properties) else { return nil }
        // Remote pixels are sRGB; without this they would be shown as display-native (too saturated on P3).
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colorSpace)
        }
        self.surface = surface
        self.width = width
        self.height = height
        self.pending = [CGRect(x: 0, y: 0, width: width, height: height)]
    }

    func markDirty(_ rects: [CGRect]) {
        pending.append(contentsOf: rects)
        if pending.count > Self.maxPendingRects {
            pending = [pending.reduce(CGRect.null) { $0.union($1) }]
        }
    }

    func copyPending(from framebuffer: Framebuffer) {
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        let destination = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let destinationStride = surface.bytesPerRow
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        for rect in pending {
            let clipped = rect.intersection(bounds)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
            let x = Int(clipped.minX), rowBytes = Int(clipped.width) * 4
            for y in Int(clipped.minY)..<Int(clipped.maxY) {
                memcpy(destination + y * destinationStride + x * 4,
                       framebuffer.pixels + y * framebuffer.bytesPerRow + x * 4,
                       rowBytes)
            }
        }
        pending.removeAll(keepingCapacity: true)
    }
}
