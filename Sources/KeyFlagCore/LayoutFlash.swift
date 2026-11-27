import AppKit

/// A large flag and the layout's name in a HUD in the middle of the screen, shown briefly
/// whenever the layout switches (Settings.flashOnLayoutChange), like the volume overlay.
@MainActor
public final class LayoutFlash {
    private let settings: Settings
    private var observers: [NSObjectProtocol] = []
    private var hideWork: DispatchWorkItem?
    private var isShown = false

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private lazy var panel = makePanel()
    private lazy var animator = FlagAnimator { [weak self] image in
        self?.imageView.image = image
    }

    static let flagHeight: CGFloat = 72
    static let visibleDuration: TimeInterval = 0.9
    private static let panelSize = NSSize(width: 200, height: 160)

    public init(settings: Settings) {
        self.settings = settings
    }

    public func start() {
        observers.append(NotificationCenter.default.addObserver(forName: InputSourceMonitor.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        })
    }

    private func layoutChanged() {
        guard settings.flashOnLayoutChange else { return }
        show(InputSource.current)
    }

    func show(_ source: InputSource) {
        let frames = InputSourceIcon.frames(for: source, style: settings.flagStyle, height: Self.flagHeight)
        let isTemplate = frames[0].isTemplate
        imageView.contentTintColor = isTemplate ? .labelColor : nil
        animator.show(frames)
        label.stringValue = source.localizedName

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(origin: .zero, size: Self.panelSize)
        let origin = NSPoint(x: frame.midX - Self.panelSize.width / 2, y: frame.minY + frame.height * 0.3)
        panel.setFrameOrigin(CursorMetrics.pixelAligned(origin, scale: screen?.backingScaleFactor ?? 2))

        if !isShown {
            isShown = true
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    private func hide() {
        isShown = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.animator.stop()
                self.panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(imageView)
        background.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: background.topAnchor, constant: 26),
            imageView.heightAnchor.constraint(equalToConstant: Self.flagHeight),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: background.widthAnchor, constant: -32),
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
        ])
        panel.contentView = background
        return panel
    }
}
