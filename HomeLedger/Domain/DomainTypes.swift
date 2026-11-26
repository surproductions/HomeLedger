import Foundation

enum HomeType: String, CaseIterable, Identifiable, Codable {
    case house, apartment, condo, townhouse, cabin, rental, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .house: "House"
        case .apartment: "Apartment"
        case .condo: "Condo"
        case .townhouse: "Townhouse"
        case .cabin: "Cabin / Vacation home"
        case .rental: "Rental property"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .house: "house"
        case .apartment: "building.2"
        case .condo: "building"
        case .townhouse: "house.and.flag"
        case .cabin: "tree"
        case .rental: "key"
        case .other: "mappin.and.ellipse"
        }
    }
}

enum AssetCategory: String, CaseIterable, Identifiable, Codable {
    case appliance, electronics, furniture, hvac, plumbing, electrical, tools, outdoor, vehicle, jewelry, art, kitchen, decor, sports, other
    var id: String { rawValue }
    var info: CategoryInfo {
        switch self {
        case .appliance: CategoryInfo(key: rawValue, name: "Appliances", symbol: "washer")
        case .electronics: CategoryInfo(key: rawValue, name: "Electronics", symbol: "tv")
        case .furniture: CategoryInfo(key: rawValue, name: "Furniture", symbol: "sofa")
        case .hvac: CategoryInfo(key: rawValue, name: "Heating & Cooling", symbol: "fan")
        case .plumbing: CategoryInfo(key: rawValue, name: "Plumbing", symbol: "drop")
        case .electrical: CategoryInfo(key: rawValue, name: "Electrical", symbol: "bolt")
        case .tools: CategoryInfo(key: rawValue, name: "Tools", symbol: "wrench.and.screwdriver")
        case .outdoor: CategoryInfo(key: rawValue, name: "Outdoor & Garden", symbol: "leaf")
        case .vehicle: CategoryInfo(key: rawValue, name: "Vehicles", symbol: "car")
        case .jewelry: CategoryInfo(key: rawValue, name: "Jewelry & Watches", symbol: "sparkles")
        case .art: CategoryInfo(key: rawValue, name: "Art & Collectibles", symbol: "photo.artframe")
        case .kitchen: CategoryInfo(key: rawValue, name: "Kitchenware", symbol: "fork.knife")
        case .decor: CategoryInfo(key: rawValue, name: "Decor & Lighting", symbol: "lamp.floor")
        case .sports: CategoryInfo(key: rawValue, name: "Sports & Leisure", symbol: "figure.run")
        case .other: CategoryInfo(key: rawValue, name: "Other", symbol: "shippingbox")
        }
    }
}

/// A resolved category: either built-in or user-defined (`custom:<name>`).
struct CategoryInfo: Hashable, Identifiable {
    let key: String
    let name: String
    let symbol: String
    var id: String { key }

    static let customPrefix = "custom:"

    static func custom(name: String, symbol: String = "tag") -> CategoryInfo {
        CategoryInfo(key: customPrefix + name, name: name, symbol: symbol)
    }

    static func resolve(_ key: String) -> CategoryInfo {
        if let builtIn = AssetCategory(rawValue: key) { return builtIn.info }
        if key.hasPrefix(customPrefix) {
            return CategoryInfo(key: key, name: String(key.dropFirst(customPrefix.count)), symbol: "tag")
        }
        return AssetCategory.other.info
    }
}

enum AssetCondition: String, CaseIterable, Identifiable, Codable {
    case new, excellent, good, fair, poor, unknown
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum DocumentKind: String, CaseIterable, Identifiable, Codable {
    case receipt, warranty, manual, invoice, service, insurance, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .receipt: "Receipt"
        case .warranty: "Warranty"
        case .manual: "Manual"
        case .invoice: "Invoice"
        case .service: "Service record"
        case .insurance: "Insurance"
        case .other: "Other"
        }
    }
    var pluralLabel: String {
        switch self {
        case .receipt: "Receipts"
        case .warranty: "Warranties"
        case .manual: "Manuals"
        case .invoice: "Invoices"
        case .service: "Service records"
        case .insurance: "Insurance"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .receipt: "receipt"
        case .warranty: "checkmark.shield"
        case .manual: "book.closed"
        case .invoice: "doc.text"
        case .service: "wrench.and.screwdriver"
        case .insurance: "umbrella"
        case .other: "doc"
        }
    }
}

enum StoredContentType: String, Codable {
    case pdf, jpeg, png, heic
    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
    var isImage: Bool { self != .pdf }
}

enum ServiceKind: String, CaseIterable, Identifiable, Codable {
    case repair, service, inspection, installation, improvement
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .repair: "wrench.adjustable"
        case .service: "gearshape.2"
        case .inspection: "magnifyingglass"
        case .installation: "shippingbox"
        case .improvement: "hammer"
        }
    }
    var expenseCategory: ExpenseCategory {
        switch self {
        case .repair: .repair
        case .service, .inspection: .maintenance
        case .installation, .improvement: .improvement
        }
    }
}

enum MaintenancePriority: String, CaseIterable, Identifiable, Codable, Comparable {
    case low, normal, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    private var rank: Int { switch self { case .low: 0; case .normal: 1; case .high: 2 } }
    static func < (lhs: MaintenancePriority, rhs: MaintenancePriority) -> Bool { lhs.rank < rhs.rank }
}

enum MaintenanceLogKind: String, Codable {
    case completed, skipped
}

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case purchase, maintenance, repair, improvement, utilities, insurance, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .purchase: "bag"
        case .maintenance: "wrench.and.screwdriver"
        case .repair: "wrench.adjustable"
        case .improvement: "hammer"
        case .utilities: "bolt"
        case .insurance: "umbrella"
        case .other: "ellipsis.circle"
        }
    }
}

// MARK: - Money

/// Monetary helpers. Values are stored as integer cents and rounded half-up (bankers' rounding is
/// avoided so totals match what people see on receipts).
enum Money {
    static func cents(from decimal: Decimal) -> Int {
        var value = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func decimal(fromCents cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    static func format(cents: Int, currencyCode: String = Preferences.currencyCode, showCents: Bool = true) -> String {
        let decimal = decimal(fromCents: cents)
        return decimal.formatted(.currency(code: currencyCode).precision(.fractionLength(showCents ? 2 : 0)))
    }

    static func format(_ decimal: Decimal, currencyCode: String = Preferences.currencyCode) -> String {
        decimal.formatted(.currency(code: currencyCode))
    }

    /// Parses user-entered amounts such as "1,299.99", "$45", "45.5" or "1.299,99".
    static func parse(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !cleaned.isEmpty, cleaned.contains(where: \.isNumber) else { return nil }
        let lastDot = cleaned.lastIndex(of: ".")
        let lastComma = cleaned.lastIndex(of: ",")
        if let dot = lastDot, let comma = lastComma {
            if comma > dot { // 1.299,99
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else { // 1,299.99
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if let comma = lastComma {
            let decimals = cleaned.distance(from: comma, to: cleaned.endIndex) - 1
            if (1...2).contains(decimals) && cleaned.filter({ $0 == "," }).count == 1 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func sum(_ cents: [Int]) -> Int { cents.reduce(0, +) }
}

// MARK: - Preferences

enum Preferences {
    static let currencyCodeKey = "pref.currencyCode"
    static let displayNameKey = "pref.displayName"
    static let onboardingCompleteKey = "pref.onboardingComplete"
    static let defaultWarrantyOffsetsKey = "pref.defaultWarrantyOffsets"
    static let reminderHourKey = "pref.reminderHour"
    static let notificationsEnabledKey = "pref.notificationsEnabled"
    static let selectedHomeIDKey = "pref.selectedHomeID"
    static let dateStyleKey = "pref.dateStyle"

    static var defaults: UserDefaults = .standard

    static var currencyCode: String {
        defaults.string(forKey: currencyCodeKey) ?? Locale.current.currency?.identifier ?? "USD"
    }

    static var reminderHour: Int {
        let value = defaults.object(forKey: reminderHourKey) as? Int
        return value ?? 9
    }

    static var defaultWarrantyOffsets: [Int] {
        (defaults.array(forKey: defaultWarrantyOffsetsKey) as? [Int]) ?? [30, 14, 7]
    }

    static var notificationsEnabled: Bool {
        defaults.object(forKey: notificationsEnabledKey) as? Bool ?? true
    }
}
