import XCTest
@testable import HomeLedger

@MainActor
final class MaintenanceTests: HomeLedgerTestCase {
    var calc: RecurrenceCalculator { RecurrenceCalculator(calendar: calendar) }

    func testMonthlyKeepsMonthEndWithoutDrift() {
        let anchor = date(2024, 1, 31)
        let r = Recurrence.every(1, .month)
        let dates = calc.upcoming(from: anchor, recurrence: r, count: 4).map { calendar.dateComponents([.month, .day], from: $0) }
        XCTAssertEqual(dates.map(\.month), [1, 2, 3, 4])
        XCTAssertEqual(dates.map(\.day), [31, 29, 31, 30], "leap-year Feb 29, then back to month end")
    }

    func testScheduleBasisCompletedOnTimeAdvancesOneStep() {
        let due = date(2025, 3, 1)
        let next = calc.nextDueDate(currentDue: due, completedOn: date(2025, 3, 1), recurrence: .every(3, .month))
        XCTAssertEqual(next, date(2025, 6, 1))
    }

    func testScheduleBasisCompletedEarlyAdvancesOneStep() {
        let due = date(2025, 3, 1)
        let next = calc.nextDueDate(currentDue: due, completedOn: date(2025, 2, 20), recurrence: .every(1, .month))
        XCTAssertEqual(next, date(2025, 4, 1))
    }

    func testScheduleBasisCompletedVeryLateSkipsMissedOccurrences() {
        let due = date(2025, 1, 10)
        let next = calc.nextDueDate(currentDue: due, completedOn: date(2025, 4, 20), recurrence: .every(1, .month))
        XCTAssertEqual(next, date(2025, 5, 10), "never immediately overdue after completing")
    }

    func testCompletionBasisCountsFromCompletionDay() {
        let due = date(2025, 1, 10)
        let next = calc.nextDueDate(currentDue: due, completedOn: date(2025, 2, 3, hour: 18), recurrence: .every(3, .month, basis: .completion))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next!), DateComponents(year: 2025, month: 5, day: 3))
    }

    func testWeeklyAndYearlyIncludingLeapDay() {
        XCTAssertEqual(calc.nextDueDate(currentDue: date(2025, 1, 6), completedOn: date(2025, 1, 6), recurrence: .every(2, .week)), date(2025, 1, 20))
        let leap = calc.nextDueDate(currentDue: date(2024, 2, 29), completedOn: date(2024, 2, 29), recurrence: .every(1, .year))
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: leap!), DateComponents(month: 2, day: 28))
    }

    func testOneTimeTaskHasNoNextDate() {
        XCTAssertNil(calc.nextDueDate(currentDue: date(2025, 1, 1), completedOn: date(2025, 1, 1), recurrence: .none))
    }

    func testCompletingRecurringTaskUpdatesSameTaskAndLogsHistory() throws {
        let home = makeHome()
        let task = MaintenanceTask(title: "HVAC filter", dueDate: date(2025, 3, 1), recurrence: .every(3, .month), home: home)
        context.insert(task)
        try context.save()

        service.complete(task, on: date(2025, 3, 2), note: "MERV 11", costCents: 2_499, logExpense: true, calculator: calc)
        try context.save()

        XCTAssertEqual(fetch(MaintenanceTask.self).count, 1, "completion never creates a duplicate task")
        XCTAssertEqual(task.dueDate, date(2025, 6, 1))
        XCTAssertFalse(task.isArchived)
        XCTAssertEqual(task.sortedLogs.count, 1)
        XCTAssertEqual(task.sortedLogs.first?.dueDateResolved, date(2025, 3, 1))
        XCTAssertEqual(task.lastCompleted, date(2025, 3, 2))
        XCTAssertEqual(fetch(Expense.self).first?.amountCents, 2_499)
        XCTAssertEqual(fetch(Expense.self).first?.category, .maintenance)

        service.complete(task, on: date(2025, 6, 1), calculator: calc)
        XCTAssertEqual(fetch(MaintenanceTask.self).count, 1)
        XCTAssertEqual(task.sortedLogs.count, 2)
        XCTAssertEqual(task.dueDate, date(2025, 9, 1))
    }

    func testCompletingOneTimeTaskArchivesIt() throws {
        let task = MaintenanceTask(title: "Fix gate", dueDate: date(2025, 5, 1))
        context.insert(task)
        service.complete(task, on: date(2025, 5, 2), calculator: calc)
        XCTAssertTrue(task.isArchived)
        XCTAssertEqual(task.sortedLogs.count, 1)
        service.reopen(task)
        XCTAssertFalse(task.isArchived)
    }

    func testSkipAdvancesAndRecordsSkip() {
        let task = MaintenanceTask(title: "Test detectors", dueDate: date(2025, 1, 1), recurrence: .every(1, .month))
        context.insert(task)
        service.skip(task, on: date(2025, 1, 1), calculator: calc)
        XCTAssertEqual(task.dueDate, date(2025, 2, 1))
        XCTAssertEqual(task.sortedLogs.first?.kind, .skipped)
        XCTAssertNil(task.lastCompleted)
    }

    func testSnoozeMovesFromLaterOfDueAndToday() {
        let task = MaintenanceTask(title: "Clean gutters", dueDate: date(2025, 1, 1))
        context.insert(task)
        service.snooze(task, days: 7, now: date(2025, 1, 10), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: task.dueDate), DateComponents(month: 1, day: 17))
    }

    func testEditingRecurrenceKeepsSingleTask() throws {
        let task = MaintenanceTask(title: "Filter", dueDate: date(2025, 1, 1), recurrence: .every(1, .month))
        context.insert(task)
        task.recurrence = .every(2, .week, basis: .completion)
        try context.save()
        XCTAssertEqual(fetch(MaintenanceTask.self).count, 1)
        XCTAssertEqual(task.recurrence, .every(2, .week, basis: .completion))
        XCTAssertEqual(task.recurrence.summary, "Every 2 weeks")
    }

    func testDueStates() {
        let now = date(2025, 6, 10)
        XCTAssertEqual(TaskDueState.evaluate(due: date(2025, 6, 8), now: now, calendar: calendar), .overdue(days: 2))
        XCTAssertEqual(TaskDueState.evaluate(due: date(2025, 6, 10, hour: 23), now: now, calendar: calendar), .dueToday)
        XCTAssertEqual(TaskDueState.evaluate(due: date(2025, 6, 13), now: now, calendar: calendar), .dueSoon(days: 3))
        XCTAssertEqual(TaskDueState.evaluate(due: date(2025, 7, 30), now: now, calendar: calendar), .upcoming(days: 50))
    }

    func testTemplatesAreEditableSuggestions() {
        XCTAssertGreaterThanOrEqual(MaintenanceTemplate.all.count, 8)
        XCTAssertEqual(Set(MaintenanceTemplate.all.map(\.key)).count, MaintenanceTemplate.all.count)
        XCTAssertNotNil(MaintenanceTemplate.template(forKey: "hvac-filter"))
        XCTAssertTrue(MaintenanceTemplate.all.allSatisfy { $0.recurrence.isRepeating })
    }
}
