import Foundation
import SwiftData
import UserNotifications

/// Abstraction over UNUserNotificationCenter so scheduling can be tested.
protocol NotificationCenterClient: AnyObject {
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String])
    func add(_ reminder: PlannedReminder, calendar: Calendar) async throws
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

final class SystemNotificationCenter: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ reminder: PlannedReminder, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// Reconciles pending notifications with the desired plan: removes stale HomeLedger reminders
/// and adds missing ones. Idempotent — safe to call after every edit and on every launch.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    let client: NotificationCenterClient
    var calendar: Calendar = .current

    init(client: NotificationCenterClient = SystemNotificationCenter()) {
        self.client = client
    }

    func requestPermission() async -> Bool {
        (try? await client.requestAuthorization()) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await client.authorizationStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func plan(context: ModelContext, now: Date = .now) -> [PlannedReminder] {
        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<MaintenanceTask>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? []
        let planner = ReminderPlanner(calendar: calendar, reminderHour: Preferences.reminderHour)
        return planner.plan(
            warranties: assets.map {
                WarrantyReminderInput(assetID: $0.id, assetName: $0.name, expiration: $0.warrantyExpiration,
                                      isEstimated: $0.warrantyIsEstimated, enabled: $0.warrantyRemindersEnabled,
                                      offsets: $0.warrantyReminderOffsets, isArchived: $0.isArchived)
            },
            tasks: tasks.map {
                TaskReminderInput(taskID: $0.id, title: $0.title, dueDate: $0.dueDate, enabled: $0.remindersEnabled,
                                  daysBefore: $0.reminderDaysBefore, isArchived: $0.isArchived)
            },
            followUps: records.map { FollowUpReminderInput(recordID: $0.id, title: $0.title, followUpDate: $0.followUpDate) },
            now: now)
    }

    @discardableResult
    func sync(context: ModelContext, now: Date = .now) async -> Int {
        let desired = Preferences.notificationsEnabled ? plan(context: context, now: now) : []
        let pending = await client.pendingIdentifiers().filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        // Replace everything we own: identifiers are deterministic so this never duplicates,
        // and content (titles/dates) always reflects the latest edits.
        client.removePending(identifiers: pending)
        guard await isAuthorized() else { return 0 }
        var added = 0
        for reminder in desired {
            do {
                try await client.add(reminder, calendar: calendar)
                added += 1
            } catch {
                continue
            }
        }
        return added
    }
}
