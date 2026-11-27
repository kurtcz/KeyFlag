import AppKit
import Testing
@testable import KeyFlagCore

@MainActor
struct InputSourceIconTests {
    private func solidImage(_ color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private func pixel(_ image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB)
    }

    @Test func tintRecolorsOpaquePixels() throws {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let tinted = InputSourceIcon.tinted(solidImage(.black, size: NSSize(width: 8, height: 8)), color: red)
        let color = try #require(pixel(tinted))
        // Allow for color-space conversion in the offscreen context.
        #expect(color.redComponent > 0.9)
        #expect(color.greenComponent < 0.35)
        #expect(color.blueComponent < 0.35)
        #expect(color.alphaComponent > 0.9)
    }

    @Test func tintKeepsTransparentPixelsTransparent() throws {
        let tinted = InputSourceIcon.tinted(solidImage(.clear, size: NSSize(width: 8, height: 8)), color: .red)
        let color = try #require(pixel(tinted))
        #expect(color.alphaComponent < 0.01)
    }

    @Test func scaledKeepsAspectRatio() {
        let scaled = InputSourceIcon.scaled(solidImage(.black, size: NSSize(width: 32, height: 16)), toHeight: 12)
        #expect(scaled.size == NSSize(width: 24, height: 12))
    }

    @Test func textImageIsAtLeastSquare() {
        let image = InputSourceIcon.textImage("EN", height: 16)
        #expect(image.size.height == 16)
        #expect(image.size.width >= 16)
        #expect(image.isTemplate)
    }
}

struct TextFieldDetectorTests {
    @Test(arguments: ["AXTextField", "AXTextArea", "AXComboBox"])
    func textRolesAreTextInputs(role: String) {
        #expect(TextFieldDetector.isTextInput(role: role, subrole: nil, hasEditableAncestor: false))
    }

    @Test func searchFieldSubroleIsTextInput() {
        #expect(TextFieldDetector.isTextInput(role: "AXGroup", subrole: "AXSearchField", hasEditableAncestor: false))
    }

    @Test func editableWebContentIsTextInput() {
        #expect(TextFieldDetector.isTextInput(role: "AXStaticText", subrole: nil, hasEditableAncestor: true))
    }

    @Test(arguments: ["AXButton", "AXStaticText", "AXImage", "AXWindow"])
    func otherRolesAreNotTextInputs(role: String) {
        #expect(!TextFieldDetector.isTextInput(role: role, subrole: nil, hasEditableAncestor: false))
    }

    @Test func missingRoleIsNotTextInput() {
        #expect(!TextFieldDetector.isTextInput(role: nil, subrole: nil, hasEditableAncestor: false))
    }
}
