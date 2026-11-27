import Foundation

/// Picks the country whose flag stands for a keyboard layout.
public enum FlagMapping {
    private static let layoutPrefix = "com.apple.keylayout."

    /// Layouts whose country differs from the one their language suggests
    /// (British is "en", which would otherwise give the US flag).
    static let layoutCountries: [String: String] = [
        "ABC-India": "IN",
        "AfghanDari": "AF",
        "Australian": "AU",
        "Austrian": "AT",
        "Belgian": "BE",
        "British": "GB",
        "British-PC": "GB",
        "Canadian": "CA",
        "Canadian-CSA": "CA",
        "CanadianFrench-PC": "CA",
        "Irish": "IE",
        "IrishExtended": "IE",
        "LatinAmerican": "MX",
        "NewZealand": "NZ",
        "Portuguese": "PT",
        "SwissFrench": "CH",
        "SwissGerman": "CH",
        "Welsh": "GB",
    ]

    /// An ISO 3166 country code such as "CZ", or nil when the source should keep its own
    /// icon: input methods (Japanese, Chinese, ...) and layouts without a language.
    public static func countryCode(inputSourceID id: String, languages: [String]) -> String? {
        guard id.hasPrefix(layoutPrefix) else { return nil }
        let name = String(id.dropFirst(layoutPrefix.count))
        if let country = layoutCountries[name] {
            return country
        }
        guard let language = languages.first, !language.isEmpty else { return nil }
        return region(forLanguage: language)
    }

    /// The most likely country for a language, e.g. "cs" → "CZ", "en" → "US".
    static func region(forLanguage language: String) -> String? {
        let maximal = Locale.Language(identifier: language).maximalIdentifier
        guard let last = maximal.split(separator: "-").last, last.count == 2,
              last.allSatisfy(\.isUppercase) else { return nil }
        return String(last)
    }
}
