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
        let special = SpecialFlag.withCode(code)
        guard special != nil || (code.count == 2 && code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }))
        else { return nil }
        let size = canvasSize(height: height)
        switch style {
        case .system:
            return nil
        case .classic:
            return [hasDrawing(code) ? classicImage(code, size: size) : emojiImage(code, size: size)]
        case .emoji:
            // Regional and historical flags mostly have no emoji; their drawing stands in.
            if special != nil && special?.emoji == nil { return [classicImage(code, size: size)] }
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
        // Nepal's flag is the one that isn't a rectangle.
        let pennon = code == "NP" ? nepalOutline(in: rect) : nil
        let outline = pennon ?? NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
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

        let edge = pennon ?? NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 1, yRadius: 1)
        edge.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.45).setStroke()
        edge.stroke()
    }

    private static func emojiImage(_ code: String, size: NSSize) -> NSImage {
        let emoji = SpecialFlag.withCode(code)?.emoji ?? String(String.UnicodeScalarView(code.unicodeScalars.compactMap {
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
        case "CZ", "HIST-CZECHOSLOVAKIA":
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
        case "TR", "HIST-OTTOMAN":
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
        // Further flags, with emblems simplified to what reads at menu bar size
        case "AF":
            v([0x000000, 0xD32011, 0x007A36], r)
            ring(r.mid, r.height * 0.2, 0xFFFFFF, width: r.height * 0.05)
            shape([(0.45, 0.6), (0.45, 0.46), (0.47, 0.46), (0.5, 0.38), (0.53, 0.46), (0.55, 0.46), (0.55, 0.6)], 0xFFFFFF, r)
        case "AL":
            fill(0xE41E20, r)
            // The left half of the double-headed eagle, mirrored for the right.
            let half: [(CGFloat, CGFloat)] = [
                (0.5, 0.3), (0.47, 0.2), (0.42, 0.16), (0.36, 0.2), (0.42, 0.23), (0.45, 0.33), (0.4, 0.34),
                (0.26, 0.17), (0.29, 0.32), (0.25, 0.33), (0.31, 0.44), (0.27, 0.47), (0.35, 0.55), (0.32, 0.59),
                (0.43, 0.62), (0.38, 0.73), (0.43, 0.71), (0.42, 0.8), (0.47, 0.75), (0.5, 0.86),
            ]
            shape(half + half.reversed().map { (1 - $0.0, $0.1) }, 0x000000, r)
        case "DZ":
            v([0x006233, 0xFFFFFF], r)
            crescent(r.mid, r.height * 0.27, cut: CGPoint(x: r.midX + r.height * 0.09, y: r.midY), r.height * 0.215, 0xD21034)
            star(CGPoint(x: r.midX + r.height * 0.09, y: r.midY), r.height * 0.14, 0xD21034)
        case "BT":
            fill(0xFF4E12, r)
            shape([(0, 0), (1, 0), (0, 1)], 0xFFD520, r)
            // The dragon: a sinuous white body along the diagonal.
            let dragon = NSBezierPath()
            dragon.move(to: point(0.18, 0.8, r))
            dragon.curve(to: point(0.5, 0.5, r), controlPoint1: point(0.32, 0.92, r), controlPoint2: point(0.34, 0.38, r))
            dragon.curve(to: point(0.8, 0.22, r), controlPoint1: point(0.66, 0.62, r), controlPoint2: point(0.64, 0.14, r))
            dragon.lineWidth = r.height * 0.11
            dragon.lineCapStyle = .round
            color(0xFFFFFF).setStroke()
            dragon.stroke()
            disc(point(0.8, 0.23, r), r.height * 0.09, 0xFFFFFF)
        case "KH":
            h([0x032EA1, 0xE00025, 0x032EA1], weights: [1, 2, 1], r)
            shape([(0.28, 0.69), (0.28, 0.62), (0.33, 0.62), (0.33, 0.52), (0.37, 0.44), (0.41, 0.52), (0.44, 0.52),
                   (0.45, 0.4), (0.5, 0.31), (0.55, 0.4), (0.56, 0.52), (0.59, 0.52), (0.63, 0.44), (0.67, 0.52),
                   (0.67, 0.62), (0.72, 0.62), (0.72, 0.69)], 0xFFFFFF, r)
        case "ET":
            h([0x078930, 0xFCDD09, 0xDA121A], r)
            disc(r.mid, r.height * 0.3, 0x0F47AF)
            pentagram(r.mid, r.height * 0.24, 0xFCDD09, width: r.height * 0.045)
        case "GH": h([0xCE1126, 0xFCD116, 0x006B3F], r); star(r.mid, r.height * 0.18, 0x000000)
        case "HT":
            h([0x00209F, 0xD21034], r)
            fill(0xFFFFFF, rect(0.36, 0.29, 0.28, 0.42, r))
            shape([(0.39, 0.66), (0.45, 0.56), (0.55, 0.56), (0.61, 0.66)], 0x016A16, r)
            fill(0x016A16, rect(0.49, 0.38, 0.02, 0.2, r))
            disc(point(0.5, 0.39, r), r.height * 0.065, 0x016A16)
        case "IR":
            h([0x239F40, 0xFFFFFF, 0xDA0000], r)
            // The Kufic script bordering the white stripe, as a row of ticks.
            for i in 0..<11 {
                let x = (CGFloat(i) + 0.2) / 11
                fill(0xFFFFFF, rect(x, 0.27, 0.055, 0.05, r))
                fill(0xFFFFFF, rect(x, 0.68, 0.055, 0.05, r))
            }
            // The emblem: a sword between two pairs of crescents.
            fill(0xDA0000, rect(0.487, 0.37, 0.026, 0.27, r))
            for side in [-1.0, 1.0] as [CGFloat] {
                for (reach, top) in [(0.07, 0.4), (0.125, 0.43)] as [(CGFloat, CGFloat)] {
                    let blade = NSBezierPath()
                    blade.move(to: point(0.5 + side * reach * 0.45, top, r))
                    blade.curve(to: point(0.5 + side * 0.02, 0.63, r), controlPoint1: point(0.5 + side * reach, top + 0.05, r),
                                controlPoint2: point(0.5 + side * reach, 0.62, r))
                    blade.lineWidth = r.height * 0.03
                    color(0xDA0000).setStroke()
                    blade.stroke()
                }
            }
        case "IQ":
            h([0xCE1126, 0xFFFFFF, 0x000000], r)
            text("\u{0627}\u{0644}\u{0644}\u{0647} \u{0623}\u{0643}\u{0628}\u{0631}", at: r.mid, size: r.height * 0.27, 0x007A3D)
        case "KG":
            fill(0xE8112D, r)
            burst(r.mid, r.height * 0.37, r.height * 0.27, points: 40, 0xFFEF00)
            disc(r.mid, r.height * 0.22, 0xFFEF00)
            // The tunduk, the crown of a yurt.
            ring(r.mid, r.height * 0.13, 0xE8112D, width: r.height * 0.035)
            for offset in [-0.05, 0.05] as [CGFloat] {
                fill(0xE8112D, NSRect(x: r.midX - r.height * 0.13, y: r.midY + r.height * (offset - 0.012),
                                      width: r.height * 0.26, height: r.height * 0.024))
                fill(0xE8112D, NSRect(x: r.midX + r.height * (offset - 0.012), y: r.midY - r.height * 0.13,
                                      width: r.height * 0.024, height: r.height * 0.26))
            }
        case "MY":
            h((0..<14).map { $0 % 2 == 0 ? 0xCC0001 : 0xFFFFFF as UInt32 }, r)
            fill(0x010066, rect(0, 0, 0.5, 8.0 / 14, r))
            let c = point(0.19, 4.0 / 14, r)
            crescent(c, r.height * 0.21, cut: CGPoint(x: c.x + r.height * 0.07, y: c.y), r.height * 0.18, 0xFFCC00)
            burst(point(0.33, 4.0 / 14, r), r.height * 0.17, r.height * 0.08, points: 14, 0xFFCC00)
        case "MV":
            fill(0xD21034, r)
            fill(0x007E3A, rect(0.2, 0.23, 0.6, 0.54, r))
            crescent(r.mid, r.height * 0.18, cut: CGPoint(x: r.midX + r.height * 0.09, y: r.midY), r.height * 0.16, 0xFFFFFF)
        case "MN":
            v([0xC4272F, 0x015197, 0xC4272F], r)
            // The Soyombo symbol, from the flame at the top down.
            let gold: UInt32 = 0xF9CF02
            shape([(0.13, 0.25), (0.167, 0.1), (0.203, 0.25)], gold, r)
            disc(point(0.167, 0.32, r), r.height * 0.055, gold)
            shape([(0.12, 0.4), (0.213, 0.4), (0.167, 0.47)], gold, r)
            fill(gold, rect(0.13, 0.49, 0.074, 0.045, r))
            disc(point(0.167, 0.62, r), r.height * 0.07, gold)
            fill(gold, rect(0.13, 0.71, 0.074, 0.045, r))
            shape([(0.12, 0.78), (0.213, 0.78), (0.167, 0.87)], gold, r)
            fill(gold, rect(0.075, 0.39, 0.033, 0.48, r))
            fill(gold, rect(0.225, 0.39, 0.033, 0.48, r))
        case "MA": fill(0xC1272D, r); pentagram(r.mid, r.height * 0.3, 0x006233, width: r.height * 0.055)
        case "MM":
            h([0xFECB00, 0x34B233, 0xEA2839], r)
            star(CGPoint(x: r.midX, y: r.minY + r.height * 0.54), r.height * 0.45, 0xFFFFFF)
        case "NP":
            let outline = nepalOutline(in: r)
            color(0xDC143C).setFill()
            outline.fill()
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            outline.lineWidth = r.height * 0.13
            color(0x003893).setStroke()
            outline.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let x = nepalOutline(in: r).bounds.minX + r.height * 0.29
            let moon = CGPoint(x: x, y: r.minY + r.height * 0.27)
            crescent(moon, r.height * 0.13, cut: CGPoint(x: x, y: moon.y - r.height * 0.07), r.height * 0.13, 0xFFFFFF)
            disc(CGPoint(x: x, y: moon.y + r.height * 0.04), r.height * 0.055, 0xFFFFFF)
            burst(CGPoint(x: x, y: r.minY + r.height * 0.7), r.height * 0.17, r.height * 0.1, points: 12, 0xFFFFFF)
        case "PK":
            fill(0x01411C, r)
            fill(0xFFFFFF, rect(0, 0, 0.25, 1, r))
            let c = point(0.61, 0.52, r)
            crescent(c, r.height * 0.3, cut: CGPoint(x: c.x + r.height * 0.1, y: c.y - r.height * 0.08), r.height * 0.265, 0xFFFFFF)
            star(point(0.71, 0.31, r), r.height * 0.12, 0xFFFFFF)
        case "WS":
            fill(0xCE1126, r)
            fill(0x002B7F, rect(0, 0, 0.5, 0.5, r))
            for (x, y, size) in [(0.25, 0.09, 0.065), (0.15, 0.22, 0.065), (0.36, 0.2, 0.065), (0.29, 0.29, 0.04),
                                 (0.25, 0.4, 0.075)] as [(CGFloat, CGFloat, CGFloat)] {
                star(point(x, y, r), r.height * size, 0xFFFFFF)
            }
        case "KR":
            fill(0xFFFFFF, r)
            taegeuk(r.mid, r.height * 0.25)
            // The four trigrams; true marks a broken bar, listed from the outside in.
            trigram(point(0.2, 0.23, r), toward: r.mid, [false, false, false], r.height)
            trigram(point(0.8, 0.23, r), toward: r.mid, [true, false, true], r.height)
            trigram(point(0.2, 0.77, r), toward: r.mid, [false, true, false], r.height)
            trigram(point(0.8, 0.77, r), toward: r.mid, [true, true, true], r.height)
        case "LK":
            fill(0xFFB700, r)
            fill(0x005F56, rect(0.06, 0.09, 0.13, 0.82, r))
            fill(0xFF5B00, rect(0.19, 0.09, 0.13, 0.82, r))
            fill(0x8D153A, rect(0.38, 0.09, 0.56, 0.82, r))
            // The lion holding a sword.
            shape([(0.51, 0.75), (0.54, 0.6), (0.51, 0.45), (0.56, 0.5), (0.65, 0.47), (0.67, 0.32), (0.73, 0.27),
                   (0.79, 0.34), (0.78, 0.45), (0.74, 0.49), (0.8, 0.55), (0.76, 0.6), (0.76, 0.75), (0.72, 0.75),
                   (0.71, 0.63), (0.61, 0.63), (0.59, 0.75), (0.55, 0.75), (0.57, 0.62)], 0xFFB700, r)
            fill(0xFFB700, rect(0.815, 0.22, 0.022, 0.38, r))
            for (x, y) in [(0.43, 0.18), (0.89, 0.18), (0.43, 0.82), (0.89, 0.82)] as [(CGFloat, CGFloat)] {
                disc(point(x, y, r), r.height * 0.045, 0xFFB700)
            }
        case "TW":
            fill(0xFE0000, r)
            fill(0x000095, rect(0, 0, 0.5, 0.5, r))
            let c = point(0.25, 0.25, r)
            burst(c, r.height * 0.21, r.height * 0.11, points: 12, 0xFFFFFF)
            disc(c, r.height * 0.11, 0x000095)
            disc(c, r.height * 0.09, 0xFFFFFF)
        case "TJ":
            h([0xCC0000, 0xFFFFFF, 0x006600], weights: [2, 3, 2], r)
            shape([(0.43, 0.63), (0.42, 0.51), (0.46, 0.56), (0.5, 0.47), (0.54, 0.56), (0.58, 0.51), (0.57, 0.63)], 0xF8C300, r)
            for i in 0..<7 {
                let a = CGFloat.pi * (1.1 + 0.8 * CGFloat(i) / 6)
                star(CGPoint(x: r.midX + cos(a) * r.height * 0.2, y: r.minY + r.height * 0.56 + sin(a) * r.height * 0.18),
                     r.height * 0.035, 0xF8C300)
            }
        case "TO":
            fill(0xC10000, r)
            fill(0xFFFFFF, rect(0, 0, 0.48, 0.52, r))
            fill(0xC10000, rect(0.21, 0.08, 0.07, 0.36, r))
            fill(0xC10000, rect(0.12, 0.215, 0.25, 0.09, r))
        case "TM":
            fill(0x00843D, r)
            fill(0x9C2A2F, rect(0.14, 0, 0.17, 1, r))
            for i in 0..<5 {
                let c = point(0.225, (CGFloat(i) + 0.5) / 5, r)
                diamond(c, r.height * 0.09, 0xFFFFFF)
                diamond(c, r.height * 0.05, 0xD7791E)
            }
            let c = point(0.47, 0.27, r)
            crescent(c, r.height * 0.18, cut: CGPoint(x: c.x + r.height * 0.07, y: c.y + r.height * 0.05), r.height * 0.16, 0xFFFFFF)
            for (x, y) in [(0.52, 0.12), (0.57, 0.19), (0.52, 0.23), (0.57, 0.31), (0.53, 0.36)] as [(CGFloat, CGFloat)] {
                star(point(x, y, r), r.height * 0.04, 0xFFFFFF)
            }
        case "UZ":
            h([0x0099B5, 0xCE1126, 0xFFFFFF, 0xCE1126, 0x1EB53A], weights: [16, 1, 16, 1, 16], r)
            let c = point(0.16, 0.16, r)
            crescent(c, r.height * 0.12, cut: CGPoint(x: c.x + r.height * 0.06, y: c.y), r.height * 0.11, 0xFFFFFF)
            for (row, count) in [3, 4, 5].enumerated() {
                for i in 0..<count {
                    disc(point(0.46 - 0.05 * CGFloat(i), 0.07 + 0.09 * CGFloat(row), r), r.height * 0.024, 0xFFFFFF)
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

        // British Crown Dependencies and Overseas Territories
        case "IM":
            fill(0xCF101A, r)
            triskelion(r.mid, r.height * 0.36)
        case "JE":
            fill(0xFFFFFF, r)
            saltire(0xDF112D, r.height * 0.13, r)
            badge(point(0.5, 0.3, r), r.height * 0.34, top: 0xDF112D, bottom: 0xDF112D, edge: 0xF9DD16, mark: nil)
        case "GG":
            fill(0xFFFFFF, r)
            centeredCross(0xE8112D, r.height * 0.27, r)
            centeredCross(0xF9DD16, r.height * 0.1, r, inset: r.height * 0.18)
        case "GI":
            h([0xFFFFFF, 0xDA000C], weights: [2, 1], r)
            castle(r)
        case "BM":
            ensign(0xCF142B, r)
            badge(point(0.75, 0.5, r), r.height * 0.5, top: 0xFFFFFF, bottom: 0xFFFFFF, edge: 0xFFFFFF, mark: 0xCF142B)
        case "KY": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0xC8102E, bottom: 0x00A3E0, edge: 0xFFFFFF, mark: 0xF9DD16)
        case "VG": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0x00843D, bottom: 0x00843D, edge: 0xF9DD16, mark: 0xFFFFFF)
        case "AI": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0xFFFFFF, bottom: 0x00A1DE, edge: 0xFFFFFF, mark: 0xF68B1F)
        case "MS": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0x00A1DE, bottom: 0x8B5A2B, edge: 0xFFFFFF, mark: 0x00843D)
        case "TC": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0xFFD100, bottom: 0xFFD100, edge: 0xFFFFFF, mark: 0xF68B1F)
        case "FK": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0x00A1DE, bottom: 0xFFFFFF, edge: 0xFFFFFF, mark: 0xFFFFFF)
        case "SH": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0xFFD100, bottom: 0x00A1DE, edge: 0xFFFFFF, mark: nil)
        case "PN": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0x00843D, bottom: 0x00A1DE, edge: 0xFFFFFF, mark: 0xFFD100)
        case "GS": ensign(0x012169, r); badge(point(0.75, 0.5, r), r.height * 0.5, top: 0xFFFFFF, bottom: 0x00A1DE, edge: 0xFFD100, mark: 0x3C3C3C)
        case "IO":
            h([0xFFFFFF, 0x00247D, 0xFFFFFF, 0x00247D, 0xFFFFFF, 0x00247D, 0xFFFFFF, 0x00247D], r)
            unionJack(NSRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height / 2))
            fill(0x7B4A12, rect(0.745, 0.42, 0.03, 0.45, r))
            burst(point(0.76, 0.42, r), r.height * 0.2, r.height * 0.06, points: 6, 0x00843D)

        // UK nations and other regions
        case "GB-ENG": fill(0xFFFFFF, r); centeredCross(0xCE1124, r.height * 0.2, r)
        case "GB-SCT": fill(0x005EB8, r); saltire(0xFFFFFF, r.height * 0.2, r)
        case "GB-WLS": h([0xFFFFFF, 0x00B140], r); dragon(r)
        case "GB-NIR":
            fill(0xFFFFFF, r)
            centeredCross(0xCE1124, r.height * 0.2, r)
            hexagram(r.mid, r.height * 0.27, 0xFFFFFF)
            fill(0xCE1124, NSRect(x: r.midX - r.height * 0.06, y: r.midY - r.height * 0.07,
                                  width: r.height * 0.12, height: r.height * 0.16))
            crown(point(0.5, 0.13, r), r.height * 0.2, 0xF7C600)
        case "GB-CON": fill(0x000000, r); centeredCross(0xFFFFFF, r.height * 0.2, r)
        case "FR-BRE":
            h((0..<9).map { $0 % 2 == 0 ? 0x000000 : 0xFFFFFF }, r)
            fill(0xFFFFFF, rect(0, 0, 0.42, 5.0 / 9, r))
            for (x, y) in [(0.09, 0.14), (0.21, 0.14), (0.33, 0.14), (0.15, 0.39), (0.27, 0.39)] as [(CGFloat, CGFloat)] {
                ermine(point(x, y, r), r.height * 0.09)
            }
        case "ES-CT": h((0..<9).map { $0 % 2 == 0 ? 0xFCDD09 : 0xDA121A }, r)
        case "ES-PV":
            fill(0xD52B1E, r)
            saltire(0x009B48, r.height * 0.15, r)
            centeredCross(0xFFFFFF, r.height * 0.12, r)
        case "KURDISTAN":
            h([0xED2024, 0xFFFFFF, 0x278E43], r)
            burst(r.mid, r.height * 0.24, r.height * 0.14, points: 21, 0xFEBD11)
        case "SAPMI":
            v([0xD52B1E, 0x007A3D, 0xFFCE00, 0x0039A6], weights: [10, 3, 3, 11], r)
            sapmiRing(point(13.0 / 27, 0.5, r), r.height * 0.3, width: r.height * 0.09)

        case "CA-QC":
            fill(0x003DA5, r)
            centeredCross(0xFFFFFF, r.height * 0.2, r)
            for (x, y) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] as [(CGFloat, CGFloat)] {
                fleurDeLis(point(x, y, r), r.height * 0.34, 0xFFFFFF)
            }

        // Old monarchies
        case "HIST-AUSTRIAN-EMPIRE": h([0x000000, 0xFFD200], r)
        case "HIST-HRE": fill(0xFFD200, r); eagle(r.mid, r.height * 0.8, 0x000000, doubleHeaded: true)
        case "HIST-BAVARIA": lozenges(r)
        case "HIST-FRANCE-KINGDOM":
            fill(0x0D3B8C, r)
            for (x, y) in [(0.33, 0.3), (0.67, 0.3), (0.5, 0.7)] as [(CGFloat, CGFloat)] {
                fleurDeLis(point(x, y, r), r.height * 0.36, 0xF7C600)
            }
        case "HIST-GREECE-KINGDOM":
            _ = draw("GR", in: r)
            crown(point(0.185, 0.278, r), r.height * 0.2, 0xF7C600)
        case "HIST-HANOVER": h([0xFFD200, 0xFFFFFF], r)
        case "HIST-HUNGARY-KINGDOM":
            h([0xCE2939, 0xFFFFFF, 0x477050], r)
            shield(point(0.5, 0.55, r), r.height * 0.52, fill: 0xCE2939, edge: 0xFFFFFF)
            crown(point(0.5, 0.18, r), r.height * 0.24, 0xF7C600)
        case "HIST-POLAND-KINGDOM": fill(0xDC143C, r); eagle(r.mid, r.height * 0.8, 0xFFFFFF, doubleHeaded: false)
        case "HIST-PORTUGAL-KINGDOM":
            v([0x0D47A1, 0xFFFFFF], r)
            badge(point(0.5, 0.58, r), r.height * 0.5, top: 0xFFFFFF, bottom: 0xFFFFFF, edge: 0xD7141A, mark: 0x0D47A1)
            crown(point(0.5, 0.2, r), r.height * 0.24, 0xF7C600)
        case "HIST-PRUSSIA":
            h([0x000000, 0xFFFFFF, 0x000000], weights: [1, 6, 1], r)
            eagle(r.mid, r.height * 0.66, 0x000000, doubleHeaded: false)
        case "HIST-ROMANIA-KINGDOM":
            v([0x002B7F, 0xFCD116, 0xCE1126], r)
            badge(point(0.5, 0.55, r), r.height * 0.48, top: 0x002B7F, bottom: 0xCE1126, edge: 0xF7C600, mark: 0xF7C600)
        case "HIST-SARDINIA": fill(0xCE2B37, r); centeredCross(0xFFFFFF, r.height * 0.2, r)
        case "HIST-SAXONY": h([0xFFFFFF, 0x009A49], r)
        case "HIST-SERBIA-KINGDOM": h([0xC6363C, 0x0C4076, 0xFFFFFF], r)
        case "HIST-WURTTEMBERG": h([0x000000, 0xDD0000], r)
        case "HIST-YUGOSLAVIA-KINGDOM": h([0x003893, 0xFFFFFF, 0xDE0000], r)

        // Historical
        case "HIST-AUSTRIA-HUNGARY":
            h([0xED2939, 0xFFFFFF, 0xED2939], NSRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height))
            h([0xCE2939, 0xFFFFFF, 0x477050], NSRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height))
        case "HIST-BOHEMIA": h([0xFFFFFF, 0xD7141A], r)
        case "HIST-GDR":
            h([0x000000, 0xDD0000, 0xFFCE00], r)
            disc(r.mid, r.height * 0.2, 0xDD0000)
            ring(r.mid, r.height * 0.2, 0xE8B92E, width: r.height * 0.07)
            fill(0x000000, NSRect(x: r.midX - r.height * 0.02, y: r.midY - r.height * 0.1, width: r.height * 0.04, height: r.height * 0.2))
            fill(0x000000, NSRect(x: r.midX - r.height * 0.08, y: r.midY - r.height * 0.1, width: r.height * 0.16, height: r.height * 0.05))
        case "HIST-GERMAN-EMPIRE": h([0x000000, 0xFFFFFF, 0xDD0000], r)
        case "HIST-ITALY-KINGDOM":
            v([0x009246, 0xFFFFFF, 0xCE2B37], r)
            savoyShield(r.mid, r.height * 0.5)
        case "HIST-PERSIA":
            h([0x239F40, 0xFFFFFF, 0xDA0000], r)
            lionAndSun(r.mid, r.height * 0.42)
        case "HIST-RUSSIAN-EMPIRE": h([0x000000, 0xFDD017, 0xFFFFFF], r)
        case "HIST-USSR":
            fill(0xCC0000, r)
            star(point(0.17, 0.14, r), r.height * 0.07, 0xFFD700)
            hammerAndSickle(point(0.17, 0.36, r), r.height * 0.24)
        case "HIST-YUGOSLAVIA":
            h([0x003893, 0xFFFFFF, 0xDE0000], r)
            star(r.mid, r.height * 0.34, 0xFCD116)
            star(r.mid, r.height * 0.28, 0xDE0000)
        default:
            return false
        }
        return true
    }

    // MARK: - Drawing helpers

    /// A point given as fractions of the flag's width and height.
    private static func point(_ x: CGFloat, _ y: CGFloat, _ r: NSRect) -> CGPoint {
        CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ r: NSRect) -> NSRect {
        NSRect(x: r.minX + r.width * x, y: r.minY + r.height * y, width: r.width * width, height: r.height * height)
    }

    /// A filled polygon with corners given as fractions of the flag.
    private static func shape(_ points: [(CGFloat, CGFloat)], _ hex: UInt32, _ r: NSRect) {
        let path = NSBezierPath()
        for (i, (x, y)) in points.enumerated() {
            i == 0 ? path.move(to: point(x, y, r)) : path.line(to: point(x, y, r))
        }
        path.close()
        color(hex).setFill()
        path.fill()
    }

    /// A disc with a second disc cut out of it, leaving whatever is underneath visible.
    private static func crescent(_ center: CGPoint, _ radius: CGFloat, cut: CGPoint, _ cutRadius: CGFloat, _ hex: UInt32) {
        NSGraphicsContext.saveGraphicsState()
        let outside = NSBezierPath(rect: NSRect(x: center.x - radius * 2, y: center.y - radius * 2,
                                                width: radius * 4, height: radius * 4))
        outside.appendOval(in: NSRect(x: cut.x - cutRadius, y: cut.y - cutRadius, width: cutRadius * 2, height: cutRadius * 2))
        outside.windingRule = .evenOdd
        outside.addClip()
        disc(center, radius, hex)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A sun or star with `points` rays.
    private static func burst(_ center: CGPoint, _ outer: CGFloat, _ inner: CGFloat, points: Int, _ hex: UInt32) {
        let path = NSBezierPath()
        for i in 0..<(points * 2) {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let length = i % 2 == 0 ? outer : inner
            let p = CGPoint(x: center.x + cos(a) * length, y: center.y + sin(a) * length)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        color(hex).setFill()
        path.fill()
    }

    /// An outlined five-pointed star drawn with crossing lines.
    private static func pentagram(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32, width: CGFloat) {
        let path = NSBezierPath()
        for i in 0..<5 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * 4 * .pi / 5
            let p = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        path.lineWidth = width
        color(hex).setStroke()
        path.stroke()
    }

    private static func text(_ string: String, at center: CGPoint, size: CGFloat, _ hex: UInt32) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: size),
                                                         .foregroundColor: color(hex)]
        let bounds = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2),
                                  withAttributes: attributes)
    }

    /// Korea's red-over-blue swirl, tilted along the flag's diagonal.
    private static func taegeuk(_ center: CGPoint, _ radius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: 33.7)
        transform.concat()
        disc(.zero, radius, 0x0047A0)
        let top = NSBezierPath()
        top.appendArc(withCenter: .zero, radius: radius, startAngle: 180, endAngle: 360)
        top.close()
        color(0xCD2E3A).setFill()
        top.fill()
        disc(CGPoint(x: -radius / 2, y: 0), radius / 2, 0xCD2E3A)
        disc(CGPoint(x: radius / 2, y: 0), radius / 2, 0x0047A0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func trigram(_ center: CGPoint, toward middle: CGPoint, _ broken: [Bool], _ height: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: atan2(middle.y - center.y, middle.x - center.x))
        transform.concat()
        let length = height * 0.22, thickness = height * 0.045, gap = height * 0.025
        for (i, isBroken) in broken.enumerated() {
            let x = CGFloat(i - 1) * (thickness + gap) - thickness / 2
            fill(0x000000, NSRect(x: x, y: -length / 2, width: thickness, height: length))
            if isBroken { fill(0xFFFFFF, NSRect(x: x, y: -gap / 2, width: thickness, height: gap)) }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The two stacked pennons of Nepal's flag, centered in the 3:2 space.
    private static func nepalOutline(in r: NSRect) -> NSBezierPath {
        let width = r.height * 0.9
        let area = NSRect(x: r.midX - width / 2, y: r.minY, width: width, height: r.height)
        let path = NSBezierPath()
        path.move(to: point(0, 0, area))
        path.line(to: point(1, 0.5, area))
        path.line(to: point(0.4, 0.5, area))
        path.line(to: point(1, 1, area))
        path.line(to: point(0, 1, area))
        path.close()
        return path
    }

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

    // MARK: - Helpers for regional and historical flags

    /// A cross through the middle, like St George's, optionally stopping `inset` short of the edges.
    private static func centeredCross(_ hex: UInt32, _ thickness: CGFloat, _ r: NSRect, inset: CGFloat = 0) {
        fill(hex, NSRect(x: r.midX - thickness / 2, y: r.minY + inset, width: thickness, height: r.height - 2 * inset))
        fill(hex, NSRect(x: r.minX + inset, y: r.midY - thickness / 2, width: r.width - 2 * inset, height: thickness))
    }

    /// A diagonal cross from corner to corner, like St Andrew's.
    private static func saltire(_ hex: UInt32, _ width: CGFloat, _ r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: r.minX, y: r.minY)); path.line(to: CGPoint(x: r.maxX, y: r.maxY))
        path.move(to: CGPoint(x: r.maxX, y: r.minY)); path.line(to: CGPoint(x: r.minX, y: r.maxY))
        path.lineWidth = width
        color(hex).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A British ensign: plain field with the Union Jack in the canton.
    private static func ensign(_ field: UInt32, _ r: NSRect) {
        fill(field, r)
        unionJack(NSRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height / 2))
    }

    private static func shieldPath(_ center: CGPoint, _ height: CGFloat) -> NSBezierPath {
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
        return path
    }

    /// A territory's badge reduced to what reads at menu-bar size: a shield in its two main
    /// colours, with a dot for the main charge.
    private static func badge(_ center: CGPoint, _ height: CGFloat, top: UInt32, bottom: UInt32, edge: UInt32, mark: UInt32?) {
        let path = shieldPath(center, height)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        fill(top, NSRect(x: center.x - height, y: center.y - height, width: height * 2, height: height * 2))
        fill(bottom, NSRect(x: center.x - height, y: center.y + height * 0.05, width: height * 2, height: height))
        if let mark { disc(CGPoint(x: center.x, y: center.y - height * 0.15), height * 0.16, mark) }
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = max(0.3, height * 0.07)
        color(edge).setStroke()
        path.stroke()
    }

    /// The Isle of Man's three armoured legs, white with gold spurs.
    private static func triskelion(_ center: CGPoint, _ radius: CGFloat) {
        for i in 0..<3 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 3
            let knee = CGPoint(x: center.x + cos(a) * radius * 0.6, y: center.y + sin(a) * radius * 0.6)
            let bend = a + .pi / 2.4
            let foot = CGPoint(x: knee.x + cos(bend) * radius * 0.55, y: knee.y + sin(bend) * radius * 0.55)
            let leg = NSBezierPath()
            leg.move(to: center); leg.line(to: knee); leg.line(to: foot)
            leg.lineWidth = radius * 0.26
            leg.lineCapStyle = .butt
            leg.lineJoinStyle = .round
            color(0xFFFFFF).setStroke()
            leg.stroke()
            disc(foot, radius * 0.13, 0xF9DD16)
        }
        disc(center, radius * 0.16, 0xFFFFFF)
    }

    /// Gibraltar's red castle with the gold key hanging below.
    private static func castle(_ r: NSRect) {
        fill(0xDA000C, rect(0.38, 0.3, 0.24, 0.34, r))
        for x in [0.36, 0.46, 0.56] as [CGFloat] {
            fill(0xDA000C, rect(x, 0.16, 0.08, 0.16, r))
        }
        fill(0x000000, rect(0.475, 0.46, 0.05, 0.18, r))
        disc(point(0.5, 0.76, r), r.height * 0.07, 0xF8D80F)
        fill(0xF8D80F, rect(0.49, 0.76, 0.02, 0.18, r))
    }

    /// Y Ddraig Goch, passant toward the hoist.
    private static func dragon(_ r: NSRect) {
        let box = NSRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.14, width: r.width * 0.68, height: r.height * 0.74)
        let points: [(CGFloat, CGFloat)] = [
            (0.0, 0.3), (0.1, 0.12), (0.2, 0.2), (0.26, 0.36), (0.34, 0.0), (0.44, 0.16), (0.56, 0.0),
            (0.6, 0.3), (0.74, 0.32), (0.88, 0.2), (1.0, 0.02), (0.98, 0.3), (0.84, 0.48), (0.8, 0.58),
            (0.84, 1.0), (0.72, 1.0), (0.68, 0.64), (0.44, 0.64), (0.4, 1.0), (0.28, 1.0), (0.3, 0.6),
            (0.2, 0.46), (0.1, 0.38),
        ]
        shape(points, 0xD30731, box)
    }

    /// Two overlapping triangles (the Ulster Banner's star).
    private static func hexagram(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32) {
        color(hex).setFill()
        polygon(center, radius, sides: 3, rotation: -.pi / 2).fill()
        polygon(center, radius, sides: 3, rotation: .pi / 2).fill()
    }

    private static func crown(_ center: CGPoint, _ width: CGFloat, _ hex: UInt32) {
        let h = width * 0.7
        let box = NSRect(x: center.x - width / 2, y: center.y - h / 2, width: width, height: h)
        shape([(0, 1), (0, 0.2), (0.25, 0.55), (0.5, 0), (0.75, 0.55), (1, 0.2), (1, 1)], hex, box)
    }

    /// One ermine spot: a small black diamond with a tail.
    private static func ermine(_ center: CGPoint, _ size: CGFloat) {
        diamond(center, size * 0.5, 0x000000)
        fill(0x000000, NSRect(x: center.x - size * 0.12, y: center.y, width: size * 0.24, height: size))
    }

    /// The Sámi ring: blue on the red side, red on the blue side.
    private static func sapmiRing(_ center: CGPoint, _ radius: CGFloat, width: CGFloat) {
        for (left, hex) in [(true, UInt32(0x0039A6)), (false, UInt32(0xD52B1E))] {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: left ? center.x - radius * 2 : center.x, y: center.y - radius * 2,
                                      width: radius * 2, height: radius * 4)).addClip()
            ring(center, radius, hex, width: width)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// The House of Savoy's arms: a white cross on red, edged in blue.
    private static func savoyShield(_ center: CGPoint, _ height: CGFloat) {
        let path = shieldPath(center, height)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        fill(0xCE2B37, NSRect(x: center.x - height, y: center.y - height, width: height * 2, height: height * 2))
        let arm = height * 0.2
        fill(0xFFFFFF, NSRect(x: center.x - arm / 2, y: center.y - height, width: arm, height: height * 2))
        fill(0xFFFFFF, NSRect(x: center.x - height, y: center.y - height * 0.12 - arm / 2, width: height * 2, height: arm))
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = max(0.4, height * 0.1)
        color(0x0055A4).setStroke()
        path.stroke()
    }

    /// The Lion and Sun: a gold lion facing the hoist, sword raised, the sun rising behind it.
    private static func lionAndSun(_ center: CGPoint, _ size: CGFloat) {
        burst(CGPoint(x: center.x + size * 0.08, y: center.y - size * 0.18), size * 0.42, size * 0.28, points: 12, 0xF7B500)
        disc(CGPoint(x: center.x + size * 0.08, y: center.y - size * 0.18), size * 0.26, 0xF7C600)
        let box = NSRect(x: center.x - size * 0.6, y: center.y - size * 0.15, width: size * 1.2, height: size * 0.62)
        let sword = NSBezierPath()
        sword.move(to: point(0.18, 0.35, box)); sword.line(to: point(0.0, -0.55, box))
        sword.lineWidth = max(0.4, size * 0.07)
        color(0x6E6E6E).setStroke()
        sword.stroke()
        shape([(0.04, 0.2), (0.2, 0.0), (0.32, 0.3), (0.86, 0.34), (1.0, 0.0), (0.96, 0.44), (0.9, 1.0),
               (0.76, 1.0), (0.72, 0.66), (0.36, 0.66), (0.3, 1.0), (0.17, 1.0), (0.15, 0.5), (0.02, 0.42)],
              0xB8860B, box)
    }

    private static func hammerAndSickle(_ center: CGPoint, _ size: CGFloat) {
        let gold = color(0xFFD700)
        gold.setStroke()
        let sickle = NSBezierPath()
        sickle.appendArc(withCenter: center, radius: size * 0.36, startAngle: 200, endAngle: 80, clockwise: true)
        sickle.lineWidth = size * 0.13
        sickle.stroke()
        let hammer = NSBezierPath()
        hammer.move(to: CGPoint(x: center.x - size * 0.4, y: center.y + size * 0.42))
        hammer.line(to: CGPoint(x: center.x + size * 0.2, y: center.y - size * 0.2))
        hammer.lineWidth = size * 0.11
        hammer.stroke()
        let head = NSBezierPath()
        head.move(to: CGPoint(x: center.x + size * 0.02, y: center.y - size * 0.38))
        head.line(to: CGPoint(x: center.x + size * 0.38, y: center.y - size * 0.02))
        head.lineWidth = size * 0.16
        head.stroke()
    }

    /// A simplified fleur-de-lis: tall middle petal, two side petals, a band across.
    private static func fleurDeLis(_ center: CGPoint, _ size: CGFloat, _ hex: UInt32) {
        let box = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        shape([(0.5, 0.0), (0.64, 0.3), (0.5, 0.62), (0.36, 0.3)], hex, box)
        shape([(0.1, 0.25), (0.3, 0.32), (0.42, 0.6), (0.24, 0.62)], hex, box)
        shape([(0.9, 0.25), (0.7, 0.32), (0.58, 0.6), (0.76, 0.62)], hex, box)
        fill(hex, NSRect(x: box.minX + size * 0.22, y: box.minY + size * 0.58, width: size * 0.56, height: size * 0.12))
        shape([(0.42, 0.7), (0.58, 0.7), (0.5, 1.0)], hex, box)
    }

    /// A heraldic eagle with spread wings, single- or double-headed.
    private static func eagle(_ center: CGPoint, _ size: CGFloat, _ hex: UInt32, doubleHeaded: Bool) {
        let box = NSRect(x: center.x - size * 0.6, y: center.y - size / 2, width: size * 1.2, height: size)
        let heads: [(CGFloat, CGFloat)] = doubleHeaded
            ? [(0.3, 0.06), (0.4, 0.0), (0.46, 0.22), (0.54, 0.22), (0.6, 0.0), (0.7, 0.06)]
            : [(0.42, 0.12), (0.5, 0.0), (0.58, 0.12)]
        let points: [(CGFloat, CGFloat)] = [(0.0, 0.15), (0.38, 0.3)] + heads + [
            (0.62, 0.3), (1.0, 0.15), (0.9, 0.55), (0.8, 0.42), (0.7, 0.62), (0.62, 0.56), (0.66, 0.95),
            (0.5, 0.84), (0.34, 0.95), (0.38, 0.56), (0.3, 0.62), (0.2, 0.42), (0.1, 0.55),
        ]
        shape(points, hex, box)
    }

    /// Bavaria's white and blue lozenges: a checkerboard of slanted rhombi.
    private static func lozenges(_ r: NSRect) {
        fill(0xFFFFFF, r)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        color(0x0098D4).setFill()
        let side = r.height / 2.6
        // Flipped coordinates (y down): both edge directions fall to the right, one shallow
        // and one steep, which makes the long, leaning rhombi of the real flag.
        let shallow = CGFloat(22) * .pi / 180, steep = CGFloat(72) * .pi / 180
        let a = CGPoint(x: side * cos(shallow), y: side * sin(shallow))
        let b = CGPoint(x: side * cos(steep), y: side * sin(steep))
        let count = Int(ceil((r.width + r.height) / side)) + 2
        for i in -count...count {
            for j in -count...count where (i + j) % 2 == 0 {
                let o = CGPoint(x: r.minX + CGFloat(i) * a.x + CGFloat(j) * b.x,
                                y: r.minY + CGFloat(i) * a.y + CGFloat(j) * b.y)
                let path = NSBezierPath()
                path.move(to: o)
                path.line(to: CGPoint(x: o.x + a.x, y: o.y + a.y))
                path.line(to: CGPoint(x: o.x + a.x + b.x, y: o.y + a.y + b.y))
                path.line(to: CGPoint(x: o.x + b.x, y: o.y + b.y))
                path.close()
                path.fill()
            }
        }
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
