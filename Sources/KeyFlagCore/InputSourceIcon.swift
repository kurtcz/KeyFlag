import AppKit

/// Builds the images shown in the menu bar and next to the pointer.
@MainActor
public enum InputSourceIcon {
    /// The images to show for `source`: a flag in `style` (several frames when it waves),
    /// or else the input source's own icon. All are `height` points tall, except coats of
    /// arms, which are taller (`FlagArt.coatOfArmsHeightFactor`).
    public static func frames(for source: InputSource, style: FlagStyle, height: CGFloat) -> [NSImage] {
        flagFrames(for: source, style: style, height: height) ?? [scaled(systemImage(for: source), toHeight: height)]
    }

    /// A still image for `source`, e.g. for menu items.
    public static func image(for source: InputSource, style: FlagStyle, height: CGFloat) -> NSImage {
        frames(for: source, style: style, height: height)[0]
    }

    /// The flag frames for a keyboard layout, or nil for `.system`, input methods and
    /// layouts without a country. Cached, since waving frames take a moment to render.
    public static func flagFrames(for source: InputSource, style: FlagStyle, height: CGFloat) -> [NSImage]? {
        guard let country = countryCode(for: source) else { return nil }
        let key = "\(country)/\(style.rawValue)/\(height)"
        if let cached = flagCache[key] { return cached }
        let frames = FlagArt.frames(countryCode: country, style: style, height: height)
        flagCache[key] = frames
        return frames
    }

    /// The country whose flag stands for `source`: the user's choice for it if any, else
    /// the one `FlagMapping` picks.
    public static func countryCode(for source: InputSource) -> String? {
        FlagMapping.countryCode(inputSourceID: source.id, languages: source.languages,
                                overrides: Settings.shared.flagOverrides)
    }

    private static var flagCache: [String: [NSImage]?] = [:]

    /// The input source's own icon, or a two-letter badge if it has none.
    ///
    /// Apple's keyboard layouts report no icon of their own through the Text Input Sources
    /// API, so they get the label icon macOS draws in its Input menu ("A", "РУ", "ف•"), or a
    /// badge if the system can't provide it.
    public static func systemImage(for source: InputSource) -> NSImage {
        if source.id.hasPrefix("com.apple.keylayout.") && source.iconImageURL == nil {
            return SystemInputSourceIcon.image(for: source) ?? textImage(abbreviation(for: source))
        }
        if let url = source.iconImageURL, let image = NSImage(contentsOf: url) {
            return image
        }
        if let iconRef = source.iconRef {
            return NSImage(iconRef: iconRef)
        }
        return textImage(abbreviation(for: source))
    }

    /// False when KeyFlag can only show a letter badge for a source that should have an icon:
    /// a third-party layout or input method that reports no usable icon. Apple's layouts, flags
    /// and badges by design count as supported.
    public static func hasOwnIcon(_ source: InputSource) -> Bool {
        if countryCode(for: source) != nil { return true }
        if source.id.hasPrefix("com.apple.keylayout.") { return true }
        if let url = source.iconImageURL, NSImage(contentsOf: url) != nil { return true }
        return source.iconRef != nil
    }

    /// The layout's country when known (British → GB, so it differs from U.S.), else its language.
    static func abbreviation(for source: InputSource) -> String {
        if let country = countryCode(for: source) {
            return SpecialFlag.withCode(country)?.badge ?? country.uppercased()
        }
        let language = source.languages.first.flatMap { $0.isEmpty ? nil : $0 }
        return String((language ?? source.localizedName).prefix(2)).uppercased()
    }

    /// A rounded badge with short text, drawn at whatever scale the screen needs.
    public static func textImage(_ text: String, height: CGFloat = 16) -> NSImage {
        let font = NSFont.systemFont(ofSize: height * 0.62, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = NSSize(width: max(height, ceil(textSize.width) + height * 0.5), height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: height * 0.2, yRadius: height * 0.2)
            path.lineWidth = 1.5
            path.stroke()
            let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Scales to a given height, keeping the aspect ratio.
    public static func scaled(_ image: NSImage, toHeight height: CGFloat) -> NSImage {
        guard image.size.height > 0 else { return image }
        let width = (image.size.width * height / image.size.height).rounded()
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: width, height: height)
        return copy
    }

    /// Fills every non-transparent pixel with `color`, keeping the alpha.
    public static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }
}
