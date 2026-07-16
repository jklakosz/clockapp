import Foundation

/// Spawns and kills the Node MCP server as a child process. The app owns its lifecycle:
/// started when the MCP toggle turns on, terminated on toggle-off and app quit.
@MainActor
final class MCPProcessManager {
    /// Stable port the MCP *client* (Claude) connects to — keep it fixed so the
    /// configured URL never changes.
    static let mcpPort: UInt16 = 39217

    private var process: Process?
    private(set) var lastError: String?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Launches `node server.js`, passing the app's local API port + token via env.
    @discardableResult
    func start(appAPIPort: UInt16, token: String) -> Bool {
        stop()
        guard let node = Self.findNode() else {
            lastError = "Node.js introuvable (installe Node ou ajoute-le au PATH)."
            return false
        }
        guard let server = Self.serverScriptPath() else {
            lastError = "Serveur MCP introuvable (mcp/server.js non embarqué)."
            return false
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [server]
        var env = ProcessInfo.processInfo.environment
        env["APP_API_PORT"] = String(appAPIPort)
        env["APP_API_TOKEN"] = token
        env["MCP_PORT"] = String(Self.mcpPort)
        p.environment = env

        let errPipe = Pipe()
        p.standardError = errPipe
        p.terminationHandler = { [weak self] proc in
            if proc.terminationStatus != 0 {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8) ?? ""
                Task { @MainActor in self?.lastError = msg.isEmpty ? "Le serveur MCP s'est arrêté." : msg }
            }
        }

        do {
            try p.run()
            process = p
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// GUI apps get a minimal PATH, so probe the usual install locations directly.
    static func findNode() -> String? {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// server.js is bundled into the app under Resources/mcp/ by build-app.sh.
    static func serverScriptPath() -> String? {
        if let res = Bundle.main.resourcePath {
            let bundled = res + "/mcp/server.js"
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }
        return nil
    }
}
