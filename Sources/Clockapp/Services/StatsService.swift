import Foundation

/// Aggregations over time entries for goals & the day×hour heatmap.
enum StatsService {
    /// Sum of durations for entries overlapping [dayStart, dayStart+1d).
    static func total(for entries: [TimeEntry], on day: Date, calendar: Calendar = .current, asOf now: Date = Date()) -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return overlapTotal(entries, from: start, to: end, asOf: now)
    }

    /// Sum of durations for entries overlapping the calendar week containing `day`.
    static func weekTotal(for entries: [TimeEntry], containing day: Date, calendar: Calendar = .current, asOf now: Date = Date()) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day) else { return 0 }
        return overlapTotal(entries, from: interval.start, to: interval.end, asOf: now)
    }

    /// Sum of durations for entries overlapping the calendar month containing `day`.
    static func monthTotal(for entries: [TimeEntry], containing day: Date, calendar: Calendar = .current, asOf now: Date = Date()) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .month, for: day) else { return 0 }
        return overlapTotal(entries, from: interval.start, to: interval.end, asOf: now)
    }

    private static func overlapTotal(_ entries: [TimeEntry], from: Date, to: Date, asOf now: Date) -> TimeInterval {
        entries.reduce(0) { acc, e in
            let s = max(e.start, from)
            let end = min(e.end ?? now, to)
            return acc + max(0, end.timeIntervalSince(s))
        }
    }

    /// 7×24 grid of seconds tracked, indexed [weekdayIndex 0=Mon ... 6=Sun][hour 0...23].
    static func heatmap(for entries: [TimeEntry], calendar: Calendar = .current, asOf now: Date = Date()) -> [[TimeInterval]] {
        var grid = Array(repeating: Array(repeating: TimeInterval(0), count: 24), count: 7)
        for e in entries {
            var cursor = e.start
            let end = e.end ?? now
            guard end > cursor else { continue }
            // Walk hour-by-hour so a long entry is split across buckets.
            while cursor < end {
                let comps = calendar.dateComponents([.weekday, .hour], from: cursor)
                guard let wd = comps.weekday, let hour = comps.hour else { break }
                let mondayIndex = (wd + 5) % 7 // 1=Sun→6, 2=Mon→0 ...
                let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: cursor) ?? cursor
                let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? end
                let sliceEnd = min(end, nextHour)
                grid[mondayIndex][hour] += max(0, sliceEnd.timeIntervalSince(cursor))
                cursor = sliceEnd == cursor ? end : sliceEnd // guard against non-advancing cursor
            }
        }
        return grid
    }
}
