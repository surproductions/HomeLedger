import XCTest
@testable import HomeLedger

@MainActor
final class WarrantyReminderTests: HomeLedgerTestCase {
    func testWarrantyStatus() {
        let now = date(2025, 6, 1)
        XCTAssertEqual(WarrantyStatus.evaluate(expiration: nil, now: now, calendar: calendar), .unknown)
        XCTAssertEqual(WarrantyStatus.evaluate(expiration: date(2025, 5, 31), now: now, calendar: calendar), .expired)
        XCTAssertEqual(WarrantyStatus.evaluate(expiration: date(2025, 6, 1), now: now, calendar: calendar), .expiringSoon, "last day of coverage is still covered")
        XCTAssertEqual(WarrantyStatus.evaluate(expiration: date(2025, 7, 15), now: now, calendar: calendar), .expiringSoon)
        XCTAssertEqual(WarrantyStatus.evaluate(expiration: date(2026, 1, 1), now: now, calendar: calendar), .active)
        XCTAssertEqual(WarrantyStatus.daysRemaining(expiration: date(2025, 6, 11), now: now, calendar: calendar), 10)
    }

    func testWarrantyMathFromPeriod() {
        let end = WarrantyMath.expiration(start: date(2025, 3, 15), months: 24, calendar: calendar)!
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: end), DateComponents(year: 2027, month: 3, day: 14))
        XCTAssertNil(WarrantyMath.expiration(start: date(2025, 3, 15), months: 0, calendar: calendar))
    }

    func testPlannerCreatesOneReminderPerOffsetWithStableIDs() {
        let id = UUID()
        let planner = ReminderPlanner(calendar: calendar, reminderHour: 9)
        let input = WarrantyReminderInput(assetID: id, assetName: "Fridge", expiration: date(2025, 12, 31), isEstimated: false,
                                          enabled: true, offsets: [30, 14, 7, 7], isArchived: false)
        let plan = planner.plan(warranties: [input], tasks: [], now: date(2025, 11, 1))
        XCTAssertEqual(plan.count, 3, "duplicate offsets are ignored")
        XCTAssertEqual(Set(plan.map(\.identifier)), ["hl.warranty.\(id.uuidString).30", "hl.warranty.\(id.uuidString).14", "hl.warranty.\(id.uuidString).7"])
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: plan[0].fireDate), DateComponents(month: 12, day: 1, hour: 9))
        XCTAssertEqual(plan, planner.plan(warranties: [input], tasks: [], now: date(2025, 11, 1)), "planning is deterministic")
    }

    func testPlannerSkipsPastUnknownDisabledAndArchived() {
        let planner = ReminderPlanner(calendar: calendar)
        let now = date(2025, 12, 20)
        let inputs = [
            WarrantyReminderInput(assetID: UUID(), assetName: "A", expiration: date(2025, 12, 31), isEstimated: false, enabled: true, offsets: [30, 14, 7], isArchived: false),
            WarrantyReminderInput(assetID: UUID(), assetName: "Unknown", expiration: nil, isEstimated: false, enabled: true, offsets: [30], isArchived: false),
            WarrantyReminderInput(assetID: UUID(), assetName: "Off", expiration: date(2026, 2, 1), isEstimated: false, enabled: false, offsets: [30], isArchived: false),
            WarrantyReminderInput(assetID: UUID(), assetName: "Archived", expiration: date(2026, 2, 1), isEstimated: false, enabled: true, offsets: [30], isArchived: true)
        ]
        let plan = planner.plan(warranties: inputs, tasks: [], now: now)
        XCTAssertEqual(plan.count, 1, "only the 7-day reminder for A is still in the future")
        XCTAssertTrue(plan[0].identifier.hasSuffix(".7"))
    }

    func testEstimatedDatesAreLabelledInReminders() {
        let planner = ReminderPlanner(calendar: calendar)
        let plan = planner.plan(warranties: [WarrantyReminderInput(assetID: UUID(), assetName: "TV", expiration: date(2026, 1, 31), isEstimated: true, enabled: true, offsets: [7], isArchived: false)],
                                tasks: [], now: date(2025, 1, 1))
        XCTAssertTrue(plan[0].body.contains("estimated"))
    }

    func testTaskRemindersRespectLeadTimeAndFallBackToDueDay() {
        let planner = ReminderPlanner(calendar: calendar, reminderHour: 9)
        let id = UUID()
        let task = TaskReminderInput(taskID: id, title: "Filter", dueDate: date(2025, 3, 10), enabled: true, daysBefore: 3, isArchived: false)
        let early = planner.plan(warranties: [], tasks: [task], now: date(2025, 3, 1))
        XCTAssertEqual(early.first?.identifier, "hl.task.\(id.uuidString)")
        XCTAssertEqual(calendar.dateComponents([.day, .hour], from: early.first!.fireDate), DateComponents(day: 7, hour: 9))

        let late = planner.plan(warranties: [], tasks: [task], now: date(2025, 3, 8))
        XCTAssertEqual(calendar.component(.day, from: late.first!.fireDate), 10, "inside the lead window → remind on the due day")

        let overdue = planner.plan(warranties: [], tasks: [task], now: date(2025, 3, 11))
        XCTAssertTrue(overdue.isEmpty)
    }

    func testPlannerCapsPendingNotifications() {
        let planner = ReminderPlanner(calendar: calendar)
        let tasks = (0..<100).map { i in
            TaskReminderInput(taskID: UUID(), title: "T\(i)", dueDate: date(2026, 1, 1).addingTimeInterval(Double(i) * 86_400), enabled: true, daysBefore: 0, isArchived: false)
        }
        let plan = planner.plan(warranties: [], tasks: tasks, now: date(2025, 1, 1))
        XCTAssertEqual(plan.count, ReminderPlanner.maxPending)
        XCTAssertEqual(plan.first?.body, "T0", "soonest reminders are kept")
    }

    func testNotificationSyncReplacesOwnRemindersWithoutDuplicates() async throws {
        Preferences.defaults.set(true, forKey: Preferences.notificationsEnabledKey)
        let home = makeHome()
        let asset = makeAsset("Fridge", in: home)
        asset.warrantyExpiration = Calendar.current.date(byAdding: .day, value: 60, to: .now)
        asset.warrantyReminderOffsets = [30, 7]
        let task = MaintenanceTask(title: "Filter", dueDate: Calendar.current.date(byAdding: .day, value: 10, to: .now)!, recurrence: .every(1, .month), home: home)
        context.insert(task)
        try context.save()

        let mock = MockNotificationCenter()
        mock.pending = ["other.app.reminder", "hl.task.stale"]
        let service = NotificationService(client: mock)

        let added = await service.sync(context: context)
        XCTAssertEqual(added, 3)
        XCTAssertTrue(mock.removed.contains("hl.task.stale"))
        XCTAssertFalse(mock.removed.contains("other.app.reminder"), "never touches notifications it doesn't own")

        await service.sync(context: context)
        let ours = mock.pending.filter { $0.hasPrefix("hl.") }
        XCTAssertEqual(ours.count, 3, "re-syncing doesn't duplicate")
        XCTAssertEqual(Set(ours).count, ours.count)

        asset.warrantyRemindersEnabled = false
        await service.sync(context: context)
        XCTAssertEqual(mock.pending.filter { $0.hasPrefix("hl.warranty") }.count, 0, "turning off per-warranty reminders removes them")
    }

    func testNotificationSyncDoesNothingWhenUnauthorized() async {
        Preferences.defaults.set(true, forKey: Preferences.notificationsEnabledKey)
        let mock = MockNotificationCenter()
        mock.status = .denied
        context.insert(MaintenanceTask(title: "X", dueDate: Calendar.current.date(byAdding: .day, value: 5, to: .now)!))
        let added = await NotificationService(client: mock).sync(context: context)
        XCTAssertEqual(added, 0)
        XCTAssertTrue(mock.added.isEmpty)
    }
}
