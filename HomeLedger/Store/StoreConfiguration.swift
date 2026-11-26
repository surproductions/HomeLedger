import Foundation

/// Single source of truth for App Store product identifiers.
/// These IDs must match the products created in App Store Connect (and `Config/HomeLedger.storekit`
/// for local testing). Changing a price is done in App Store Connect — never in code.
enum StoreConfiguration {
    static let yearlyProductID = "com.surproductions.homeledger.premium.yearly"
    static let lifetimeProductID = "com.surproductions.homeledger.premium.lifetime"
    static let subscriptionGroupName = "HomeLedger Premium"

    static var allProductIDs: [String] { [yearlyProductID, lifetimeProductID] }

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://github.com/surproductions/HomeLedger/blob/main/docs/PRIVACY.md")!
}

/// What the current user is entitled to. Basic access to existing records is never gated.
struct EntitlementState: Equatable {
    enum Source: Equatable { case none, subscription(expires: Date?), lifetime }

    var source: Source = .none
    var isPremium: Bool { source != .none }

    static let freeAssetLimit = 25
    static let freeHomeLimit = 1

    static let free = EntitlementState()

    func canAddHome(currentCount: Int) -> Bool { isPremium || currentCount < Self.freeHomeLimit }
    func canAddAsset(currentActiveCount: Int) -> Bool { isPremium || currentActiveCount < Self.freeAssetLimit }
}

enum PremiumFeature: String, CaseIterable, Identifiable {
    case unlimitedItems, multipleHomes, photoReports, expenseInsights, customReminders
    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedItems: "Unlimited items"
        case .multipleHomes: "Multiple homes"
        case .photoReports: "Photo inventory reports"
        case .expenseInsights: "Expense insights"
        case .customReminders: "Custom reminder schedules"
        }
    }

    var detail: String {
        switch self {
        case .unlimitedItems: "Free includes up to \(EntitlementState.freeAssetLimit) active items."
        case .multipleHomes: "Track a vacation home, rental or a parent's house."
        case .photoReports: "PDF reports with photos and replacement values."
        case .expenseInsights: "Annual trends, category breakdowns and lifetime cost per item."
        case .customReminders: "Choose your own warranty reminder intervals."
        }
    }

    var symbol: String {
        switch self {
        case .unlimitedItems: "square.stack.3d.up"
        case .multipleHomes: "house.and.flag"
        case .photoReports: "doc.richtext"
        case .expenseInsights: "chart.bar.xaxis"
        case .customReminders: "bell.badge"
        }
    }
}

/// A minimal, testable view of a StoreKit transaction.
struct EntitlementTransaction: Equatable {
    var productID: String
    var expirationDate: Date?
    var revocationDate: Date?
    var isUpgraded: Bool = false
}

enum EntitlementResolver {
    /// Resolves verified transactions into an entitlement. Revoked or expired transactions grant nothing.
    static func resolve(_ transactions: [EntitlementTransaction], now: Date = .now) -> EntitlementState {
        var best: EntitlementState.Source = .none
        for t in transactions where t.revocationDate == nil && !t.isUpgraded {
            switch t.productID {
            case StoreConfiguration.lifetimeProductID:
                return EntitlementState(source: .lifetime)
            case StoreConfiguration.yearlyProductID:
                if let exp = t.expirationDate, exp <= now { continue }
                if case .subscription(let existing) = best, let existing, let exp = t.expirationDate, existing >= exp { continue }
                best = .subscription(expires: t.expirationDate)
            default:
                continue
            }
        }
        return EntitlementState(source: best)
    }
}
