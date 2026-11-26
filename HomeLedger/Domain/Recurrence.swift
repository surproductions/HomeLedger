import Foundation

enum RecurrenceUnit: String, CaseIterable, Identifiable, Codable {
    case none, day, week, month, year
    var id: String { rawValue }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .none: nil
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func label(plural: Bool) -> String {
        switch self {
        case .none: "Does not repeat"
        case .day: plural ? "days" : "day"
        case .week: plural ? "weeks" : "week"
        case .month: plural ? "months" : "month"
        case .year: plural ? "years" : "year"
        }
    }
}

/// How the next occurrence is calculated after completion.
enum RecurrenceBasis: String, CaseIterable, Identifiable, Codable {
    /// Keep a fixed calendar rhythm (e.g. the 1st of every quarter), regardless of when it was done.
    case schedule
    /// Restart the interval from the day the task was completed (e.g. "3 months after last change").
    case completion
    var id: String { rawValue }
    var label: String {
        switch self {
        case .schedule: "Keep a fixed schedule"
        case .completion: "Count from completion"
        }
    }
}

struct Recurrence: Hashable, Codable {
    var unit: RecurrenceUnit
    var interval: Int
    var basis: RecurrenceBasis

    static let none = Recurrence(unit: .none, interval: 1, basis: .schedule)

    static func every(_ interval: Int, _ unit: RecurrenceUnit, basis: RecurrenceBasis = .schedule) -> Recurrence {
        Recurrence(unit: unit, interval: max(1, interval), basis: basis)
    }

    var isRepeating: Bool { unit != .none }

    var summary: String {
        guard isRepeating else { return "One-time" }
        if interval == 1 {
            switch unit {
            case .day: return "Daily"
            case .week: return "Weekly"
            case .month: return "Monthly"
            case .year: return "Yearly"
            case .none: return "One-time"
            }
        }
        return "Every \(interval) \(unit.label(plural: true))"
    }
}

/// Pure scheduling logic for recurring maintenance. All date math goes through `Calendar` so
/// month-end and leap-year cases behave the way people expect (Jan 31 + 1 month = Feb 28/29).
struct RecurrenceCalculator {
    var calendar: Calendar = .current

    /// Adds `count` recurrence steps to an anchor date. Always computed from the original anchor
    /// (not iteratively) so month-end dates do not drift (Jan 31 → Feb 29 → Mar 31, not Mar 29).
    func date(byAdding count: Int, of recurrence: Recurrence, to anchor: Date) -> Date? {
        guard let component = recurrence.unit.calendarComponent else { return nil }
        return calendar.date(byAdding: component, value: recurrence.interval * count, to: anchor)
    }

    /// The next due date after a task is completed (or skipped) on `completionDate`.
    ///
    /// - `.completion` basis: one interval after the completion day.
    /// - `.schedule` basis: the first scheduled occurrence strictly after the current due date
    ///   that is also after the completion day, so completing late never leaves the task
    ///   immediately overdue again, and completing early simply advances one step.
    func nextDueDate(currentDue: Date, completedOn completionDate: Date, recurrence: Recurrence) -> Date? {
        guard recurrence.isRepeating else { return nil }
        switch recurrence.basis {
        case .completion:
            let start = calendar.startOfDay(for: completionDate)
            return date(byAdding: 1, of: recurrence, to: start)
        case .schedule:
            let completionDay = calendar.startOfDay(for: completionDate)
            var step = 1
            while let candidate = date(byAdding: step, of: recurrence, to: currentDue) {
                if calendar.startOfDay(for: candidate) > completionDay { return candidate }
                step += 1
                if step > 10_000 { return candidate } // defensive guard against bad data
            }
            return nil
        }
    }

    /// Upcoming occurrences starting at `due` (inclusive) — used for previews in the editor.
    func upcoming(from due: Date, recurrence: Recurrence, count: Int) -> [Date] {
        guard recurrence.isRepeating else { return [due] }
        return (0..<count).compactMap { date(byAdding: $0, of: recurrence, to: due) }
    }
}

enum TaskDueState: Equatable {
    case overdue(days: Int)
    case dueToday
    case dueSoon(days: Int)
    case upcoming(days: Int)

    static func evaluate(due: Date, now: Date = .now, soonWindowDays: Int = 7, calendar: Calendar = .current) -> TaskDueState {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        if days < 0 { return .overdue(days: -days) }
        if days == 0 { return .dueToday }
        if days <= soonWindowDays { return .dueSoon(days: days) }
        return .upcoming(days: days)
    }

    var isOverdue: Bool { if case .overdue = self { return true }; return false }
    var isDueSoonOrToday: Bool {
        switch self {
        case .dueToday, .dueSoon: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .overdue(let d): return d == 1 ? "Overdue by 1 day" : "Overdue by \(d) days"
        case .dueToday: return "Due today"
        case .dueSoon(let d): return d == 1 ? "Due tomorrow" : "Due in \(d) days"
        case .upcoming(let d):
            if d < 60 { return "Due in \(d) days" }
            return "Due in \(d / 30) months"
        }
    }
}
