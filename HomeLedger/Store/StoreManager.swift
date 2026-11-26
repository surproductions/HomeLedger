import Foundation
import Observation
import StoreKit

/// StoreKit 2 purchase and entitlement layer. Entitlements are derived only from verified
/// transactions returned by StoreKit — there is no local "unlock" flag that could be faked.
@MainActor
@Observable
final class StoreManager {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    enum PurchaseOutcome: Equatable { case success, pending, cancelled, failed(String) }

    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .idle
    private(set) var entitlement: EntitlementState = .free
    private(set) var isPurchasing = false
    var lastMessage: String?

    private var updatesTask: Task<Void, Never>?

    var isPremium: Bool { entitlement.isPremium }
    var yearly: Product? { products.first { $0.id == StoreConfiguration.yearlyProductID } }
    var lifetime: Product? { products.first { $0.id == StoreConfiguration.lifetimeProductID } }

    init(listenForUpdates: Bool = true) {
        if listenForUpdates { startListening() }
    }

    func startListening() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: StoreConfiguration.allProductIDs)
            products = fetched.sorted { $0.price < $1.price }
            loadState = fetched.isEmpty ? .failed("Purchases are not available right now.") : .loaded
        } catch {
            loadState = .failed("Couldn't reach the App Store. Check your connection and try again.")
        }
    }

    func refreshEntitlements() async {
        var transactions: [EntitlementTransaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            transactions.append(EntitlementTransaction(productID: t.productID, expirationDate: t.expirationDate,
                                                       revocationDate: t.revocationDate, isUpgraded: t.isUpgraded))
        }
        entitlement = EntitlementResolver.resolve(transactions)
    }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    lastMessage = "Thank you — HomeLedger Premium is active."
                    return .success
                case .unverified:
                    lastMessage = "The purchase couldn't be verified. You have not been charged twice; try Restore Purchases."
                    return .failed(lastMessage ?? "")
                }
            case .pending:
                lastMessage = "Your purchase is pending approval. Premium unlocks automatically once it's approved."
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("Unknown purchase result.")
            }
        } catch {
            lastMessage = "The purchase couldn't be completed. \(error.localizedDescription)"
            return .failed(lastMessage ?? "")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastMessage = isPremium ? "Purchases restored." : "No previous purchases were found for this Apple Account."
        } catch {
            lastMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}
