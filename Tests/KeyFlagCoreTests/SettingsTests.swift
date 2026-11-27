import Foundation
import Testing
@testable import KeyFlagCore

final class Counter: @unchecked Sendable {
    var value = 0
}

@MainActor
struct SettingsTests {
    let suiteName = "KeyFlagTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let center = NotificationCenter()
    let settings: Settings

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = Settings(defaults: defaults, notificationCenter: center)
    }

    @Test func defaultValues() {
        #expect(settings.statusbarIconMode == .inputSource)
        #expect(settings.indicatorTint == .disabled)
        #expect(settings.showCursorIndicator)
        #expect(settings.hideIndicatorWhileTyping)
        #expect(settings.flagStyle == .classic)
        #expect(!settings.reduceIndicatorSize)
        #expect(settings.unsupportedInputSourceWarningsShown.isEmpty)
        #expect(settings.showCapsLockState)
    }

    @Test func valuesPersistAcrossInstances() {
        settings.reduceIndicatorSize = true
        settings.statusbarIconMode = .inputSourceWithName
        settings.indicatorTint = .blue
        settings.unsupportedInputSourceWarningsShown = ["com.example.layout"]

        let reloaded = Settings(defaults: defaults, notificationCenter: center)
        #expect(reloaded.reduceIndicatorSize)
        #expect(reloaded.statusbarIconMode == .inputSourceWithName)
        #expect(reloaded.indicatorTint == .blue)
        #expect(reloaded.unsupportedInputSourceWarningsShown == ["com.example.layout"])
    }

    @Test func unknownRawValuesFallBackToDefaults() {
        defaults.set(99, forKey: "statusbarIconMode")
        defaults.set(-5, forKey: "indicatorTint")
        #expect(settings.statusbarIconMode == .inputSource)
        #expect(settings.indicatorTint == .disabled)
    }

    @Test func removedHideModeShowsTheIcon() {
        defaults.set(0, forKey: "statusbarIconMode")
        #expect(settings.statusbarIconMode == .inputSource)
    }

    @Test func oldBringBackFlagsSwitchMigrates() {
        defaults.set(false, forKey: "returnFlags")
        #expect(settings.flagStyle == .system)
        settings.flagStyle = .emoji
        #expect(settings.flagStyle == .emoji)
        defaults.set(2, forKey: "flagStyle") // the removed Pixel style, even with returnFlags off
        #expect(settings.flagStyle == .classic)
    }

    @Test func everyChangePostsNotification() {
        let count = Counter()
        let token = center.addObserver(forName: Settings.didChangeNotification, object: nil, queue: nil) { _ in
            count.value += 1
        }
        defer { center.removeObserver(token) }

        settings.flagStyle = .waving
        settings.indicatorTint = .red
        #expect(count.value == 2)
    }
}
