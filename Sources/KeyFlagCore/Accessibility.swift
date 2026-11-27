import AppKit
import ApplicationServices

public enum Accessibility {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that sends the user to Privacy & Security > Accessibility.
    public static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 treats as mutable global state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// Decides whether the pointer is over a text input, using the Accessibility API.
@MainActor
public enum TextFieldDetector {
    nonisolated static let textRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
        kAXComboBoxRole,
    ]

    /// Pure classification, separated out so it can be unit tested.
    nonisolated public static func isTextInput(role: String?, subrole: String?, hasEditableAncestor: Bool) -> Bool {
        if let role, textRoles.contains(role) { return true }
        if subrole == "AXSearchField" { return true }
        // Web content (contenteditable, rich editors) reports AXEditableAncestor.
        return hasEditableAncestor
    }

    public static func isTextElementUnderMouse() -> Bool {
        guard let element = elementAtMouse() else { return false }
        return isTextInput(element)
    }

    public static func isFocusedElementTextInput() -> Bool {
        guard let focused = attribute(systemWide, kAXFocusedUIElementAttribute) else { return false }
        return isTextInput(focused as! AXUIElement)
    }

    // MARK: - Accessibility queries

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // Don't stall on apps that are slow to answer.
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }()

    static func elementAtMouse() -> AXUIElement? {
        // AX uses top-left origin coordinates relative to the primary screen.
        guard let primary = NSScreen.screens.first else { return nil }
        let mouse = NSEvent.mouseLocation
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(mouse.x), Float(primary.frame.maxY - mouse.y), &element)
        return error == .success ? element : nil
    }

    static func isTextInput(_ element: AXUIElement) -> Bool {
        isTextInput(
            role: attribute(element, kAXRoleAttribute) as? String,
            subrole: attribute(element, kAXSubroleAttribute) as? String,
            hasEditableAncestor: attribute(element, "AXEditableAncestor") != nil
        )
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
