import Foundation

/// A single tracked interval. Mirrors a Clockify time entry once synced.
struct TimeEntry: Identifiable, Codable, Equatable {
    /// Local UUID string until pushed to Clockify, then replaced by the Clockify id.
    var id: String
    var start: Date
    var end: Date?
    var description: String
    var projectId: String?
    var billable: Bool
    var source: Source
    var syncState: SyncState

    enum Source: String, Codable {
        case manual
        case auto
    }

    enum SyncState: String, Codable {
        case local     // never sent to Clockify
        case synced    // exists on Clockify (running or completed)
        case pending   // needs to be (re)sent
        case failed    // last sync attempt failed
    }

    init(id: String = UUID().uuidString,
         start: Date,
         end: Date? = nil,
         description: String = "",
         projectId: String? = nil,
         billable: Bool = false,
         source: Source = .manual,
         syncState: SyncState = .local) {
        self.id = id
        self.start = start
        self.end = end
        self.description = description
        self.projectId = projectId
        self.billable = billable
        self.source = source
        self.syncState = syncState
    }

    var isRunning: Bool { end == nil }

    /// Duration up to `reference` for running entries, or fixed duration once ended.
    func duration(asOf reference: Date = Date()) -> TimeInterval {
        (end ?? reference).timeIntervalSince(start)
    }
}
