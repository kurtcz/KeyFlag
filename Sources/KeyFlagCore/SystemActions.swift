import AppKit
import os
import ServiceManagement

/// Launch at login through SMAppService. Only works from a bundled KeyFlag.app.
@MainActor
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

private let log = Logger(subsystem: "KeyFlag", category: "SystemActions")

/// System features reachable from the menu.
@MainActor
public enum SystemActions {
    public static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    /// Since macOS 12 the Keyboard Viewer is the Accessibility Keyboard. Its setting can only
    /// be written by Apple processes, the old `com.apple.KeyboardViewer` input source is
    /// gone, and selecting its replacement does nothing from a menu bar app. Two routes work:
    ///
    /// 1. The "KeyFlag Keyboard Viewer" shortcut (Set Accessibility Keyboard: On), run in the
    ///    background. Silent, but the user has to add the shortcut once.
    /// 2. Pressing the input menu's own "Show Keyboard Viewer" item through Accessibility,
    ///    which briefly opens that menu.
    ///
    /// Without either, open the setting so the user can turn it on.
    public static func showKeyboardViewer() {
        guard !InputMenu.isKeyboardViewerShown else { return }
        Task { @MainActor in
            if await KeyboardViewerShortcut.run() { return }
            if Accessibility.isTrusted {
                // Let the status menu close first; only one menu can be open at a time.
                try? await Task.sleep(for: .milliseconds(150))
                if await !InputMenu.pressKeyboardViewerItem() {
                    log.error("Couldn't press the input menu's Keyboard Viewer item")
                    openAccessibilityKeyboardSettings()
                }
            } else {
                openAccessibilityKeyboardSettings()
            }
            KeyboardViewerShortcut.offerSetupOnce()
        }
    }

    private static func openAccessibilityKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Keyboard")!)
    }

    /// On macOS 26 the Character Viewer only opens for the active app, and a menu bar app
    /// never is. So post the system's ⌃⌘Space shortcut to the frontmost app instead.
    public static func showEmojiAndSymbols() {
        if #available(macOS 26, *), Accessibility.isTrusted {
            // Let the status menu close first so the shortcut reaches the frontmost app.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                postEmojiShortcut()
            }
            return
        }
        InputSource.withID("com.apple.CharacterPaletteIM")?.select()
    }

    private static func postEmojiShortcut() {
        let space: CGKeyCode = 49
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: space, keyDown: keyDown)
            event?.flags = [.maskControl, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Drives the system input menu (the menu bar's input source menu, run by
/// TextInputMenuAgent) through Accessibility.
@MainActor
enum InputMenu {
    private static let agentBundleID = "com.apple.TextInputMenuAgent"
    private static let menuDomain = "com.apple.TextInputMenu" as CFString
    private static let visibleKey = "visible" as CFString
    /// The menu item's AXIdentifier is its action selector, which doesn't depend on the
    /// system language.
    private static let keyboardViewerItemID = "toggle"

    static var isKeyboardViewerShown: Bool {
        CFPreferencesCopyAppValue("virtualKeyboardOnOff" as CFString, "com.apple.universalaccess" as CFString) as? Bool ?? false
    }

    /// Opens the input menu and presses its Keyboard Viewer item. If the input menu is
    /// hidden, it's shown just for the press. Returns false if the item wasn't found.
    static func pressKeyboardViewerItem() async -> Bool {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first?.processIdentifier else {
            return false
        }
        let wasVisible = CFPreferencesCopyAppValue(visibleKey, menuDomain) as? Bool ?? false
        if !wasVisible { setVisible(true) }
        defer {
            if !wasVisible {
                // Hide it again once the menu has had time to close.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    setVisible(false)
                }
            }
        }

        let agent = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(agent, 0.5)
        guard let menuBarItem = await poll({
            children(of: agent, "AXExtrasMenuBar")?.first.flatMap { children(of: $0)?.first }
        }) else { return false }
        AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString)
        let item = await poll {
            children(of: menuBarItem)?.first.flatMap { children(of: $0) }?
                .first { string($0, kAXIdentifierAttribute) == keyboardViewerItemID }
        }
        guard let item else {
            if let menu = children(of: menuBarItem)?.first {
                AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
            return false
        }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func setVisible(_ visible: Bool) {
        CFPreferencesSetAppValue(visibleKey, visible as CFBoolean, menuDomain)
        CFPreferencesAppSynchronize(menuDomain)
    }

    /// Retries `find` for up to two seconds; menus and menu bar items appear asynchronously.
    private static func poll<T>(_ find: () -> T?) async -> T? {
        for _ in 0..<40 {
            if let found = find() { return found }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// The element's children, or the element(s) stored under `attribute`.
    private static func children(of element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if let array = value as? [AXUIElement] { return array }
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return [value as! AXUIElement] }
        return nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }
}

/// A user-installed shortcut that turns the Accessibility Keyboard on without any UI.
/// Apps can't add shortcuts themselves, so KeyFlag offers it once and Shortcuts asks the
/// user to confirm.
@MainActor
enum KeyboardViewerShortcut {
    static let name = "KeyFlag Keyboard Viewer"

    /// Runs the shortcut in the background. False if it's missing or failed.
    static func run() async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// The first time the shortcut is missing, explain and offer to add it.
    static func offerSetupOnce(settings: Settings = .shared) {
        guard !settings.keyboardViewerShortcutOffered else { return }
        settings.keyboardViewerShortcutOffered = true
        offerSetup()
    }

    static func offerSetup() {
        let bundled = Bundle.main.url(forResource: name, withExtension: "shortcut")
        let alert = NSAlert()
        alert.messageText = "Open the Keyboard Viewer silently?"
        alert.informativeText = bundled != nil
            ? "KeyFlag can open the Keyboard Viewer without the input menu flashing, using a shortcut. Shortcuts will ask you to add it."
            : "KeyFlag can open the Keyboard Viewer without the input menu flashing, using a shortcut. In Shortcuts, create a shortcut named “\(name)” with the action Set Accessibility Keyboard set to On."
        alert.addButton(withTitle: bundled != nil ? "Add Shortcut" : "Open Shortcuts")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let bundled {
            NSWorkspace.shared.open(bundled)
        } else if let shortcuts = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: shortcuts, configuration: .init())
        }
    }
}
