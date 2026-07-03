import Foundation

/// A "trackable time range": certain weekdays, between two times of day.
/// When auto-track is on, unlocking the Mac inside a window starts a timer,
/// and locking it (or leaving the window) stops it.
struct TrackingWindow: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// Calendar weekday numbers: 1 = Sunday ... 7 = Saturday.
    var weekdays: Set<Int>
    /// Minutes from midnight (local time).
    var startMinutes: Int
    var endMinutes: Int
    /// Project to attribute auto entries to (falls back to the default project).
    var projectId: String?
    var enabled: Bool

    init(id: UUID = UUID(),
         name: String = "Nouvelle plage",
         weekdays: Set<Int> = [2, 3, 4, 5, 6], // Mon–Fri
         startMinutes: Int = 9 * 60,
         endMinutes: Int = 18 * 60,
         projectId: String? = nil,
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.projectId = projectId
        self.enabled = enabled
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, let h = c.hour, let m = c.minute else { return false }
        guard weekdays.contains(wd) else { return false }
        let minutes = h * 60 + m
        return minutes >= startMinutes && minutes < endMinutes
    }

    var timeRangeLabel: String {
        "\(Self.hhmm(startMinutes)) – \(Self.hhmm(endMinutes))"
    }

    var weekdaysLabel: String {
        Weekday.allCases
            .filter { weekdays.contains($0.calendarValue) }
            .map(\.short)
            .joined(separator: " ")
    }

    static func hhmm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// Weekday ordered Monday-first for UI, mapped to Calendar's 1=Sunday scheme.
enum Weekday: Int, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }

    /// Calendar weekday value (1 = Sunday ... 7 = Saturday).
    var calendarValue: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    var short: String {
        switch self {
        case .monday: return "Lun"
        case .tuesday: return "Mar"
        case .wednesday: return "Mer"
        case .thursday: return "Jeu"
        case .friday: return "Ven"
        case .saturday: return "Sam"
        case .sunday: return "Dim"
        }
    }
}
