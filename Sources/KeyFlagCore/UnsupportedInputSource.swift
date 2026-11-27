import AppKit

/// Warns once per input source when KeyFlag can't get its icon and shows a letter badge
/// instead, and asks the user to report it so the source can get proper support.
@MainActor
public enum UnsupportedInputSourceWarning {
    static let issuesURL = URL(string: "https://github.com/kurtcz/KeyFlag/issues/new")!

    /// Shows the warning for the current input source if it is unsupported and the user
    /// hasn't seen it for that source yet.
    public static func checkCurrent(settings: Settings = .shared) {
        let source = InputSource.current
        guard needsWarning(id: source.id, isSupported: InputSourceIcon.hasOwnIcon(source),
                           alreadyShown: settings.unsupportedInputSourceWarningsShown) else { return }
        settings.unsupportedInputSourceWarningsShown.append(source.id)
        // Leave the notification handler (and any open menu) before going modal.
        DispatchQueue.main.async { show(name: source.localizedName, id: source.id) }
    }

    nonisolated static func needsWarning(id: String, isSupported: Bool, alreadyShown: [String]) -> Bool {
        !id.isEmpty && !isSupported && !alreadyShown.contains(id)
    }

    private static func show(name: String, id: String) {
        let alert = NSAlert()
        alert.messageText = "KeyFlag can't show the icon for “\(name)”"
        alert.informativeText = "It shows a letter badge for this input source instead. "
            + "Report it with the input source ID below and a future version can support it properly.\n\n\(id)"
        alert.addButton(withTitle: "Report…")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var components = URLComponents(url: issuesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: "Unsupported input source: \(id)"),
            URLQueryItem(name: "body", value: "Input source: \(name)\nID: \(id)\n"),
        ]
        NSWorkspace.shared.open(components.url ?? issuesURL)
    }
}
