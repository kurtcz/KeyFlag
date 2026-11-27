import AppKit

/// Decides when the cursor indicator is visible: the pointer is over a text input,
/// the feature is on, and the user isn't typing, scrolling or dragging.
@MainActor
public final class IndicatorController {
    private let settings: Settings
    private let indicator: CursorIndicator
    private let throttler = Throttler(minimumDelay: 0.1)
    private var observers: [NSObjectProtocol] = []

    /// Set by typing, scrolling or dragging; cleared by a deliberate pointer move or a layout
    /// switch. Holds where the pointer was at the last such activity.
    private var suppressedAt: NSPoint?
    private var suppressedByActivity: Bool { suppressedAt != nil }

    private lazy var mouseMonitor = EventMonitor(mask: [.mouseMoved]) { [weak self] _ in
        self?.mouseMoved()
    }

    private lazy var activityMonitor = EventMonitor(
        mask: [.keyDown, .scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    ) { [weak self] _ in
        self?.activityDetected()
    }

    public init(settings: Settings, indicator: CursorIndicator) {
        self.settings = settings
        self.indicator = indicator
    }

    public func start() {
        mouseMonitor.start()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: InputSourceMonitor.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        })
        observers.append(center.addObserver(forName: CapsLockMonitor.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        })
        observers.append(center.addObserver(forName: Settings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        applySettings()
    }

    private func applySettings() {
        if settings.hideIndicatorWhileTyping {
            activityMonitor.start()
        } else {
            activityMonitor.stop()
            suppressedAt = nil
        }
        indicator.updateImage()
        scheduleUpdate()
    }

    private func mouseMoved() {
        if let anchor = suppressedAt {
            guard Self.isDeliberateMove(from: anchor, to: NSEvent.mouseLocation) else { return }
            suppressedAt = nil
        }
        indicator.updatePosition()
        scheduleUpdate()
    }

    private func activityDetected() {
        // Re-anchored on every key, so slow drift while typing never adds up to a move.
        suppressedAt = NSEvent.mouseLocation
        throttler.cancel()
        indicator.setVisible(false)
    }

    /// A layout switch or Caps Lock toggle: show what changed.
    private func inputSourceChanged() {
        suppressedAt = nil
        indicator.updateImage()
        scheduleUpdate()
        UnsupportedInputSourceWarning.checkCurrent(settings: settings)
    }

    /// How far the pointer must travel after typing, scrolling or dragging before the
    /// indicator returns, so a nudged trackpad or mouse doesn't bring it back mid-sentence.
    static let resumeDistance: CGFloat = 8

    static func isDeliberateMove(from anchor: NSPoint, to location: NSPoint) -> Bool {
        hypot(location.x - anchor.x, location.y - anchor.y) >= resumeDistance
    }

    private func scheduleUpdate() {
        throttler.throttle { [weak self] in
            guard let self else { return }
            self.indicator.setVisible(self.shouldShow())
        }
    }

    private func shouldShow() -> Bool {
        settings.showCursorIndicator
            && !suppressedByActivity
            && Accessibility.isTrusted
            && TextFieldDetector.isTextElementUnderMouse()
    }
}
