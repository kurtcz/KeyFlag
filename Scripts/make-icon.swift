#!/usr/bin/env swift
// Draws the KeyFlag app icon with Core Graphics and writes Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift            writes Resources/AppIcon.icns and MenuIcon*.png
//   swift Scripts/make-icon.swift out.png    also writes a 1024 px preview PNG
//
// The artwork: a softly spotlit white keycap filling a dark charcoal tile,
// with two overlapping flags on the key for switching between keyboard layouts.
// It is vector code, so every size is rendered from scratch rather than downscaled; up to 64 px
// it drops the keycap and shows the flags large on the tile.
// All coordinates are on a 1024 x 1024 canvas, origin at the bottom left.

import AppKit
import CoreGraphics
import ImageIO

// MARK: - Palette

let red: UInt32 = 0xD52B1E
let blue: UInt32 = 0x0B3D91
let gold: UInt32 = 0xFFC726
let tileTop: UInt32 = 0x343A45
let tileBottom: UInt32 = 0x16191E

// MARK: - Helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { $0.0 })!
}

/// A superellipse ("squircle"), close to the continuous-corner shape of macOS icons.
func squircle(_ rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Fills `path` with a vertical gradient from `bottom` to `top` colour stops.
func fillVertical(_ ctx: CGContext, _ path: CGPath, _ stops: [(CGFloat, CGColor)]) {
    let box = path.boundingBox
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: box.midX, y: box.minY),
                           end: CGPoint(x: box.midX, y: box.maxY), options: [])
    ctx.restoreGState()
}

// MARK: - Drawing

/// The keycap's top face; the legend and flags are laid out on it.
let faceRect = CGRect(x: 172, y: 222, width: 660, height: 638)

func drawIcon(in ctx: CGContext) {
    ctx.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawTile(in: ctx)
    drawKeycap(in: ctx)
    drawCommandLegend(in: ctx, face: faceRect)
    drawFlagPair(in: ctx, center: CGPoint(x: faceRect.midX + 10, y: faceRect.midY - 6), scale: 1.2)
}

/// Whether flags cast a drop shadow; off for the menu icon, where it shows as a grey smudge.
nonisolated(unsafe) var flagShadows = true

/// The icon for 16 and 32 pt (Finder lists, System Settings, Spotlight), where the keycap and its
/// legend would be mush: the same dark tile with just the two flags, as large as it allows.
func drawSmallIcon(in ctx: CGContext) {
    ctx.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawTile(in: ctx)
    flagShadows = false
    defer { flagShadows = true }
    // The pair is 428 x 344 at scale 1, centred 14 right of and 18 below `center`.
    let s: CGFloat = 1.6
    drawFlagPair(in: ctx, center: CGPoint(x: 512 - 14 * s, y: 512 + 18 * s), scale: s)
}

/// The two flags at `scale`: back flag up and to the right, front flag down and to the left.
/// At scale 1 they span x -200...228 and y -190...154 around `center`.
func drawFlagPair(in ctx: CGContext, center c: CGPoint, scale s: CGFloat) {
    drawFlag(in: ctx, CGRect(x: c.x - 62 * s, y: c.y - 40 * s, width: 290 * s, height: 194 * s), front: false)
    drawFlag(in: ctx, CGRect(x: c.x - 200 * s, y: c.y - 190 * s, width: 290 * s, height: 194 * s), front: true)
}

/// A dark charcoal tile, faintly lit from the top left, with a thin bright rim along its upper edge.
func drawTile(in ctx: CGContext) {
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = squircle(tileRect)

    // Drop shadow, as macOS icons carry.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x000000, 0.4))
    ctx.addPath(tile)
    ctx.setFillColor(rgb(tileBottom))
    ctx.fillPath()
    ctx.restoreGState()

    fillVertical(ctx, tile, [(0, rgb(tileBottom)), (1, rgb(tileTop))])
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    // The spotlight's spill onto the tile.
    ctx.drawRadialGradient(gradient([(0, rgb(0xFFFFFF, 0.10)), (1, rgb(0xFFFFFF, 0))]),
                           startCenter: CGPoint(x: 260, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 260, y: 860), endRadius: 760, options: [])
    // Rim: bright along the top, fading out down the sides.
    ctx.addPath(tile)
    ctx.setLineWidth(6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0)), (0.6, rgb(0xFFFFFF, 0.04)), (1, rgb(0xFFFFFF, 0.28))]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()
}

/// A sculpted white keycap seen slightly from above and the left, so its bottom and right walls show,
/// under a soft spotlight from the top left.
func drawKeycap(in ctx: CGContext) {
    let skirtRect = CGRect(x: 146, y: 132, width: 732, height: 748)
    let skirt = roundedRect(skirtRect, 118)

    // Contact shadow on the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 6, height: -20), blur: 40, color: rgb(0x000000, 0.75))
    ctx.addPath(skirt)
    ctx.setFillColor(rgb(0xB8BDC4))
    ctx.fillPath()
    ctx.restoreGState()

    // Walls: light at the top, shading down to the bottom wall, darker on the right away from the light.
    fillVertical(ctx, skirt, [(0, rgb(0x8F959E)), (0.18, rgb(0xB9BEC5)), (0.6, rgb(0xDADDE1)), (1, rgb(0xEEF0F2))])
    ctx.saveGState()
    ctx.addPath(skirt)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.25)), (0.12, rgb(0xFFFFFF, 0)),
                                     (0.86, rgb(0x000000, 0)), (1, rgb(0x000000, 0.22))]),
                           start: CGPoint(x: skirtRect.minX, y: 0), end: CGPoint(x: skirtRect.maxX, y: 0), options: [])
    // A thin reflected-light line along the very bottom edge.
    ctx.addPath(skirt)
    ctx.setLineWidth(5)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.35)), (0.1, rgb(0xFFFFFF, 0)), (0.9, rgb(0xFFFFFF, 0)),
                                     (1, rgb(0xFFFFFF, 0.6))]),
                           start: CGPoint(x: 512, y: skirtRect.minY), end: CGPoint(x: 512, y: skirtRect.maxY), options: [])
    ctx.restoreGState()

    // Top face, with a soft crease where it rolls over into the walls.
    let face = roundedRect(faceRect, 96)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 3, height: -8), blur: 22, color: rgb(0x3A414C, 0.35))
    ctx.addPath(face)
    ctx.setFillColor(rgb(0xEEF0F2))
    ctx.fillPath()
    ctx.restoreGState()
    fillVertical(ctx, face, [(0, rgb(0xE1E4E8)), (0.55, rgb(0xF0F2F4)), (1, rgb(0xF9FAFB))])
    ctx.saveGState()
    ctx.addPath(face)
    ctx.clip()
    // The shallow dish: slightly darker towards the middle-bottom.
    ctx.drawRadialGradient(gradient([(0, rgb(0x000000, 0)), (0.7, rgb(0x000000, 0)), (1, rgb(0x000000, 0.05))]),
                           startCenter: CGPoint(x: faceRect.midX, y: faceRect.midY + 40), startRadius: 0,
                           endCenter: CGPoint(x: faceRect.midX, y: faceRect.midY + 40), endRadius: 470, options: [])
    // Spotlight from the top left.
    ctx.drawRadialGradient(gradient([(0, rgb(0xFFFFFF, 0.95)), (0.45, rgb(0xFFFFFF, 0.35)), (1, rgb(0xFFFFFF, 0))]),
                           startCenter: CGPoint(x: 330, y: 760), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 760), endRadius: 560, options: [])
    // Rounded edge of the face: catches the light at the top left, falls into shade at the bottom right.
    ctx.addPath(face)
    ctx.setLineWidth(16)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x000000, 0.10)), (0.5, rgb(0x000000, 0)), (1, rgb(0xFFFFFF, 0.9))]),
                           start: CGPoint(x: faceRect.maxX, y: faceRect.minY),
                           end: CGPoint(x: faceRect.minX, y: faceRect.maxY), options: [])
    ctx.restoreGState()
}

/// The ⌘ legend in the top-left corner of the key, as on a Mac keyboard.
func drawCommandLegend(in ctx: CGContext, face: CGRect) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 118, weight: .light),
        .foregroundColor: NSColor(srgbRed: 0x6B / 255, green: 0x71 / 255, blue: 0x7C / 255, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2318}", attributes: attrs))
    let bounds = CTLineGetImageBounds(line, ctx)
    ctx.textPosition = CGPoint(x: face.minX + 64 - bounds.minX, y: face.maxY - 62 - bounds.maxY)
    CTLineDraw(line, ctx)
}

/// The griffin artwork from Scripts/icon-griffin.png: black line art on a white background, facing left.
/// Split into two masks cropped to the drawing: `ink` (the black lines) and `body` (the whole silhouette,
/// i.e. everything the white background does not reach), so the griffin keeps its white body on any field.
let griffinArt: (ink: CGImage, body: CGImage) = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("icon-griffin.png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(url.path)") }
    let w = image.width, h = image.height
    var gray = [UInt8](repeating: 255, count: w * h)
    gray.withUnsafeMutableBytes { buf in
        let g = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        g.setFillColor(gray: 1, alpha: 1); g.fill(CGRect(x: 0, y: 0, width: w, height: h))
        g.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    // Flood the light background in from the edges; whatever it cannot reach is the griffin.
    var body = [UInt8](repeating: 255, count: w * h)
    var stack: [Int] = []
    for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
    for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
    while let i = stack.popLast() {
        guard body[i] != 0, gray[i] > 128 else { continue }
        body[i] = 0
        let x = i % w
        if x > 0 { stack.append(i - 1) }
        if x < w - 1 { stack.append(i + 1) }
        if i >= w { stack.append(i - w) }
        if i < (h - 1) * w { stack.append(i + w) }
    }
    // Invert so ink becomes coverage, and find the drawing's bounds.
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w {
        let v = 255 - gray[y * w + x]; gray[y * w + x] = v
        if v > 64 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    } }
    let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    func mask(_ bytes: [UInt8]) -> CGImage {
        CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)!.cropping(to: crop)!
    }
    return (mask(gray), mask(body))
}()

/// Draws the griffin, white with near-black lines, as large as fits in `box` and centred in it.
func drawGriffin(_ ctx: CGContext, in box: CGRect) {
    let aspect = CGFloat(griffinArt.ink.width) / CGFloat(griffinArt.ink.height)
    let w = min(box.width, box.height * aspect), h = w / aspect
    let r = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    for (mask, color) in [(griffinArt.body, rgb(0xFFFFFF)), (griffinArt.ink, rgb(0x121214))] {
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.clip(to: r, mask: mask)
        ctx.setFillColor(color)
        ctx.fill(r)
        ctx.restoreGState()
    }
}

/// The back flag's design, measured from Scripts/icon-backflag.png (blue, gold, blue with a black
/// fleur-de-lis): where the gold band starts and ends as fractions of the flag's width, the
/// fleur-de-lis as a mask, and the box it sits in as fractions of the flag (y measured from the top).
let backFlagArt: (goldFrom: CGFloat, goldTo: CGFloat, lily: CGImage, lilyBox: CGRect) = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("icon-backflag.png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(url.path)") }
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    px.withUnsafeMutableBytes { buf in
        let g = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        g.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    func rgbAt(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * w + x) * 4; return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
    }
    // The flag is the strongly coloured area; the paper around it is near-grey.
    var fx0 = w, fy0 = h, fx1 = 0, fy1 = 0
    for y in 0..<h { for x in 0..<w {
        let (r, g, b) = rgbAt(x, y)
        if max(r, g, b) - min(r, g, b) > 80 { fx0 = min(fx0, x); fx1 = max(fx1, x); fy0 = min(fy0, y); fy1 = max(fy1, y) }
    } }
    let fw = CGFloat(fx1 - fx0 + 1), fh = CGFloat(fy1 - fy0 + 1)
    // The gold band, along a row near the top where nothing else is drawn.
    let row = fy0 + Int(fh * 0.05)
    var gx0 = fx1, gx1 = fx0
    for x in fx0...fx1 { let (r, _, b) = rgbAt(x, row); if r > b + 60 { gx0 = min(gx0, x); gx1 = max(gx1, x) } }
    // The fleur-de-lis: dark pixels inside the gold band, as coverage.
    var ink = [UInt8](repeating: 0, count: w * h)
    var lx0 = w, ly0 = h, lx1 = 0, ly1 = 0
    for y in fy0...fy1 { for x in gx0...gx1 {
        let (r, g, b) = rgbAt(x, y)
        let v = 255 - max(r, g, b)
        guard v > 40 else { continue }
        ink[y * w + x] = UInt8(min(255, v * 255 / 215))
        if v > 100 { lx0 = min(lx0, x); lx1 = max(lx1, x); ly0 = min(ly0, y); ly1 = max(ly1, y) }
    } }
    let crop = CGRect(x: lx0, y: ly0, width: lx1 - lx0 + 1, height: ly1 - ly0 + 1)
    let lily = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: CGDataProvider(data: Data(ink) as CFData)!, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!.cropping(to: crop)!
    return (CGFloat(gx0 - fx0) / fw, CGFloat(gx1 + 1 - fx0) / fw, lily,
            CGRect(x: CGFloat(lx0 - fx0) / fw, y: CGFloat(ly0 - fy0) / fh, width: crop.width / fw, height: crop.height / fh))
}()

/// Heater shield: flat top, straight sides, curving to a point at the bottom.
func shieldPath(_ r: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: r.minX, y: r.maxY))
    path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    path.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.45))
    path.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.18),
                  control2: CGPoint(x: r.midX + r.width * 0.2, y: r.minY + r.height * 0.06))
    path.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.45), control1: CGPoint(x: r.midX - r.width * 0.2, y: r.minY + r.height * 0.06),
                  control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.18))
    path.closeSubpath()
    return path
}

/// A rounded 3:2 flag: a white cross with blue and red corners and a griffin shield in front,
/// a Barbados-style triband behind.
func drawFlag(in ctx: CGContext, _ rect: CGRect, front: Bool) {
    let shape = roundedRect(rect, 22)

    ctx.saveGState()
    if flagShadows {
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: front ? 22 : 16, color: rgb(0x1A2030, 0.40))
    }
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fill(rect)
    if front {
        // Quebec's white cross over Panama's colours: blue and red corners, alternating.
        let bar = rect.height * 0.22
        let qw = (rect.width - bar) / 2, qh = (rect.height - bar) / 2
        ctx.setFillColor(rgb(blue))
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - qh, width: qw, height: qh))     // top left
        ctx.fill(CGRect(x: rect.maxX - qw, y: rect.minY, width: qw, height: qh))     // bottom right
        ctx.setFillColor(rgb(red))
        ctx.fill(CGRect(x: rect.maxX - qw, y: rect.maxY - qh, width: qw, height: qh))  // top right
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: qw, height: qh))            // bottom left
        // Coat of arms where the arms of the cross meet: a black-and-white griffin on a gold shield.
        let shieldRect = CGRect(x: rect.midX - rect.height * 0.23, y: rect.midY - rect.height * 0.275,
                                width: rect.height * 0.46, height: rect.height * 0.55)
        let shield = shieldPath(shieldRect)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: rgb(0x000000, 0.3))
        ctx.addPath(shield)
        ctx.setFillColor(rgb(gold))
        ctx.fillPath()
        ctx.restoreGState()
        // A little relief on the gold: lighter at the top, deeper towards the point.
        ctx.saveGState()
        ctx.addPath(shield); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, rgb(0xB07A10, 0.45)), (0.6, rgb(0xB07A10, 0)), (1, rgb(0xFFFFFF, 0.3))]),
                               start: CGPoint(x: 0, y: shieldRect.minY), end: CGPoint(x: 0, y: shieldRect.maxY), options: [])
        ctx.restoreGState()
        drawGriffin(ctx, in: CGRect(x: shieldRect.minX + shieldRect.width * 0.07, y: shieldRect.minY + shieldRect.height * 0.24,
                                    width: shieldRect.width * 0.86, height: shieldRect.height * 0.68))
        ctx.addPath(shield)
        ctx.setStrokeColor(rgb(0x1A1A1F))
        ctx.setLineWidth(3)
        ctx.strokePath()
    } else {
        // Blue, gold, blue with a black fleur-de-lis, laid out as in Scripts/icon-backflag.png.
        let art = backFlagArt
        ctx.setFillColor(rgb(blue))
        ctx.fill(rect)
        ctx.setFillColor(rgb(gold))
        ctx.fill(CGRect(x: rect.minX + rect.width * art.goldFrom, y: rect.minY,
                        width: rect.width * (art.goldTo - art.goldFrom), height: rect.height))
        let lily = CGRect(x: rect.minX + rect.width * art.lilyBox.minX,
                          y: rect.maxY - rect.height * art.lilyBox.maxY,
                          width: rect.width * art.lilyBox.width, height: rect.height * art.lilyBox.height)
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.clip(to: lily, mask: art.lily)
        ctx.setFillColor(rgb(0x121214))
        ctx.fill(lily)
        ctx.restoreGState()
    }
    // Soft light from above, a gentle shade toward the bottom.
    ctx.drawLinearGradient(gradient([(0, rgb(0x000000, 0.10)), (0.45, rgb(0x000000, 0)),
                                     (0.75, rgb(0xFFFFFF, 0.06)), (1, rgb(0xFFFFFF, 0.20))]),
                           start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                           options: [])
    ctx.restoreGState()

    // Hairline so the white parts hold their shape against the white key.
    ctx.addPath(roundedRect(rect.insetBy(dx: 1, dy: 1), 21))
    ctx.setStrokeColor(rgb(0x1A2030, 0.18))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

// MARK: - Output

func render(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    if pixels <= 64 { drawSmallIcon(in: ctx) } else { drawIcon(in: ctx) }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

/// Just the two flags, `width` x `height` pixels, for the About item in the menu where the whole
/// icon is too small to read. The pair fills the width, centred, with no drop shadow.
func renderFlags(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    flagShadows = false
    defer { flagShadows = true }
    let k = CGFloat(width) / 440 // 428 wide plus a 6-unit margin each side
    ctx.scaleBy(x: k, y: k)
    drawFlagPair(in: ctx, center: CGPoint(x: 220 - 14, y: CGFloat(height) / k / 2 + 18), scale: 1)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(icns.path)")

if CommandLine.arguments.count > 1 {
    let preview = URL(fileURLWithPath: CommandLine.arguments[1])
    try render(pixels: 1024).write(to: preview)
    print("Wrote \(preview.path)")
}

for (suffix, factor) in [("", 1), ("@2x", 2), ("@3x", 3)] {
    let png = root.appendingPathComponent("Resources/MenuIcon\(suffix).png")
    try renderFlags(width: 20 * factor, height: 16 * factor).write(to: png)
    print("Wrote \(png.path)")
}
