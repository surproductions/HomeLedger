import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @AppStorage(Preferences.displayNameKey) private var displayName = ""

    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query private var allAssets: [Asset]
    @Query private var allDocuments: [DocumentRecord]
    @Query private var allTasks: [MaintenanceTask]
    @Query private var allServices: [ServiceRecord]
    @Query private var allExpenses: [Expense]

    private var home: Home? { app.currentHome(in: homes) }
    private var scope: HomeScope { HomeScope(home: home) }
    private var assets: [Asset] { scope.assets(allAssets) }
    private var documents: [DocumentRecord] { scope.documents(allDocuments) }
    private var openTasks: [MaintenanceTask] { scope.tasks(allTasks).filter { !$0.isArchived }.sorted { $0.dueDate < $1.dueDate } }
    private var overdue: [MaintenanceTask] { openTasks.filter { TaskDueState.evaluate(due: $0.dueDate).isOverdue } }
    private var dueSoon: [MaintenanceTask] { openTasks.filter { TaskDueState.evaluate(due: $0.dueDate).isDueSoonOrToday } }
    private var expiringWarranties: [Asset] {
        assets.filter { $0.warrantyStatus == .expiringSoon }.sorted { ($0.warrantyExpiration ?? .distantFuture) < ($1.warrantyExpiration ?? .distantFuture) }
    }
    private var activeWarranties: Int { assets.filter { $0.warrantyStatus == .active || $0.warrantyStatus == .expiringSoon }.count }
    private var totalValueCents: Int { assets.map { $0.recordedValueCents * max(1, $0.quantity) }.reduce(0, +) }
    private var yearSpendCents: Int {
        let calc = ExpenseCalculator()
        let year = Calendar.current.component(.year, from: .now)
        return calc.total(calc.filter(scope.expenses(allExpenses), .init(range: calc.yearRange(year))))
    }
    private var addedThisMonth: Int {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        return assets.filter { $0.createdAt >= start }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                content
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                    .background(Theme.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            }
        }
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Theme.heroGradient.frame(height: 520)
                Theme.canvas
            }
            .ignoresSafeArea()
        }
        .scrollIndicators(.hidden)
        .toolbar { toolbarContent }
        .toolbarBackground(Theme.heroTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("dashboard")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(homes) { h in
                    Button {
                        app.selectedHomeID = h.id
                    } label: {
                        if h.id == home?.id { Label(h.name, systemImage: "checkmark") } else { Text(h.name) }
                    }
                }
                Divider()
                Button { if app.entitlement.canAddHome(currentCount: homes.count) { app.present(.newHome) } else { app.present(.paywall(.multipleHomes)) } } label: {
                    Label("Add home", systemImage: "plus")
                }
                Button { app.navigate(.homes, in: .home) } label: { Label("Manage homes", systemImage: "house.and.flag") }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: home?.homeType.symbol ?? "house").font(.subheadline.weight(.semibold))
                    Text(home?.name ?? "HomeLedger").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.16), in: Capsule())
            }
            .accessibilityLabel("Current home: \(home?.name ?? "none"). Switch home")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { app.present(.search) } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(.white)
            }
            .accessibilityLabel("Search and ask")
            .accessibilityIdentifier("dashboard.search")
            Button { app.present(.settings) } label: {
                Image(systemName: "gearshape").foregroundStyle(.white)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("dashboard.settings")
        }
    }

    // MARK: Hero

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return displayName.isEmpty ? base : "\(base), \(displayName)"
    }

    private var hero: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Recorded value")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .textCase(.uppercase)
                    .kerning(0.6)
                Text(Money.format(cents: totalValueCents, showCents: false))
                    .font(.hlLargeNumber)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("dashboard.totalValue")
                Text("\(assets.count) item\(assets.count == 1 ? "" : "s") · \(documents.count) document\(documents.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 8)

            HStack(alignment: .top, spacing: 4) {
                HeroActionButton(title: "Add Item", symbol: "plus", prominent: true) { addItem() }
                    .accessibilityIdentifier("quick.addItem")
                HeroActionButton(title: "Scan Doc", symbol: "doc.viewfinder") { app.present(.importDocument(.chooser, assetID: nil)) }
                    .accessibilityIdentifier("quick.scan")
                HeroActionButton(title: "Add Task", symbol: "checklist") { app.present(.newTask(assetID: nil)) }
                    .accessibilityIdentifier("quick.task")
                HeroActionButton(title: "Report", symbol: "doc.richtext") { app.present(.report) }
                    .accessibilityIdentifier("quick.report")
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    private func addItem() {
        if DataService(context: context).canAddAsset(entitlements: app.entitlement) {
            app.present(.newAsset(roomID: nil))
        } else {
            app.present(.paywall(.unlimitedItems))
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 22) {
            if homes.isEmpty {
                ListCard {
                    EmptyStateView(symbol: "house", title: "Create your home", message: "Add a home to start organizing rooms, items and maintenance.", actionTitle: "Create home") { app.present(.newHome) }
                }
            } else {
                attentionCard
                metricsGrid
                highlightRow
                if assets.isEmpty { gettingStarted }
                upcomingTasksSection
                warrantiesSection
                recentItemsSection
                activitySection
                if !app.isPremium { premiumCard }
            }
        }
    }

    private var attentionCard: some View {
        let total = max(openTasks.filter { $0.dueDate <= Calendar.current.date(byAdding: .day, value: 30, to: .now)! }.count, 1)
        let onTrack = openTasks.isEmpty ? 1.0 : Double(total - overdue.count) / Double(total)
        let subtitle: String = {
            if openTasks.isEmpty { return "No maintenance scheduled yet" }
            var parts: [String] = []
            if !overdue.isEmpty { parts.append("\(overdue.count) overdue") }
            parts.append("\(dueSoon.count) due this week")
            return parts.joined(separator: " · ")
        }()
        return Button { app.navigate(.maintenanceList(overdue.isEmpty ? .upcoming : .overdue), in: .home) } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: overdue.isEmpty ? "checkmark.seal" : "exclamationmark.triangle", tint: overdue.isEmpty ? Theme.success : Theme.danger, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(overdue.isEmpty ? "Maintenance on track" : "Needs attention").font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                RingProgress(progress: onTrack, tint: overdue.isEmpty ? Theme.success : Theme.brand)
            }
            .card(padding: 14, radius: Theme.radiusL)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("dashboard.attention")
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink(value: AppRoute.assets(AssetListFilter(title: "All items"))) {
                MetricTile(symbol: "shippingbox", tint: Theme.tintBlue, value: "\(assets.count)", label: "Items",
                           footnote: addedThisMonth > 0 ? "+\(addedThisMonth) this month" : nil, footnoteTone: .success)
            }
            .accessibilityIdentifier("metric.items")
            NavigationLink(value: AppRoute.documents(nil)) {
                MetricTile(symbol: "doc.text", tint: Theme.tintPurple, value: "\(documents.count)", label: "Documents",
                           footnote: documents.isEmpty ? "Scan your first receipt" : nil)
            }
            .accessibilityIdentifier("metric.documents")
            NavigationLink(value: AppRoute.warranties(expiringWarranties.isEmpty ? nil : .expiringSoon)) {
                MetricTile(symbol: "checkmark.shield", tint: Theme.tintGreen, value: "\(activeWarranties)", label: "Active warranties",
                           footnote: expiringWarranties.isEmpty ? nil : "\(expiringWarranties.count) expiring soon", footnoteTone: .warning)
            }
            .accessibilityIdentifier("metric.warranties")
            NavigationLink(value: AppRoute.maintenanceList(overdue.isEmpty ? .upcoming : .overdue)) {
                MetricTile(symbol: "wrench.and.screwdriver", tint: Theme.tintOrange, value: "\(dueSoon.count + overdue.count)", label: "Tasks due soon",
                           footnote: overdue.isEmpty ? nil : "\(overdue.count) overdue", footnoteTone: .danger)
            }
            .accessibilityIdentifier("metric.tasks")
        }
        .buttonStyle(PressableStyle())
    }

    private var highlightRow: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AppRoute.expenses) {
                GradientStatCard(title: "Spent this year", value: Money.format(cents: yearSpendCents, showCents: false),
                                 caption: "Home expenses", symbol: "chart.bar.fill", gradient: Theme.indigoGradient)
            }
            .accessibilityIdentifier("highlight.expenses")
            NavigationLink(value: AppRoute.repairs) {
                GradientStatCard(title: "Repairs & service", value: "\(scope.services(allServices).count)",
                                 caption: "Records on file", symbol: "wrench.adjustable.fill", gradient: Theme.warmGradient)
            }
            .accessibilityIdentifier("highlight.repairs")
        }
        .buttonStyle(PressableStyle())
    }

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Get started")
            ListCard {
                Button { addItem() } label: { RecordRow(symbol: "camera", tint: Theme.tintBlue, title: "Add your first item", subtitle: "Snap a photo of an appliance or something valuable") }
                RowDivider()
                Button { app.present(.importDocument(.chooser, assetID: nil)) } label: { RecordRow(symbol: "doc.viewfinder", tint: Theme.tintPurple, title: "Scan a receipt or manual", subtitle: "Text is read on your iPhone — nothing is uploaded") }
                RowDivider()
                Button { app.present(.newTask(assetID: nil)) } label: { RecordRow(symbol: "calendar.badge.plus", tint: Theme.tintOrange, title: "Set up a maintenance reminder", subtitle: "Start from editable suggestions") }
            }
            .buttonStyle(.plain)
        }
    }

    private var upcomingTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Upcoming maintenance", actionTitle: openTasks.isEmpty ? nil : "View all") { app.navigate(.maintenanceList(.upcoming), in: .home) }
            if openTasks.isEmpty {
                ListCard { EmptyStateView(symbol: "calendar", title: "No tasks yet", message: "Add recurring reminders like filter changes or detector tests.", actionTitle: "Add task") { app.present(.newTask(assetID: nil)) } }
            } else {
                ListCard {
                    ForEach(Array(openTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                        if index > 0 { RowDivider() }
                        TaskRow(task: task, showComplete: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var warrantiesSection: some View {
        if !expiringWarranties.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Warranties ending soon", actionTitle: "View all") { app.navigate(.warranties(.expiringSoon), in: .home) }
                ListCard {
                    ForEach(Array(expiringWarranties.prefix(3).enumerated()), id: \.element.id) { index, asset in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: AppRoute.asset(asset)) {
                            RecordRow(symbol: "exclamationmark.shield", tint: Theme.warning, title: asset.name,
                                      subtitle: "Ends \(asset.warrantyExpiration?.formatted(date: .abbreviated, time: .omitted) ?? "")\(asset.warrantyIsEstimated ? " (est.)" : "")",
                                      pill: ("\(asset.warrantyDaysRemaining ?? 0)d left", StatusTone.warning))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentItemsSection: some View {
        let recent = assets.sorted { $0.createdAt > $1.createdAt }.prefix(8)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recently added", actionTitle: "See all") {
                    app.navigate(.assets(AssetListFilter(title: "Recently added", recentOnly: true)), in: .home)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(recent)) { asset in
                            NavigationLink(value: AppRoute.asset(asset)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    AssetThumbnail(asset: asset, size: 116)
                                    Text(asset.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Text(asset.room?.name ?? asset.categoryInfo.name).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                                }
                                .frame(width: 116)
                                .card(padding: 10)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        let items = ActivityItem.build(assets: assets, documents: documents, tasks: scope.tasks(allTasks), services: scope.services(allServices), limit: 4)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recent activity", actionTitle: "View all") { app.navigate(.activity, in: .home) }
                ListCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: item.ref) { ActivityRow(item: item) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var premiumCard: some View {
        Button { app.present(.paywall(nil)) } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("HomeLedger Premium").font(.headline).foregroundStyle(.white)
                    Text("Unlimited items, multiple homes, photo reports and expense insights.").font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .background(Theme.indigoGradient, in: RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("dashboard.premium")
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    var body: some View {
        RecordRow(symbol: item.symbol, tint: tint, title: item.title, subtitle: "\(item.subtitle) · \(item.date.formatted(.relative(presentation: .named)))")
    }
    private var tint: Color {
        switch item.tint {
        case .blue: Theme.tintBlue
        case .green: Theme.tintGreen
        case .orange: Theme.tintOrange
        case .purple: Theme.tintPurple
        }
    }
}

struct ActivityView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query private var assets: [Asset]
    @Query private var documents: [DocumentRecord]
    @Query private var tasks: [MaintenanceTask]
    @Query private var services: [ServiceRecord]

    var body: some View {
        let scope = HomeScope(home: app.currentHome(in: homes))
        let items = ActivityItem.build(assets: scope.assets(assets, includeArchived: true), documents: scope.documents(documents), tasks: scope.tasks(tasks), services: scope.services(services), limit: 200)
        List {
            if items.isEmpty {
                EmptyStateView(symbol: "clock", title: "No activity yet", message: "Items, documents, repairs and completed tasks appear here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                NavigationLink(value: item.ref) { ActivityRow(item: item) }
            }
        }
        .navigationTitle("Activity")
    }
}
