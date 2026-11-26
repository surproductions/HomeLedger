import SwiftData
import SwiftUI

struct WarrantiesView: View {
    let initialStatus: WarrantyStatus?
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query private var allAssets: [Asset]
    @State private var status: WarrantyStatus?

    init(initialStatus: WarrantyStatus?) {
        self.initialStatus = initialStatus
        _status = State(initialValue: initialStatus)
    }

    private var assets: [Asset] { HomeScope(home: app.currentHome(in: homes)).assets(allAssets) }

    var body: some View {
        let grouped = Dictionary(grouping: assets) { $0.warrantyStatus }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    counter(.expiringSoon, grouped[.expiringSoon]?.count ?? 0)
                    counter(.active, grouped[.active]?.count ?? 0)
                    counter(.expired, grouped[.expired]?.count ?? 0)
                    counter(.unknown, grouped[.unknown]?.count ?? 0)
                }
                let order: [WarrantyStatus] = status.map { [$0] } ?? [.expiringSoon, .active, .expired, .unknown]
                ForEach(order) { s in
                    let items = (grouped[s] ?? []).sorted { ($0.warrantyExpiration ?? .distantFuture) < ($1.warrantyExpiration ?? .distantFuture) }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: s.label)
                            if s == .unknown {
                                Text("No end date recorded. HomeLedger won't guess — add the date from your receipt or warranty card to get reminders.")
                                    .font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 4)
                            }
                            ListCard {
                                ForEach(Array(items.enumerated()), id: \.element.id) { i, asset in
                                    if i > 0 { RowDivider() }
                                    NavigationLink(value: AppRoute.asset(asset)) { WarrantyRow(asset: asset) }.buttonStyle(.plain)
                                }
                            }
                        }
                    } else if status == s {
                        ListCard { EmptyStateView(symbol: s.symbol, title: "No \(s.label.lowercased()) warranties", message: "Warranty status is calculated from each item's end date.") }
                    }
                }
                if assets.isEmpty {
                    ListCard { EmptyStateView(symbol: "checkmark.shield", title: "No items yet", message: "Add items with warranty dates to track coverage.") }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Warranties")
    }

    private func counter(_ s: WarrantyStatus, _ count: Int) -> some View {
        Button { status = status == s ? nil : s } label: {
            VStack(spacing: 4) {
                Text("\(count)").font(.hlMetric).foregroundStyle(s.tone.color)
                Text(s.label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(status == s ? s.tone.color.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous).strokeBorder(status == s ? s.tone.color.opacity(0.5) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(s.label)")
        .accessibilityAddTraits(status == s ? .isSelected : [])
    }
}

struct WarrantyRow: View {
    let asset: Asset
    var body: some View {
        HStack(spacing: 12) {
            AssetThumbnail(asset: asset, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                Group {
                    if let end = asset.warrantyExpiration {
                        Text("\(asset.warrantyStatus == .expired ? "Ended" : "Ends") \(end.formatted(date: .abbreviated, time: .omitted))\(asset.warrantyIsEstimated ? " · estimated" : "")")
                    } else {
                        Text("End date unknown")
                    }
                }
                .font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if let days = asset.warrantyDaysRemaining, days >= 0 {
                StatusPill(text: "\(DurationText.compact(days: days)) left", tone: asset.warrantyStatus.tone)
            } else {
                StatusPill(text: asset.warrantyStatus.label, tone: asset.warrantyStatus.tone)
            }
            if asset.warrantyRemindersEnabled && asset.warrantyExpiration != nil && asset.warrantyStatus != .expired {
                Image(systemName: "bell.fill").font(.caption).foregroundStyle(Theme.inkTertiary).accessibilityLabel("Reminders on")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
