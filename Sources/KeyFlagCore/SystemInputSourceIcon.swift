import AppKit
import Carbon
import ObjectiveC

/// The label icons macOS draws for its keyboard layouts in its own Input menu: "A", "US",
/// "РУ", "ف•", "א▸" and so on, as template images.
///
/// Apple's layouts report no icon through the Text Input Sources API. The icons come from
/// `KLInputSourceIconManager` in the private KeyboardLayouts framework, which also picks the
/// label: the least specific one that still tells the enabled layouts apart (US alone is "A",
/// US with British is "US" and "GB"). So the manager is built from the enabled layouts and
/// rebuilt when they change.
///
/// Everything is looked up at run time; if a macOS update renames or removes any of it,
/// `image(for:)` returns nil and callers fall back to their own badge.
@MainActor
enum SystemInputSourceIcon {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/KeyboardLayouts.framework/KeyboardLayouts"

    private typealias AllocIMP = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias InitIMP = @convention(c) (UnsafeMutableRawPointer, Selector, NSArray) -> UnsafeMutableRawPointer?
    private typealias ImageIMP = @convention(c) (AnyObject, Selector, TISInputSource) -> NSImage?

    private static let allocSelector = NSSelectorFromString("alloc")
    private static let initSelector = NSSelectorFromString("initWithEnableInputSources:")
    private static let imageSelector = NSSelectorFromString("imageForTISInputSource:")

    private static let managerClass: AnyClass? = {
        guard dlopen(frameworkPath, RTLD_LAZY) != nil,
              let cls = NSClassFromString("KLInputSourceIconManager"),
              class_getClassMethod(cls, allocSelector) != nil,
              class_getInstanceMethod(cls, initSelector) != nil,
              class_getInstanceMethod(cls, imageSelector) != nil else { return nil }
        return cls
    }()

    private static var manager: AnyObject?
    private static var managerSources: [String] = []

    /// macOS's icon for `source` as the Input menu would show it now, or nil if the system
    /// can't provide one.
    static func image(for source: InputSource) -> NSImage? {
        guard let manager = manager(including: source.id),
              let method = class_getInstanceMethod(object_getClass(manager), imageSelector) else { return nil }
        let imageFor = unsafeBitCast(method_getImplementation(method), to: ImageIMP.self)
        guard let image = imageFor(manager, imageSelector, source.ref),
              image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }

    /// A manager for the enabled sources, plus `id` in case it isn't enabled (e.g. a layout
    /// shown in the flag picker), rebuilt only when that list changes.
    private static func manager(including id: String) -> AnyObject? {
        guard let cls = managerClass else { return nil }
        var ids = InputSource.selectableKeyboardSources().map(\.id)
        if !ids.contains(id) { ids.append(id) }
        if let manager, ids == managerSources { return manager }

        guard let allocMethod = class_getClassMethod(cls, allocSelector),
              let initMethod = class_getInstanceMethod(cls, initSelector) else { return nil }
        let alloc = unsafeBitCast(method_getImplementation(allocMethod), to: AllocIMP.self)
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: InitIMP.self)
        // alloc and init hand back +1 references; take ownership of the result once.
        guard let allocated = alloc(cls, allocSelector),
              let initialized = initialize(allocated, initSelector, ids as NSArray) else { return nil }
        let created = Unmanaged<AnyObject>.fromOpaque(initialized).takeRetainedValue()
        manager = created
        managerSources = ids
        return created
    }
}
