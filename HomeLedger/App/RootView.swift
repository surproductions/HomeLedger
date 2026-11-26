import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Preferences.onboardingCompleteKey) private var onboardingComplete = false

    var body: some View {
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .task {
            await app.store.refreshEntitlements()
            await app.store.loadProducts()
            applyStartScreen()
            app.syncReminders(context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.syncReminders(context) }
            if phase == .background { try? context.save() }
        }
    }

    /// Screenshot automation: jump directly to a screen with sample data.
    private func applyStartScreen() {
        guard let screen = app.launch.startScreen else { return }
        let data = DataService(context: context)
        switch screen {
        case "myhome": app.selectedTab = .myHome
        case "maintenance": app.selectedTab = .maintenance
        case "documents": app.selectedTab = .documents
        case "asset":
            if let asset = data.fetchAll(Asset.self).first(where: { $0.name == "Refrigerator" }) { app.navigate(.asset(asset), in: .myHome) }
        case "warranties": app.navigate(.warranties(nil), in: .home)
        case "expenses": app.navigate(.expenses, in: .home)
        case "assistant": app.sheet = .search
        case "report": app.sheet = .report
        case "settings": app.sheet = .settings
        case "paywall": app.sheet = .paywall(nil)
        default: app.selectedTab = .home
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            NavigationStack(path: $app.homePath) { DashboardView().withAppDestinations() }
                .tag(AppTab.home)
                .toolbar(.hidden, for: .tabBar)
            NavigationStack(path: $app.myHomePath) { MyHomeView().withAppDestinations() }
                .tag(AppTab.myHome)
                .toolbar(.hidden, for: .tabBar)
            NavigationStack(path: $app.maintenancePath) { MaintenanceView().withAppDestinations() }
                .tag(AppTab.maintenance)
                .toolbar(.hidden, for: .tabBar)
            NavigationStack(path: $app.documentsPath) { DocumentsView().withAppDestinations() }
                .tag(AppTab.documents)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $app.selectedTab) { app.present(.addMenu) }
        }
        .overlay(alignment: .top) { ToastView(message: app.toast) }
        .sheet(item: $app.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(app)
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                if tab == .add {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Theme.heroGradient, in: Circle())
                            .shadow(color: Theme.brand.opacity(0.35), radius: 10, y: 4)
                    }
                    .buttonStyle(PressableStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Add")
                    .accessibilityHint("Add an item, document, task, repair or expense")
                    .accessibilityIdentifier("tab.add")
                } else {
                    tabButton(tab)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.10), radius: 18, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(MotionSafe.animation(reduceMotion)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? "\(tab.symbol).fill" : tab.symbol)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .frame(height: 22)
                Text(tab == .maintenance ? "Upkeep" : tab.title)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.brand : Theme.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? Theme.brandSoft : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

struct ToastView: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.ink.opacity(0.92), in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }
}

/// Resolves sheet enum cases to views.
struct SheetHost: View {
    let sheet: AppSheet
    @Environment(\.modelContext) private var context

    var body: some View {
        switch sheet {
        case .addMenu: AddMenuView().presentationDetents([.medium, .large])
        case .newAsset(let roomID): AssetEditorView(asset: nil, initialRoomID: roomID)
        case .editAsset(let asset): AssetEditorView(asset: asset, initialRoomID: nil)
        case .importDocument(let source, let assetID): DocumentImportFlow(source: source, assetID: assetID)
        case .newTask(let assetID): TaskEditorView(task: nil, assetID: assetID)
        case .editTask(let task): TaskEditorView(task: task, assetID: nil)
        case .newService(let assetID): ServiceEditorView(record: nil, assetID: assetID)
        case .editService(let record): ServiceEditorView(record: record, assetID: nil)
        case .newExpense(let assetID): ExpenseEditorView(expense: nil, assetID: assetID)
        case .editExpense(let expense): ExpenseEditorView(expense: expense, assetID: nil)
        case .report: ReportBuilderView()
        case .paywall(let feature): PaywallView(highlight: feature)
        case .search: SearchView()
        case .settings: SettingsView()
        case .newHome: HomeEditorView(home: nil)
        case .editHome(let home): HomeEditorView(home: home)
        }
    }
}

extension View {
    func withAppDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteView(route: route)
        }
        .navigationDestination(for: RecordRef.self) { ref in
            RecordRefView(ref: ref)
        }
    }
}

struct AppRouteView: View {
    let route: AppRoute
    var body: some View {
        switch route {
        case .assets(let filter): AssetListView(filter: filter)
        case .warranties(let status): WarrantiesView(initialStatus: status)
        case .repairs: RepairsView()
        case .expenses: ExpensesView()
        case .maintenanceList(let filter): MaintenanceListView(filter: filter)
        case .documents(let kind): DocumentListView(kind: kind)
        case .homes: HomesManagerView()
        case .room(let room): RoomDetailView(room: room)
        case .asset(let asset): AssetDetailView(asset: asset)
        case .document(let doc): DocumentDetailView(document: doc)
        case .task(let task): TaskDetailView(task: task)
        case .service(let record): ServiceDetailView(record: record)
        case .expense(let expense): ExpenseDetailView(expense: expense)
        case .activity: ActivityView()
        }
    }
}

struct RecordRefView: View {
    let ref: RecordRef
    var body: some View {
        switch ref {
        case .asset(let a): AssetDetailView(asset: a)
        case .room(let r): RoomDetailView(room: r)
        case .document(let d): DocumentDetailView(document: d)
        case .task(let t): TaskDetailView(task: t)
        case .service(let s): ServiceDetailView(record: s)
        case .expense(let e): ExpenseDetailView(expense: e)
        }
    }
}
