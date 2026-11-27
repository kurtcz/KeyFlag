import AppKit

/// The menu bar item and its menu. The menu is rebuilt each time it opens.
///
/// Order: layouts, indicator options, appearance, system shortcuts, app items. Titles use
/// macOS 13+ wording ("Keyboard Settings", not "Preferences") and title case.
@MainActor
public final class StatusMenu: NSObject, NSMenuDelegate {
    private let settings: Settings
    private var statusItem: NSStatusItem?
    private var observers: [NSObjectProtocol] = []
    private lazy var animator = FlagAnimator { [weak self] image in
        self?.statusItem?.button?.image = image
    }

    public init(settings: Settings) {
        self.settings = settings
    }

    public func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        let center = NotificationCenter.default
        for name in [InputSourceMonitor.didChangeNotification, Settings.didChangeNotification, CapsLockMonitor.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateIcon() }
            })
        }
        updateIcon()
    }

    public func updateIcon() {
        guard let item = statusItem, let button = item.button else { return }
        let mode = settings.statusbarIconMode
        // macOS remembers a hidden status item across launches; the icon is the only way
        // into the app, so always show it (it may have been hidden by an older version).
        item.isVisible = true
        let source = InputSource.current
        var frames = InputSourceIcon.frames(for: source, style: settings.flagStyle, height: 16)
        if settings.showCapsLockState && CapsLockMonitor.shared.isOn {
            frames = InputSourceIcon.addingCapsLockBadge(frames)
        }
        animator.show(frames)
        button.title = mode == .inputSourceWithName ? " \(source.localizedName)" : ""
        button.imagePosition = .imageLeading
    }

    // MARK: - Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        CapsLockMonitor.shared.refresh()

        let current = InputSource.current
        for source in InputSource.selectableKeyboardSources() {
            let item = action(source.localizedName, #selector(selectInputSource(_:)))
            item.representedObject = source.id
            item.state = source == current ? .on : .off
            item.image = InputSourceIcon.image(for: source, style: settings.flagStyle, height: 16)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let trusted = Accessibility.isTrusted
        menu.addItem(toggle("Show Indicator Next to Pointer", settings.showCursorIndicator, #selector(toggleShowCursorIndicator))
            .symbol("cursorarrow.rays")
            .tip("Shows the current layout next to the pointer whenever it's over a text field."
                + (trusted ? "" : " Needs Accessibility access.")))
        menu.addItem(toggle("Hide Indicator While Typing", settings.hideIndicatorWhileTyping, #selector(toggleHideWhileTyping))
            .symbol("eye.slash")
            .tip("Hides the indicator while you type, scroll or drag, until the pointer moves."
                + (trusted ? "" : " Needs Accessibility access.")))
        menu.addItem(toggle("Show Caps Lock State", settings.showCapsLockState, #selector(toggleShowCapsLock))
            .symbol("capslock")
            .tip("Adds ⇪ to the indicator and the menu bar icon while Caps Lock is on."))
        menu.addItem(toggle("Reduce Indicator Size", settings.reduceIndicatorSize, #selector(toggleReduceSize))
            .symbol("arrow.down.right.and.arrow.up.left"))
        menu.addItem(submenu(
            "Flags",
            options: FlagStyle.allCases.map { ($0.title, $0.rawValue) },
            selected: settings.flagStyle.rawValue,
            action: #selector(selectFlagStyle(_:))
        ).symbol("flag")
            .tip("Flags for keyboard layouts. Input methods keep their own icons."))
        menu.addItem(submenu(
            "Fix Translucent Indicator",
            options: IndicatorTint.allCases.map { ($0.title, $0.rawValue) },
            selected: settings.indicatorTint.rawValue,
            action: #selector(selectTint(_:))
        ).symbol("circle.lefthalf.filled")
            .tip("Some input sources have see-through icons that are hard to see next to the pointer. Pick a color to fill them."))
        menu.addItem(submenu(
            "Menu Bar Icon",
            options: StatusbarIconMode.allCases.map { ($0.title, $0.rawValue) },
            selected: settings.statusbarIconMode.rawValue,
            action: #selector(selectStatusbarMode(_:))
        ).symbol("menubar.rectangle"))
        menu.addItem(toggle("Launch at Login", LoginItem.isEnabled, #selector(toggleLaunchAtLogin)).symbol("togglepower"))
        menu.addItem(.separator())

        menu.addItem(action("Open Keyboard Settings…", #selector(openKeyboardSettings)).symbol("gearshape"))
        menu.addItem(action("Show Keyboard Viewer", #selector(showKeyboardViewer)).symbol("keyboard"))
        menu.addItem(action("Show Emoji & Symbols", #selector(showEmojiAndSymbols)).symbol("face.smiling"))
        menu.addItem(.separator())

        if !Accessibility.isTrusted {
            menu.addItem(action("Grant Accessibility Access…", #selector(grantAccessibility)).symbol("accessibility"))
            menu.addItem(.separator())
        }

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = Updater.shared
        updates.symbol("arrow.triangle.2.circlepath")
        menu.addItem(updates)
        let about = action("About KeyFlag", #selector(showAbout))
        about.image = Bundle.main.image(forResource: "MenuIcon") // just the two flags from the app icon
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit KeyFlag", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .symbol("power"))
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ isOn: Bool, _ selector: Selector) -> NSMenuItem {
        let item = action(title, selector)
        item.state = isOn ? .on : .off
        return item
    }

    private func submenu(_ title: String, options: [(String, Int)], selected: Int, action selector: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for (optionTitle, value) in options {
            let item = toggle(optionTitle, value == selected, selector)
            item.tag = value
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }

    // MARK: - Actions

    @objc private func selectInputSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        InputSource.withID(id)?.select()
    }

    @objc private func toggleShowCursorIndicator() { settings.showCursorIndicator.toggle() }
    @objc private func toggleHideWhileTyping() { settings.hideIndicatorWhileTyping.toggle() }
    @objc private func toggleShowCapsLock() { settings.showCapsLockState.toggle() }
    @objc private func toggleReduceSize() { settings.reduceIndicatorSize.toggle() }

    @objc private func selectFlagStyle(_ sender: NSMenuItem) {
        settings.flagStyle = FlagStyle(rawValue: sender.tag) ?? .classic
    }

    @objc private func selectTint(_ sender: NSMenuItem) {
        settings.indicatorTint = IndicatorTint(rawValue: sender.tag) ?? .disabled
    }

    @objc private func selectStatusbarMode(_ sender: NSMenuItem) {
        settings.statusbarIconMode = StatusbarIconMode(rawValue: sender.tag) ?? .inputSource
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openKeyboardSettings() { SystemActions.openKeyboardSettings() }
    @objc private func showKeyboardViewer() { SystemActions.showKeyboardViewer() }
    @objc private func showEmojiAndSymbols() { SystemActions.showEmojiAndSymbols() }
    @objc private func grantAccessibility() { Accessibility.requestTrust() }

    private lazy var aboutWindow = AboutWindow()

    @objc private func showAbout() { aboutWindow.show() }
}

private extension NSMenuItem {
    /// Sets an SF Symbol as the item's image; on systems that lack the symbol the item just has no image.
    @discardableResult
    func symbol(_ name: String) -> NSMenuItem {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        return self
    }

    @discardableResult
    func tip(_ text: String) -> NSMenuItem {
        toolTip = text
        return self
    }
}
