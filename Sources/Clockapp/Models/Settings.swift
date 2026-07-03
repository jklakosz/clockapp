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

    init() {}

    private enum CodingKeys: String, CodingKey {
        case autoTrackEnabled, nudgesEnabled, showSecondsInMenuBar
        case workspaceId, userId, defaultProjectId
        case useLastProjectAsDefault, lastUsedProjectId, language
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
