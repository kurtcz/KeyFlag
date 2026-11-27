import AppKit

/// What the menu bar item shows.
/// Raw values are stored in UserDefaults, so existing values must not change. Values 0 (Hide,
/// which left no way to reach the menu) and 1 (the KeyFlag icon) were removed; they now read
/// as missing and fall back to the default.
public enum StatusbarIconMode: Int, CaseIterable, Sendable {
    case inputSource = 2
    case inputSourceWithName = 3

    public var title: String {
        switch self {
        case .inputSource: "Current Input Source"
        case .inputSourceWithName: "Current Input Source with Name"
        }
    }
}

/// Which flags stand for keyboard layouts.
/// Raw values are stored in UserDefaults, so existing values must not change.
public enum FlagStyle: Int, CaseIterable, Sendable {
    /// The icons macOS itself shows (letters on macOS 12.4+).
    case system = 0
    /// Our own vector flags, styled after the Mac OS X input menu.
    case classic = 1
    // 2 was the removed famfamfam "Pixel" style; it now reads as missing → Classic.
    /// Apple Color Emoji flags.
    case emoji = 3
    /// The classic flags, waving.
    case waving = 4

    public var title: String {
        switch self {
        case .system: "Off (macOS Icons)"
        case .classic: "Classic"
        case .emoji: "Emoji"
        case .waving: "Waving"
        }
    }
}

/// Recolors the cursor indicator for layouts whose icon is a see-through template.
public enum IndicatorTint: Int, CaseIterable, Sendable {
    case disabled = 0
    case gray
    case red
    case green
    case blue

    public var title: String {
        switch self {
        case .disabled: "Disabled"
        case .gray: "Gray"
        case .red: "Red"
        case .green: "Green"
        case .blue: "Blue"
        }
    }

    public var color: NSColor? {
        switch self {
        case .disabled: nil
        case .gray: .systemGray
        case .red: .systemRed
        case .green: .systemGreen
        case .blue: .systemBlue
        }
    }
}

/// User preferences, persisted in UserDefaults. Every change posts `didChangeNotification`.
@MainActor
public final class Settings {
    public static let shared = Settings()
    public static let didChangeNotification = Notification.Name("KeyFlagSettingsDidChange")

    enum Key: String {
        case statusbarIconMode
        case indicatorTint
        case reduceIndicatorSize
        case flagStyle
        /// Replaced by flagStyle; read once to migrate.
        case returnFlags
        case showCursorIndicator
        case hideIndicatorWhileTyping
        case showCapsLockState
        case unsupportedInputSourceWarningsShown
        case keyboardViewerShortcutOffered
    }

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    public var statusbarIconMode: StatusbarIconMode {
        get { StatusbarIconMode(rawValue: integer(.statusbarIconMode)) ?? .inputSource }
        set { store(newValue.rawValue, .statusbarIconMode) }
    }

    public var indicatorTint: IndicatorTint {
        get { IndicatorTint(rawValue: integer(.indicatorTint)) ?? .disabled }
        set { store(newValue.rawValue, .indicatorTint) }
    }

    public var reduceIndicatorSize: Bool {
        get { bool(.reduceIndicatorSize, default: false) }
        set { store(newValue, .reduceIndicatorSize) }
    }

    /// Flags instead of the letter icons macOS 12.4+ uses. Before this setting existed,
    /// "Bring Back Flags" (returnFlags) was an on/off switch; off maps to `.system`.
    public var flagStyle: FlagStyle {
        get {
            let stored = integer(.flagStyle)
            if let style = FlagStyle(rawValue: stored) { return style }
            if stored != -1 { return .classic } // a removed style, such as Pixel
            return bool(.returnFlags, default: true) ? .classic : .system
        }
        set { store(newValue.rawValue, .flagStyle) }
    }

    public var showCursorIndicator: Bool {
        get { bool(.showCursorIndicator, default: true) }
        set { store(newValue, .showCursorIndicator) }
    }

    public var hideIndicatorWhileTyping: Bool {
        get { bool(.hideIndicatorWhileTyping, default: true) }
        set { store(newValue, .hideIndicatorWhileTyping) }
    }

    /// Mark the indicator and menu bar icon while Caps Lock is on.
    public var showCapsLockState: Bool {
        get { bool(.showCapsLockState, default: true) }
        set { store(newValue, .showCapsLockState) }
    }

    /// Input source IDs we already warned the user about.
    public var unsupportedInputSourceWarningsShown: [String] {
        get { defaults.stringArray(forKey: Key.unsupportedInputSourceWarningsShown.rawValue) ?? [] }
        set { store(newValue, .unsupportedInputSourceWarningsShown) }
    }

    /// Whether we already offered to add the Keyboard Viewer shortcut.
    public var keyboardViewerShortcutOffered: Bool {
        get { bool(.keyboardViewerShortcutOffered, default: false) }
        set { store(newValue, .keyboardViewerShortcutOffered) }
    }

    private func bool(_ key: Key, default value: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) as? Bool ?? value
    }

    /// Missing keys read as -1 so the enum getters fall back to their default case.
    private func integer(_ key: Key) -> Int {
        defaults.object(forKey: key.rawValue) as? Int ?? -1
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
