import Foundation

/// Generates short time-entry descriptions for a day by feeding the day's Claude Code
/// sessions (per mapped project folder) into a single `claude -p` invocation that
/// returns a JSON map `{ entryId: description }`.
enum AutoDescriptionService {
    struct EntryInfo {
        let id: String
        let timeRange: String
        let projectName: String?
        let currentDescription: String
    }

    // MARK: - Claude session directory encoding

    /// Claude Code stores sessions under `<root>/<encoded cwd>/*.jsonl`, where the cwd's
    /// non-alphanumeric characters (`/`, spaces, dots…) are replaced by `-`.
    static func encodedDir(for folderPath: String) -> String {
        String(folderPath.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// Extracted text from the sessions in `folderPath` that were active on `day`.
    static func sessionsText(root: String, folderPath: String, day: Date,
                             maxChars: Int = 14000) -> String {
        // Expand `~` so a typed path encodes to the same dir name Claude created.
        let absFolder = (folderPath as NSString).expandingTildeInPath
        let dir = (root as NSString).appendingPathComponent(encodedDir(for: absFolder))
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return "" }
        let cal = Calendar.current

        var out = ""
        for name in files.sorted() where name.hasSuffix(".jsonl") {
            let path = (dir as NSString).appendingPathComponent(name)
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let mod = attrs[.modificationDate] as? Date,
               !cal.isDate(mod, inSameDayAs: day) { continue }
            out += extractText(fromJSONL: path, day: day, cal: cal)
            if out.count >= maxChars { break }
        }
        return String(out.prefix(maxChars))
    }

    /// Pulls user prompts and assistant text (skipping tool noise) from a session file.
    private static func extractText(fromJSONL path: String, day: Date, cal: Calendar) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        var lines: [String] = []
        for raw in content.split(separator: "\n") {
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            guard type == "user" || type == "assistant" else { continue }
            guard let message = obj["message"] as? [String: Any] else { continue }
            let role = (message["role"] as? String) ?? (type ?? "")
            let text = textFromContent(message["content"])
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append("\(role == "user" ? "User" : "Assistant"): \(trimmed)")
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func textFromContent(_ content: Any?) -> String {
        if let s = content as? String { return s }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            if block["type"] as? String == "text" { return block["text"] as? String }
            return nil
        }.joined(separator: " ")
    }

    // MARK: - Prompt + invocation

    /// Prompt for a SINGLE entry: asks for just the one-line description text (no JSON).
    static func buildEntryPrompt(entry: EntryInfo, sessionText: String) -> String {
        let proj = entry.projectName.map { " [\($0)]" } ?? ""
        var p = """
        You write ONE short timesheet description for a single time entry, based on the
        Claude coding session context below. Return ONLY the description — one line, max
        ~140 chars, professional, timesheet-style, in the same language as the existing
        description (default English). No quotes, no JSON, no code fences, no preamble.

        ENTRY: \(entry.timeRange)\(proj)
        """
        if !entry.currentDescription.isEmpty {
            p += "\nExisting description: \(entry.currentDescription)"
        }
        if sessionText.isEmpty {
            p += "\n\n(No Claude session context available — infer from the entry above.)"
        } else {
            p += "\n\nClaude session context:\n\(sessionText)"
        }
        p += "\n\nDescription:"
        return p
    }

    /// Resolves a bare command (e.g. `claude`) to an absolute path, since a GUI app's
    /// environment has a minimal PATH. Custom commands (with a path, env prefix or args)
    /// are left untouched.
    static func resolveCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("="), !trimmed.contains(" ") else {
            return command
        }
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/\(trimmed)",
            "/usr/local/bin/\(trimmed)",
            "\(home)/.claude/local/\(trimmed)",
            "\(home)/.local/bin/\(trimmed)",
            "/usr/bin/\(trimmed)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? command
    }

    /// The process environment with common CLI install dirs prepended to PATH, so a
    /// custom command (e.g. `CLAUDE_CONFIG_DIR=… claude`) resolves without a login shell.
    private static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.claude/local",
            "\(home)/.local/bin",
            "/usr/bin",
            "/bin",
        ]
        let existing = env["PATH"].map { [$0] } ?? []
        env["PATH"] = (extra + existing).joined(separator: ":")
        return env
    }

    /// Runs `<command> -p` with the prompt and returns stdout. Non-blocking.
    ///
    /// Uses a plain `/bin/sh -c` (no zsh, no interactive shell — those source `~/.zshrc`,
    /// which is slow and can hang a GUI app). `$HOME` and env prefixes like
    /// `CLAUDE_CONFIG_DIR=… claude` still work; a bare `claude` is resolved to an absolute
    /// path, and PATH is enriched with the usual install dirs so custom commands resolve too.
    static func runClaude(command: String, prompt: String) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clockapp-adesc-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)
        let resolved = resolveCommand(command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(resolved) -p \"$(cat '\(tmp.path)')\""]
        process.environment = enrichedEnvironment()
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { proc in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                try? FileManager.default.removeItem(at: tmp)
                if proc.terminationStatus == 0 {
                    cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } else {
                    let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(throwing: AutoDescError.claudeFailed(e.isEmpty ? "exit \(proc.terminationStatus)" : e))
                }
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// Extracts a single one-line description from the model output: the last non-empty
    /// line, stripped of surrounding quotes/backticks and capped in length.
    static func parseSingleDescription(from output: String) -> String {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return "" }
        let stripped = last.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”"))
        return String(stripped.prefix(200))
    }
}

enum AutoDescError: LocalizedError {
    case claudeFailed(String)
    case noSessions
    var errorDescription: String? {
        switch self {
        case .claudeFailed(let m): return "Claude: \(m.prefix(200))"
        case .noSessions: return "Aucune session trouvée pour ce jour."
        }
    }
}
