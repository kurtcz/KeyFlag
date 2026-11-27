import AppKit

/// Watches events both in other apps (global) and in KeyFlag itself (local).
/// Global key events only arrive once the app has Accessibility access.
@MainActor
public final class EventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: @MainActor (NSEvent) -> Void
    private var tokens: [Any] = []

    public init(mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    public var isRunning: Bool { !tokens.isEmpty }

    public func start() {
        guard tokens.isEmpty else { return }
        let handler = handler
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) {
            tokens.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }) {
            tokens.append(local)
        }
    }

    public func stop() {
        tokens.forEach(NSEvent.removeMonitor)
        tokens.removeAll()
    }
}
