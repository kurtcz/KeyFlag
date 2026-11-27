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

/// Re-posts the system's "selected input source changed" distributed notification
/// as `InputSourceMonitor.didChangeNotification` on the default center.
@MainActor
public final class InputSourceMonitor {
    public static let didChangeNotification = Notification.Name("KeyFlagInputSourceDidChange")

    private var token: NSObjectProtocol?

    public init() {}

    public func start() {
        guard token == nil else { return }
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }
}
