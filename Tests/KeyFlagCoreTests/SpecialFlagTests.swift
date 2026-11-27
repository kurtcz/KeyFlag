import AppKit
import Testing
@testable import KeyFlagCore

@MainActor
struct SpecialFlagTests {
    @Test func everySpecialFlagIsDrawnInEveryStyle() {
        for flag in SpecialFlag.all {
            #expect(FlagArt.hasDrawing(flag.code), "\(flag.code)")
            for style in [FlagStyle.classic, .emoji, .waving, .coatOfArms] {
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

    @Test func eurozoneIsNotSelectable() {
        let codes = FlagMapping.selectableCountries(locale: Locale(identifier: "en_US")).map(\.code)
        #expect(!codes.contains("EZ"))
        #expect(codes.contains("EU"))
    }

    @Test func welshLayoutShowsWales() {
        #expect(FlagMapping.countryCode(inputSourceID: "com.apple.keylayout.Welsh", languages: ["cy"], overrides: [:]) == SpecialFlag.wales)
    }

    @Test func coatOfArmsDrawsShieldsAndFallsBack() throws {
        for code in ["CZ", "SK", "GB", "US", "HIST-BAVARIA", "CA-QC"] {
            #expect(FlagArt.hasCoatOfArms(code), "\(code)")
        }
        #expect(!FlagArt.hasCoatOfArms("JP"))
        // As wide as the flags, so the menu bar doesn't jump when switching styles, but
        // taller, so the shields aren't tiny.
        let arms = try #require(FlagArt.image(countryCode: "CZ", style: .coatOfArms))
        #expect(arms.size.width == FlagArt.canvasSize(height: 16).width)
        #expect(arms.size.height == 20)
        // Emblems that were unreadable at this size were dropped in favor of the flag.
        for code in ["BY", "FR", "HIST-OTTOMAN", "HIST-AUSTRIA-HUNGARY"] {
            #expect(!FlagArt.hasCoatOfArms(code), "\(code)")
            #expect(FlagArt.image(countryCode: code, style: .coatOfArms)?.size.height == 16, "\(code)")
        }
        // No arms: the emoji, or the drawn flag for a special flag without an emoji.
        #expect(FlagArt.image(countryCode: "JP", style: .coatOfArms) != nil)
        #expect(FlagArt.image(countryCode: "SAPMI", style: .coatOfArms) != nil)
    }

    @Test func everyBundledWikimediaImageLoads() throws {
        let root = try #require(WikimediaArt.resourceRoot)
        for kind in [WikimediaArt.Kind.flag, .coatOfArms] {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(kind.rawValue).path)
                .filter { $0.hasSuffix(".png") }
            #expect(files.count > 70, "\(kind)")
            for file in files {
                let code = String(file.dropLast(4))
                #expect(WikimediaArt.image(kind, code: code) != nil, "\(kind) \(code)")
                #expect(kind == .coatOfArms || FlagArt.hasDrawing(code), "\(code)")
            }
        }
        #expect(WikimediaArt.image(.flag, code: "GB-WLS") != nil)
        #expect(WikimediaArt.image(.coatOfArms, code: "HIST-BOHEMIA") != nil)
    }

    @Test func coatOfArmsIsAStoredStyle() {
        #expect(FlagStyle(rawValue: 5) == .coatOfArms)
        #expect(FlagStyle.coatOfArms.title == "Coat of Arms")
    }

    /// Writes every special flag at a large size when KEYFLAG_RENDER_DIR is set, for eyeballing.
    @Test func renderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["KEYFLAG_RENDER_DIR"] else { return }
        let bundled = (try? FileManager.default.contentsOfDirectory(
            atPath: WikimediaArt.resourceRoot?.appendingPathComponent("Flags").path ?? "")) ?? []
        let codes = Set(SpecialFlag.all.map(\.code) + bundled.map { String($0.dropLast(4)) })
        for code in codes.sorted() {
            let image = try #require(FlagArt.image(countryCode: code, style: .classic, height: 96))
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(code).png"))
        }
    }

    /// Writes every coat of arms large when KEYFLAG_ARMS_DIR is set, for eyeballing.
    @Test func renderArmsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["KEYFLAG_ARMS_DIR"] else { return }
        let letters = (65...90).map { String(UnicodeScalar($0)!) }
        let codes = letters.flatMap { a in letters.map { a + $0 } } + SpecialFlag.all.map(\.code)
        for code in codes where FlagArt.hasCoatOfArms(code) {
            let height = Double(ProcessInfo.processInfo.environment["KEYFLAG_ARMS_HEIGHT"] ?? "") ?? 96
            let image = try #require(FlagArt.image(countryCode: code, style: .coatOfArms, height: height))
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(code).png"))
        }
    }
}
