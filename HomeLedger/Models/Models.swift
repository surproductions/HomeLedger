import Foundation
import SwiftData

// MARK: - Persistence models (Schema V1)
//
// Design notes
// - Every model carries a stable `id: UUID` used for backups, notifications and future sync.
// - All attributes have defaults and all relationships are optional so the schema stays
//   compatible with a future, optional CloudKit mirror (CloudKit requires both).
// - Relationships use `.nullify` unless the child cannot exist without its parent
//   (photos, completion logs, rooms). Destructive cascades that the user should be
//   warned about are performed explicitly in `DataService`, never implicitly.
// - Money is stored as integer minor units (cents) to avoid floating-point drift.
// - Enums are stored as raw strings so new cases never break decoding of old data.

@Model
final class Home {
    var id: UUID = UUID()
    var name: String = ""
    var homeTypeRaw: String = HomeType.house.rawValue
    var addressLine: String = ""
    var notes: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Room.home) var rooms: [Room]? = []
    @Relationship(deleteRule: .nullify, inverse: \Asset.home) var assets: [Asset]? = []
    @Relationship(deleteRule: .nullify, inverse: \MaintenanceTask.home) var tasks: [MaintenanceTask]? = []
    @Relationship(deleteRule: .nullify, inverse: \DocumentRecord.home) var documents: [DocumentRecord]? = []
    @Relationship(deleteRule: .nullify, inverse: \Expense.home) var expenses: [Expense]? = []
    @Relationship(deleteRule: .nullify, inverse: \ServiceRecord.home) var serviceRecords: [ServiceRecord]? = []

    init(name: String, type: HomeType = .house, sortIndex: Int = 0, isSample: Bool = false) {
        self.id = UUID()
        self.name = name
        self.homeTypeRaw = type.rawValue
        self.sortIndex = sortIndex
        self.isSample = isSample
        self.createdAt = .now
        self.updatedAt = .now
    }

    var homeType: HomeType {
        get { HomeType(rawValue: homeTypeRaw) ?? .other }
        set { homeTypeRaw = newValue.rawValue }
    }

    var sortedRooms: [Room] { (rooms ?? []).sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) } }
    var activeAssets: [Asset] { (assets ?? []).filter { !$0.isArchived } }
}

@Model
final class Room {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String = "square.split.bottomrightquarter"
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    var isSample: Bool = false

    var home: Home?
    @Relationship(deleteRule: .nullify, inverse: \Asset.room) var assets: [Asset]? = []
    @Relationship(deleteRule: .nullify, inverse: \MaintenanceTask.room) var tasks: [MaintenanceTask]? = []

    init(name: String, symbolName: String = "square.split.bottomrightquarter", sortIndex: Int = 0, home: Home? = nil, isSample: Bool = false) {
        self.id = UUID()
        self.name = name
        self.symbolName = symbolName
        self.sortIndex = sortIndex
        self.home = home
        self.isSample = isSample
        self.createdAt = .now
    }

    var activeAssets: [Asset] { (assets ?? []).filter { !$0.isArchived } }
}

@Model
final class Asset {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = AssetCategory.other.rawValue
    var brand: String = ""
    var modelNumber: String = ""
    var serialNumber: String = ""
    var barcode: String = ""
    var purchaseDate: Date?
    var purchasePriceCents: Int?
    var retailer: String = ""
    var warrantyStart: Date?
    var warrantyExpiration: Date?
    /// True when the expiration date was calculated from a stated period rather than printed explicitly.
    var warrantyIsEstimated: Bool = false
    var warrantyProvider: String = ""
    var warrantyNotes: String = ""
    var warrantyRemindersEnabled: Bool = true
    var warrantyReminderOffsets: [Int] = [30, 14, 7]
    var conditionRaw: String = AssetCondition.good.rawValue
    var notes: String = ""
    var replacementValueCents: Int?
    var quantity: Int = 1
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    var home: Home?
    var room: Room?
    @Relationship(deleteRule: .cascade, inverse: \AssetPhoto.asset) var photos: [AssetPhoto]? = []
    @Relationship(deleteRule: .nullify, inverse: \DocumentRecord.asset) var documents: [DocumentRecord]? = []
    @Relationship(deleteRule: .nullify, inverse: \ServiceRecord.asset) var serviceRecords: [ServiceRecord]? = []
    @Relationship(deleteRule: .nullify, inverse: \MaintenanceTask.asset) var tasks: [MaintenanceTask]? = []
    @Relationship(deleteRule: .nullify, inverse: \Expense.asset) var expenses: [Expense]? = []

    init(name: String, category: AssetCategory = .other, home: Home? = nil, room: Room? = nil, isSample: Bool = false) {
        self.id = UUID()
        self.name = name
        self.category = category.rawValue
        self.home = home
        self.room = room
        self.isSample = isSample
        self.createdAt = .now
        self.updatedAt = .now
    }

    var condition: AssetCondition {
        get { AssetCondition(rawValue: conditionRaw) ?? .unknown }
        set { conditionRaw = newValue.rawValue }
    }

    var categoryInfo: CategoryInfo { CategoryInfo.resolve(category) }

    var purchasePrice: Decimal? {
        get { purchasePriceCents.map(Money.decimal(fromCents:)) }
        set { purchasePriceCents = newValue.map(Money.cents(from:)) }
    }

    var replacementValue: Decimal? {
        get { replacementValueCents.map(Money.decimal(fromCents:)) }
        set { replacementValueCents = newValue.map(Money.cents(from:)) }
    }

    var sortedPhotos: [AssetPhoto] { (photos ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) } }
    var sortedDocuments: [DocumentRecord] { (documents ?? []).sorted { $0.createdAt > $1.createdAt } }
    var sortedServiceRecords: [ServiceRecord] { (serviceRecords ?? []).sorted { $0.date > $1.date } }

    var displaySubtitle: String {
        let parts = [brand, modelNumber].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return categoryInfo.name
    }

    func touch() { updatedAt = .now }
}

@Model
final class AssetPhoto {
    var id: UUID = UUID()
    var fileName: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    var isSample: Bool = false
    var asset: Asset?

    init(fileName: String, sortIndex: Int = 0, asset: Asset? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.sortIndex = sortIndex
        self.asset = asset
        self.createdAt = .now
    }
}

@Model
final class DocumentRecord {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = DocumentKind.other.rawValue
    var fileName: String = ""
    var originalFileName: String = ""
    var contentTypeRaw: String = StoredContentType.pdf.rawValue
    var fileSize: Int = 0
    var documentDate: Date?
    var vendor: String = ""
    var amountCents: Int?
    var notes: String = ""
    /// Text recognized on-device. Kept locally to power search; never logged or transmitted.
    var recognizedText: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    var home: Home?
    var asset: Asset?
    var serviceRecord: ServiceRecord?
    @Relationship(deleteRule: .nullify, inverse: \Expense.receipt) var expenses: [Expense]? = []

    init(title: String, kind: DocumentKind, fileName: String, contentType: StoredContentType, home: Home? = nil, asset: Asset? = nil) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.contentTypeRaw = contentType.rawValue
        self.home = home
        self.asset = asset
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var contentType: StoredContentType {
        get { StoredContentType(rawValue: contentTypeRaw) ?? .pdf }
        set { contentTypeRaw = newValue.rawValue }
    }

    var amount: Decimal? {
        get { amountCents.map(Money.decimal(fromCents:)) }
        set { amountCents = newValue.map(Money.cents(from:)) }
    }
}

@Model
final class ServiceRecord {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = ServiceKind.repair.rawValue
    var date: Date = Date()
    var details: String = ""
    var vendor: String = ""
    var costCents: Int?
    var followUpDate: Date?
    var followUpNote: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    var home: Home?
    var asset: Asset?
    var task: MaintenanceTask?
    @Relationship(deleteRule: .nullify, inverse: \DocumentRecord.serviceRecord) var documents: [DocumentRecord]? = []
    @Relationship(deleteRule: .nullify, inverse: \Expense.serviceRecord) var expenses: [Expense]? = []

    init(title: String, kind: ServiceKind = .repair, date: Date = .now, home: Home? = nil, asset: Asset? = nil) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.date = date
        self.home = home
        self.asset = asset
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: ServiceKind {
        get { ServiceKind(rawValue: kindRaw) ?? .repair }
        set { kindRaw = newValue.rawValue }
    }

    var cost: Decimal? {
        get { costCents.map(Money.decimal(fromCents:)) }
        set { costCents = newValue.map(Money.cents(from:)) }
    }
}

@Model
final class MaintenanceTask {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var dueDate: Date = Date()
    /// First occurrence of the current schedule. Fixed-schedule recurrences are always computed from
    /// this anchor so month-end dates don't drift (Jan 31 → Feb 29 → Mar 31). Reset when the schedule is edited.
    var recurrenceAnchor: Date?
    var recurrenceUnitRaw: String = RecurrenceUnit.none.rawValue
    var recurrenceInterval: Int = 1
    var recurrenceBasisRaw: String = RecurrenceBasis.schedule.rawValue
    var priorityRaw: String = MaintenancePriority.normal.rawValue
    var estimatedCostCents: Int?
    var remindersEnabled: Bool = true
    var reminderDaysBefore: Int = 1
    var isArchived: Bool = false
    var templateKey: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    var home: Home?
    var room: Room?
    var asset: Asset?
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceLog.task) var logs: [MaintenanceLog]? = []
    @Relationship(deleteRule: .nullify, inverse: \ServiceRecord.task) var serviceRecords: [ServiceRecord]? = []

    init(title: String, dueDate: Date, recurrence: Recurrence = .none, priority: MaintenancePriority = .normal, home: Home? = nil, isSample: Bool = false) {
        self.id = UUID()
        self.title = title
        self.dueDate = dueDate
        self.recurrenceUnitRaw = recurrence.unit.rawValue
        self.recurrenceInterval = recurrence.interval
        self.recurrenceBasisRaw = recurrence.basis.rawValue
        self.priorityRaw = priority.rawValue
        self.home = home
        self.isSample = isSample
        self.createdAt = .now
        self.updatedAt = .now
    }

    var recurrence: Recurrence {
        get {
            Recurrence(unit: RecurrenceUnit(rawValue: recurrenceUnitRaw) ?? .none,
                       interval: max(1, recurrenceInterval),
                       basis: RecurrenceBasis(rawValue: recurrenceBasisRaw) ?? .schedule)
        }
        set {
            recurrenceUnitRaw = newValue.unit.rawValue
            recurrenceInterval = max(1, newValue.interval)
            recurrenceBasisRaw = newValue.basis.rawValue
        }
    }

    var priority: MaintenancePriority {
        get { MaintenancePriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var estimatedCost: Decimal? {
        get { estimatedCostCents.map(Money.decimal(fromCents:)) }
        set { estimatedCostCents = newValue.map(Money.cents(from:)) }
    }

    var sortedLogs: [MaintenanceLog] { (logs ?? []).sorted { $0.date > $1.date } }
    var lastCompleted: Date? { (logs ?? []).filter { $0.kind == .completed }.map(\.date).max() }
}

@Model
final class MaintenanceLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = MaintenanceLogKind.completed.rawValue
    var note: String = ""
    var costCents: Int?
    /// The due date this entry resolved, so history stays meaningful after the task advances.
    var dueDateResolved: Date?
    var isSample: Bool = false
    var task: MaintenanceTask?

    init(date: Date, kind: MaintenanceLogKind, note: String = "", costCents: Int? = nil, dueDateResolved: Date? = nil, task: MaintenanceTask? = nil) {
        self.id = UUID()
        self.date = date
        self.kindRaw = kind.rawValue
        self.note = note
        self.costCents = costCents
        self.dueDateResolved = dueDateResolved
        self.task = task
    }

    var kind: MaintenanceLogKind {
        get { MaintenanceLogKind(rawValue: kindRaw) ?? .completed }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class Expense {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var amountCents: Int = 0
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var vendor: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    var home: Home?
    var asset: Asset?
    var serviceRecord: ServiceRecord?
    var receipt: DocumentRecord?

    init(title: String, amountCents: Int, date: Date = .now, category: ExpenseCategory = .other, home: Home? = nil, asset: Asset? = nil) {
        self.id = UUID()
        self.title = title
        self.amountCents = amountCents
        self.date = date
        self.categoryRaw = category.rawValue
        self.home = home
        self.asset = asset
        self.createdAt = .now
        self.updatedAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { Money.decimal(fromCents: amountCents) }
        set { amountCents = Money.cents(from: newValue) }
    }
}

@Model
final class CustomCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String = "tag"
    var createdAt: Date = Date()

    init(name: String, symbolName: String = "tag") {
        self.id = UUID()
        self.name = name
        self.symbolName = symbolName
        self.createdAt = .now
    }
}

// MARK: - Versioned schema & migration plan

enum HomeLedgerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Home.self, Room.self, Asset.self, AssetPhoto.self, DocumentRecord.self,
         ServiceRecord.self, MaintenanceTask.self, MaintenanceLog.self, Expense.self, CustomCategory.self]
    }
}

/// Add `HomeLedgerSchemaV2` and a `MigrationStage` here when the schema changes.
/// Lightweight changes (new attributes with defaults) can use `.lightweight`.
enum HomeLedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HomeLedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
