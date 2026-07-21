import Foundation

/// Persisted app preferences (everything except the API key, which lives in the Keychain).
struct AppSettings: Codable, Equatable {
    var autoTrackEnabled = false
    var nudgesEnabled = false
    var showSecondsInMenuBar = true
    var workspaceId = ""
    var userId = ""
    var defaultProjectId: String?
    /// When true, the effective default project is whatever was tracked most recently.
    var useLastProjectAsDefault = false
    var lastUsedProjectId: String?
    var language: AppLanguage = .detected()
    /// When true, the updater also offers pre-releases (release candidates).
    var receivePrereleases = false
    /// When true, the app runs the local MCP server subprocess.
    var mcpEnabled = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case autoTrackEnabled, nudgesEnabled, showSecondsInMenuBar
        case workspaceId, userId, defaultProjectId
        case useLastProjectAsDefault, lastUsedProjectId, language
        case receivePrereleases, mcpEnabled
    }

    // Tolerant decoding: any missing key (e.g. a field added in a later version) falls
    // back to its default instead of throwing and wiping the whole settings file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoTrackEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoTrackEnabled) ?? false
        nudgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .nudgesEnabled) ?? false
        showSecondsInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showSecondsInMenuBar) ?? true
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        defaultProjectId = try c.decodeIfPresent(String.self, forKey: .defaultProjectId)
        useLastProjectAsDefault = try c.decodeIfPresent(Bool.self, forKey: .useLastProjectAsDefault) ?? false
        lastUsedProjectId = try c.decodeIfPresent(String.self, forKey: .lastUsedProjectId)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .detected()
        receivePrereleases = try c.decodeIfPresent(Bool.self, forKey: .receivePrereleases) ?? false
        mcpEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? false
    }
}

extension AppLanguage {
    /// Best-matching supported language from the Mac's preferred languages, else English.
    static func detected() -> AppLanguage {
        for lang in Locale.preferredLanguages {
            let code = lang.lowercased()
            if code.hasPrefix("fr") { return .fr }
            if code.hasPrefix("pt") { return .ptBR }
            if code.hasPrefix("it") { return .it }
            if code.hasPrefix("ar") { return .tn } // only Arabic variant we ship is Tunisian
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// Daily / weekly time goals, in minutes.
struct Goals: Codable, Equatable {
    var dailyMinutes: Int = 8 * 60
    var weeklyMinutes: Int = 40 * 60
    var enabled: Bool = false
}

enum Currency: String, Codable, CaseIterable, Identifiable {
    case eur, usd, gbp, chf, cad, aud, jpy
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .eur: return "€"
        case .usd: return "$"
        case .gbp: return "£"
        case .chf: return "CHF"
        case .cad: return "CA$"
        case .aud: return "A$"
        case .jpy: return "¥"
        }
    }

    /// € and CHF sit after the amount; the rest before.
    var symbolBefore: Bool { self != .eur && self != .chf }

    var displayName: String {
        switch self {
        case .eur: return "Euro (€)"
        case .usd: return "Dollar US ($)"
        case .gbp: return "Livre (£)"
        case .chf: return "Franc suisse (CHF)"
        case .cad: return "Dollar canadien (CA$)"
        case .aud: return "Dollar australien (A$)"
        case .jpy: return "Yen (¥)"
        }
    }
}

/// Earnings estimation from tracked time, with optional URSSAF (French social
/// contributions) deduction. Rates are configurable; the BNC micro-entrepreneur
/// rate is 26.1% in 2026.
struct Earnings: Codable, Equatable {
    var enabled: Bool = false
    var hourlyRate: Double = 0
    /// Currency of the hourly rate.
    var currency: Currency = .eur
    /// Currency to also display amounts in (converted via ECB rates).
    var convertTo: Currency = .usd
    var urssafEnabled: Bool = false
    var urssafRatePercent: Double = 26.1

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, hourlyRate, currency, convertTo, urssafEnabled, urssafRatePercent
    }

    // Tolerant decoding so adding fields never wipes saved earnings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        hourlyRate = try c.decodeIfPresent(Double.self, forKey: .hourlyRate) ?? 0
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? .eur
        convertTo = try c.decodeIfPresent(Currency.self, forKey: .convertTo) ?? .usd
        urssafEnabled = try c.decodeIfPresent(Bool.self, forKey: .urssafEnabled) ?? false
        urssafRatePercent = try c.decodeIfPresent(Double.self, forKey: .urssafRatePercent) ?? 26.1
    }

    /// Whether a currency conversion is meaningful (different target).
    var convertsCurrency: Bool { convertTo != currency }

    /// Gross amount for a given tracked duration.
    func gross(for seconds: TimeInterval) -> Double {
        (seconds / 3600.0) * hourlyRate
    }

    func urssaf(for seconds: TimeInterval) -> Double {
        urssafEnabled ? gross(for: seconds) * urssafRatePercent / 100.0 : 0
    }

    /// Net = gross minus the URSSAF contribution.
    func net(for seconds: TimeInterval) -> Double {
        gross(for: seconds) - urssaf(for: seconds)
    }
}
