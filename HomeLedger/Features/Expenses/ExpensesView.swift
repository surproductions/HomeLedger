import Charts
import SwiftData
import SwiftUI

struct ExpensesView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var category: ExpenseCategory?

    private let calc = ExpenseCalculator()

    var body: some View {
        let scoped = HomeScope(home: app.currentHome(in: homes)).expenses(allExpenses)
        let yearExpenses = calc.filter(scoped, .init(range: calc.yearRange(year), category: category))
        let monthly = calc.monthly(yearExpenses, year: year)
        let byCategory = calc.byCategory(calc.filter(scoped, .init(range: calc.yearRange(year))))
        let years = Array(Set(scoped.map { Calendar.current.component(.year, from: $0.date) } + [Calendar.current.component(.year, from: .now)])).sorted(by: >)
        let thisMonth = calc.total(calc.filter(scoped, .init(range: calc.monthRange(containing: .now), category: category)))

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Menu {
                        ForEach(years, id: \.self) { y in Button(String(y)) { year = y } }
                    } label: {
                        Label(String(year), systemImage: "calendar").font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Year \(year)")
                    Spacer()
                    if let category { Button { self.category = nil } label: { StatusPill(text: category.label, tone: .brand, symbol: "xmark") } }
                }

                HStack(spacing: 12) {
                    GradientStatCard(title: "\(String(year)) total", value: Money.format(cents: calc.total(yearExpenses), showCents: false),
                                     caption: "\(yearExpenses.count) expense\(yearExpenses.count == 1 ? "" : "s")", symbol: "sum", gradient: Theme.indigoGradient)
                    GradientStatCard(title: "This month", value: Money.format(cents: thisMonth, showCents: false),
                                     caption: "Avg \(Money.format(cents: calc.averageMonthly(yearExpenses, year: year), showCents: false))/mo", symbol: "calendar", gradient: Theme.warmGradient)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Monthly")
                    Chart(monthly) { m in
                        BarMark(x: .value("Month", m.label), y: .value("Amount", Double(m.cents) / 100))
                            .foregroundStyle(Theme.brand.gradient)
                            .cornerRadius(5)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 180)
                    .accessibilityLabel("Monthly spending for \(String(year))")
                    .card()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "By category")
                    if app.isPremium {
                        if byCategory.isEmpty {
                            Text("No expenses in \(String(year)).").font(.subheadline).foregroundStyle(Theme.inkSecondary).card()
                        } else {
                            ListCard {
                                ForEach(Array(byCategory.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { RowDivider() }
                                    Button { category = category == c.category ? nil : c.category } label: {
                                        CategoryBarRow(total: c, max: byCategory.first?.cents ?? 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        Button { app.present(.paywall(.expenseInsights)) } label: {
                            HStack {
                                IconBadge(systemName: "chart.pie", tint: Theme.tintPurple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Category breakdowns & multi-year trends").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text("Part of HomeLedger Premium").font(.caption).foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "lock.fill").foregroundStyle(Theme.inkTertiary)
                            }
                            .card(padding: 14)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                if app.isPremium && years.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Year over year")
                        Chart(calc.yearly(scoped)) { y in
                            BarMark(x: .value("Year", String(y.year)), y: .value("Amount", Double(y.cents) / 100))
                                .foregroundStyle(Theme.tintPurple.gradient).cornerRadius(5)
                        }
                        .frame(height: 140)
                        .card()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Expenses", actionTitle: "Add") { app.present(.newExpense(assetID: nil)) }
                    if yearExpenses.isEmpty {
                        ListCard { EmptyStateView(symbol: "creditcard", title: "No expenses", message: "Track purchases, maintenance and repairs. Repair costs you log are added automatically.", actionTitle: "Add expense") { app.present(.newExpense(assetID: nil)) } }
                    } else {
                        ListCard {
                            ForEach(Array(yearExpenses.enumerated()), id: \.element.id) { i, e in
                                if i > 0 { RowDivider() }
                                NavigationLink(value: AppRoute.expense(e)) { ExpenseRow(expense: e) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text("Totals reflect only the expenses you've recorded. HomeLedger doesn't provide financial advice.")
                    .font(.footnote).foregroundStyle(Theme.inkTertiary).padding(.horizontal, 4)
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.present(.newExpense(assetID: nil)) } label: { Image(systemName: "plus") }.accessibilityLabel("Add expense")
            }
        }
    }
}

struct CategoryBarRow: View {
    let total: CategoryTotal
    let max: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(total.category.label, systemImage: total.category.symbol).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(Money.format(cents: total.cents)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            GeometryReader { geo in
                Capsule().fill(Theme.brandSoft)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.brand).frame(width: geo.size.width * CGFloat(total.cents) / CGFloat(Swift.max(max, 1)))
                    }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct ExpenseRow: View {
    let expense: Expense
    var body: some View {
        RecordRow(symbol: expense.category.symbol, tint: Theme.tintPurple, title: expense.title,
                  subtitle: [expense.date.formatted(date: .abbreviated, time: .omitted), expense.asset?.name, expense.vendor.isEmpty ? nil : expense.vendor].compactMap { $0 }.joined(separator: " · "),
                  trailing: Money.format(cents: expense.amountCents), trailingDetail: expense.category.label)
    }
}

struct ExpenseDetailView: View {
    @Bindable var expense: Expense
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(text: expense.category.label, tone: .info, symbol: expense.category.symbol)
                    Text(expense.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(Money.format(cents: expense.amountCents)).font(.hlLargeNumber).foregroundStyle(Theme.ink)
                }
                VStack(spacing: 0) {
                    DetailRow(label: "Date", value: expense.date.formatted(date: .long, time: .omitted))
                    if !expense.vendor.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Vendor", value: expense.vendor) }
                    if let s = expense.serviceRecord { Divider().overlay(Theme.hairline); DetailRow(label: "From service record", value: s.title) }
                    if !expense.notes.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Notes", value: expense.notes) }
                }
                .card(padding: 14)
                if let asset = expense.asset {
                    NavigationLink(value: AppRoute.asset(asset)) { HStack { AssetRow(asset: asset); Image(systemName: "chevron.right").foregroundStyle(Theme.inkTertiary) }.card(padding: 12) }.buttonStyle(.plain)
                }
                if let receipt = expense.receipt {
                    NavigationLink(value: AppRoute.document(receipt)) { DocumentRow(document: receipt).card(padding: 12) }.buttonStyle(.plain)
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if expense.serviceRecord == nil { Button("Edit") { app.present(.editExpense(expense)) } }
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("Delete expense")
            }
        }
        .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete expense", role: .destructive) {
                if let s = expense.serviceRecord { s.costCents = nil }
                context.delete(expense); try? context.save(); dismiss()
            }
        } message: { Text(expense.serviceRecord != nil ? "The linked service record's cost will be cleared. Receipts are kept." : "Any attached receipt is kept in Documents.") }
    }
}

struct ExpenseEditorView: View {
    let expense: Expense?
    let assetID: UUID?
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \Asset.name) private var assets: [Asset]
    @State private var title = ""
    @State private var amount: Int?
    @State private var date = Date.now
    @State private var category: ExpenseCategory = .maintenance
    @State private var vendor = ""
    @State private var notes = ""
    @State private var linkedAssetID: UUID?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Description (required)", text: $title).accessibilityIdentifier("expense.title")
                    MoneyField(title: "Amount (required)", cents: $amount).accessibilityIdentifier("expense.amount")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) { ForEach(ExpenseCategory.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                }
                Section {
                    TextField("Vendor", text: $vendor)
                    Picker("Item", selection: $linkedAssetID) {
                        Text("None").tag(UUID?.none)
                        ForEach(assets) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                } footer: { Text("To attach a receipt, add it from Documents and choose “Also record as an expense”.") }
            }
            .navigationTitle(expense == nil ? "New expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amount == nil)
                        .accessibilityIdentifier("expense.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = expense {
                    title = e.title; amount = e.amountCents; date = e.date; category = e.category; vendor = e.vendor; notes = e.notes; linkedAssetID = e.asset?.id
                } else { linkedAssetID = assetID }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let home = app.currentHome(in: homes)
        let e = expense ?? {
            let new = Expense(title: title, amountCents: amount, home: home)
            context.insert(new)
            return new
        }()
        e.title = title.trimmingCharacters(in: .whitespaces); e.amountCents = amount; e.date = date; e.category = category
        e.vendor = vendor; e.notes = notes
        e.asset = assets.first { $0.id == linkedAssetID }
        e.home = e.asset?.home ?? e.home ?? home
        e.updatedAt = .now
        try? context.save()
        app.showToast(expense == nil ? "Expense added" : "Expense updated")
        dismiss()
    }
}
