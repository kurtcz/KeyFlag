import AppKit

/// The About window: the app icon shown large (about Quick Look size), then the name, version,
/// copyright and a link to the project. Replaces the standard About panel, whose icon is fixed
/// at 64 points.
@MainActor
final class AboutWindow: NSObject, NSWindowDelegate {
    static let projectURL = URL(string: "https://github.com/kurtcz/KeyFlag")!
    private static let iconSize: CGFloat = 256

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil // rebuilt next time, so a rebuilt bundle's version shows
    }

    private func makeWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? "KeyFlag"
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        let build = info["CFBundleVersion"] as? String
        let copyright = info["NSHumanReadableCopyright"] as? String

        let icon = NSImageView()
        icon.image = Self.appIcon()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: Self.iconSize).isActive = true
        icon.heightAnchor.constraint(equalToConstant: Self.iconSize).isActive = true

        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let versionLabel = NSTextField(labelWithString: "Version \(version)" + (build.map { " (\($0))" } ?? ""))
        versionLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true

        let link = NSButton(title: Self.projectURL.host! + Self.projectURL.path, target: self, action: #selector(openProject))
        link.isBordered = false
        link.contentTintColor = .linkColor
        link.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        var views: [NSView] = [icon, title, versionLabel, link]
        if let copyright {
            let label = NSTextField(labelWithString: copyright)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            views.append(label)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(14, after: versionLabel)

        // Margins: the top one is small since the window has no visible title bar and the icon
        // artwork has its own transparent border.
        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),
        ])

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "About \(name)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        window.setContentSize(content.fittingSize)
        return window
    }

    @objc private func openProject() {
        NSWorkspace.shared.open(Self.projectURL)
    }

    /// The bundle's AppIcon.icns (all sizes, so the large one is used), else whatever icon the app has.
    private static func appIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage
    }
}
