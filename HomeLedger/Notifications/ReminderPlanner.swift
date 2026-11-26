import Foundation

/// A local notification HomeLedger intends to have scheduled.
struct PlannedReminder: Equatable, Hashable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Snapshot inputs so planning is pure and unit-testable (no SwiftData or UIKit involved).
struct WarrantyReminderInput {
    let assetID: UUID
    let assetName: String
    let expiration: Date?
    let isEstimated: Bool
    let enabled: Bool
    let offsets: [Int]
    let isArchived: Bool
}

struct TaskReminderInput {
    let taskID: UUID
    let title: String
    let dueDate: Date
    let enabled: Bool
    let daysBefore: Int
    let isArchived: Bool
}

struct FollowUpReminderInput {
    let recordID: UUID
    let title: String
    let followUpDate: Date?
}

/// Produces the complete desired set of reminders. Identifiers are deterministic
/// (`warranty.<id>.<days>`, `task.<id>`, `followup.<id>`) so rescheduling replaces rather than
/// duplicates notifications.
struct ReminderPlanner {
    static let identifierPrefix = "hl."
    /// iOS keeps at most 64 pending local notifications per app; leave headroom.
    static let maxPending = 60

    var calendar: Calendar = .current
    var reminderHour: Int = 9

    func fireDate(onDayOf date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: day) ?? day
    }

    func plan(warranties: [WarrantyReminderInput], tasks: [TaskReminderInput], followUps: [FollowUpReminderInput] = [], now: Date = .now) -> [PlannedReminder] {
        var result: [PlannedReminder] = []

        for w in warranties where w.enabled && !w.isArchived {
            guard let expiration = w.expiration else { continue } // unknown dates are never guessed
            for offset in Set(w.offsets) where offset >= 0 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: expiration) else { continue }
                let fire = fireDate(onDayOf: day)
                guard fire > now else { continue }
                let when = offset == 0 ? "today" : (offset == 1 ? "tomorrow" : "in \(offset) days")
                let estimated = w.isEstimated ? " (estimated date — check your warranty terms)" : ""
                result.append(PlannedReminder(identifier: "\(Self.identifierPrefix)warranty.\(w.assetID.uuidString).\(offset)",
                                              fireDate: fire,
                                              title: "Warranty ending \(when)",
                                              body: "The warranty for \(w.assetName) ends \(expiration.formatted(date: .abbreviated, time: .omitted))\(estimated)."))
            }
        }

        for t in tasks where t.enabled && !t.isArchived {
            let lead = max(0, t.daysBefore)
            guard let day = calendar.date(byAdding: .day, value: -lead, to: t.dueDate) else { continue }
            var fire = fireDate(onDayOf: day)
            if fire <= now {
                // Already inside the lead window: remind on the due day itself if that's still ahead.
                fire = fireDate(onDayOf: t.dueDate)
                guard fire > now else { continue }
            }
            let when = calendar.isDate(fire, inSameDayAs: t.dueDate) ? "today" : "on \(t.dueDate.formatted(date: .abbreviated, time: .omitted))"
            result.append(PlannedReminder(identifier: "\(Self.identifierPrefix)task.\(t.taskID.uuidString)",
                                          fireDate: fire,
                                          title: "Maintenance due \(when)",
                                          body: t.title))
        }

        for f in followUps {
            guard let date = f.followUpDate else { continue }
            let fire = fireDate(onDayOf: date)
            guard fire > now else { continue }
            result.append(PlannedReminder(identifier: "\(Self.identifierPrefix)followup.\(f.recordID.uuidString)",
                                          fireDate: fire, title: "Repair follow-up", body: f.title))
        }

        // Deduplicate by identifier, keep the soonest, and respect the system limit.
        var seen = Set<String>()
        return result.sorted { $0.fireDate < $1.fireDate }
            .filter { seen.insert($0.identifier).inserted }
            .prefix(Self.maxPending)
            .map { $0 }
    }
}
