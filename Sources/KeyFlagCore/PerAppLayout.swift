import AppKit

/// Remembers the layout used last in each app and switches back to it when that app comes
/// to the front (Settings.rememberLayoutPerApp).
///
/// macOS's own "Automatically switch to a document's input source" works per window; this
/// works per app, which is what most people mean ("Czech in Messages, U.S. in Xcode").
@MainActor
public final class PerAppLayoutSwitcher {
    private let settings: Settings
    private var observers: [NSObjectProtocol] = []
    /// The app we last switched for, so the change notification our own `select()` causes
    /// is recorded for that app and not for whichever app is frontmost when it arrives.
    private var activeBundleID: String?

    public init(settings: Settings) {
        self.settings = settings
    }

    public func start() {
        activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.appActivated(bundleID) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: InputSourceMonitor.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        })
    }

    private func appActivated(_ bundleID: String?) {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
        activeBundleID = bundleID
        guard settings.rememberLayoutPerApp else { return }
        let current = InputSource.current.id
        switch Self.action(stored: settings.appLayouts[bundleID], current: current) {
        case .none:
            break
        case .remember:
            settings.appLayouts[bundleID] = current
        case .select(let id):
            // The layout may have been removed since; then just remember the current one.
            if let source = InputSource.withID(id), source.isEnabled, source.select() { return }
            settings.appLayouts[bundleID] = current
        }
    }

    private func layoutChanged() {
        guard settings.rememberLayoutPerApp, let bundleID = activeBundleID else { return }
        let current = InputSource.current.id
        guard !current.isEmpty, settings.appLayouts[bundleID] != current else { return }
        settings.appLayouts[bundleID] = current
    }

    enum Action: Equatable {
        case none
        case remember
        case select(String)
    }

    /// What to do when an app comes to the front: switch to its stored layout, or, for an
    /// app seen for the first time, remember the layout it starts with.
    nonisolated static func action(stored: String?, current: String) -> Action {
        guard let stored else { return current.isEmpty ? .none : .remember }
        return stored == current ? .none : .select(stored)
    }
}
