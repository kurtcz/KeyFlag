import AppKit
import Testing
@testable import KeyFlagCore

struct CursorMetricsTests {
    let ibeam = CursorMetrics(size: NSSize(width: 9, height: 18), hotSpot: NSPoint(x: 4, y: 8))
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let indicator = NSSize(width: 19, height: 16)

    @Test func belowRightOfCursorByDefault() {
        let origin = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 500, y: 400), cursor: ibeam,
                                                   indicatorSize: indicator, screenFrame: screen)
        // 5 pt of cursor right of the hot spot + gap; top edge level with the hot spot.
        #expect(origin == NSPoint(x: 507, y: 400 - 16))
    }

    @Test func flipsAtScreenEdges() {
        let origin = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 995, y: 5), cursor: ibeam,
                                                   indicatorSize: indicator, screenFrame: screen)
        #expect(origin.x == CGFloat(995 - 4 - 2 - 19))
        #expect(origin.y == 5)
    }

    @Test func largerCursorMovesIndicatorFurther() {
        let big = CursorMetrics(size: NSSize(width: 36, height: 72), hotSpot: NSPoint(x: 16, y: 32))
        let small = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 500, y: 400), cursor: ibeam, indicatorSize: indicator, screenFrame: screen)
        let large = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 500, y: 400), cursor: big, indicatorSize: indicator, screenFrame: screen)
        #expect(large.x > small.x)
        #expect(large.y == small.y)
    }

    @Test func paddedCursorPlacesFromVisiblePart() {
        // The macOS 26 I-beam: 23×22 pt image, hot spot centred, drawn part 8×19 pt.
        let padded = CursorMetrics(size: NSSize(width: 23, height: 22), hotSpot: NSPoint(x: 12, y: 11),
                                   visibleRect: NSRect(x: 7.5, y: 1.5, width: 8, height: 19))
        let origin = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 500, y: 400), cursor: padded,
                                                   indicatorSize: indicator, screenFrame: screen)
        #expect(origin == NSPoint(x: 500 + 3.5 + 2, y: 400 - 16))
        let flipped = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 995, y: 5), cursor: padded,
                                                    indicatorSize: indicator, screenFrame: screen)
        #expect(flipped == NSPoint(x: 995 - 4.5 - 2 - 19, y: 5))
    }

    @Test func measuresOpaquePixelsIgnoringShadow() throws {
        // 20×20 px drawn at 10×10 pt: solid block at px x 4..7, y 2..11 from the top, and a
        // faint shadow around it that must not count.
        let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 0.2))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 4, y: 20 - 12, width: 4, height: 10)) // CG origin is bottom-left
        let image = try #require(context.makeImage())
        let rect = CursorMetrics.opaqueRect(of: image, pointSize: NSSize(width: 10, height: 10))
        #expect(rect == NSRect(x: 2, y: 1, width: 2, height: 5))
    }

    @Test func pixelAlignment() {
        #expect(CursorMetrics.pixelAligned(NSPoint(x: 10.3, y: 4.8), scale: 1) == NSPoint(x: 10, y: 5))
        #expect(CursorMetrics.pixelAligned(NSPoint(x: 10.3, y: 4.8), scale: 2) == NSPoint(x: 10.5, y: 5))
    }
}

@MainActor
struct CapsLockBadgeTests {
    @Test func badgeWidensImageAndKeepsTemplate() {
        let base = InputSourceIcon.textImage("CZ")
        let badged = InputSourceIcon.addingCapsLockBadge(base)
        #expect(badged.size.height == base.size.height)
        #expect(badged.size.width > base.size.width)
        #expect(badged.isTemplate)
    }

    @Test func framesAreCached() {
        let frames = [InputSourceIcon.textImage("CZ")]
        let a = InputSourceIcon.addingCapsLockBadge(frames)
        let b = InputSourceIcon.addingCapsLockBadge(frames)
        #expect(a[0] === b[0])
    }
}

struct UnsupportedWarningTests {
    @Test func warnsOncePerUnsupportedSource() {
        #expect(UnsupportedInputSourceWarning.needsWarning(id: "com.example.im", isSupported: false, alreadyShown: []))
        #expect(!UnsupportedInputSourceWarning.needsWarning(id: "com.example.im", isSupported: false, alreadyShown: ["com.example.im"]))
        #expect(!UnsupportedInputSourceWarning.needsWarning(id: "com.example.im", isSupported: true, alreadyShown: []))
        #expect(!UnsupportedInputSourceWarning.needsWarning(id: "", isSupported: false, alreadyShown: []))
    }
}

@MainActor
struct WavingRepsTests {
    @Test func wavingFramesCarryOneAndTwoX() throws {
        let frames = try #require(FlagArt.frames(countryCode: "CZ", style: .waving, height: 16))
        #expect(frames.count > 1)
        let widths = Set(frames[0].representations.map(\.pixelsWide))
        #expect(widths.count == 2)
    }
}

struct ResumeAfterTypingTests {
    @Test @MainActor func smallNudgeKeepsIndicatorHidden() {
        let anchor = NSPoint(x: 500, y: 400)
        #expect(!IndicatorController.isDeliberateMove(from: anchor, to: NSPoint(x: 503, y: 402)))
        #expect(!IndicatorController.isDeliberateMove(from: anchor, to: NSPoint(x: 494, y: 400.5)))
    }

    @Test @MainActor func deliberateMoveBringsItBack() {
        let anchor = NSPoint(x: 500, y: 400)
        #expect(IndicatorController.isDeliberateMove(from: anchor, to: NSPoint(x: 508, y: 400)))
        #expect(IndicatorController.isDeliberateMove(from: anchor, to: NSPoint(x: 494, y: 394)))
    }
}
