import SwiftUI

// MARK: - Icon badge

struct IconBadge: View {
    let systemName: String
    var tint: Color = Theme.brand
    var size: CGFloat = 40
    var filled: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: size, height: size)
            .background((filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12))), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Theme.brand)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Status pill

enum StatusTone {
    case neutral, success, warning, danger, info, brand
    var color: Color {
        switch self {
        case .neutral: Theme.inkSecondary
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .info: Theme.info
        case .brand: Theme.brand
        }
    }
}

struct StatusPill: View {
    let text: String
    var tone: StatusTone = .neutral
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.color.opacity(0.12), in: Capsule())
    }
}

extension WarrantyStatus {
    var tone: StatusTone {
        switch self {
        case .active: .success
        case .expiringSoon: .warning
        case .expired: .danger
        case .unknown: .neutral
        }
    }
}

extension TaskDueState {
    var tone: StatusTone {
        switch self {
        case .overdue: .danger
        case .dueToday, .dueSoon: .warning
        case .upcoming: .neutral
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            IconBadge(systemName: symbol, tint: Theme.brand, size: 56)
            Text(title).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .clipShape(Capsule())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String
    var footnote: String?
    var footnoteTone: StatusTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBadge(systemName: symbol, tint: tint, size: 34)
            Text(value)
                .font(.hlMetric)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
            if let footnote {
                Text(footnote)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(footnoteTone.color)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Gradient feature card (Traceflow-style highlight tile)

struct GradientStatCard: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24).background(.white.opacity(0.18), in: Circle())
            }
            Text(value).font(.hlMetric).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(gradient, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ring progress

struct RingProgress: View {
    let progress: Double
    var tint: Color = Theme.brand
    var lineWidth: CGFloat = 6
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent")
    }
}

// MARK: - Hero quick action (banking-app style circle button)

struct HeroActionButton: View {
    let title: String
    let symbol: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.brand : .white)
                    .frame(width: 54, height: 54)
                    .background(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.16)), in: Circle())
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Rows

struct RecordRow: View {
    let symbol: String
    var tint: Color = Theme.brand
    let title: String
    var subtitle: String?
    var trailing: String?
    var trailingDetail: String?
    var pill: (String, StatusTone)?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let trailing { Text(trailing).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1) }
                if let trailingDetail { Text(trailingDetail).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1) }
                if let pill { StatusPill(text: pill.0, tone: pill.1) }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AssetThumbnail: View {
    let asset: Asset
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let photo = asset.sortedPhotos.first, let image = FileStore.shared.thumbnail(for: photo.fileName, maxPixel: size * 3) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: asset.categoryInfo.symbol)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.brandSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct AssetRow: View {
    let asset: Asset
    var showRoom: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            AssetThumbnail(asset: asset)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                Text(joinedParts([showRoom ? asset.room?.name : nil, asset.displaySubtitle], separator: " · "))
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let price = asset.purchasePriceCents {
                    Text(Money.format(cents: price, showCents: false)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                if asset.isArchived {
                    StatusPill(text: "Archived", tone: .neutral)
                } else if asset.warrantyStatus == .expiringSoon || asset.warrantyStatus == .expired {
                    StatusPill(text: asset.warrantyStatus == .expired ? "Warranty ended" : "Warranty ending", tone: asset.warrantyStatus.tone)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A card that hosts a vertical list of rows separated by hairlines.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .card(padding: 0)
    }
}

struct RowDivider: View {
    var body: some View { Divider().overlay(Theme.hairline).padding(.leading, 52) }
}

// MARK: - Filter chips

struct FilterChip: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .background(isSelected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.card), in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Labeled value row (detail screens)

struct DetailRow: View {
    let label: String
    let value: String
    var valueTone: Color = Theme.ink
    var copyable: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(valueTone).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if copyable {
                Button { UIPasteboard.general.string = value } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
        }
    }
}

// MARK: - Money field

/// Text field bound to optional cents with forgiving parsing ("1,299.99", "$45").
struct MoneyField: View {
    let title: String
    @Binding var cents: Int?
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(Money.format(cents: 0), text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onAppear { text = Self.display(cents) }
                .onChange(of: cents) { _, newValue in
                    // Keep the text in sync with external changes, but never rewrite while the user types.
                    if !focused && Money.parse(text).map(Money.cents(from:)) != newValue { text = Self.display(newValue) }
                }
                .onChange(of: text) { _, newValue in
                    let parsed = Money.parse(newValue).map(Money.cents(from:))
                    if parsed != cents { cents = parsed }
                }
                .accessibilityLabel(title)
        }
    }

    private static func display(_ cents: Int?) -> String {
        cents.map { Money.decimal(fromCents: $0).formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
    }
}

/// Optional date picker: shows "Add" until a date is set and lets the user clear it.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?
    var defaultDate: Date = .now

    var body: some View {
        if let value = date {
            HStack {
                DatePicker(title, selection: Binding(get: { value }, set: { date = $0 }), displayedComponents: .date)
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            }
        } else {
            Button { date = defaultDate } label: {
                HStack {
                    Text(title).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("Add").foregroundStyle(Theme.brand)
                }
            }
        }
    }
}
