import AppKit

/// Where the indicator goes relative to the pointer, worked out from the current cursor's
/// size and hot spot so it sits just past the cursor's lower right corner whatever its shape
/// (I-beam, arrow, enlarged accessibility cursor).
public struct CursorMetrics: Equatable, Sendable {
    /// The cursor image's size in points.
    public var size: NSSize
    /// The hot spot, measured from the image's top-left corner (as NSCursor reports it).
    public var hotSpot: NSPoint

    public init(size: NSSize, hotSpot: NSPoint) {
        self.size = size
        self.hotSpot = hotSpot
    }

    /// Roughly the I-beam, used when the system cursor can't be read.
    public static let fallback = CursorMetrics(size: NSSize(width: 9, height: 18), hotSpot: NSPoint(x: 4, y: 8))

    /// Space between the cursor image and the indicator.
    static let gap: CGFloat = 2

    @MainActor
    public static func current() -> CursorMetrics? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        let size = cursor.image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return CursorMetrics(size: size, hotSpot: cursor.hotSpot)
    }

    /// The indicator's bottom-left origin (screen coordinates, y up) for a pointer at `mouse`.
    /// Below and right of the cursor by default; flipped left or above when that would leave
    /// `screenFrame`, then clamped inside it.
    public static func indicatorOrigin(mouse: NSPoint, cursor: CursorMetrics, indicatorSize: NSSize,
                                       screenFrame: NSRect) -> NSPoint {
        let right = max(0, cursor.size.width - cursor.hotSpot.x)
        let below = max(0, cursor.size.height - cursor.hotSpot.y)
        let left = max(0, cursor.hotSpot.x)
        let above = max(0, cursor.hotSpot.y)

        var x = mouse.x + right + gap
        if x + indicatorSize.width > screenFrame.maxX {
            x = mouse.x - left - gap - indicatorSize.width
        }
        var y = mouse.y - below - gap - indicatorSize.height
        if y < screenFrame.minY {
            y = mouse.y + above + gap
        }
        guard !screenFrame.isInfinite else { return NSPoint(x: x, y: y) }
        x = min(max(x, screenFrame.minX), screenFrame.maxX - indicatorSize.width)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - indicatorSize.height)
        return NSPoint(x: x, y: y)
    }

    /// Rounds to the screen's pixel grid so the indicator isn't drawn between pixels (blurry).
    public static func pixelAligned(_ point: NSPoint, scale: CGFloat) -> NSPoint {
        let scale = max(scale, 1)
        return NSPoint(x: (point.x * scale).rounded() / scale, y: (point.y * scale).rounded() / scale)
    }
}
