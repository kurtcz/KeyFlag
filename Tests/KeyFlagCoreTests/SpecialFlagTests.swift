import AppKit
import Testing
@testable import KeyFlagCore

@MainActor
struct SpecialFlagTests {
    @Test func everySpecialFlagIsDrawnInEveryStyle() {
        for flag in SpecialFlag.all {
            #expect(FlagArt.hasDrawing(flag.code), "\(flag.code)")
            for style in [FlagStyle.classic, .emoji, .waving] {
                #expect(FlagArt.image(countryCode: flag.code, style: style) != nil, "\(flag.code) \(style)")
            }
        }
    }

    @Test func britishTerritoriesAreDrawn() {
        for code in "IM JE GG GI BM KY VG AI MS TC FK SH IO PN GS".split(separator: " ") {
            #expect(FlagArt.hasDrawing(String(code)), "\(code)")
        }
    }

    @Test func codesAndBadgesAreUnique() {
        #expect(Set(SpecialFlag.all.map(\.code)).count == SpecialFlag.all.count)
        #expect(SpecialFlag.all.allSatisfy { !$0.badge.isEmpty && $0.badge.count <= 3 })
        #expect(SpecialFlag.Group.allCases.allSatisfy { !SpecialFlag.inGroup($0).isEmpty })
    }

    @Test func homeNationsHaveEmojiOthersDoNot() {
        for code in ["GB-ENG", "GB-SCT", "GB-WLS"] {
            #expect(SpecialFlag.withCode(code)?.emoji?.unicodeScalars.first?.value == 0x1F3F4)
        }
        #expect(SpecialFlag.withCode("CA-QC")?.emoji == nil)
    }

    @Test func namesAndAbbreviations() {
        let en = Locale(identifier: "en_US")
        #expect(FlagMapping.name(forFlag: "CA-QC", locale: en) == "Quebec")
        #expect(FlagMapping.name(forFlag: "HIST-FRANCE-KINGDOM", locale: en) == "Kingdom of France")
        #expect(FlagMapping.name(forFlag: "CZ", locale: en) == "Czechia")
        #expect(SpecialFlag.withCode("HIST-BAVARIA")?.group == .monarchy)
        #expect(SpecialFlag.withCode("HIST-USSR")?.group == .historical)
    }

    @Test func welshLayoutShowsWales() {
        #expect(FlagMapping.countryCode(inputSourceID: "com.apple.keylayout.Welsh", languages: ["cy"], overrides: [:]) == SpecialFlag.wales)
    }

    /// Writes every special flag at a large size when KEYFLAG_RENDER_DIR is set, for eyeballing.
    @Test func renderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["KEYFLAG_RENDER_DIR"] else { return }
        let codes = SpecialFlag.all.map(\.code) + "IM JE GG GI BM KY VG AI MS TC FK SH IO PN GS".split(separator: " ").map(String.init)
        for code in codes {
            let image = try #require(FlagArt.image(countryCode: code, style: .classic, height: 96))
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(code).png"))
        }
    }
}
