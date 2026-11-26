import SwiftData
import SwiftUI

struct TaskEditorView: View {
    let task: MaintenanceTask?
    let assetID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \Asset.name) private var assets: [Asset]

    @State private var title = ""
    @State private var details = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var unit: RecurrenceUnit = .none
    @State private var interval = 1
    @State private var basis: RecurrenceBasis = .schedule
    @State private var priority: MaintenancePriority = .normal
    @State private var estimatedCost: Int?
    @State private var remindersEnabled = true
    @State private var reminderDaysBefore = 1
    @State private var roomID: UUID?
    @State private var linkedAssetID: UUID?
    @State private var templateKey = ""
    @State private var loaded = false
    @State private var notificationsDenied = false

    private var home: Home? { app.currentHome(in: homes) }
    private var recurrence: Recurrence { Recurrence(unit: unit, interval: interval, basis: basis) }

    var body: some View {
        NavigationStack {
            Form {
                if task == nil {
                    Section {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(MaintenanceTemplate.all) { t in
                                    FilterChip(title: t.title, symbol: t.symbol, isSelected: templateKey == t.key) { apply(t) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                        .accessibilityIdentifier("task.templates")
                    } header: { Text("Suggestions") } footer: {
                        Text("Suggestions are editable starting points, not requirements. Follow your equipment's manual where it differs.")
                    }
                }
                Section("Task") {
                    TextField("Title (required)", text: $title).accessibilityIdentifier("task.title")
                    TextField("Details", text: $details, axis: .vertical).lineLimit(2...6)
                    Picker("Priority", selection: $priority) { ForEach(MaintenancePriority.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    DatePicker(task == nil ? "First due" : "Next due", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeat", selection: $unit) {
                        Text("Does not repeat").tag(RecurrenceUnit.none)
                        Text("Days").tag(RecurrenceUnit.day)
                        Text("Weeks").tag(RecurrenceUnit.week)
                        Text("Months").tag(RecurrenceUnit.month)
                        Text("Years").tag(RecurrenceUnit.year)
                    }
                    .accessibilityIdentifier("task.repeat")
                    if unit != .none {
                        Stepper("Every \(interval) \(unit.label(plural: interval != 1))", value: $interval, in: 1...365)
                        Picker("Next date", selection: $basis) { ForEach(RecurrenceBasis.allCases) { Text($0.label).tag($0) } }
                    }
                } header: { Text("Schedule") } footer: {
                    if unit != .none {
                        Text("Upcoming: " + RecurrenceCalculator().upcoming(from: dueDate, recurrence: recurrence, count: 3).map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", "))
                    }
                }
                Section("Related to") {
                    Picker("Item", selection: $linkedAssetID) {
                        Text("None").tag(UUID?.none)
                        ForEach(assets.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Room", selection: $roomID) {
                        Text("None").tag(UUID?.none)
                        ForEach(home?.sortedRooms ?? []) { Text($0.name).tag(Optional($0.id)) }
                    }
                    MoneyField(title: "Estimated cost", cents: $estimatedCost)
                }
                Section {
                    Toggle("Remind me", isOn: $remindersEnabled).accessibilityIdentifier("task.reminders")
                    if remindersEnabled {
                        Picker("When", selection: $reminderDaysBefore) {
                            Text("On the due date").tag(0)
                            Text("1 day before").tag(1)
                            Text("3 days before").tag(3)
                            Text("1 week before").tag(7)
                        }
                    }
                } header: { Text("Reminder") } footer: {
                    if notificationsDenied { Text("Notifications are turned off for HomeLedger in iOS Settings, so reminders won't appear until you allow them.") }
                }
            }
            .navigationTitle(task == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("task.save")
                }
            }
            .onAppear(perform: load)
            .task {
                if !app.launch.isUITesting { notificationsDenied = !(await NotificationService.shared.isAuthorized()) && Preferences.notificationsEnabled }
            }
        }
    }

    private func apply(_ t: MaintenanceTemplate) {
        templateKey = t.key
        title = t.title
        details = t.details
        unit = t.recurrence.unit
        interval = t.recurrence.interval
        basis = t.recurrence.basis
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let task {
            title = task.title; details = task.details; dueDate = task.dueDate
            unit = task.recurrence.unit; interval = task.recurrence.interval; basis = task.recurrence.basis
            priority = task.priority; estimatedCost = task.estimatedCostCents
            remindersEnabled = task.remindersEnabled; reminderDaysBefore = task.reminderDaysBefore
            roomID = task.room?.id; linkedAssetID = task.asset?.id; templateKey = task.templateKey
        } else {
            linkedAssetID = assetID
            if let assetID, let asset = assets.first(where: { $0.id == assetID }) { roomID = asset.room?.id }
        }
    }

    /// Edits update the same task in place, so changing a recurrence never creates duplicates.
    private func save() {
        let target = task ?? {
            let t = MaintenanceTask(title: title, dueDate: dueDate, home: home)
            context.insert(t)
            return t
        }()
        // Editing the date or rhythm starts a new schedule anchored at the chosen date.
        if target.dueDate != dueDate || target.recurrence != recurrence { target.recurrenceAnchor = nil }
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.details = details
        target.dueDate = dueDate
        target.recurrence = recurrence
        target.priority = priority
        target.estimatedCostCents = estimatedCost
        target.remindersEnabled = remindersEnabled
        target.reminderDaysBefore = reminderDaysBefore
        target.templateKey = templateKey
        target.asset = assets.first { $0.id == linkedAssetID }
        target.room = (target.asset?.home ?? home)?.rooms?.first { $0.id == roomID }
        target.home = target.asset?.home ?? target.home ?? home
        target.updatedAt = .now
        try? context.save()
        if remindersEnabled { app.requestPermissionAndSyncReminders(context) } else { app.syncReminders(context) }
        app.showToast(task == nil ? "Task added" : "Task updated")
        dismiss()
    }
}
