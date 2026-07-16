import Foundation
import Network

/// Minimal localhost HTTP/1.1 server backing the MCP bridge. Binds 127.0.0.1 only
/// (loopback) and requires a bearer token. One request per connection (Connection: close).
///
/// It knows nothing about the app: the owner passes an async `handler` that turns a
/// parsed request into a JSON response. This keeps all business logic in AppState.
final class LocalAPIServer {
    struct Request {
        let method: String
        let path: String
        let body: Data
        let authorized: Bool
    }
    struct Response {
        let status: Int
        let json: Any
        init(_ status: Int, _ json: Any) { self.status = status; self.json = json }
    }

    private let token: String
    private let handler: (Request) async -> Response
    private let queue = DispatchQueue(label: "com.jules.clockapp.localapi")
    private var listener: NWListener?
    private var onReady: ((UInt16) -> Void)?

    init(token: String, handler: @escaping (Request) async -> Response) {
        self.token = token
        self.handler = handler
    }

    /// Starts on an OS-assigned loopback port; `onReady` receives the actual port.
    func start(onReady: @escaping (UInt16) -> Void) throws {
        self.onReady = onReady
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = listener.port?.rawValue {
                self?.onReady?(port)
                self?.onReady = nil
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let (request, complete) = self.tryParse(buffer) {
                if complete {
                    Task { [weak self] in
                        guard let self else { return }
                        let response = await self.route(request)
                        self.send(conn, response)
                    }
                    return
                }
                // headers parsed but body not fully received yet → keep reading
            }

            if error != nil || isComplete {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: buffer)
        }
    }

    /// Returns (request, bodyComplete) once headers are present. `bodyComplete` is false
    /// while we still need more bytes to satisfy Content-Length.
    private func tryParse(_ buffer: Data) -> (Request, Bool)? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        let method = requestLine[0]
        let path = requestLine[1]

        var contentLength = 0
        var authorized = false
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let name = parts[0].lowercased()
            if name == "content-length" { contentLength = Int(parts[1]) ?? 0 }
            if name == "authorization" { authorized = parts[1] == "Bearer \(token)" }
        }

        let bodyStart = headerEnd.upperBound
        let received = buffer.distance(from: bodyStart, to: buffer.endIndex)
        let complete = received >= contentLength
        let body = complete ? buffer.subdata(in: bodyStart..<buffer.index(bodyStart, offsetBy: contentLength)) : Data()

        return (Request(method: method, path: path, body: body, authorized: authorized), complete)
    }

    private func route(_ request: Request) async -> Response {
        guard request.authorized else { return Response(401, ["error": "unauthorized"]) }
        return await handler(request)
    }

    private func send(_ conn: NWConnection, _ response: Response) {
        let bodyData = (try? JSONSerialization.data(withJSONObject: response.json)) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(bodyData)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 409: return "Conflict"
        default: return "Error"
        }
    }
}
