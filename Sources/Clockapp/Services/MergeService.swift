import Foundation

/// "Smart merge": collapses chains of consecutive finished entries that are close in
/// time (gap < 10 min) AND share the same project into a single entry spanning from
/// the first start to the last end. Different projects break the chain.
enum MergeService {
    static let maxGapSeconds: TimeInterval = 10 * 60

    /// Chains (>= 2 entries) that should be merged, in chronological order.
    /// Running/unfinished entries are ignored.
    static func plan(_ entries: [TimeEntry]) -> [[TimeEntry]] {
        let sorted = entries.filter { $0.end != nil }.sorted { $0.start < $1.start }
        var groups: [[TimeEntry]] = []
        var current: [TimeEntry] = []
        var chainEnd: Date?

        for e in sorted {
            if let ce = chainEnd, let last = current.last,
               e.start.timeIntervalSince(ce) < maxGapSeconds,
               e.projectId == last.projectId {
                current.append(e)
                chainEnd = max(ce, e.end ?? e.start)   // handle overlapping/nested entries
            } else {
                if current.count >= 2 { groups.append(current) }
                current = [e]
                chainEnd = e.end
            }
        }
        if current.count >= 2 { groups.append(current) }
        return groups
    }

    /// The single entry a chain collapses into: first entry's id/project/billable,
    /// end = latest end in the chain, description = distinct non-empty descriptions
    /// joined by newlines (in chronological order).
    static func merged(from chain: [TimeEntry]) -> TimeEntry {
        var e = chain[0]
        e.end = chain.compactMap { $0.end }.max()
        e.description = mergedDescription(chain)
        return e
    }

    static func mergedDescription(_ chain: [TimeEntry]) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        for entry in chain {
            let d = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !d.isEmpty, !seen.contains(d) else { continue }
            seen.insert(d)
            lines.append(d)
        }
        return lines.joined(separator: "\n")
    }

    /// Number of entries deleted by applying a plan (each chain leaves one entry).
    static func deletedCount(_ groups: [[TimeEntry]]) -> Int {
        groups.reduce(0) { $0 + $1.count - 1 }
    }
}
