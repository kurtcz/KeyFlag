import AppKit

/// The Coat of Arms style: the country's (or old state's) arms from Wikimedia Commons,
/// scaled to fit a canvas as wide as a flag's but taller.
extension FlagArt {
    /// Whether `code` has bundled arms; the others fall back to their flag.
    public static func hasCoatOfArms(_ code: String) -> Bool {
        WikimediaArt.image(.coatOfArms, code: code) != nil
    }

    /// Arms are mostly taller than wide, so in a flag's canvas they'd leave a third of it
    /// empty and be unreadably small. They get a canvas this much taller instead, at the
    /// flag's width, so switching styles never changes the width of the menu bar item
    /// (19×20 at 16pt, which still fits the 24pt menu bar).
    static let coatOfArmsHeightFactor: CGFloat = 1.25

    static func coatOfArmsCanvasSize(height: CGFloat) -> NSSize {
        NSSize(width: canvasSize(height: height).width, height: (height * coatOfArmsHeightFactor).rounded())
    }

    static func coatOfArmsImage(_ code: String, size: NSSize) -> NSImage {
        let arms = WikimediaArt.image(.coatOfArms, code: code)
        return NSImage(size: size, flipped: false) { bounds in
            guard let arms, arms.size.width > 0, arms.size.height > 0 else { return false }
            // Use the whole height, less a hairline; wide arms are limited by the width.
            let box = bounds.insetBy(dx: 0, dy: bounds.height * 0.02)
            let scale = min(box.width / arms.size.width, box.height / arms.size.height)
            let fitted = NSSize(width: arms.size.width * scale, height: arms.size.height * scale)
            let rect = NSRect(x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                              width: fitted.width, height: fitted.height)
            NSGraphicsContext.current?.imageInterpolation = .high
            arms.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
