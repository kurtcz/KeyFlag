import AppKit

/// Tracks Caps Lock and posts `didChangeNotification` when it turns on or off.
/// Modifier changes in other apps only arrive once KeyFlag has Accessibility access;
/// `refresh()` catches up on anything missed.
@MainActor
public final class CapsLockMonitor {
    public static let shared = CapsLockMonitor()
    public static let didChangeNotification = Notification.Name("KeyFlagCapsLockDidChange")

    public private(set) var isOn = CapsLockMonitor.currentState()
    private lazy var monitor = EventMonitor(mask: [.flagsChanged]) { [weak self] event in
        self?.update(event.modifierFlags.contains(.capsLock))
    }

    public init() {}

    public func start() {
        monitor.start()
        refresh()
    }

    /// Re-reads the hardware state, e.g. after waking or when the menu opens.
    public func refresh() {
        update(Self.currentState())
    }

    private func update(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func currentState() -> Bool {
        NSEvent.modifierFlags.contains(.capsLock)
    }
}

extension InputSourceIcon {
    /// `frames` with a Caps Lock symbol to the right of each one. Template images stay
    /// templates so the menu bar can tint them; colored ones (flags) get a dark badge that
    /// reads on any background.
    public static func addingCapsLockBadge(_ frames: [NSImage]) -> [NSImage] {
        guard let first = frames.first else { return frames }
        let key = ObjectIdentifier(first)
        if let cached = capsCache[key], cached.base.count == frames.count,
           zip(cached.base, frames).allSatisfy({ $0 === $1 }) {
            return cached.badged
        }
        let badged = frames.map(addingCapsLockBadge)
        if capsCache.count > 64 { capsCache.removeAll() }
        capsCache[key] = (frames, badged)
        return badged
    }

    private static var capsCache: [ObjectIdentifier: (base: [NSImage], badged: [NSImage])] = [:]

    static func addingCapsLockBadge(_ image: NSImage) -> NSImage {
        let height = image.size.height
        let badgeSide = (height * 0.75).rounded()
        let gap = max(1, (height * 0.12).rounded())
        let size = NSSize(width: image.size.width + gap + badgeSide, height: height)
        let template = image.isTemplate
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: badgeSide * (template ? 0.9 : 0.7), weight: .bold)
        let symbol = NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: "Caps Lock")?
            .withSymbolConfiguration(symbolConfig)
        let result = NSImage(size: size, flipped: false) { rect in
            image.draw(in: NSRect(origin: .zero, size: image.size))
            let badge = NSRect(x: rect.maxX - badgeSide, y: ((height - badgeSide) / 2).rounded(),
                               width: badgeSide, height: badgeSide)
            if !template {
                NSColor(white: 0, alpha: 0.75).setFill()
                NSBezierPath(roundedRect: badge, xRadius: badgeSide * 0.22, yRadius: badgeSide * 0.22).fill()
            }
            if let symbol {
                let color: NSColor = template ? .black : .white
                let tinted = NSImage(size: symbol.size, flipped: false) { r in
                    symbol.draw(in: r)
                    color.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                let s = symbol.size
                tinted.draw(in: NSRect(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2,
                                       width: s.width, height: s.height))
            }
            return true
        }
        result.isTemplate = template
        result.accessibilityDescription = image.accessibilityDescription
        return result
    }
}
