import Foundation

/// Thin async wrapper over the Clockify REST API (https://docs.clockify.me/).
final class ClockifyClient {
    var apiKey: String?
    var workspaceId: String = ""
    var userId: String = ""

    private let base = URL(string: "https://api.clockify.me/api/v1")!
    private let session: URLSession

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Clockify may or may not include fractional seconds; try both.
    static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoFractional.date(from: s)
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    // MARK: - Public API

    struct User: Decodable {
        let id: String
        let name: String?
        let email: String?
        let activeWorkspace: String?
        let defaultWorkspace: String?
    }

    func fetchUser() async throws -> User {
        try await request("/user", method: "GET")
    }

    func fetchProjects(workspaceId: String) async throws -> [Project] {
        var page = 1
        var all: [ProjectDTO] = []
        while true {
            let batch: [ProjectDTO] = try await request(
                "/workspaces/\(workspaceId)/projects?page-size=200&page=\(page)&archived=false",
                method: "GET")
            all.append(contentsOf: batch)
            if batch.count < 200 { break }
            page += 1
        }
        return all.map { Project(id: $0.id, name: $0.name, colorHex: $0.color, clientName: $0.clientName) }
    }

    /// Starts a running time entry (no end). Returns the Clockify entry id.
    func startEntry(description: String, projectId: String?, billable: Bool, start: Date) async throws -> String {
        var body: [String: Any] = [
            "start": Self.iso.string(from: start),
            "description": description,
            "billable": billable,
        ]
        if let projectId { body["projectId"] = projectId }
        let entry: EntryDTO = try await request(
            "/workspaces/\(workspaceId)/time-entries",
            method: "POST",
            body: body)
        return entry.id
    }

    /// Stops the currently running entry for the user.
    func stopRunningEntry(end: Date) async throws {
        let _: EntryDTO = try await request(
            "/workspaces/\(workspaceId)/user/\(userId)/time-entries",
            method: "PATCH",
            body: ["end": Self.iso.string(from: end)])
    }

    /// Creates an already-finished entry (used to push offline / auto entries in one shot).
    func createCompletedEntry(description: String, projectId: String?, billable: Bool,
                              start: Date, end: Date) async throws -> String {
        var body: [String: Any] = [
            "start": Self.iso.string(from: start),
            "end": Self.iso.string(from: end),
            "description": description,
            "billable": billable,
        ]
        if let projectId { body["projectId"] = projectId }
        let entry: EntryDTO = try await request(
            "/workspaces/\(workspaceId)/time-entries",
            method: "POST",
            body: body)
        return entry.id
    }

    /// Fetches the user's time entries overlapping [start, end), mapped to TimeEntry.
    /// Running entries keep `end == nil` so their live duration is counted by the caller.
    func fetchTimeEntries(start: Date, end: Date) async throws -> [TimeEntry] {
        var page = 1
        var all: [TimeEntry] = []
        let startStr = Self.iso.string(from: start)
        let endStr = Self.iso.string(from: end)
        while true {
            let path = "/workspaces/\(workspaceId)/user/\(userId)/time-entries"
                + "?start=\(startStr)&end=\(endStr)&page-size=1000&page=\(page)"
            let batch: [TimeEntryDTO] = try await request(path, method: "GET")
            all.append(contentsOf: batch.map { dto in
                TimeEntry(
                    id: dto.id,
                    start: Self.parseDate(dto.timeInterval.start) ?? start,
                    end: dto.timeInterval.end.flatMap(Self.parseDate),
                    description: dto.description ?? "",
                    projectId: dto.projectId,
                    billable: dto.billable ?? false,
                    source: .manual,
                    syncState: .synced)
            })
            if batch.count < 1000 { break }
            page += 1
        }
        return all
    }

    /// Returns the project id of the user's most recent time entry (any date).
    /// Clockify returns entries most-recent-first, so we take the first one carrying a project.
    func fetchMostRecentProjectId() async throws -> String? {
        let path = "/workspaces/\(workspaceId)/user/\(userId)/time-entries?page-size=20&page=1"
        let batch: [TimeEntryDTO] = try await request(path, method: "GET")
        return batch.first(where: { $0.projectId != nil })?.projectId
    }

    /// Updates an existing time entry (times, description, project). PUT replaces the entry,
    /// so `end` is omitted for a still-running entry.
    func updateEntry(id: String, description: String, projectId: String?, billable: Bool,
                     start: Date, end: Date?) async throws {
        var body: [String: Any] = [
            "start": Self.iso.string(from: start),
            "description": description,
            "billable": billable,
        ]
        if let projectId { body["projectId"] = projectId }
        if let end { body["end"] = Self.iso.string(from: end) }
        _ = try await send("/workspaces/\(workspaceId)/time-entries/\(id)", method: "PUT", body: body)
    }

    func deleteEntry(id: String) async throws {
        _ = try await send("/workspaces/\(workspaceId)/time-entries/\(id)", method: "DELETE")
    }

    // MARK: - Networking

    /// Performs the request, validates the status, and returns the raw body (may be empty).
    @discardableResult
    private func send(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty else { throw ClockifyError.missingKey }
        guard let url = URL(string: base.absoluteString + path) else { throw ClockifyError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClockifyError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw ClockifyError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private func request<T: Decodable>(_ path: String, method: String, body: [String: Any]? = nil) async throws -> T {
        let data = try await send(path, method: method, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - DTOs

    private struct ProjectDTO: Decodable {
        let id: String
        let name: String
        let color: String?
        let clientName: String?
    }

    private struct EntryDTO: Decodable {
        let id: String
    }

    private struct TimeEntryDTO: Decodable {
        let id: String
        let description: String?
        let projectId: String?
        let billable: Bool?
        let timeInterval: TimeIntervalDTO

        struct TimeIntervalDTO: Decodable {
            let start: String
            let end: String?
        }
    }
}

enum ClockifyError: LocalizedError {
    case missingKey
    case badURL
    case noResponse
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Aucune clé API Clockify configurée."
        case .badURL: return "URL invalide."
        case .noResponse: return "Pas de réponse du serveur."
        case .http(let status, let message):
            if status == 401 { return "Clé API invalide (401)." }
            return "Erreur Clockify \(status): \(message)"
        }
    }
}
