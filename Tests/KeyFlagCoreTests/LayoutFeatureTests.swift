import AppKit
import Testing
@testable import KeyFlagCore

struct PerAppLayoutTests {
    @Test func firstVisitRemembersCurrentLayout() {
        #expect(PerAppLayoutSwitcher.action(stored: nil, current: "com.apple.keylayout.US") == .remember)
        #expect(PerAppLayoutSwitcher.action(stored: nil, current: "") == PerAppLayoutSwitcher.Action.none)
    }

    @Test func switchesOnlyWhenDifferent() {
        #expect(PerAppLayoutSwitcher.action(stored: "com.apple.keylayout.Czech", current: "com.apple.keylayout.US")
            == .select("com.apple.keylayout.Czech"))
        #expect(PerAppLayoutSwitcher.action(stored: "com.apple.keylayout.US", current: "com.apple.keylayout.US")
            == PerAppLayoutSwitcher.Action.none)
    }
}

struct CaretPlacementTests {
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let size = NSSize(width: 19, height: 16)

    @Test func sitsRightOfCaretHangingFromItsMiddle() {
        let caret = NSRect(x: 100, y: 400, width: 1, height: 18)
        let origin = CursorMetrics.caretIndicatorOrigin(caret: caret, indicatorSize: size, screenFrame: screen)
        #expect(origin == NSPoint(x: 101 + CursorMetrics.gap, y: 409 - 16))
    }

    @Test func flipsLeftAndUpAtScreenEdges() {
        let caret = NSRect(x: 995, y: 0, width: 1, height: 18)
        let origin = CursorMetrics.caretIndicatorOrigin(caret: caret, indicatorSize: size, screenFrame: screen)
        #expect(origin == NSPoint(x: 995 - CursorMetrics.gap - 19, y: 9))
    }

    @Test func convertsAXRectangles() {
        let screens = [NSRect(x: 0, y: 0, width: 1000, height: 800)]
        let rect = TextFieldDetector.cocoaRect(fromAX: CGRect(x: 100, y: 200, width: 0, height: 20),
                                               primaryScreenHeight: 800, screens: screens)
        #expect(rect == NSRect(x: 100, y: 580, width: 0, height: 20))
    }

    @Test func rejectsBogusAXRectangles() {
        let screens = [NSRect(x: 0, y: 0, width: 1000, height: 800)]
        #expect(TextFieldDetector.cocoaRect(fromAX: .zero, primaryScreenHeight: 800, screens: screens) == nil)
        #expect(TextFieldDetector.cocoaRect(fromAX: CGRect(x: 0, y: 0, width: 0, height: 20),
                                            primaryScreenHeight: 800, screens: screens) == nil)
        #expect(TextFieldDetector.cocoaRect(fromAX: CGRect(x: 5000, y: 100, width: 1, height: 20),
                                            primaryScreenHeight: 800, screens: screens) == nil)
    }
}

struct CaretFollowTests {
    let shown = NSRect(x: 100, y: 400, width: 1, height: 18)

    @Test func staysWhileCaretIsStill() {
        #expect(CaretIndicatorController.followAction(sameElement: true, caret: shown, shownAt: shown) == .keep)
        let jitter = shown.offsetBy(dx: 0.25, dy: 0)
        #expect(CaretIndicatorController.followAction(sameElement: true, caret: jitter, shownAt: shown) == .keep)
    }

    @Test func followsCaretWhenWindowScrollsOrMoves() {
        let moved = shown.offsetBy(dx: 0, dy: -40)
        #expect(CaretIndicatorController.followAction(sameElement: true, caret: moved, shownAt: shown) == .move(moved))
    }

    @Test func hidesWhenFocusLeavesOrCaretIsUnknown() {
        #expect(CaretIndicatorController.followAction(sameElement: false, caret: shown, shownAt: shown) == .hide)
        #expect(CaretIndicatorController.followAction(sameElement: true, caret: nil, shownAt: shown) == .hide)
    }
}

struct FlagOverrideTests {
    let us = "com.apple.keylayout.US"

    @Test func overrideWinsOverMapping() {
        #expect(FlagMapping.countryCode(inputSourceID: us, languages: ["en"], overrides: [:]) == "US")
        #expect(FlagMapping.countryCode(inputSourceID: us, languages: ["en"], overrides: [us: "GB"]) == "GB")
        #expect(FlagMapping.countryCode(inputSourceID: us, languages: ["en"],
                                        overrides: [us: FlagMapping.systemIconOverride]) == nil)
    }

    @Test func overrideAppliesToInputMethods() {
        let id = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        #expect(FlagMapping.countryCode(inputSourceID: id, languages: ["ja"], overrides: [:]) == nil)
        #expect(FlagMapping.countryCode(inputSourceID: id, languages: ["ja"], overrides: [id: "JP"]) == "JP")
    }

    @Test func countryListIsSortedAndUsable() {
        let countries = FlagMapping.selectableCountries(locale: Locale(identifier: "en_US"))
        let codes = countries.map(\.code)
        #expect(codes.count > 200)
        #expect(codes.contains("CZ") && codes.contains("GB") && codes.contains("MX"))
        #expect(codes.allSatisfy { $0.count == 2 })
        #expect(countries.map(\.name) == countries.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}

@MainActor
struct NewSettingsTests {
    let defaults = UserDefaults(suiteName: "KeyFlagTests.\(UUID().uuidString)")!

    @Test func newFeaturesAreOffByDefaultAndPersist() {
        let settings = Settings(defaults: defaults, notificationCenter: NotificationCenter())
        #expect(!settings.rememberLayoutPerApp)
        #expect(!settings.showIndicatorAtCaret)
        #expect(!settings.flashOnLayoutChange)
        #expect(settings.appLayouts.isEmpty)
        #expect(settings.flagOverrides.isEmpty)

        settings.rememberLayoutPerApp = true
        settings.showIndicatorAtCaret = true
        settings.flashOnLayoutChange = true
        settings.appLayouts = ["com.apple.MobileSMS": "com.apple.keylayout.Czech"]
        settings.flagOverrides = ["com.apple.keylayout.US": "GB"]

        let reloaded = Settings(defaults: defaults, notificationCenter: NotificationCenter())
        #expect(reloaded.rememberLayoutPerApp)
        #expect(reloaded.showIndicatorAtCaret)
        #expect(reloaded.flashOnLayoutChange)
        #expect(reloaded.appLayouts == ["com.apple.MobileSMS": "com.apple.keylayout.Czech"])
        #expect(reloaded.flagOverrides == ["com.apple.keylayout.US": "GB"])
    }
}
