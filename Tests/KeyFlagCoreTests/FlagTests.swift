import XCTest
@testable import KeyFlagCore

final class FlagTests: XCTestCase {
    private func country(_ layout: String, _ languages: [String]) -> String? {
        FlagMapping.countryCode(inputSourceID: "com.apple.keylayout.\(layout)", languages: languages)
    }

    func testLanguageGivesCountry() {
        XCTAssertEqual(country("US", ["en"]), "US")
        XCTAssertEqual(country("Czech-QWERTY", ["cs"]), "CZ")
        XCTAssertEqual(country("Russian", ["ru"]), "RU")
        XCTAssertEqual(country("Ukrainian-PC", ["uk"]), "UA")
        XCTAssertEqual(country("German", ["de"]), "DE")
    }

    func testLayoutsWhoseCountryDiffersFromTheirLanguage() {
        XCTAssertEqual(country("British", ["en"]), "GB")
        XCTAssertEqual(country("AfghanDari", ["fa"]), "AF")
        XCTAssertEqual(country("SwissGerman", ["de"]), "CH")
        XCTAssertEqual(country("Canadian-CSA", ["fr"]), "CA")
        XCTAssertEqual(country("Portuguese", ["pt"]), "PT")
    }

    func testInputMethodsAndLanguagelessLayoutsKeepTheirIcons() {
        XCTAssertNil(FlagMapping.countryCode(inputSourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", languages: ["ja"]))
        XCTAssertNil(country("UnicodeHexInput", [""]))
        XCTAssertNil(country("PinyinKeyboard", []))
    }

    func testFlagImages() {
        XCTAssertTrue(FlagArt.hasDrawing("CZ"))
        XCTAssertNotNil(FlagArt.image(countryCode: "JM", style: .classic)) // emoji fallback
        XCTAssertNil(FlagArt.image(countryCode: "X1", style: .classic))
        XCTAssertNil(FlagArt.image(countryCode: "DE", style: .system))
        for style in FlagStyle.allCases where style != .system {
            // Coats of arms are taller, but every style keeps the same width.
            let height: CGFloat = style == .coatOfArms ? 20 : 16
            XCTAssertEqual(FlagArt.image(countryCode: "DE", style: style, height: 16)?.size, NSSize(width: 19, height: height), "\(style)")
        }
    }

    func testFlagsThatUsedToFallBackToEmojiAreDrawn() {
        let codes = "AF AL DZ BT KH ET GH HT IR IQ KG MY MV MN MA MM NP PK WS KR LK TW TJ TO TM UZ".split(separator: " ")
        XCTAssertEqual(codes.count, 26)
        for code in codes {
            XCTAssertTrue(FlagArt.hasDrawing(String(code)), String(code))
        }
    }

    func testOnlyWavingFlagsAnimate() {
        XCTAssertEqual(FlagArt.frames(countryCode: "CZ", style: .waving)?.count, 16)
        XCTAssertEqual(FlagArt.frames(countryCode: "CZ", style: .classic)?.count, 1)
        XCTAssertEqual(FlagArt.frames(countryCode: "JM", style: .waving)?.count, 1) // emoji already waves
    }
}
