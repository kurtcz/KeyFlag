import AppKit

/// The small click-through window that shows the current layout next to the pointer.
@MainActor
public final class CursorIndicator {
    private let settings: Settings
    private lazy var imageView = NSImageView()
    private lazy var window = makeWindow()
    private var isShown = false
    private lazy var animator = FlagAnimator { [weak self] image in
        self?.imageView.image = image
    }

    /// The current cursor's size and hot spot, re-read at most every `cursorRefreshInterval`
    /// since asking for the system cursor on every mouse move is wasteful.
    private var cursorMetrics = CursorMetrics.fallback
    private var cursorMetricsDate = Date.distantPast
    private let cursorRefreshInterval: TimeInterval = 0.1

    public init(settings: Settings) {
        self.settings = settings
    }

    private var height: CGFloat { settings.reduceIndicatorSize ? 12 : 16 }

    public func updateImage() {
        let source = InputSource.current
        var frames: [NSImage]
        if let flag = InputSourceIcon.flagFrames(for: source, style: settings.flagStyle, height: height) {
            frames = flag // Flags have their own colors; never tint them.
        } else {
            var image = InputSourceIcon.systemImage(for: source)
            if let color = settings.indicatorTint.color {
                image = InputSourceIcon.tinted(image, color: color)
            }
            frames = [InputSourceIcon.scaled(image, toHeight: height)]
        }
        if settings.showCapsLockState && CapsLockMonitor.shared.isOn {
            frames = InputSourceIcon.addingCapsLockBadge(frames)
        }
        window.setContentSize(frames[0].size)
        // Only animate while visible; setVisible(true) calls this again.
        if isShown { animator.show(frames) } else { imageView.image = frames[0] }
        updatePosition()
    }

    public func updatePosition() {
        if Date().timeIntervalSince(cursorMetricsDate) > cursorRefreshInterval {
            cursorMetrics = CursorMetrics.current() ?? .fallback
            cursorMetricsDate = Date()
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let origin = CursorMetrics.indicatorOrigin(
            mouse: mouse, cursor: cursorMetrics, indicatorSize: window.frame.size,
            screenFrame: screen?.frame ?? .infinite
        )
        window.setFrameOrigin(CursorMetrics.pixelAligned(origin, scale: screen?.backingScaleFactor ?? 2))
    }

    public func setVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != isShown else { return }
        isShown = visible
        if visible {
            updateImage()
            window.orderFrontRegardless()
        } else {
            animator.stop()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            window.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.window.orderOut(nil)
            }
        }
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 16, height: 16),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.alphaValue = 0
        imageView.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = imageView
        return panel
    }
}
