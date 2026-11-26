import SwiftData
import SwiftUI

struct RepairsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \ServiceRecord.date, order: .reverse) private var allRecords: [ServiceRecord]
    @State private var kind: ServiceKind?
    @State private var searchText = ""

    var body: some View {
        var records = HomeScope(home: app.currentHome(in: homes)).services(allRecords)
        if let kind { records = records.filter { $0.kind == kind } }
        let terms = SearchService.tokens(searchText)
        if !terms.isEmpty {
            records = records.filter { r in
                let hay = SearchService.normalize([r.title, r.details, r.vendor, r.asset?.name ?? "", r.kind.label].joined(separator: " "))
                return terms.allSatisfy { hay.contains($0) }
            }
        }
        let total = records.compactMap(\.costCents).reduce(0, +)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: kind == nil) { kind = nil }
                        ForEach(ServiceKind.allCases) { k in FilterChip(title: k.label, symbol: k.symbol, isSelected: kind == k) { kind = kind == k ? nil : k } }
                    }
                }
                .scrollIndicators(.hidden)
                if !records.isEmpty {
                    Text("\(records.count) record\(records.count == 1 ? "" : "s") · \(Money.format(cents: total)) total")
                        .font(.subheadline).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 4)
                }
                if records.isEmpty {
                    ListCard { EmptyStateView(symbol: "wrench.adjustable", title: "No repair or service records", message: "Log repairs, servicing and inspections — with costs, vendors and documents.", actionTitle: "Log repair") { app.present(.newService(assetID: nil)) } }
                } else {
                    ListCard {
                        ForEach(Array(records.enumerated()), id: \.element.id) { i, r in
                            if i > 0 { RowDivider() }
                            NavigationLink(value: AppRoute.service(r)) {
                                RecordRow(symbol: r.kind.symbol, tint: Theme.tintOrange, title: r.title,
                                          subtitle: [r.date.formatted(date: .abbreviated, time: .omitted), r.asset?.name, r.vendor.isEmpty ? nil : r.vendor].compactMap { $0 }.joined(separator: " · "),
                                          trailing: r.costCents.map { Money.format(cents: $0) },
                                          pill: r.followUpDate.map { ("Follow-up \($0.formatted(.dateTime.month(.abbreviated).day()))", StatusTone.info) })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Repairs & service")
        .searchable(text: $searchText, prompt: "Search repairs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.present(.newService(assetID: nil)) } label: { Image(systemName: "plus") }.accessibilityLabel("Log repair")
            }
        }
    }
}

struct ServiceDetailView: View {
    @Bindable var record: ServiceRecord
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(text: record.kind.label, tone: .warning, symbol: record.kind.symbol)
                    Text(record.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    if !record.details.isEmpty { Text(record.details).foregroundStyle(Theme.inkSecondary) }
                }
                VStack(spacing: 0) {
                    DetailRow(label: "Date", value: record.date.formatted(date: .long, time: .omitted))
                    if !record.vendor.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Vendor / technician", value: record.vendor) }
                    if let c = record.costCents { Divider().overlay(Theme.hairline); DetailRow(label: "Cost", value: Money.format(cents: c)) }
                    if let f = record.followUpDate { Divider().overlay(Theme.hairline); DetailRow(label: "Follow-up", value: f.formatted(date: .long, time: .omitted)) }
                    if !record.followUpNote.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Follow-up note", value: record.followUpNote) }
                    if let t = record.task { Divider().overlay(Theme.hairline); DetailRow(label: "Maintenance task", value: t.title) }
                }
                .card(padding: 14)
                if let asset = record.asset {
                    NavigationLink(value: AppRoute.asset(asset)) {
                        HStack { AssetRow(asset: asset); Image(systemName: "chevron.right").foregroundStyle(Theme.inkTertiary) }.card(padding: 12)
                    }.buttonStyle(.plain)
                }
                let docs = record.documents ?? []
                SectionHeader(title: "Documents")
                if docs.isEmpty {
                    Text("Attach invoices or photos from the item's page, then link them here by editing the document.").font(.footnote).foregroundStyle(Theme.inkSecondary)
                } else {
                    ListCard {
                        ForEach(docs) { d in NavigationLink(value: AppRoute.document(d)) { DocumentRow(document: d) }.buttonStyle(.plain) }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Service record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { app.present(.editService(record)) }
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("Delete record")
            }
        }
        .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete record and its linked expense", role: .destructive) {
                DataService(context: context).deleteServiceRecord(record)
                try? context.save(); app.syncReminders(context); dismiss()
            }
            Button("Delete record, keep expense") {
                DataService(context: context).deleteServiceRecord(record, deleteLinkedExpense: false)
                try? context.save(); app.syncReminders(context); dismiss()
            }
        } message: { Text("Attached documents are kept.") }
    }
}

struct ServiceEditorView: View {
    let record: ServiceRecord?
    let assetID: UUID?
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \Asset.name) private var assets: [Asset]
    @Query(sort: \MaintenanceTask.title) private var tasks: [MaintenanceTask]

    @State private var title = ""
    @State private var kind: ServiceKind = .repair
    @State private var date = Date.now
    @State private var details = ""
    @State private var vendor = ""
    @State private var cost: Int?
    @State private var linkedAssetID: UUID?
    @State private var linkedTaskID: UUID?
    @State private var followUp: Date?
    @State private var followUpNote = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened") {
                    TextField("Issue or work done (required)", text: $title).accessibilityIdentifier("service.title")
                    Picker("Type", selection: $kind) { ForEach(ServiceKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $details, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    TextField("Vendor or technician", text: $vendor)
                    MoneyField(title: "Cost", cents: $cost)
                } header: { Text("Who & cost") } footer: { Text("A cost is also recorded in Expenses and kept in sync with this record.") }
                Section("Related to") {
                    Picker("Item", selection: $linkedAssetID) {
                        Text("None").tag(UUID?.none)
                        ForEach(assets) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Maintenance task", selection: $linkedTaskID) {
                        Text("None").tag(UUID?.none)
                        ForEach(tasks) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                Section {
                    OptionalDatePicker(title: "Follow-up reminder", date: $followUp, defaultDate: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
                    if followUp != nil { TextField("Follow-up note", text: $followUpNote) }
                } header: { Text("Follow-up") }
            }
            .navigationTitle(record == nil ? "Log repair or service" : "Edit record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("service.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let r = record {
                    title = r.title; kind = r.kind; date = r.date; details = r.details; vendor = r.vendor; cost = r.costCents
                    linkedAssetID = r.asset?.id; linkedTaskID = r.task?.id; followUp = r.followUpDate; followUpNote = r.followUpNote
                } else {
                    linkedAssetID = assetID
                }
            }
        }
    }

    private func save() {
        let home = app.currentHome(in: homes)
        let r = record ?? {
            let new = ServiceRecord(title: title, home: home)
            context.insert(new)
            return new
        }()
        r.title = title.trimmingCharacters(in: .whitespaces)
        r.kind = kind; r.date = date; r.details = details; r.vendor = vendor; r.costCents = cost
        r.asset = assets.first { $0.id == linkedAssetID }
        r.task = tasks.first { $0.id == linkedTaskID }
        r.home = r.asset?.home ?? r.home ?? home
        r.followUpDate = followUp; r.followUpNote = followUpNote
        r.updatedAt = .now
        r.asset?.touch()
        DataService(context: context).syncExpense(for: r)
        try? context.save()
        app.syncReminders(context)
        app.showToast(record == nil ? "Repair logged" : "Record updated")
        dismiss()
    }
}
