import Foundation

enum WarrantyStatus: String, CaseIterable, Identifiable {
    case expiringSoon, active, expired, unknown
    var id: String { rawValue }

    var label: String {
        switch self {
        case .expiringSoon: "Expiring soon"
        case .active: "Active"
        case .expired: "Expired"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .expiringSoon: "exclamationmark.shield"
        case .active: "checkmark.shield"
        case .expired: "xmark.shield"
        case .unknown: "questionmark.diamond"
        }
    }

    /// Status is purely date-based. A missing expiration is reported as `.unknown` — never guessed.
    static func evaluate(expiration: Date?, now: Date = .now, soonWindowDays: Int = 60, calendar: Calendar = .current) -> WarrantyStatus {
        guard let expiration else { return .unknown }
        let today = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiration)
        if end < today { return .expired }
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return days <= soonWindowDays ? .expiringSoon : .active
    }

    static func daysRemaining(expiration: Date?, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let expiration else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiration)).day
    }
}

extension Asset {
    var warrantyStatus: WarrantyStatus { WarrantyStatus.evaluate(expiration: warrantyExpiration) }
    var hasWarrantyInfo: Bool { warrantyExpiration != nil || warrantyStart != nil || !warrantyProvider.isEmpty }
    var warrantyDaysRemaining: Int? { WarrantyStatus.daysRemaining(expiration: warrantyExpiration) }

    /// Optional suggestions for incomplete records — shown as gentle prompts, never as errors.
    var missingInfoSuggestions: [String] {
        var items: [String] = []
        if (photos ?? []).isEmpty { items.append("Add a photo") }
        if serialNumber.isEmpty && [AssetCategory.appliance.rawValue, AssetCategory.electronics.rawValue, AssetCategory.hvac.rawValue, AssetCategory.tools.rawValue].contains(category) {
            items.append("Add the serial number")
        }
        if purchaseDate == nil { items.append("Add the purchase date") }
        if purchasePriceCents == nil { items.append("Add the purchase price") }
        if !(documents ?? []).contains(where: { $0.kind == .receipt || $0.kind == .invoice }) { items.append("Attach a receipt") }
        if warrantyExpiration == nil && [AssetCategory.appliance.rawValue, AssetCategory.electronics.rawValue, AssetCategory.hvac.rawValue].contains(category) {
            items.append("Add warranty details")
        }
        return items
    }

    /// Lifetime cost: purchase price plus every linked non-purchase expense.
    /// Purchase-category expenses are only counted when no purchase price is recorded, to avoid double counting.
    var lifetimeCostCents: Int {
        let linked = expenses ?? []
        let nonPurchase = linked.filter { $0.category != .purchase }.map(\.amountCents)
        let purchase = purchasePriceCents ?? linked.filter { $0.category == .purchase }.map(\.amountCents).reduce(0, +)
        return purchase + nonPurchase.reduce(0, +)
    }

    /// Replacement value when recorded, otherwise purchase price, otherwise zero.
    var recordedValueCents: Int {
        if let r = replacementValueCents { return r }
        if let p = purchasePriceCents { return p }
        return 0
    }

    var repairCostCents: Int {
        (expenses ?? []).filter { $0.category == .repair }.map(\.amountCents).reduce(0, +)
    }
}

/// Computes warranty expiration from a stated coverage period.
enum WarrantyMath {
    static func expiration(start: Date, months: Int, calendar: Calendar = .current) -> Date? {
        guard months > 0 else { return nil }
        guard let end = calendar.date(byAdding: .month, value: months, to: start) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: end)
    }
}
