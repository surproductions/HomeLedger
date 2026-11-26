import Foundation
import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, myHome, add, maintenance, documents
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .myHome: "My Home"
        case .add: "Add"
        case .maintenance: "Maintenance"
        case .documents: "Documents"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .myHome: "house"
        case .add: "plus"
        case .maintenance: "wrench.and.screwdriver"
        case .documents: "doc.text"
        }
    }
}

/// Navigation destinations shared by every tab's stack.
enum AppRoute: Hashable {
    case assets(AssetListFilter)
    case warranties(WarrantyStatus?)
    case repairs
    case expenses
    case maintenanceList(MaintenanceFilter)
    case documents(DocumentKind?)
    case homes
    case room(Room)
    case asset(Asset)
    case document(DocumentRecord)
    case task(MaintenanceTask)
    case service(ServiceRecord)
    case expense(Expense)
    case activity
}

struct AssetListFilter: Hashable {
    var title: String = "All items"
    var roomID: UUID?
    var categoryKey: String?
    var unassignedOnly = false
    var recentOnly = false
    var showArchived = false
}

enum MaintenanceFilter: String, Hashable, CaseIterable, Identifiable {
    case upcoming, overdue, all, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .overdue: "Overdue"
        case .all: "All"
        case .history: "History"
        }
    }
}

enum DocumentSource: String, Identifiable {
    case camera, photos, files, chooser
    var id: String { rawValue }
}

enum AppSheet: Identifiable {
    case addMenu
    case newAsset(roomID: UUID?)
    case editAsset(Asset)
    case importDocument(DocumentSource, assetID: UUID?)
    case newTask(assetID: UUID?)
    case editTask(MaintenanceTask)
    case newService(assetID: UUID?)
    case editService(ServiceRecord)
    case newExpense(assetID: UUID?)
    case editExpense(Expense)
    case report
    case paywall(PremiumFeature?)
    case search
    case settings
    case newHome
    case editHome(Home)

    var id: String {
        switch self {
        case .addMenu: "addMenu"
        case .newAsset(let r): "newAsset-\(r?.uuidString ?? "")"
        case .editAsset(let a): "editAsset-\(a.id)"
        case .importDocument(let s, let a): "import-\(s.rawValue)-\(a?.uuidString ?? "")"
        case .newTask(let a): "newTask-\(a?.uuidString ?? "")"
        case .editTask(let t): "editTask-\(t.id)"
        case .newService(let a): "newService-\(a?.uuidString ?? "")"
        case .editService(let s): "editService-\(s.id)"
        case .newExpense(let a): "newExpense-\(a?.uuidString ?? "")"
        case .editExpense(let e): "editExpense-\(e.id)"
        case .report: "report"
        case .paywall(let f): "paywall-\(f?.rawValue ?? "")"
        case .search: "search"
        case .settings: "settings"
        case .newHome: "newHome"
        case .editHome(let h): "editHome-\(h.id)"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .home
    var homePath: [AppRoute] = []
    var myHomePath: [AppRoute] = []
    var maintenancePath: [AppRoute] = []
    var documentsPath: [AppRoute] = []
    var sheet: AppSheet?
    var toast: String?
    var selectedHomeID: UUID? {
        didSet { UserDefaults.standard.set(selectedHomeID?.uuidString, forKey: Preferences.selectedHomeIDKey) }
    }

    let store = StoreManager()
    let launch = LaunchOptions.current
    private var toastTask: Task<Void, Never>?

    init() {
        selectedHomeID = UserDefaults.standard.string(forKey: Preferences.selectedHomeIDKey).flatMap(UUID.init(uuidString:))
    }

    var entitlement: EntitlementState { store.entitlement }
    var isPremium: Bool { store.isPremium }

    func currentHome(in homes: [Home]) -> Home? {
        let sorted = homes.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
        return sorted.first { $0.id == selectedHomeID } ?? sorted.first
    }

    func present(_ sheet: AppSheet) {
        // Dismiss any current sheet first so chained presentations are reliable.
        if self.sheet != nil {
            self.sheet = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                self.sheet = sheet
            }
        } else {
            self.sheet = sheet
        }
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { self.toast = nil }
        }
    }

    func navigate(_ route: AppRoute, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        selectedTab = target
        switch target {
        case .home, .add: homePath.append(route)
        case .myHome: myHomePath.append(route)
        case .maintenance: maintenancePath.append(route)
        case .documents: documentsPath.append(route)
        }
    }

    /// Requests a premium feature; presents the paywall when not entitled.
    func requirePremium(_ feature: PremiumFeature) -> Bool {
        if isPremium { return true }
        present(.paywall(feature))
        return false
    }

    func syncReminders(_ context: ModelContext) {
        Task { await NotificationService.shared.sync(context: context) }
    }
}
