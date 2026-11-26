import StoreKit
import SwiftUI

struct PaywallView: View {
    let highlight: PremiumFeature?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String = StoreConfiguration.yearlyProductID

    private var store: StoreManager { app.store }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 64, height: 64).background(.white.opacity(0.18), in: Circle())
                        Text("HomeLedger Premium").font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("Everything in Free, plus:").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))

                    VStack(spacing: 0) {
                        ForEach(PremiumFeature.allCases) { f in
                            HStack(alignment: .top, spacing: 12) {
                                IconBadge(systemName: f.symbol, tint: f == highlight ? .white : Theme.brand, size: 38, filled: f == highlight)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text(f.detail).font(.caption).foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .card(padding: 14)

                    Text("Free always includes one home, up to \(EntitlementState.freeAssetLimit) active items, documents with on-device text recognition, maintenance and warranty reminders, search, backups and a full PDF report without photos. Your existing records always stay accessible.")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)

                    productsSection

                    if app.isPremium {
                        Label("Premium is active. Thank you!", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.success)
                    }

                    VStack(spacing: 8) {
                        Button("Restore purchases") { Task { await store.restore() } }.font(.subheadline.weight(.semibold))
                        if let message = store.lastMessage { Text(message).font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center) }
                        Text("The yearly plan renews automatically at the price shown unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple Account settings. Payment is charged to your Apple Account at confirmation. The lifetime option is a one-time purchase.")
                            .font(.caption2).foregroundStyle(Theme.inkTertiary).multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Button("Terms of Use") { openURL(StoreConfiguration.termsURL) }
                            Button("Privacy Policy") { openURL(StoreConfiguration.privacyURL) }
                        }
                        .font(.caption)
                    }
                }
                .padding(Theme.gutter)
            }
            .canvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() }.accessibilityIdentifier("paywall.close") } }
            .task { if store.products.isEmpty { await store.loadProducts() } }
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        switch store.loadState {
        case .loading, .idle:
            ProgressView("Loading prices…").padding()
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await store.loadProducts() } }
            }
            .card()
        case .loaded:
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    Button { selectedID = product.id } label: { productRow(product) }
                        .buttonStyle(.plain)
                }
                Button {
                    guard let product = store.products.first(where: { $0.id == selectedID }) else { return }
                    Task {
                        let outcome = await store.purchase(product)
                        if outcome == .success { dismiss() }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if store.isPurchasing { ProgressView().tint(.white) } else { Text(ctaTitle).font(.headline) }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(store.isPurchasing || app.isPremium)
                .accessibilityIdentifier("paywall.purchase")
            }
        }
    }

    private var ctaTitle: String {
        guard let p = store.products.first(where: { $0.id == selectedID }) else { return "Continue" }
        if p.id == StoreConfiguration.yearlyProductID, p.subscription?.introductoryOffer != nil { return "Start free trial" }
        return "Continue — \(p.displayPrice)"
    }

    private func productRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        let isYearly = product.id == StoreConfiguration.yearlyProductID
        return HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selected ? Theme.brand : Theme.inkTertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(isYearly ? "Yearly" : "Lifetime").font(.headline).foregroundStyle(Theme.ink)
                Text(subtitle(for: product)).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Text(isYearly ? "\(product.displayPrice)/yr" : product.displayPrice).font(.headline).foregroundStyle(Theme.ink)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).strokeBorder(selected ? Theme.brand : Theme.hairline, lineWidth: selected ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func subtitle(for product: Product) -> String {
        if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "\(offer.period.value) \(String(describing: offer.period.unit).lowercased())\(offer.period.value == 1 ? "" : "s") free, then billed yearly"
        }
        return product.id == StoreConfiguration.lifetimeProductID ? "Pay once, keep Premium" : product.description
    }
}
