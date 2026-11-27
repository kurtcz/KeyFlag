import AppKit

/// Shows the flag next to the text caret (Settings.showIndicatorAtCaret) after a click that
/// leaves a text input focused, and when the layout or Caps Lock changes while one is
/// focused. It has no timeout. Like the pointer indicator it hides when you type if
/// Settings.hideIndicatorWhileTyping is on; otherwise it stays and moves along with the
/// caret. It also hides when you scroll or click, another app comes to the front, or focus
/// leaves the field.
@MainActor
public final class CaretIndicatorController {
    private let settings: Settings
    private let indicator: CursorIndicator
    private var observers: [NSObjectProtocol] = []
    private var showWork: DispatchWorkItem?

    /// The field the indicator is shown for and where its caret was, while visible.
    private var shown: (element: AXUIElement, rect: NSRect)?
    private var followTimer: Timer?

    /// Time for the clicked app to move focus and the caret before we ask where they are.
    static let clickSettleDelay: TimeInterval = 0.08
    /// How often the focused field and caret are re-checked while the indicator is visible.
    static let followInterval: TimeInterval = 0.25

    private lazy var clickMonitor = EventMonitor(mask: [.leftMouseUp]) { [weak self] _ in
        self?.scheduleShow(after: Self.clickSettleDelay)
    }

    private lazy var activityMonitor = EventMonitor(
        mask: [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
        self?.hide()
    }

    /// Hides on a keystroke when "Hide Indicator While Typing" is on; otherwise follows the
    /// caret right after it instead of waiting for the next check.
    private lazy var keyMonitor = EventMonitor(mask: [.keyDown]) { [weak self] _ in
        guard let self else { return }
        if self.settings.hideIndicatorWhileTyping { self.hide() } else { self.followSoon() }
    }
    private var followWork: DispatchWorkItem?
    /// Time for the app to insert the character and move its caret.
    static let keySettleDelay: TimeInterval = 0.03

    public init(settings: Settings, indicator: CursorIndicator) {
        self.settings = settings
        self.indicator = indicator
    }

    public func start() {
        let center = NotificationCenter.default
        for name in [InputSourceMonitor.didChangeNotification, CapsLockMonitor.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleShow(after: 0) }
            })
        }
        observers.append(center.addObserver(forName: Settings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
        applySettings()
    }

    private func applySettings() {
        if settings.showIndicatorAtCaret {
            clickMonitor.start()
            activityMonitor.start()
            keyMonitor.start()
            if shown != nil { indicator.updateImage() }
        } else {
            clickMonitor.stop()
            activityMonitor.stop()
            keyMonitor.stop()
            hide()
        }
    }

    private func scheduleShow(after delay: TimeInterval) {
        guard settings.showIndicatorAtCaret else { return }
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.showAtCaret() }
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func showAtCaret() {
        guard settings.showIndicatorAtCaret, Accessibility.isTrusted,
              let caret = TextFieldDetector.focusedCaret() else { return }
        shown = caret
        indicator.anchor = .caret(caret.rect)
        indicator.updateImage()
        indicator.setVisible(true)
        startFollowing()
    }

    private func startFollowing() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: Self.followInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func followSoon() {
        guard shown != nil else { return }
        followWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.follow() }
        }
        followWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keySettleDelay, execute: work)
    }

    private func follow() {
        guard let shown else { return hide() }
        let current = TextFieldDetector.focusedCaret()
        let sameElement = current.map { CFEqual($0.element, shown.element) } ?? false
        switch Self.followAction(sameElement: sameElement, caret: current?.rect, shownAt: shown.rect) {
        case .keep:
            break
        case .hide:
            hide()
        case .move(let rect):
            self.shown = (shown.element, rect)
            indicator.anchor = .caret(rect)
            indicator.updatePosition()
        }
    }

    enum FollowAction: Equatable {
        case keep
        case hide
        case move(NSRect)
    }

    /// What a re-check finds: focus left the field (or its caret can't be read any more),
    /// the caret moved, or nothing changed.
    nonisolated static func followAction(sameElement: Bool, caret: NSRect?, shownAt: NSRect) -> FollowAction {
        guard sameElement, let caret else { return .hide }
        let moved = abs(caret.minX - shownAt.minX) > 0.5 || abs(caret.minY - shownAt.minY) > 0.5
            || abs(caret.height - shownAt.height) > 0.5
        return moved ? .move(caret) : .keep
    }

    private func hide() {
        showWork?.cancel()
        followWork?.cancel()
        followTimer?.invalidate()
        followTimer = nil
        shown = nil
        indicator.setVisible(false)
    }
}
