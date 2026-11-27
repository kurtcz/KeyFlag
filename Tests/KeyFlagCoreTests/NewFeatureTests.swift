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
        // 5 pt of cursor right of the hot spot + gap; 10 pt below + gap + own height.
        #expect(origin == NSPoint(x: 507, y: 400 - 10 - 2 - 16))
    }

    @Test func flipsAtScreenEdges() {
        let origin = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 995, y: 5), cursor: ibeam,
                                                   indicatorSize: indicator, screenFrame: screen)
        #expect(origin.x == CGFloat(995 - 4 - 2 - 19))
        #expect(origin.y == CGFloat(5 + 8 + 2))
    }

    @Test func largerCursorMovesIndicatorFurther() {
        let big = CursorMetrics(size: NSSize(width: 36, height: 72), hotSpot: NSPoint(x: 16, y: 32))
        let small = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 500, y: 400), cursor: ibeam, indicatorSize: indicator, screenFrame: screen)
        let large = CursorMetrics.indicatorOrigin(mouse: NSPoint(x: 500, y: 400), cursor: big, indicatorSize: indicator, screenFrame: screen)
        #expect(large.x > small.x)
        #expect(large.y < small.y)
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
