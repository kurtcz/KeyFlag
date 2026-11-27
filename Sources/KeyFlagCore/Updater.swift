import AppKit
import Sparkle

/// Automatic updates through Sparkle. Only runs from a bundled KeyFlag.app whose Info.plist
/// has a feed URL and an EdDSA public key (set by build-app.sh); otherwise the menu item
/// stays disabled, so unsigned local builds never offer updates they couldn't verify.
@MainActor
public final class Updater: NSObject, NSMenuItemValidation {
    public static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    public static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let feed = info["SUFeedURL"] as? String ?? ""
        return Bundle.main.bundleURL.pathExtension == "app" && !key.isEmpty && !feed.isEmpty
    }

    public func start() {
        guard controller == nil, Self.isConfigured else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    public var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    public var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    @objc public func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(checkForUpdates(_:)) ? canCheckForUpdates : true
    }
}
