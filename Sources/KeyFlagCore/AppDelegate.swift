import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let inputSourceMonitor = InputSourceMonitor()
    private lazy var indicator = CursorIndicator(settings: settings)
    private lazy var indicatorController = IndicatorController(settings: settings, indicator: indicator)
    private lazy var statusMenu = StatusMenu(settings: settings)

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        inputSourceMonitor.start()
        CapsLockMonitor.shared.start()
        Updater.shared.start()
        statusMenu.start()
        indicatorController.start()
        UnsupportedInputSourceWarning.checkCurrent(settings: settings)
        if !Accessibility.isTrusted {
            Accessibility.requestTrust()
        }
    }
}
