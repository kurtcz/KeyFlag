import AppKit

/// Country flag images in each `FlagStyle`.
///
/// Classic flags are our own simplified vector drawings (no Apple artwork), styled after
/// the Mac OS X input menu: a small 3:2 rectangle with a thin dark edge and a soft glossy
/// highlight. Countries without a drawing fall back to the Apple Color Emoji flag.
public enum FlagArt {
    /// A flag image `height` points tall in the given style (the first frame for
    /// `.waving`), or nil for `.system` or an invalid `countryCode`.
    public static func image(countryCode: String, style: FlagStyle, height: CGFloat = 16) -> NSImage? {
        frames(countryCode: countryCode, style: style, height: height)?.first
    }

    /// One image for still styles, a looping animation for `.waving`.
    public static func frames(countryCode: String, style: FlagStyle, height: CGFloat = 16) -> [NSImage]? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        let size = canvasSize(height: height)
        switch style {
        case .system:
            return nil
        case .classic:
            return [hasDrawing(code) ? classicImage(code, size: size) : emojiImage(code, size: size)]
        case .emoji:
            return [emojiImage(code, size: size)]
        case .waving:
            // The emoji flag already waves; only our drawings get animated.
            guard hasDrawing(code) else { return [emojiImage(code, size: size)] }
            return wavingFrames(classicImage(code, size: size))
        }
    }

    /// Room for a 3:2 flag with a little margin above and below.
    /// Flags are 3:2, like the old Mac OS X ones, whatever the country's real proportions.
    static let flagAspect: CGFloat = 3.0 / 2.0

    /// Blank space above and below the flag, so it sits like a glyph in the menu bar.
    private static func verticalMargin(height: CGFloat) -> CGFloat {
        (height * 0.1).rounded()
    }

    /// 19×16 at 16pt: an 18×12 flag plus half a point on each side for the edge.
    static func canvasSize(height: CGFloat) -> NSSize {
        let flagHeight = height - 2 * verticalMargin(height: height)
        return NSSize(width: (flagHeight * flagAspect).rounded() + 1, height: height)
    }

    private static func flagRect(in bounds: NSRect) -> NSRect {
        let margin = verticalMargin(height: bounds.height)
        return NSRect(x: 0.5, y: margin, width: bounds.width - 1, height: bounds.height - 2 * margin)
    }

    private static func classicImage(_ code: String, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { bounds in
            drawClassic(code, in: flagRect(in: bounds))
            return true
        }
    }

    // MARK: - Waving

    /// Bends `flat` into a travelling wave, fixed at the hoist (left edge), with light and
    /// shade following the folds. Each frame holds a bitmap per scale (1× and 2×), each drawn
    /// from the vector flag at that resolution, so AppKit picks the sharp one on every screen
    /// instead of downsampling Retina pixels on a 1× display.
    static func wavingFrames(_ flat: NSImage, frameCount: Int = 16, scales: [CGFloat] = [1, 2]) -> [NSImage] {
        let perScale = scales.map { wavingBitmaps(flat, frameCount: frameCount, scale: $0) }
        guard let count = perScale.map(\.count).min(), count > 0 else { return [flat] }
        return (0..<count).map { frame in
            let image = NSImage(size: flat.size)
            for bitmaps in perScale {
                let rep = NSBitmapImageRep(cgImage: bitmaps[frame])
                rep.size = flat.size
                image.addRepresentation(rep)
            }
            return image
        }
    }

    private static func wavingBitmaps(_ flat: NSImage, frameCount: Int, scale: CGFloat) -> [CGImage] {
        let pixelWidth = Int(flat.size.width * scale), pixelHeight = Int(flat.size.height * scale)
        guard let source = bitmap(flat, width: pixelWidth, height: pixelHeight) else { return [] }
        let space = CGColorSpaceCreateDeviceRGB()
        return (0..<frameCount).compactMap { frame in
            guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            let t = CGFloat(frame) / CGFloat(frameCount)
            for x in 0..<pixelWidth {
                let u = CGFloat(x) / CGFloat(pixelWidth)
                let phase = 2 * .pi * (u * 1.1 - t)
                let amplitude = CGFloat(pixelHeight) * 0.07 * (0.25 + 0.75 * u)
                let dy = sin(phase) * amplitude
                guard let column = source.cropping(to: CGRect(x: x, y: 0, width: 1, height: pixelHeight)) else { continue }
                let rect = CGRect(x: CGFloat(x), y: dy, width: 1, height: CGFloat(pixelHeight))
                context.draw(column, in: rect)
                // Slope of the wave → facing the light or turned away from it.
                let light = cos(phase) * (0.25 + 0.75 * u)
                context.saveGState()
                context.clip(to: rect, mask: column)
                context.setFillColor(light > 0 ? CGColor(gray: 1, alpha: light * 0.22) : CGColor(gray: 0, alpha: -light * 0.28))
                context.fill(rect)
                context.restoreGState()
            }
            return context.makeImage()
        }
    }

    private static func bitmap(_ image: NSImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Whether `code` has its own drawing rather than the emoji fallback.
    public static func hasDrawing(_ code: String) -> Bool {
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        return draw(code, in: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Classic frame

    private static func drawClassic(_ code: String, in rect: NSRect) {
        let outline = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        _ = draw(code, in: rect)
        // Light from above: a highlight on the top half, slight shade at the bottom.
        NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.38), 0),
            (NSColor.white.withAlphaComponent(0.08), 0.45),
            (NSColor.clear, 0.55),
            (NSColor.black.withAlphaComponent(0.12), 1)
        )?.draw(in: rect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 1, yRadius: 1)
        edge.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.45).setStroke()
        edge.stroke()
    }

    private static func emojiImage(_ code: String, size: NSSize) -> NSImage {
        let emoji = String(String.UnicodeScalarView(code.unicodeScalars.compactMap {
            Unicode.Scalar(0x1F1E6 + $0.value - 65)
        }))
        return NSImage(size: size, flipped: false) { bounds in
            let font = NSFont(name: "Apple Color Emoji", size: bounds.height * 0.95) ?? .systemFont(ofSize: bounds.height * 0.95)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (emoji as NSString).size(withAttributes: attributes)
            (emoji as NSString).draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2),
                                     withAttributes: attributes)
            return true
        }
    }

    // MARK: - Flags

    /// Draws the flag into `r` (flipped coordinates: y grows downward). Returns false if
    /// there is no drawing for `code`.
    private static func draw(_ code: String, in r: NSRect) -> Bool {
        switch code {
        // Horizontal stripes
        case "DE": h([0x000000, 0xDD0000, 0xFFCE00], r)
        case "RU": h([0xFFFFFF, 0x0039A6, 0xD52B1E], r)
        case "NL": h([0xAE1C28, 0xFFFFFF, 0x21468B], r)
        case "LU": h([0xEA141D, 0xFFFFFF, 0x00A1DE], r)
        case "AT": h([0xED2939, 0xFFFFFF, 0xED2939], r)
        case "HU": h([0xCE2939, 0xFFFFFF, 0x477050], r)
        case "BG": h([0xFFFFFF, 0x00966E, 0xD62612], r)
        case "EE": h([0x0072CE, 0x000000, 0xFFFFFF], r)
        case "LT": h([0xFDB913, 0x006A44, 0xC1272D], r)
        case "LV": h([0x9E3039, 0xFFFFFF, 0x9E3039], weights: [2, 1, 2], r)
        case "UA": h([0x0057B7, 0xFFD700], r)
        case "PL": h([0xFFFFFF, 0xDC143C], r)
        case "CZ":
            h([0xFFFFFF, 0xD7141A], r)
            let wedge = NSBezierPath()
            wedge.move(to: CGPoint(x: r.minX, y: r.minY))
            wedge.line(to: CGPoint(x: r.minX + r.width / 2, y: r.midY))
            wedge.line(to: CGPoint(x: r.minX, y: r.maxY))
            wedge.close()
            color(0x11457E).setFill(); wedge.fill()
        case "ID", "MC": h([0xFF0000, 0xFFFFFF], r)
        case "AM": h([0xD90012, 0x0033A0, 0xF2A800], r)
        case "AZ": h([0x0092BC, 0xE4002B, 0x00AF66], r)
        case "ES": h([0xAA151B, 0xF1BF00, 0xAA151B], weights: [1, 2, 1], r)
        case "TH": h([0xA51931, 0xF4F5F8, 0x2D2A4A, 0xF4F5F8, 0xA51931], weights: [1, 1, 2, 1, 1], r)
        case "CO": h([0xFCD116, 0x003893, 0xCE1126], weights: [2, 1, 1], r)
        case "GA": h([0x009E60, 0xFCD116, 0x3A75C4], r)
        case "SL": h([0x1EB53A, 0xFFFFFF, 0x0072C6], r)
        case "YE": h([0xCE1126, 0xFFFFFF, 0x000000], r)
        case "SY": h([0xCE1126, 0xFFFFFF, 0x000000], r)
            star(CGPoint(x: r.midX - r.width * 0.15, y: r.midY), r.height * 0.11, 0x007A3D)
            star(CGPoint(x: r.midX + r.width * 0.15, y: r.midY), r.height * 0.11, 0x007A3D)
        case "EG": h([0xCE1126, 0xFFFFFF, 0x000000], r); disc(r.mid, r.height * 0.11, 0xC09300)
        case "IN":
            h([0xFF9933, 0xFFFFFF, 0x138808], r)
            ring(r.mid, r.height * 0.13, 0x000080, width: r.height * 0.035)
        case "AR", "SV":
            h([0x74ACDF, 0xFFFFFF, 0x74ACDF], r); disc(r.mid, r.height * 0.1, 0xF6B40E)
        case "KZ": fill(0x00AFCA, r); disc(r.mid, r.height * 0.2, 0xFEC50C)
        case "BY":
            h([0xC8313E, 0x4AA657], weights: [2, 1], r)
            fill(0xFFFFFF, NSRect(x: r.minX, y: r.minY, width: r.width * 0.11, height: r.height))
            for i in 0..<5 {
                let y = r.minY + r.height * (CGFloat(i) + 0.5) / 5
                diamond(CGPoint(x: r.minX + r.width * 0.055, y: y), r.width * 0.035, 0xC8313E)
            }

        // Vertical stripes
        case "FR": v([0x002395, 0xFFFFFF, 0xED2939], r)
        case "IT": v([0x009246, 0xFFFFFF, 0xCE2B37], r)
        case "BE": v([0x000000, 0xFDDA24, 0xEF3340], r)
        case "IE": v([0x169B62, 0xFFFFFF, 0xFF883E], r)
        case "RO": v([0x002B7F, 0xFCD116, 0xCE1126], r)
        case "NG": v([0x008751, 0xFFFFFF, 0x008751], r)
        case "ML": v([0x14B53A, 0xFCD116, 0xCE1126], r)
        case "GN": v([0xCE1126, 0xFCD116, 0x009460], r)
        case "MT": v([0xFFFFFF, 0xCF142B], r)
        case "MX":
            v([0x006847, 0xFFFFFF, 0xCE1126], r); disc(r.mid, r.height * 0.13, 0x8C6A2F)
        case "PT":
            v([0x006600, 0xFF0000], weights: [2, 3], r)
            disc(CGPoint(x: r.minX + r.width * 0.4, y: r.midY), r.height * 0.22, 0xFFE600)
            disc(CGPoint(x: r.minX + r.width * 0.4, y: r.midY), r.height * 0.13, 0xFF0000)

        // Nordic crosses
        case "SE": nordic(0x006AA7, cross: 0xFECC00, inner: nil, r)
        case "DK": nordic(0xC8102E, cross: 0xFFFFFF, inner: nil, r)
        case "FI": nordic(0xFFFFFF, cross: 0x002F6C, inner: nil, r)
        case "NO": nordic(0xBA0C2F, cross: 0xFFFFFF, inner: 0x00205B, r)
        case "IS": nordic(0x02529C, cross: 0xFFFFFF, inner: 0xDC1E35, r)
        case "FO": nordic(0xFFFFFF, cross: 0x005EB9, inner: 0xEF303E, r)

        // Tricolors with a coat of arms, simplified to a small shield
        case "SK":
            h([0xFFFFFF, 0x0B4EA2, 0xEE1C25], r)
            shield(CGPoint(x: r.minX + r.width * 0.32, y: r.midY), r.height * 0.5, fill: 0xEE1C25, edge: 0xFFFFFF)
        case "SI":
            h([0xFFFFFF, 0x005DA4, 0xED1C24], r)
            shield(CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.42), r.height * 0.42, fill: 0x005DA4, edge: 0xED1C24)
        case "HR":
            h([0xFF0000, 0xFFFFFF, 0x171796], r)
            shield(r.mid, r.height * 0.5, fill: 0xFF0000, edge: 0xFFFFFF, checkered: true)
        case "RS":
            h([0xC6363C, 0x0C4076, 0xFFFFFF], r)
            shield(CGPoint(x: r.minX + r.width * 0.33, y: r.midY), r.height * 0.5, fill: 0xC6363C, edge: 0xFFFFFF)
        case "MK":
            fill(0xD20000, r)
            let c = r.mid
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                let p = NSBezierPath()
                p.move(to: c)
                p.line(to: CGPoint(x: c.x + cos(a - 0.12) * r.width, y: c.y + sin(a - 0.12) * r.width))
                p.line(to: CGPoint(x: c.x + cos(a + 0.12) * r.width, y: c.y + sin(a + 0.12) * r.width))
                p.close()
                color(0xFFE600).setFill(); p.fill()
            }
            disc(c, r.height * 0.16, 0xFFE600)

        // Crosses and emblems
        case "CH":
            fill(0xDA291C, r)
            let arm = r.height * 0.18, len = r.height * 0.62
            fill(0xFFFFFF, NSRect(x: r.midX - arm / 2, y: r.midY - len / 2, width: arm, height: len))
            fill(0xFFFFFF, NSRect(x: r.midX - len / 2, y: r.midY - arm / 2, width: len, height: arm))
        case "GE":
            fill(0xFFFFFF, r)
            let arm = r.height * 0.2
            fill(0xFF0000, NSRect(x: r.midX - arm / 2, y: r.minY, width: arm, height: r.height))
            fill(0xFF0000, NSRect(x: r.minX, y: r.midY - arm / 2, width: r.width, height: arm))
            for dx in [-1.0, 1.0] as [CGFloat] {
                for dy in [-1.0, 1.0] as [CGFloat] {
                    let c = CGPoint(x: r.midX + dx * r.width * 0.25, y: r.midY + dy * r.height * 0.25)
                    let s = r.height * 0.12, t = r.height * 0.05
                    fill(0xFF0000, NSRect(x: c.x - t / 2, y: c.y - s / 2, width: t, height: s))
                    fill(0xFF0000, NSRect(x: c.x - s / 2, y: c.y - t / 2, width: s, height: t))
                }
            }
        case "JP": fill(0xFFFFFF, r); disc(r.mid, r.height * 0.3, 0xBC002D)
        case "BD": fill(0x006A4E, r); disc(CGPoint(x: r.minX + r.width * 0.45, y: r.midY), r.height * 0.3, 0xF42A41)
        case "LA":
            h([0xCE1126, 0x002868, 0xCE1126], weights: [1, 2, 1], r); disc(r.mid, r.height * 0.2, 0xFFFFFF)
        case "VN": fill(0xDA251D, r); star(r.mid, r.height * 0.32, 0xFFFF00)
        case "CN":
            fill(0xDE2910, r)
            let u = r.height / 20
            star(CGPoint(x: r.minX + 5 * u, y: r.minY + 5 * u), 3 * u, 0xFFDE00)
            for (x, y) in [(10.0, 2.0), (12.0, 4.0), (12.0, 7.0), (10.0, 9.0)] as [(CGFloat, CGFloat)] {
                star(CGPoint(x: r.minX + x * u, y: r.minY + y * u), u, 0xFFDE00)
            }
        case "TR":
            fill(0xE30A17, r)
            disc(CGPoint(x: r.minX + r.width * 0.37, y: r.midY), r.height * 0.25, 0xFFFFFF)
            disc(CGPoint(x: r.minX + r.width * 0.41, y: r.midY), r.height * 0.2, 0xE30A17)
            star(CGPoint(x: r.minX + r.width * 0.56, y: r.midY), r.height * 0.12, 0xFFFFFF)
        case "IL":
            fill(0xFFFFFF, r)
            fill(0x0038B8, NSRect(x: r.minX, y: r.minY + r.height * 0.1, width: r.width, height: r.height * 0.15))
            fill(0x0038B8, NSRect(x: r.minX, y: r.maxY - r.height * 0.25, width: r.width, height: r.height * 0.15))
            for flip in [1.0, -1.0] as [CGFloat] {
                let p = polygon(r.mid, r.height * 0.18, sides: 3, rotation: flip * -.pi / 2)
                p.lineWidth = r.height * 0.045
                color(0x0038B8).setStroke(); p.stroke()
            }
        case "GR":
            let stripes = (0..<9).map { $0 % 2 == 0 ? 0x0D5EAF : 0xFFFFFF as UInt32 }
            h(stripes, r)
            let side = r.height * 5 / 9, arm = r.height / 9
            fill(0x0D5EAF, NSRect(x: r.minX, y: r.minY, width: side, height: side))
            fill(0xFFFFFF, NSRect(x: r.minX + side / 2 - arm / 2, y: r.minY, width: arm, height: side))
            fill(0xFFFFFF, NSRect(x: r.minX, y: r.minY + side / 2 - arm / 2, width: side, height: arm))
        case "US":
            let stripes = (0..<13).map { $0 % 2 == 0 ? 0xB22234 : 0xFFFFFF as UInt32 }
            h(stripes, r)
            let canton = NSRect(x: r.minX, y: r.minY, width: r.width * 0.4, height: r.height * 7 / 13)
            fill(0x3C3B6E, canton)
            for row in 0..<4 {
                for col in 0..<5 {
                    let x = canton.minX + canton.width * (CGFloat(col) + (row % 2 == 0 ? 0.35 : 0.65)) / 5
                    let y = canton.minY + canton.height * (CGFloat(row) + 0.5) / 4
                    disc(CGPoint(x: x, y: y), max(0.25, r.height * 0.022), 0xFFFFFF)
                }
            }
        case "GB": unionJack(r)
        case "AU", "NZ":
            fill(0x012169, r)
            unionJack(NSRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height / 2))
            let starColor: UInt32 = code == "AU" ? 0xFFFFFF : 0xC8102E
            if code == "AU" { star(CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.75), r.height * 0.11, 0xFFFFFF) }
            for (x, y) in [(0.75, 0.25), (0.62, 0.5), (0.86, 0.45), (0.75, 0.82)] as [(CGFloat, CGFloat)] {
                let c = CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
                if code == "NZ" { star(c, r.height * 0.09, 0xFFFFFF) }
                star(c, r.height * 0.07, starColor)
            }
        case "CA":
            v([0xFF0000, 0xFFFFFF, 0xFF0000], weights: [1, 2, 1], r)
            mapleLeaf(r.mid, r.height * 0.36)
        case "BR":
            fill(0x009C3B, r)
            let p = NSBezierPath()
            p.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.1))
            p.line(to: CGPoint(x: r.maxX - r.width * 0.08, y: r.midY))
            p.line(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.1))
            p.line(to: CGPoint(x: r.minX + r.width * 0.08, y: r.midY))
            p.close()
            color(0xFFDF00).setFill(); p.fill()
            disc(r.mid, r.height * 0.22, 0x002776)
        default:
            return false
        }
        return true
    }

    // MARK: - Drawing helpers

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func fill(_ hex: UInt32, _ rect: NSRect) {
        color(hex).setFill()
        rect.fill()
    }

    private static func h(_ colors: [UInt32], weights: [CGFloat]? = nil, _ r: NSRect) {
        let weights = weights ?? Array(repeating: 1, count: colors.count)
        let total = weights.reduce(0, +)
        var y = r.minY
        for (hex, weight) in zip(colors, weights) {
            let height = r.height * weight / total
            fill(hex, NSRect(x: r.minX, y: y, width: r.width, height: height + 0.01))
            y += height
        }
    }

    private static func v(_ colors: [UInt32], weights: [CGFloat]? = nil, _ r: NSRect) {
        let weights = weights ?? Array(repeating: 1, count: colors.count)
        let total = weights.reduce(0, +)
        var x = r.minX
        for (hex, weight) in zip(colors, weights) {
            let width = r.width * weight / total
            fill(hex, NSRect(x: x, y: r.minY, width: width + 0.01, height: r.height))
            x += width
        }
    }

    /// Off-center Scandinavian cross, optionally with a narrower cross on top.
    private static func nordic(_ background: UInt32, cross: UInt32, inner: UInt32?, _ r: NSRect) {
        fill(background, r)
        let centerX = r.minX + r.width * 0.37
        func bars(_ hex: UInt32, _ thickness: CGFloat) {
            fill(hex, NSRect(x: centerX - thickness / 2, y: r.minY, width: thickness, height: r.height))
            fill(hex, NSRect(x: r.minX, y: r.midY - thickness / 2, width: r.width, height: thickness))
        }
        bars(cross, r.height * (inner == nil ? 0.2 : 0.26))
        if let inner { bars(inner, r.height * 0.12) }
    }

    private static func disc(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32) {
        color(hex).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    private static func ring(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32, width: CGFloat) {
        let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.lineWidth = width
        color(hex).setStroke()
        path.stroke()
    }

    private static func diamond(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32) {
        color(hex).setFill()
        polygon(center, radius, sides: 4, rotation: -.pi / 2).fill()
    }

    private static func polygon(_ center: CGPoint, _ radius: CGFloat, sides: Int, rotation: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<sides {
            let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(sides)
            let p = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        return path
    }

    /// Five-pointed star with one point straight up.
    private static func star(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32) {
        let path = NSBezierPath()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let length = i % 2 == 0 ? radius : radius * 0.4
            let p = CGPoint(x: center.x + cos(a) * length, y: center.y + sin(a) * length)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        color(hex).setFill()
        path.fill()
    }

    private static func shield(_ center: CGPoint, _ height: CGFloat, fill hex: UInt32, edge: UInt32, checkered: Bool = false) {
        let width = height * 0.8
        let top = center.y - height / 2
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - width / 2, y: top))
        path.line(to: CGPoint(x: center.x + width / 2, y: top))
        path.line(to: CGPoint(x: center.x + width / 2, y: top + height * 0.55))
        path.curve(to: CGPoint(x: center.x, y: top + height),
                   controlPoint1: CGPoint(x: center.x + width / 2, y: top + height * 0.85),
                   controlPoint2: CGPoint(x: center.x + width * 0.2, y: top + height))
        path.curve(to: CGPoint(x: center.x - width / 2, y: top + height * 0.55),
                   controlPoint1: CGPoint(x: center.x - width * 0.2, y: top + height),
                   controlPoint2: CGPoint(x: center.x - width / 2, y: top + height * 0.85))
        path.close()
        color(hex).setFill()
        path.fill()
        if checkered {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let cell = width / 4
            for row in 0..<5 {
                for col in 0..<4 where (row + col) % 2 == 1 {
                    fill(0xFFFFFF, NSRect(x: center.x - width / 2 + CGFloat(col) * cell, y: top + CGFloat(row) * cell,
                                          width: cell, height: cell))
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // A double cross, which reads as "a coat of arms" at this size.
            let arm = width * 0.14
            fill(edge, NSRect(x: center.x - arm / 2, y: top + height * 0.15, width: arm, height: height * 0.6))
            fill(edge, NSRect(x: center.x - width * 0.25, y: top + height * 0.35, width: width * 0.5, height: arm))
        }
        path.lineWidth = max(0.3, height * 0.06)
        color(edge).setStroke()
        path.stroke()
    }

    private static func unionJack(_ r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        fill(0x012169, r)
        func diagonals(_ hex: UInt32, _ width: CGFloat) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.minY)); path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.move(to: CGPoint(x: r.maxX, y: r.minY)); path.line(to: CGPoint(x: r.minX, y: r.maxY))
            path.lineWidth = width
            color(hex).setStroke()
            path.stroke()
        }
        diagonals(0xFFFFFF, r.height * 0.2)
        diagonals(0xC8102E, r.height * 0.07)
        func cross(_ hex: UInt32, _ thickness: CGFloat) {
            fill(hex, NSRect(x: r.midX - thickness / 2, y: r.minY, width: thickness, height: r.height))
            fill(hex, NSRect(x: r.minX, y: r.midY - thickness / 2, width: r.width, height: thickness))
        }
        cross(0xFFFFFF, r.height * 0.33)
        cross(0xC8102E, r.height * 0.2)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func mapleLeaf(_ center: CGPoint, _ radius: CGFloat) {
        let points: [(CGFloat, CGFloat)] = [
            (0, -1), (0.14, -0.72), (0.3, -0.8), (0.24, -0.32), (0.52, -0.58), (0.58, -0.42), (0.9, -0.5),
            (0.78, -0.2), (0.86, -0.12), (0.44, 0.22), (0.5, 0.38), (0.06, 0.3), (0.06, 0.8), (-0.06, 0.8),
            (-0.06, 0.3), (-0.5, 0.38), (-0.44, 0.22), (-0.86, -0.12), (-0.78, -0.2), (-0.9, -0.5),
            (-0.58, -0.42), (-0.52, -0.58), (-0.24, -0.32), (-0.3, -0.8), (-0.14, -0.72),
        ]
        let path = NSBezierPath()
        for (i, (x, y)) in points.enumerated() {
            let p = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        color(0xFF0000).setFill()
        path.fill()
    }
}

private extension NSRect {
    var mid: CGPoint { CGPoint(x: midX, y: midY) }
}
