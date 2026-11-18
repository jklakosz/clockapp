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

    /// One user/assistant message with its timestamp, so we can slice a folder's day of
    /// sessions down to a single entry's [start, end] window.
    struct SessionMessage {
        let date: Date
        let role: String   // "User" or "Assistant"
        let text: String
    }

    // MARK: - Claude session directory encoding

    /// Claude Code stores sessions under `<root>/<encoded cwd>/*.jsonl`, where the cwd's
    /// non-alphanumeric characters (`/`, spaces, dots…) are replaced by `-`.
    static func encodedDir(for folderPath: String) -> String {
        String(folderPath.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// All of `day`'s user/assistant messages (with timestamps) from the sessions in
    /// `folderPath`, sorted chronologically — so callers can slice them per entry window.
    static func sessionMessages(root: String, folderPath: String, day: Date) -> [SessionMessage] {
        // Expand `~` so a typed path encodes to the same dir name Claude created.
        let absFolder = (folderPath as NSString).expandingTildeInPath
        let dir = (root as NSString).appendingPathComponent(encodedDir(for: absFolder))
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)

        var out: [SessionMessage] = []
        for name in names where name.hasSuffix(".jsonl") {
            let path = (dir as NSString).appendingPathComponent(name)
            // A file last modified before `day` cannot hold `day`'s messages — skip it.
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mod = attrs[.modificationDate] as? Date, mod >= dayStart else { continue }
            out.append(contentsOf: messages(fromJSONL: path, day: day, cal: cal))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Joins the messages whose timestamp falls in [start, end] into a session context
    /// block (chronological), capped at `maxChars`.
    static func windowText(_ messages: [SessionMessage], start: Date, end: Date,
                           maxChars: Int = 14000) -> String {
        var out = ""
        for m in messages where m.date >= start && m.date <= end {
            out += "\(m.role): \(m.text)\n"
            if out.count >= maxChars { break }
        }
        return String(out.prefix(maxChars))
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// Parses the user/assistant messages (skipping tool noise) timestamped on `day` from a
    /// session file — a resumed session file can span many days, so we filter per message.
    private static func messages(fromJSONL path: String, day: Date, cal: Calendar) -> [SessionMessage] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var out: [SessionMessage] = []
        for raw in content.split(separator: "\n") {
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            guard type == "user" || type == "assistant" else { continue }
            guard let ts = obj["timestamp"] as? String,
                  let date = isoWithFractional.date(from: ts) ?? isoPlain.date(from: ts),
                  cal.isDate(date, inSameDayAs: day) else { continue }
            guard let message = obj["message"] as? [String: Any] else { continue }
            let role = (message["role"] as? String) ?? (type ?? "")
            let text = textFromContent(message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            out.append(SessionMessage(date: date, role: role == "user" ? "User" : "Assistant", text: text))
        }
        return out
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

    /// The default, user-editable prompt template. Placeholders (`{{…}}`) are filled per
    /// entry by `buildEntryPrompt`: {{day}}, {{timeRange}}, {{project}},
    /// {{existingDescription}}, {{sessionContext}}.
    static let defaultPromptTemplate = """
    You write ONE short timesheet description for a single time entry.

    Rules:
    - Write in ENGLISH, professional timesheet style, one line, max ~140 chars.
    - Do NOT use em dashes (—) or en dashes (–). Use commas, "and", or a colon instead.
    - Return ONLY the description text: no quotes, no JSON, no code fences, no preamble.
    - FIRST use your Google Calendar tools: list your calendars (including shared work \
    calendars) and find meetings/events overlapping this entry's window on {{day}}. \
    Consider ONLY those meetings that have been accepted (your response status is accepted). \
    Do this even when there is session content; ignore all-day, PTO and clearly personal \
    events. If the calendar tools are unavailable, skip this step.
    - If there is NO relevant Claude session content AND NO accepted meeting for this entry, \
    respond EXACTLY with: No session/meeting

    ENTRY: {{timeRange}} on {{day}} for project {{project}}
    {{existingDescription}}

    {{sessionContext}}

    Description:
    """

    /// Prompt for a SINGLE entry: fills `template`'s placeholders and asks for just the
    /// one-line description text (no JSON).
    static func buildEntryPrompt(entry: EntryInfo, sessionText: String, day: Date, template: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd (EEEE)"; df.locale = Locale(identifier: "en_US")
        let existing = entry.currentDescription.isEmpty ? "" : "Existing description: \(entry.currentDescription)"
        let session = sessionText.isEmpty
            ? "(No Claude session text for this entry's project on this day.)"
            : "Claude session context (this project, whole day):\n\(sessionText)"
        return template
            .replacingOccurrences(of: "{{day}}", with: df.string(from: day))
            .replacingOccurrences(of: "{{timeRange}}", with: entry.timeRange)
            .replacingOccurrences(of: "{{project}}", with: entry.projectName ?? "no specific project")
            .replacingOccurrences(of: "{{existingDescription}}", with: existing)
            .replacingOccurrences(of: "{{sessionContext}}", with: session)
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

    /// Google Calendar (read-only) MCP tools the agent may use to pull the entry's meetings.
    /// Passed as `--allowedTools …` so `claude -p` doesn't prompt. If the agent's config has
    /// no such connector, the flag is harmless and the agent proceeds without calendar.
    static let googleCalendarTools = [
        "mcp__claude_ai_Google_Calendar__list_events",
        "mcp__claude_ai_Google_Calendar__list_calendars",
        "mcp__claude_ai_Google_Calendar__search_events",
    ]

    /// Runs `<command> -p` with the prompt and returns stdout. Non-blocking.
    ///
    /// Uses a plain `/bin/sh -c` (no zsh, no interactive shell — those source `~/.zshrc`,
    /// which is slow and can hang a GUI app). `$HOME` and env prefixes like
    /// `CLAUDE_CONFIG_DIR=… claude` still work; a bare `claude` is resolved to an absolute
    /// path, and PATH is enriched with the usual install dirs so custom commands resolve too.
    /// `allowedTools`, when set, is appended as `--allowedTools t1 t2 …` (names are safe idents).
    static func runClaude(command: String, prompt: String, allowedTools: [String] = []) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clockapp-adesc-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)
        let resolved = resolveCommand(command)
        let toolsFlag = allowedTools.isEmpty ? "" : " --allowedTools " + allowedTools.joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(resolved) -p \"$(cat '\(tmp.path)')\"\(toolsFlag)"]
        process.environment = enrichedEnvironment()
        // No stdin: `claude` otherwise waits ~3s for piped input before proceeding.
        process.standardInput = FileHandle.nullDevice
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
