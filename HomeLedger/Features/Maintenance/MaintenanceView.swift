import SwiftData
import SwiftUI

struct MaintenanceView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \MaintenanceTask.dueDate) private var allTasks: [MaintenanceTask]
    @State private var filter: MaintenanceFilter = .upcoming

    private var tasks: [MaintenanceTask] { HomeScope(home: app.currentHome(in: homes)).tasks(allTasks) }
    private var open: [MaintenanceTask] { tasks.filter { !$0.isArchived } }
    private var overdue: [MaintenanceTask] { open.filter { TaskDueState.evaluate(due: $0.dueDate).isOverdue } }
    private var thisWeek: [MaintenanceTask] { open.filter { TaskDueState.evaluate(due: $0.dueDate).isDueSoonOrToday } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                Picker("Show", selection: $filter) { ForEach(MaintenanceFilter.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("maintenance.filter")
                MaintenanceTaskSections(tasks: tasks, filter: filter)
                Text("Suggested schedules are general starting points. Your equipment's manual and local conditions take priority.")
                    .font(.footnote).foregroundStyle(Theme.inkTertiary).padding(.horizontal, 4)
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.present(.newTask(assetID: nil)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add task")
                    .accessibilityIdentifier("maintenance.add")
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            GradientStatCard(title: "Overdue", value: "\(overdue.count)", caption: overdue.isEmpty ? "All caught up" : "Needs attention",
                             symbol: "exclamationmark.triangle.fill", gradient: overdue.isEmpty ? Theme.indigoGradient : Theme.warmGradient)
                .onTapGesture { filter = .overdue }
                .accessibilityAddTraits(.isButton)
            GradientStatCard(title: "Due in 7 days", value: "\(thisWeek.count)", caption: "\(open.count) active task\(open.count == 1 ? "" : "s")",
                             symbol: "calendar", gradient: Theme.indigoGradient)
                .onTapGesture { filter = .upcoming }
                .accessibilityAddTraits(.isButton)
        }
    }
}

struct MaintenanceListView: View {
    let filter: MaintenanceFilter
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \MaintenanceTask.dueDate) private var allTasks: [MaintenanceTask]
    @State private var current: MaintenanceFilter

    init(filter: MaintenanceFilter) {
        self.filter = filter
        _current = State(initialValue: filter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Show", selection: $current) { ForEach(MaintenanceFilter.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                MaintenanceTaskSections(tasks: HomeScope(home: app.currentHome(in: homes)).tasks(allTasks), filter: current)
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.present(.newTask(assetID: nil)) } label: { Image(systemName: "plus") }.accessibilityLabel("Add task")
            }
        }
    }
}

struct MaintenanceTaskSections: View {
    let tasks: [MaintenanceTask]
    let filter: MaintenanceFilter
    @Environment(AppModel.self) private var app

    var body: some View {
        let open = tasks.filter { !$0.isArchived }.sorted { $0.dueDate < $1.dueDate }
        switch filter {
        case .upcoming:
            let overdue = open.filter { TaskDueState.evaluate(due: $0.dueDate).isOverdue }
            let soon = open.filter { !TaskDueState.evaluate(due: $0.dueDate).isOverdue && $0.dueDate <= Calendar.current.date(byAdding: .day, value: 30, to: .now)! }
            let later = open.filter { $0.dueDate > Calendar.current.date(byAdding: .day, value: 30, to: .now)! }
            if open.isEmpty { emptyState }
            group("Overdue", overdue)
            group("Next 30 days", soon)
            group("Later", later)
        case .overdue:
            let overdue = open.filter { TaskDueState.evaluate(due: $0.dueDate).isOverdue }
            if overdue.isEmpty {
                ListCard { EmptyStateView(symbol: "checkmark.seal", title: "Nothing overdue", message: "You're all caught up.") }
            } else { group(nil, overdue) }
        case .all:
            if tasks.isEmpty { emptyState }
            group("Active", open)
            group("Completed one-time tasks", tasks.filter(\.isArchived).sorted { $0.updatedAt > $1.updatedAt })
        case .history:
            let logs = tasks.flatMap { $0.logs ?? [] }.sorted { $0.date > $1.date }
            if logs.isEmpty {
                ListCard { EmptyStateView(symbol: "clock.arrow.circlepath", title: "No history yet", message: "Completed and skipped tasks are recorded here.") }
            } else {
                ListCard {
                    ForEach(Array(logs.prefix(200).enumerated()), id: \.element.id) { i, log in
                        if i > 0 { RowDivider() }
                        if let task = log.task {
                            NavigationLink(value: AppRoute.task(task)) { HistoryRow(log: log, title: task.title) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ListCard {
            EmptyStateView(symbol: "calendar.badge.plus", title: "No maintenance yet", message: "Create one-time or recurring tasks, or start from a suggestion.", actionTitle: "Add task") { app.present(.newTask(assetID: nil)) }
        }
    }

    @ViewBuilder
    private func group(_ title: String?, _ items: [MaintenanceTask]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let title { SectionHeader(title: title) }
                ListCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, task in
                        if i > 0 { RowDivider() }
                        TaskRow(task: task, showComplete: !task.isArchived)
                    }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let log: MaintenanceLog
    let title: String
    var body: some View {
        RecordRow(symbol: log.kind == .completed ? "checkmark.circle.fill" : "forward.end",
                  tint: log.kind == .completed ? Theme.success : Theme.inkTertiary,
                  title: title,
                  subtitle: "\(log.kind == .completed ? "Completed" : "Skipped") \(log.date.formatted(date: .abbreviated, time: .omitted))\(log.note.isEmpty ? "" : " · \(log.note)")",
                  trailing: log.costCents.map { Money.format(cents: $0) })
    }
}

/// Task row with a one-tap completion control (opens the completion sheet).
struct TaskRow: View {
    let task: MaintenanceTask
    var showComplete: Bool = true
    @State private var completing = false

    var body: some View {
        let state = TaskDueState.evaluate(due: task.dueDate)
        HStack(spacing: 12) {
            if showComplete {
                Button { completing = true } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(state.isOverdue ? Theme.danger : Theme.brand)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(task.title)")
                .accessibilityIdentifier("task.complete.\(task.title)")
            } else {
                IconBadge(systemName: "checkmark", tint: Theme.success, size: 40)
            }
            NavigationLink(value: AppRoute.task(task)) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                        Text([task.recurrence.summary, task.asset?.name ?? task.room?.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 4) {
                        if task.isArchived {
                            StatusPill(text: "Done", tone: .success)
                        } else {
                            StatusPill(text: state.label, tone: state.tone)
                            Text(task.dueDate.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $completing) { CompleteTaskSheet(task: task) }
    }
}

// MARK: - Complete sheet

struct CompleteTaskSheet: View {
    let task: MaintenanceTask
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var note = ""
    @State private var cost: Int?
    @State private var logExpense = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Completed on", selection: $date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
                    MoneyField(title: "Cost (optional)", cents: $cost)
                    if cost != nil { Toggle("Record as an expense", isOn: $logExpense) }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    if let next = RecurrenceCalculator().nextDueDate(currentDue: task.dueDate, completedOn: date, recurrence: task.recurrence) {
                        Text("Next due \(next.formatted(date: .long, time: .omitted)) (\(task.recurrence.summary.lowercased()), \(task.recurrence.basis == .completion ? "counted from completion" : "fixed schedule")).")
                    } else {
                        Text("This one-time task will move to your history.")
                    }
                }
            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") {
                        DataService(context: context).complete(task, on: date, note: note, costCents: cost, logExpense: logExpense)
                        try? context.save()
                        app.syncReminders(context)
                        app.showToast("Marked complete")
                        dismiss()
                    }
                    .accessibilityIdentifier("task.confirmComplete")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Detail

struct TaskDetailView: View {
    @Bindable var task: MaintenanceTask
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var completing = false
    @State private var confirmDelete = false
    @State private var confirmSkip = false

    var body: some View {
        let state = TaskDueState.evaluate(due: task.dueDate)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatusPill(text: task.isArchived ? "Completed" : state.label, tone: task.isArchived ? .success : state.tone)
                        StatusPill(text: task.priority.label + " priority", tone: task.priority == .high ? .warning : .neutral)
                    }
                    Text(task.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    if !task.details.isEmpty { Text(task.details).font(.body).foregroundStyle(Theme.inkSecondary) }
                }

                if !task.isArchived {
                    HStack(spacing: 10) {
                        Button { completing = true } label: {
                            Label("Complete", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("taskDetail.complete")
                        Menu {
                            ForEach([1, 3, 7, 14, 30], id: \.self) { d in
                                Button("\(d) day\(d == 1 ? "" : "s")") { snooze(d) }
                            }
                        } label: {
                            Label("Snooze", systemImage: "moon.zzz").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(spacing: 0) {
                    DetailRow(label: task.isArchived ? "Was due" : "Due", value: task.dueDate.formatted(date: .complete, time: .omitted))
                    Divider().overlay(Theme.hairline)
                    DetailRow(label: "Repeats", value: task.recurrence.summary + (task.recurrence.isRepeating ? (task.recurrence.basis == .completion ? " after completion" : "") : ""))
                    if let asset = task.asset { Divider().overlay(Theme.hairline); DetailRow(label: "Item", value: asset.name) }
                    if let room = task.room { Divider().overlay(Theme.hairline); DetailRow(label: "Room", value: room.name) }
                    if let c = task.estimatedCostCents { Divider().overlay(Theme.hairline); DetailRow(label: "Estimated cost", value: Money.format(cents: c)) }
                    Divider().overlay(Theme.hairline)
                    DetailRow(label: "Reminder", value: task.remindersEnabled ? (task.reminderDaysBefore == 0 ? "On the due date" : "\(task.reminderDaysBefore) day\(task.reminderDaysBefore == 1 ? "" : "s") before") : "Off")
                    if let last = task.lastCompleted { Divider().overlay(Theme.hairline); DetailRow(label: "Last completed", value: last.formatted(date: .abbreviated, time: .omitted)) }
                }
                .card(padding: 14)

                if task.recurrence.isRepeating && !task.isArchived {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Next occurrences")
                        HStack {
                            ForEach(RecurrenceCalculator().upcoming(from: task.dueDate, recurrence: task.recurrence, count: 4), id: \.self) { d in
                                Text(d.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)))
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.brand)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(Theme.brandSoft, in: Capsule())
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "History")
                    if task.sortedLogs.isEmpty {
                        ListCard { EmptyStateView(symbol: "clock", title: "No history yet", message: "Completions and skips will appear here.") }
                    } else {
                        ListCard {
                            ForEach(Array(task.sortedLogs.enumerated()), id: \.element.id) { i, log in
                                if i > 0 { RowDivider() }
                                HistoryRow(log: log, title: log.kind == .completed ? "Completed" : "Skipped")
                            }
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { app.present(.editTask(task)) }
                Menu {
                    if task.recurrence.isRepeating && !task.isArchived {
                        Button { confirmSkip = true } label: { Label("Skip this occurrence", systemImage: "forward.end") }
                    }
                    if task.isArchived {
                        Button { DataService(context: context).reopen(task); try? context.save(); app.syncReminders(context) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
                    }
                    Button { app.present(.newService(assetID: task.asset?.id)) } label: { Label("Log a repair", systemImage: "wrench.adjustable") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete task", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $completing) { CompleteTaskSheet(task: task) }
        .confirmationDialog("Skip this occurrence?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Skip") { DataService(context: context).skip(task); try? context.save(); app.syncReminders(context) }
        } message: { Text("The task moves to its next scheduled date and the skip is kept in history.") }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete task and its history", role: .destructive) {
                context.delete(task)
                try? context.save()
                app.syncReminders(context)
                dismiss()
            }
        } message: { Text("Its completion history will also be deleted. Expenses you recorded are kept.") }
    }

    private func snooze(_ days: Int) {
        DataService(context: context).snooze(task, days: days)
        try? context.save()
        app.syncReminders(context)
        app.showToast("Snoozed \(days) day\(days == 1 ? "" : "s")")
    }
}
