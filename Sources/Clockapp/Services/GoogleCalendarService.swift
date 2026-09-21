import Foundation
import CryptoKit
import AppKit
import Network

/// Google Calendar (read-only) via the OAuth 2.0 loopback flow for native apps
/// (PKCE + 127.0.0.1 redirect). Needs a "Desktop app" OAuth client's id + secret.
enum GoogleCalendarService {
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    // MARK: - Authorization

    /// Runs the browser consent flow and returns a long-lived refresh token.
    static func authorize(clientId: String, clientSecret: String) async throws -> String {
        let verifier = randomURLSafe(64)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        let loopback = OAuthLoopbackServer()
        let port = try await loopback.start()
        let redirect = "http://127.0.0.1:\(port)"

        var comps = URLComponents(string: authEndpoint)!
        comps.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let authURL = comps.url!
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }

        let code = try await loopback.waitForCode()
        loopback.stop()

        // Exchange the code for tokens.
        let tokens = try await postToken([
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = tokens.refreshToken else { throw GoogleError.noRefreshToken }
        return refresh
    }

    /// Exchanges a refresh token for a fresh access token.
    static func accessToken(clientId: String, clientSecret: String, refreshToken: String) async throws -> String {
        let tokens = try await postToken([
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        guard let access = tokens.accessToken else { throw GoogleError.tokenExchange("no access_token") }
        return access
    }

    // MARK: - Events

    /// Today's events as lines like "09:00–09:30 Standup" (all-day events marked).
    static func todaysEvents(accessToken: String, day: Date = Date()) async throws -> [String] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? day
        let iso = ISO8601DateFormatter()

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        comps.queryItems = [
            .init(name: "timeMin", value: iso.string(from: start)),
            .init(name: "timeMax", value: iso.string(from: end)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "50"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleError.events((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(EventsResponse.self, from: data)

        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        return decoded.items.compactMap { ev in
            let title = ev.summary ?? "(sans titre)"
            if let s = ev.start?.dateTime, let sd = iso.date(from: s) {
                let e = ev.end?.dateTime.flatMap(iso.date(from:))
                let range = e.map { "\(hm.string(from: sd))–\(hm.string(from: $0))" } ?? hm.string(from: sd)
                return "\(range) \(title)"
            } else if ev.start?.date != nil {
                return "toute la journée — \(title)"
            }
            return nil
        }
    }

    // MARK: - Helpers

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private static func postToken(_ params: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: tokenEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\(percentEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw GoogleError.tokenExchange("\((response as? HTTPURLResponse)?.statusCode ?? -1): \(msg.prefix(200))")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private struct EventsResponse: Decodable {
        let items: [Event]
        struct Event: Decodable {
            let summary: String?
            let start: When?
            let end: When?
            struct When: Decodable { let dateTime: String?; let date: String? }
        }
    }

    private static func randomURLSafe(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

enum GoogleError: LocalizedError {
    case noRefreshToken
    case tokenExchange(String)
    case events(Int)
    case timeout
    var errorDescription: String? {
        switch self {
        case .noRefreshToken: return "Aucun refresh token reçu (réessaie avec « consent »)."
        case .tokenExchange(let m): return "OAuth: \(m)"
        case .events(let s): return "Calendar API (\(s))."
        case .timeout: return "Autorisation expirée."
        }
    }
}

/// One-shot loopback HTTP server that captures the `?code=` OAuth redirect.
/// All mutable state is accessed on `queue` (serial), hence @unchecked Sendable.
final class OAuthLoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jules.clockapp.oauth")
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var finished = false

    /// Starts on an OS-assigned loopback port and returns it.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            do {
                let params = NWParameters.tcp
                params.requiredInterfaceType = .loopback
                let l = try NWListener(using: params)
                l.newConnectionHandler = { [weak self] c in self?.handle(c) }
                l.stateUpdateHandler = { state in
                    if case .ready = state, let p = l.port?.rawValue { cont.resume(returning: p) }
                    if case .failed(let e) = state { cont.resume(throwing: e) }
                }
                l.start(queue: queue)
                self.listener = l
            } catch { cont.resume(throwing: error) }
        }
    }

    /// Waits for the browser redirect and returns the authorization code.
    func waitForCode(timeout: TimeInterval = 300) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.awaitCode() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GoogleError.timeout
            }
            let code = try await group.next()!
            group.cancelAll()
            return code
        }
    }

    private func awaitCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            queue.async { self.codeContinuation = cont }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let requestLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let code = Self.queryValue("code", inRequestLine: requestLine)
            let ok = code != nil
            let body = ok
                ? "<h2>✅ Autorisé</h2><p>Tu peux fermer cette fenêtre et revenir à Clockapp.</p>"
                : "<h2>⚠️ Échec</h2><p>Aucun code reçu.</p>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })

            if !self.finished {
                self.finished = true
                if let code {
                    self.codeContinuation?.resume(returning: code)
                } else {
                    self.codeContinuation?.resume(throwing: GoogleError.tokenExchange("no code in redirect"))
                }
                self.codeContinuation = nil
            }
        }
    }

    /// Extracts a query param from an HTTP request line ("GET /?code=... HTTP/1.1").
    private static func queryValue(_ key: String, inRequestLine line: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let comps = URLComponents(string: "http://x\(parts[1])") else { return nil }
        return comps.queryItems?.first(where: { $0.name == key })?.value
    }
}
