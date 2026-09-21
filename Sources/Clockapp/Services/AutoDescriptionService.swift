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
        let dir = (root as NSString).appendingPathComponent(encodedDir(for: folderPath))
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

    static func buildPrompt(entries: [EntryInfo],
                            folderContexts: [(project: String, text: String)],
                            calendar: String?) -> String {
        var p = """
        You write short timesheet descriptions of what was worked on during time entries.
        Given the day's entries and the context (Claude coding sessions and meetings),
        return ONLY a JSON object mapping each entry id to a concise one-line description
        (max ~140 chars, professional, timesheet-style, in the same language as the
        existing descriptions — default English). No prose, no code fences, JSON only.

        ENTRIES:
        """
        for e in entries {
            let proj = e.projectName.map { " [\($0)]" } ?? ""
            let cur = e.currentDescription.isEmpty ? "" : " (current: \(e.currentDescription))"
            p += "\n- id=\(e.id) | \(e.timeRange)\(proj)\(cur)"
        }
        if let calendar, !calendar.isEmpty {
            p += "\n\nMEETINGS TODAY:\n\(calendar)"
        }
        for ctx in folderContexts where !ctx.text.isEmpty {
            p += "\n\n### Claude sessions — \(ctx.project)\n\(ctx.text)"
        }
        p += "\n\nReturn the JSON now:"
        return p
    }

    /// Runs `<command> -p` with the prompt (via a login shell so PATH resolves `claude`),
    /// returning stdout. Non-blocking.
    static func runClaude(command: String, prompt: String) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clockapp-adesc-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(command) -p \"$(cat '\(tmp.path)')\""]
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

    /// Extracts `{ entryId: description }` from the model output (tolerates surrounding text).
    static func parseDescriptions(from output: String) -> [String: String] {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"), start < end else { return [:] }
        let json = String(output[start...end])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in obj {
            if let s = v as? String { result[k] = s }
        }
        return result
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
