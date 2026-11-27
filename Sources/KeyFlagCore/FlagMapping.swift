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
        "Welsh": SpecialFlag.wales,
    ]

    /// The override value that keeps macOS's own icon for a layout (Settings.flagOverrides).
    public static let systemIconOverride = "system"

    /// Like `countryCode(inputSourceID:languages:)`, but a flag the user picked for this
    /// input source wins. Overrides apply to any source, input methods included.
    public static func countryCode(inputSourceID id: String, languages: [String], overrides: [String: String]) -> String? {
        if let chosen = overrides[id] {
            return chosen == systemIconOverride ? nil : chosen
        }
        return countryCode(inputSourceID: id, languages: languages)
    }

    /// Countries that can be picked as a layout's flag: two-letter ISO 3166 regions with a
    /// name, sorted by that name in the user's language. The eurozone (EZ) is left out: it has
    /// no flag of its own, and the European Union (EU) is listed.
    public static func selectableCountries(locale: Locale = .current) -> [(code: String, name: String)] {
        Locale.Region.isoRegions.compactMap { region -> (code: String, name: String)? in
            let code = region.identifier
            guard code.count == 2, code != "EZ", code.allSatisfy({ $0.isASCII && $0.isUppercase }),
                  let name = locale.localizedString(forRegionCode: code), name != code else { return nil }
            return (code, name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Display name for a flag code: the country's name for an ISO code, the catalog name for
    /// a regional or historical flag.
    public static func name(forFlag code: String, locale: Locale = .current) -> String? {
        if let special = SpecialFlag.withCode(code) { return special.name }
        return locale.localizedString(forRegionCode: code)
    }

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

/// Flags with no ISO 3166 country code that can still be picked for a layout: nations and
/// regions within countries, peoples, and states that no longer exist. Their codes are stored
/// in Settings.flagOverrides like country codes; ISO 3166-2 codes where one exists
/// ("GB-WLS"), otherwise a descriptive one ("HIST-USSR"). None is two letters, so they can't
/// clash with a country.
public struct SpecialFlag: Equatable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case regional = "Regional"
        case monarchy = "Old Monarchies"
        case historical = "Historical"
    }

    public let code: String
    public let name: String
    public let group: Group
    /// Short text for the letter badge (Flags → Off) and anywhere a code is shown.
    public let badge: String
    /// The emoji, for the few that have one (England, Scotland, Wales); the others use their
    /// drawing in the Emoji style too.
    public let emoji: String?

    public static let wales = "GB-WLS"

    /// Black flag + the subdivision's tag characters + cancel tag: how Unicode spells the
    /// England, Scotland and Wales flags.
    private static func tagSequence(_ subdivision: String) -> String {
        var scalars: [Unicode.Scalar] = [Unicode.Scalar(0x1F3F4)!]
        scalars += subdivision.lowercased().unicodeScalars.compactMap { Unicode.Scalar(0xE0000 + $0.value) }
        scalars.append(Unicode.Scalar(0xE007F)!)
        return String(String.UnicodeScalarView(scalars))
    }

    public static let all: [SpecialFlag] = [
        SpecialFlag(code: "GB-ENG", name: "England", group: .regional, badge: "ENG", emoji: tagSequence("gbeng")),
        SpecialFlag(code: "GB-SCT", name: "Scotland", group: .regional, badge: "SCT", emoji: tagSequence("gbsct")),
        SpecialFlag(code: wales, name: "Wales", group: .regional, badge: "WLS", emoji: tagSequence("gbwls")),
        SpecialFlag(code: "GB-NIR", name: "Northern Ireland (Ulster Banner)", group: .regional, badge: "NIR", emoji: nil),
        SpecialFlag(code: "GB-CON", name: "Cornwall", group: .regional, badge: "KW", emoji: nil),
        SpecialFlag(code: "FR-BRE", name: "Brittany", group: .regional, badge: "BZH", emoji: nil),
        SpecialFlag(code: "ES-CT", name: "Catalonia", group: .regional, badge: "CAT", emoji: nil),
        SpecialFlag(code: "ES-PV", name: "Basque Country", group: .regional, badge: "EUS", emoji: nil),
        SpecialFlag(code: "CA-QC", name: "Quebec", group: .regional, badge: "QC", emoji: nil),
        SpecialFlag(code: "KURDISTAN", name: "Kurdistan", group: .regional, badge: "KU", emoji: nil),
        SpecialFlag(code: "SAPMI", name: "Sápmi", group: .regional, badge: "SÁ", emoji: nil),

        SpecialFlag(code: "HIST-AUSTRIAN-EMPIRE", name: "Austrian Empire", group: .monarchy, badge: "AT", emoji: nil),
        SpecialFlag(code: "HIST-HRE", name: "Holy Roman Empire", group: .monarchy, badge: "HRE", emoji: nil),
        SpecialFlag(code: "HIST-BAVARIA", name: "Kingdom of Bavaria", group: .monarchy, badge: "BY", emoji: nil),
        SpecialFlag(code: "HIST-FRANCE-KINGDOM", name: "Kingdom of France", group: .monarchy, badge: "FR", emoji: nil),
        SpecialFlag(code: "HIST-GREECE-KINGDOM", name: "Kingdom of Greece", group: .monarchy, badge: "GR", emoji: nil),
        SpecialFlag(code: "HIST-HANOVER", name: "Kingdom of Hanover", group: .monarchy, badge: "HAN", emoji: nil),
        SpecialFlag(code: "HIST-HUNGARY-KINGDOM", name: "Kingdom of Hungary", group: .monarchy, badge: "HU", emoji: nil),
        SpecialFlag(code: "HIST-ITALY-KINGDOM", name: "Kingdom of Italy", group: .monarchy, badge: "IT", emoji: nil),
        SpecialFlag(code: "HIST-POLAND-KINGDOM", name: "Kingdom of Poland", group: .monarchy, badge: "PL", emoji: nil),
        SpecialFlag(code: "HIST-PORTUGAL-KINGDOM", name: "Kingdom of Portugal", group: .monarchy, badge: "PT", emoji: nil),
        SpecialFlag(code: "HIST-PRUSSIA", name: "Kingdom of Prussia", group: .monarchy, badge: "PR", emoji: nil),
        SpecialFlag(code: "HIST-ROMANIA-KINGDOM", name: "Kingdom of Romania", group: .monarchy, badge: "RO", emoji: nil),
        SpecialFlag(code: "HIST-SARDINIA", name: "Kingdom of Sardinia (Savoy)", group: .monarchy, badge: "SAV", emoji: nil),
        SpecialFlag(code: "HIST-SAXONY", name: "Kingdom of Saxony", group: .monarchy, badge: "SX", emoji: nil),
        SpecialFlag(code: "HIST-SERBIA-KINGDOM", name: "Kingdom of Serbia", group: .monarchy, badge: "RS", emoji: nil),
        SpecialFlag(code: "HIST-WURTTEMBERG", name: "Kingdom of Württemberg", group: .monarchy, badge: "WÜ", emoji: nil),
        SpecialFlag(code: "HIST-YUGOSLAVIA-KINGDOM", name: "Kingdom of Yugoslavia", group: .monarchy, badge: "YU", emoji: nil),
        SpecialFlag(code: "HIST-AUSTRIA-HUNGARY", name: "Austria-Hungary", group: .monarchy, badge: "AH", emoji: nil),
        SpecialFlag(code: "HIST-BOHEMIA", name: "Bohemia", group: .monarchy, badge: "BOH", emoji: nil),
        SpecialFlag(code: "HIST-CZECHOSLOVAKIA", name: "Czechoslovakia", group: .historical, badge: "CS", emoji: nil),
        SpecialFlag(code: "HIST-GDR", name: "East Germany", group: .historical, badge: "DDR", emoji: nil),
        SpecialFlag(code: "HIST-GERMAN-EMPIRE", name: "German Empire", group: .monarchy, badge: "DR", emoji: nil),
        SpecialFlag(code: "HIST-OTTOMAN", name: "Ottoman Empire", group: .monarchy, badge: "OE", emoji: nil),
        SpecialFlag(code: "HIST-PERSIA", name: "Persia (Lion and Sun)", group: .monarchy, badge: "IR", emoji: nil),
        SpecialFlag(code: "HIST-RUSSIAN-EMPIRE", name: "Russian Empire", group: .monarchy, badge: "RU", emoji: nil),
        SpecialFlag(code: "HIST-USSR", name: "Soviet Union", group: .historical, badge: "SU", emoji: nil),
        SpecialFlag(code: "HIST-YUGOSLAVIA", name: "Yugoslavia", group: .historical, badge: "YU", emoji: nil),
    ]

    public static func withCode(_ code: String) -> SpecialFlag? {
        all.first { $0.code == code }
    }

    public static func inGroup(_ group: Group) -> [SpecialFlag] {
        all.filter { $0.group == group }
    }
}
