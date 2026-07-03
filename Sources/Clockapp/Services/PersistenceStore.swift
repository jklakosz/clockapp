import Foundation

/// The full persisted app state (everything except the API key).
struct PersistedState: Codable {
    var settings = AppSettings()
    var goals = Goals()
    var windows: [TrackingWindow] = []
    var projects: [Project] = []
    /// Recent finished entries kept locally for stats & offline resync (capped).
    var recentEntries: [TimeEntry] = []
}

/// Reads / writes `PersistedState` as JSON in Application Support.
final class PersistenceStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clockapp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("state.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    func save(_ state: PersistedState) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var storageLocation: URL { fileURL }
}
