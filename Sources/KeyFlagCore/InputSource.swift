import Carbon
import Foundation

/// A keyboard layout or input method, wrapping Carbon's Text Input Sources API.
public struct InputSource: @unchecked Sendable, Equatable {
    public let ref: TISInputSource

    public init(_ ref: TISInputSource) {
        self.ref = ref
    }

    public static func == (lhs: InputSource, rhs: InputSource) -> Bool {
        lhs.id == rhs.id
    }

    public var id: String { string(kTISPropertyInputSourceID) ?? "" }
    public var localizedName: String { string(kTISPropertyLocalizedName) ?? id }
    public var languages: [String] { object(kTISPropertyInputSourceLanguages) as? [String] ?? [] }
    public var isKeyboardInputSource: Bool { string(kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String) }
    public var isSelectCapable: Bool { bool(kTISPropertyInputSourceIsSelectCapable) }
    public var isEnabled: Bool { bool(kTISPropertyInputSourceIsEnabled) }
    public var iconImageURL: URL? { object(kTISPropertyIconImageURL) as? URL }
    public var iconRef: IconRef? { property(kTISPropertyIconRef).map(OpaquePointer.init) }

    @discardableResult
    public func select() -> Bool {
        TISSelectInputSource(ref) == noErr
    }

    @discardableResult
    public func enable() -> Bool {
        TISEnableInputSource(ref) == noErr
    }

    // MARK: - Lookup

    public static var current: InputSource {
        InputSource(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    /// Enabled keyboard layouts and input methods the user can switch to, sorted by name.
    public static func selectableKeyboardSources() -> [InputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
        ]
        return list(filter: filter, includeAllInstalled: false)
            .filter(\.isEnabled)
            .sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    public static func withID(_ id: String) -> InputSource? {
        list(filter: [kTISPropertyInputSourceID as String: id], includeAllInstalled: true).first
    }

    private static func list(filter: [String: Any], includeAllInstalled: Bool) -> [InputSource] {
        guard let unmanaged = TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled) else { return [] }
        let array = unmanaged.takeRetainedValue() as NSArray
        // Elements are TISInputSourceRefs; bridge them through CF.
        return array.map { InputSource($0 as! TISInputSource) }
    }

    // MARK: - Properties

    private func property(_ key: CFString) -> UnsafeMutableRawPointer? {
        TISGetInputSourceProperty(ref, key)
    }

    private func object(_ key: CFString) -> AnyObject? {
        property(key).map { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() }
    }

    private func string(_ key: CFString) -> String? {
        object(key) as? String
    }

    private func bool(_ key: CFString) -> Bool {
        (object(key) as? NSNumber)?.boolValue ?? false
    }
}

/// Posts `InputSourceMonitor.didChangeNotification` on the default center when the selected
/// input source changes, once the new one can actually be read.
///
/// The system's distributed notification can arrive before `TISCopyCurrentKeyboardInputSource`
/// returns the new source in a background app like ours, so anything that read it right away
/// showed the old layout, and the menu bar and layout flash kept it until the next switch. So
/// the monitor re-reads the source a few times after each notification and posts only when the
/// ID differs from the last one it reported. A slow poll catches switches whose notification
/// never reaches us.
@MainActor
public final class InputSourceMonitor {
    public static let didChangeNotification = Notification.Name("KeyFlagInputSourceDidChange")

    /// When to re-read the source after a system notification, in seconds.
    static let recheckDelays: [TimeInterval] = [0, 0.05, 0.15, 0.4, 1]
    static let pollInterval: TimeInterval = 1

    private var token: NSObjectProtocol?
    private var pollTimer: Timer?
    private var lastID: String?

    public init() {}

    public func start() {
        guard token == nil else { return }
        lastID = InputSource.current.id
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.systemDidChange() }
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.check() }
        }
        timer.tolerance = Self.pollInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func systemDidChange() {
        for delay in Self.recheckDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { self.check() }
            }
        }
    }

    private func check() {
        let id = InputSource.current.id
        guard Self.shouldPost(currentID: id, lastID: lastID) else { return }
        lastID = id
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    nonisolated static func shouldPost(currentID: String, lastID: String?) -> Bool {
        !currentID.isEmpty && currentID != lastID
    }
}
