import CoreGraphics
import WeitblickKit

/// Where the remote desktop sits inside the session view (aspect fit, centered) and how
/// view points map to remote pixels. View coordinates are top-left based (flipped view).
struct DesktopGeometry {
    let bounds: CGRect
    let desktop: PixelSize

    /// The rectangle the desktop image occupies, in view points.
    var contentRect: CGRect {
        guard desktop.width > 0, desktop.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = pointsPerPixel
        let size = CGSize(width: CGFloat(desktop.width) * scale, height: CGFloat(desktop.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// View points per remote pixel (0.5 for a 1:1 Retina desktop).
    var pointsPerPixel: CGFloat {
        guard desktop.width > 0, desktop.height > 0 else { return 1 }
        return min(bounds.width / CGFloat(desktop.width), bounds.height / CGFloat(desktop.height))
    }

    func remotePoint(for viewPoint: CGPoint) -> RemotePoint {
        let rect = contentRect
        let scale = pointsPerPixel
        guard scale > 0 else { return RemotePoint(x: 0, y: 0) }
        let x = Int(((viewPoint.x - rect.minX) / scale).rounded(.down))
        let y = Int(((viewPoint.y - rect.minY) / scale).rounded(.down))
        return RemotePoint(x: min(max(x, 0), desktop.width - 1), y: min(max(y, 0), desktop.height - 1))
    }
}
