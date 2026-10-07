import CoreGraphics

/// Turns macOS scroll deltas into Windows wheel units (120 per notch).
///
/// macOS deltas already carry the user's natural-scrolling choice, so the signs map
/// directly: positive deltaY scrolls the content toward its top, like a positive RDP wheel
/// value. Horizontal is mirrored: RDP's positive HWHEEL scrolls right.
struct ScrollAccumulator {
    static let notch = 120
    /// Trackpad/Magic Mouse points per notch (Windows scrolls three lines per notch).
    static let pointsPerNotch: CGFloat = 30

    private var vertical: CGFloat = 0
    private var horizontal: CGFloat = 0

    /// Adds one scroll event and returns the whole notches to send now, in wheel units.
    /// `precise` deltas are points (trackpad), others are lines (one line = one notch).
    mutating func add(deltaX: CGFloat, deltaY: CGFloat, precise: Bool, gestureBegan: Bool)
        -> (vertical: Int, horizontal: Int)
    {
        if gestureBegan {
            vertical = 0
            horizontal = 0
        }
        let notchesPerUnit = precise ? 1 / Self.pointsPerNotch : 1
        vertical += deltaY * notchesPerUnit
        horizontal -= deltaX * notchesPerUnit
        return (Self.take(&vertical) * Self.notch, Self.take(&horizontal) * Self.notch)
    }

    private static func take(_ value: inout CGFloat) -> Int {
        let whole = Int(value.rounded(.towardZero))
        value -= CGFloat(whole)
        return whole
    }
}
