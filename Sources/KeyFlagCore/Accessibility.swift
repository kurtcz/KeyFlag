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

    /// The focused text input and its caret in screen coordinates (y up), or nil when
    /// nothing editable has focus or the app doesn't report where its caret is.
    public static func focusedCaret() -> (element: AXUIElement, rect: NSRect)? {
        guard let focusedValue = attribute(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        let focused = focusedValue as! AXUIElement
        guard let rect = caretRect(in: focused) else { return nil }
        return (focused, rect)
    }

    private static func caretRect(in focused: AXUIElement) -> NSRect? {
        guard isTextInput(focused),
              let rangeValue = attribute(focused, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }

        // The character before the caret, whose right edge is where the caret is, is the
        // most reliable: some apps (TextEdit) report an empty range a line too high.
        // After a line break that character is on the line above, so use the one after.
        if range.location > 0, !endsLine(at: range.location - 1, in: focused),
           let rect = bounds(of: CFRange(location: range.location - 1, length: 1), in: focused) {
            return NSRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
        }
        if let rect = bounds(of: CFRange(location: range.location, length: 1), in: focused), rect.width > 0 {
            return NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
        }
        if var rect = bounds(of: CFRange(location: range.location, length: 0), in: focused) {
            // Right after a line break at the end of the text, TextEdit reports the empty
            // range on the line of the break; the caret is on the line below it.
            if range.location > 0, endsLine(at: range.location - 1, in: focused),
               let lineBreak = bounds(of: CFRange(location: range.location - 1, length: 1), in: focused),
               rect.minY >= lineBreak.minY - 0.5 {
                rect.origin.y = lineBreak.minY - lineBreak.height
                rect.size.height = lineBreak.height
            }
            return NSRect(x: rect.minX, y: rect.minY, width: max(rect.width, 1), height: rect.height)
        }
        return nil
    }

    /// Whether the character at `index` is a line break (so the caret after it starts a new line).
    private static func endsLine(at index: Int, in element: AXUIElement) -> Bool {
        var range = CFRange(location: index, length: 1)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
              let string = value as? String else { return false }
        return string.unicodeScalars.allSatisfy(CharacterSet.newlines.contains)
    }

    /// The on-screen bounds of a text range, converted to screen coordinates (y up).
    private static func bounds(of range: CFRange, in element: AXUIElement) -> NSRect? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              let primary = NSScreen.screens.first else { return nil }
        return cocoaRect(fromAX: rect, primaryScreenHeight: primary.frame.maxY,
                         screens: NSScreen.screens.map(\.frame))
    }

    /// Converts an AX rectangle (top-left origin on the primary screen) to screen
    /// coordinates, rejecting the empty or off-screen rectangles some apps report.
    nonisolated static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat, screens: [NSRect]) -> NSRect? {
        guard rect.height > 0, rect.origin != .zero || rect.width > 0 else { return nil }
        let converted = NSRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
        let probe = NSPoint(x: converted.minX, y: converted.midY)
        guard screens.contains(where: { NSMouseInRect(probe, $0, false) }) else { return nil }
        return converted
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
