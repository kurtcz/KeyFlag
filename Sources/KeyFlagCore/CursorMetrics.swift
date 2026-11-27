import AppKit

/// Where the indicator goes relative to the pointer, worked out from the current cursor's
/// hot spot and the part of its image that is drawn, so it sits just right of the cursor
/// whatever its shape (I-beam, arrow, enlarged accessibility cursor).
public struct CursorMetrics: Equatable, Sendable {
    /// The cursor image's size in points.
    public var size: NSSize
    /// The hot spot, measured from the image's top-left corner (as NSCursor reports it).
    public var hotSpot: NSPoint
    /// The part of the image that is actually drawn, from its top-left corner, in points.
    /// Cursor images carry transparent padding (the macOS 26 I-beam is 23×22 pt but only
    /// about 8 pt wide), so placing from the full size puts the indicator too far away.
    /// Nil means the whole image.
    public var visibleRect: NSRect?

    public init(size: NSSize, hotSpot: NSPoint, visibleRect: NSRect? = nil) {
        self.size = size
        self.hotSpot = hotSpot
        self.visibleRect = visibleRect
    }

    /// The drawn rectangle: `visibleRect`, or the whole image.
    var drawnRect: NSRect { visibleRect ?? NSRect(origin: .zero, size: size) }

    /// Roughly the I-beam, used when the system cursor can't be read.
    public static let fallback = CursorMetrics(size: NSSize(width: 9, height: 18), hotSpot: NSPoint(x: 4, y: 8))

    /// Space between the cursor image and the indicator.
    static let gap: CGFloat = 2

    @MainActor
    public static func current() -> CursorMetrics? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        let size = cursor.image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let key = VisibleRectCache.Key(size: size, hotSpot: cursor.hotSpot)
        let visible: NSRect?
        if let cached = VisibleRectCache.rects[key] {
            visible = cached
        } else {
            var proposed = NSRect(origin: .zero, size: size)
            visible = cursor.image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
                .flatMap { opaqueRect(of: $0, pointSize: size) }
            VisibleRectCache.rects[key] = visible
        }
        return CursorMetrics(size: size, hotSpot: cursor.hotSpot, visibleRect: visible)
    }

    /// Measured once per cursor shape; `current()` runs ten times a second.
    @MainActor private enum VisibleRectCache {
        struct Key: Hashable {
            var width, height, hotX, hotY: CGFloat
            init(size: NSSize, hotSpot: NSPoint) {
                (width, height, hotX, hotY) = (size.width, size.height, hotSpot.x, hotSpot.y)
            }
        }
        static var rects: [Key: NSRect?] = [:]
    }

    /// Bounds of the pixels at least half opaque (so a soft drop shadow doesn't count), in
    /// points from the top-left corner of an image drawn at `pointSize`. Nil if none are.
    static func opaqueRect(of image: CGImage, pointSize: NSSize) -> NSRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] >= 128 {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // The bitmap context's memory starts with the image's top row.
        let sx = pointSize.width / CGFloat(width), sy = pointSize.height / CGFloat(height)
        return NSRect(x: CGFloat(minX) * sx, y: CGFloat(minY) * sy,
                      width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy)
    }

    /// The indicator's bottom-left origin (screen coordinates, y up) for a pointer at `mouse`.
    /// Just right of the drawn cursor, its top level with the hot spot; flipped to the left of
    /// the cursor or up from the hot spot when that would leave `screenFrame`, then clamped.
    public static func indicatorOrigin(mouse: NSPoint, cursor: CursorMetrics, indicatorSize: NSSize,
                                       screenFrame: NSRect) -> NSPoint {
        let drawn = cursor.drawnRect
        let right = max(0, drawn.maxX - cursor.hotSpot.x)
        let left = max(0, cursor.hotSpot.x - drawn.minX)

        var x = mouse.x + right + gap
        if x + indicatorSize.width > screenFrame.maxX {
            x = mouse.x - left - gap - indicatorSize.width
        }
        // Beside the cursor rather than under it: the top edge level with the hot spot, so the
        // flag hangs down from the pointer instead of starting below the whole cursor.
        var y = mouse.y - indicatorSize.height
        if y < screenFrame.minY {
            y = mouse.y
        }
        guard !screenFrame.isInfinite else { return NSPoint(x: x, y: y) }
        x = min(max(x, screenFrame.minX), screenFrame.maxX - indicatorSize.width)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - indicatorSize.height)
        return NSPoint(x: x, y: y)
    }

    /// The indicator's origin for a text caret, placed the way `indicatorOrigin` places it
    /// next to the pointer: just right of the caret, its top level with the caret's middle
    /// (where the I-beam's hot spot is). Flipped to the left of the caret or up from its
    /// middle when that would leave `screenFrame`, then clamped inside it.
    public static func caretIndicatorOrigin(caret: NSRect, indicatorSize: NSSize, screenFrame: NSRect) -> NSPoint {
        var x = caret.maxX + gap
        if x + indicatorSize.width > screenFrame.maxX {
            x = caret.minX - gap - indicatorSize.width
        }
        var y = caret.midY - indicatorSize.height
        if y < screenFrame.minY {
            y = caret.midY
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
