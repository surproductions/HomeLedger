import Foundation
import SwiftData

// MARK: - Archive format (versioned)

/// HomeLedger backup format v1: a single JSON document containing every record plus the
/// original photo/document files (base64). Self-contained, human-inspectable and versioned.
struct BackupArchive: Codable {
    static let formatIdentifier = "com.surproductions.homeledger.backup"
    static let currentVersion = 1

    var format: String = formatIdentifier
    var formatVersion: Int = currentVersion
    var createdAt: Date
    var appVersion: String
    var homes: [HomeDTO] = []
    var rooms: [RoomDTO] = []
    var assets: [AssetDTO] = []
    var photos: [PhotoDTO] = []
    var documents: [DocumentDTO] = []
    var services: [ServiceDTO] = []
    var tasks: [TaskDTO] = []
    var logs: [LogDTO] = []
    var expenses: [ExpenseDTO] = []
    var categories: [CategoryDTO] = []
    var files: [FileBlob] = []

    struct HomeDTO: Codable { var id: UUID; var name: String; var homeType: String; var addressLine: String; var notes: String; var sortIndex: Int; var createdAt: Date; var updatedAt: Date }
    struct RoomDTO: Codable { var id: UUID; var name: String; var symbolName: String; var sortIndex: Int; var createdAt: Date; var homeID: UUID? }
    struct AssetDTO: Codable {
        var id: UUID; var name: String; var category: String; var brand: String; var modelNumber: String; var serialNumber: String; var barcode: String
        var purchaseDate: Date?; var purchasePriceCents: Int?; var retailer: String
        var warrantyStart: Date?; var warrantyExpiration: Date?; var warrantyIsEstimated: Bool; var warrantyProvider: String; var warrantyNotes: String
        var warrantyRemindersEnabled: Bool; var warrantyReminderOffsets: [Int]
        var condition: String; var notes: String; var replacementValueCents: Int?; var quantity: Int; var isArchived: Bool
        var createdAt: Date; var updatedAt: Date; var homeID: UUID?; var roomID: UUID?
    }
    struct PhotoDTO: Codable { var id: UUID; var fileName: String; var sortIndex: Int; var createdAt: Date; var assetID: UUID? }
    struct DocumentDTO: Codable {
        var id: UUID; var title: String; var kind: String; var fileName: String; var originalFileName: String; var contentType: String; var fileSize: Int
        var documentDate: Date?; var vendor: String; var amountCents: Int?; var notes: String; var recognizedText: String
        var createdAt: Date; var updatedAt: Date; var homeID: UUID?; var assetID: UUID?; var serviceRecordID: UUID?
    }
    struct ServiceDTO: Codable {
        var id: UUID; var title: String; var kind: String; var date: Date; var details: String; var vendor: String; var costCents: Int?
        var followUpDate: Date?; var followUpNote: String; var createdAt: Date; var updatedAt: Date; var homeID: UUID?; var assetID: UUID?; var taskID: UUID?
    }
    struct TaskDTO: Codable {
        var id: UUID; var title: String; var details: String; var dueDate: Date; var recurrenceUnit: String; var recurrenceInterval: Int; var recurrenceBasis: String
        var priority: String; var estimatedCostCents: Int?; var remindersEnabled: Bool; var reminderDaysBefore: Int; var isArchived: Bool; var templateKey: String
        var createdAt: Date; var updatedAt: Date; var homeID: UUID?; var roomID: UUID?; var assetID: UUID?
        var recurrenceAnchor: Date?
    }
    struct LogDTO: Codable { var id: UUID; var date: Date; var kind: String; var note: String; var costCents: Int?; var dueDateResolved: Date?; var taskID: UUID? }
    struct ExpenseDTO: Codable {
        var id: UUID; var title: String; var date: Date; var amountCents: Int; var category: String; var vendor: String; var notes: String
        var createdAt: Date; var updatedAt: Date; var homeID: UUID?; var assetID: UUID?; var serviceRecordID: UUID?; var receiptID: UUID?
    }
    struct CategoryDTO: Codable { var id: UUID; var name: String; var symbolName: String; var createdAt: Date }
    struct FileBlob: Codable { var name: String; var data: Data }

    var recordCount: Int { homes.count + rooms.count + assets.count + documents.count + services.count + tasks.count + expenses.count }
}

enum BackupError: LocalizedError {
    case notABackup
    case unsupportedVersion(Int)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .notABackup: "This file isn't a HomeLedger backup."
        case .unsupportedVersion(let v): "This backup was made by a newer version of HomeLedger (format \(v)). Update the app and try again."
        case .corrupt(let detail): "The backup appears to be damaged: \(detail). Nothing was changed."
        }
    }
}

struct BackupValidation {
    let archive: BackupArchive
    var warnings: [String]
    var summary: String {
        "\(archive.homes.count) homes · \(archive.assets.count) items · \(archive.documents.count) documents · \(archive.tasks.count) tasks · \(archive.expenses.count) expenses"
    }
}

enum RestoreMode: String, CaseIterable, Identifiable {
    /// Adds records that don't exist yet and updates existing records only when the backup copy is newer.
    case merge
    /// Replaces everything on this device with the backup (after saving a safety backup).
    case replace
    var id: String { rawValue }
}

struct RestoreReport: Equatable {
    var inserted = 0
    var updated = 0
    var skipped = 0
    var filesRestored = 0
    var safetyBackupURL: URL?
}

// MARK: - Service

@MainActor
struct BackupService {
    let context: ModelContext
    var files: FileStore = .shared

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(BackupService.isoFormatter.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = BackupService.isoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(s)")
        }
        return d
    }()

    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func suggestedFileName(now: Date = .now) -> String {
        "HomeLedger Backup \(now.formatted(.iso8601.year().month().day())).json"
    }

    // MARK: Export

    func makeArchive(includeFiles: Bool = true, now: Date = .now) -> BackupArchive {
        let svc = DataService(context: context, files: files)
        var a = BackupArchive(createdAt: now, appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        a.homes = svc.fetchAll(Home.self).map { BackupArchive.HomeDTO(id: $0.id, name: $0.name, homeType: $0.homeTypeRaw, addressLine: $0.addressLine, notes: $0.notes, sortIndex: $0.sortIndex, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
        a.rooms = svc.fetchAll(Room.self).map { BackupArchive.RoomDTO(id: $0.id, name: $0.name, symbolName: $0.symbolName, sortIndex: $0.sortIndex, createdAt: $0.createdAt, homeID: $0.home?.id) }
        a.assets = svc.fetchAll(Asset.self).map {
            BackupArchive.AssetDTO(id: $0.id, name: $0.name, category: $0.category, brand: $0.brand, modelNumber: $0.modelNumber, serialNumber: $0.serialNumber, barcode: $0.barcode,
                  purchaseDate: $0.purchaseDate, purchasePriceCents: $0.purchasePriceCents, retailer: $0.retailer,
                  warrantyStart: $0.warrantyStart, warrantyExpiration: $0.warrantyExpiration, warrantyIsEstimated: $0.warrantyIsEstimated,
                  warrantyProvider: $0.warrantyProvider, warrantyNotes: $0.warrantyNotes, warrantyRemindersEnabled: $0.warrantyRemindersEnabled,
                  warrantyReminderOffsets: $0.warrantyReminderOffsets, condition: $0.conditionRaw, notes: $0.notes,
                  replacementValueCents: $0.replacementValueCents, quantity: $0.quantity, isArchived: $0.isArchived,
                  createdAt: $0.createdAt, updatedAt: $0.updatedAt, homeID: $0.home?.id, roomID: $0.room?.id)
        }
        a.photos = svc.fetchAll(AssetPhoto.self).map { BackupArchive.PhotoDTO(id: $0.id, fileName: $0.fileName, sortIndex: $0.sortIndex, createdAt: $0.createdAt, assetID: $0.asset?.id) }
        a.documents = svc.fetchAll(DocumentRecord.self).map {
            BackupArchive.DocumentDTO(id: $0.id, title: $0.title, kind: $0.kindRaw, fileName: $0.fileName, originalFileName: $0.originalFileName, contentType: $0.contentTypeRaw,
                  fileSize: $0.fileSize, documentDate: $0.documentDate, vendor: $0.vendor, amountCents: $0.amountCents, notes: $0.notes,
                  recognizedText: $0.recognizedText, createdAt: $0.createdAt, updatedAt: $0.updatedAt, homeID: $0.home?.id, assetID: $0.asset?.id, serviceRecordID: $0.serviceRecord?.id)
        }
        a.services = svc.fetchAll(ServiceRecord.self).map {
            BackupArchive.ServiceDTO(id: $0.id, title: $0.title, kind: $0.kindRaw, date: $0.date, details: $0.details, vendor: $0.vendor, costCents: $0.costCents,
                  followUpDate: $0.followUpDate, followUpNote: $0.followUpNote, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                  homeID: $0.home?.id, assetID: $0.asset?.id, taskID: $0.task?.id)
        }
        a.tasks = svc.fetchAll(MaintenanceTask.self).map {
            BackupArchive.TaskDTO(id: $0.id, title: $0.title, details: $0.details, dueDate: $0.dueDate, recurrenceUnit: $0.recurrenceUnitRaw, recurrenceInterval: $0.recurrenceInterval,
                  recurrenceBasis: $0.recurrenceBasisRaw, priority: $0.priorityRaw, estimatedCostCents: $0.estimatedCostCents, remindersEnabled: $0.remindersEnabled,
                  reminderDaysBefore: $0.reminderDaysBefore, isArchived: $0.isArchived, templateKey: $0.templateKey, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                  homeID: $0.home?.id, roomID: $0.room?.id, assetID: $0.asset?.id, recurrenceAnchor: $0.recurrenceAnchor)
        }
        a.logs = svc.fetchAll(MaintenanceLog.self).map { BackupArchive.LogDTO(id: $0.id, date: $0.date, kind: $0.kindRaw, note: $0.note, costCents: $0.costCents, dueDateResolved: $0.dueDateResolved, taskID: $0.task?.id) }
        a.expenses = svc.fetchAll(Expense.self).map {
            BackupArchive.ExpenseDTO(id: $0.id, title: $0.title, date: $0.date, amountCents: $0.amountCents, category: $0.categoryRaw, vendor: $0.vendor, notes: $0.notes,
                  createdAt: $0.createdAt, updatedAt: $0.updatedAt, homeID: $0.home?.id, assetID: $0.asset?.id, serviceRecordID: $0.serviceRecord?.id, receiptID: $0.receipt?.id)
        }
        a.categories = svc.fetchAll(CustomCategory.self).map { BackupArchive.CategoryDTO(id: $0.id, name: $0.name, symbolName: $0.symbolName, createdAt: $0.createdAt) }
        if includeFiles {
            a.files = svc.referencedFileNames().sorted().compactMap { name in files.data(for: name).map { BackupArchive.FileBlob(name: name, data: $0) } }
        }
        return a
    }

    func exportData(now: Date = .now) throws -> Data {
        try Self.encoder.encode(makeArchive(now: now))
    }

    // MARK: Validate

    static func validate(_ data: Data) throws -> BackupValidation {
        // Quick format check before a full decode so random JSON gives a clear message.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["format"] as? String == BackupArchive.formatIdentifier else { throw BackupError.notABackup }
        if let version = object["formatVersion"] as? Int, version > BackupArchive.currentVersion { throw BackupError.unsupportedVersion(version) }
        let archive: BackupArchive
        do { archive = try decoder.decode(BackupArchive.self, from: data) } catch { throw BackupError.corrupt(error.localizedDescription) }

        var warnings: [String] = []
        let ids: [UUID] = archive.homes.map(\.id) + archive.rooms.map(\.id) + archive.assets.map(\.id) + archive.documents.map(\.id) + archive.tasks.map(\.id) + archive.expenses.map(\.id) + archive.services.map(\.id)
        if Set(ids).count != ids.count { throw BackupError.corrupt("duplicate record identifiers") }
        let homeIDs = Set(archive.homes.map(\.id)), assetIDs = Set(archive.assets.map(\.id))
        let dangling = archive.assets.filter { $0.homeID.map { !homeIDs.contains($0) } ?? false }.count
            + archive.documents.filter { $0.assetID.map { !assetIDs.contains($0) } ?? false }.count
        if dangling > 0 { warnings.append("\(dangling) links point to missing records and will be left unlinked.") }
        let blobNames = Set(archive.files.map(\.name))
        let missingFiles = (archive.photos.map(\.fileName) + archive.documents.map(\.fileName)).filter { !$0.isEmpty && !blobNames.contains($0) }.count
        if missingFiles > 0 { warnings.append("\(missingFiles) photos or documents are referenced but not included in the file.") }
        if archive.files.contains(where: { $0.name.contains("/") || $0.name.contains("..") }) { throw BackupError.corrupt("invalid file names") }
        return BackupValidation(archive: archive, warnings: warnings)
    }

    // MARK: Restore

    /// Restores an archive. The whole operation is a single save: if anything fails, the context is
    /// rolled back and existing records are untouched. Replace additionally writes a safety backup
    /// first and removes no longer referenced files only after the new data has been saved.
    func restore(_ archive: BackupArchive, mode: RestoreMode, safetyBackupDirectory: URL? = nil) throws -> RestoreReport {
        var report = RestoreReport()
        let svc = DataService(context: context, files: files)
        let isReplace = mode == .replace

        if isReplace {
            let hasExisting = !svc.fetchAll(Home.self).isEmpty || !svc.fetchAll(Asset.self).isEmpty || !svc.fetchAll(DocumentRecord.self).isEmpty
            if hasExisting {
                let dir = safetyBackupDirectory ?? Self.safetyBackupDirectory
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("Before restore \(Date.now.formatted(.iso8601)).json".replacingOccurrences(of: ":", with: "-"))
                try exportData().write(to: url, options: [.atomic, .completeFileProtection])
                report.safetyBackupURL = url
            }
        }

        do {
            if isReplace { svc.deleteAllRecords() }
            try apply(archive, replacing: isReplace, report: &report, svc: svc)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        if isReplace, let referenced = svc.referencedFileNamesIfReadable() {
            files.removeOrphans(referenced: referenced)
        }
        return report
    }

    private func apply(_ archive: BackupArchive, replacing: Bool, report: inout RestoreReport, svc: DataService) throws {
        // New files are written alongside existing ones; nothing is removed here.
        for blob in archive.files where !files.exists(blob.name) {
            try files.save(blob.data, fileExtension: (blob.name as NSString).pathExtension, preferredName: blob.name)
            report.filesRestored += 1
        }

        func existing<T: PersistentModel>(_ type: T.Type, id: (T) -> UUID) -> [UUID: T] {
            // When replacing, every current record is already marked for deletion.
            if replacing { return [:] }
            return Dictionary(svc.fetchAll(type).map { (id($0), $0) }, uniquingKeysWith: { a, _ in a })
        }
        var homes = existing(Home.self) { $0.id }
        var rooms = existing(Room.self) { $0.id }
        var assets = existing(Asset.self) { $0.id }
        var docs = existing(DocumentRecord.self) { $0.id }
        var services = existing(ServiceRecord.self) { $0.id }
        var tasks = existing(MaintenanceTask.self) { $0.id }
        let photos = existing(AssetPhoto.self) { $0.id }
        let logs = existing(MaintenanceLog.self) { $0.id }
        let expenses = existing(Expense.self) { $0.id }
        let categories = existing(CustomCategory.self) { $0.id }

        /// Returns the object to write into, or nil when the local copy is newer (merge never overwrites newer data).
        func target<T>(_ map: inout [UUID: T], id: UUID, backupUpdated: Date?, localUpdated: (T) -> Date?, make: () -> T) -> T? {
            if let local = map[id] {
                if let b = backupUpdated, let l = localUpdated(local), b > l { report.updated += 1; return local }
                report.skipped += 1
                return nil
            }
            let obj = make()
            map[id] = obj
            report.inserted += 1
            return obj
        }

        for d in archive.homes {
            guard let h = target(&homes, id: d.id, backupUpdated: d.updatedAt, localUpdated: { $0.updatedAt }, make: { let h = Home(name: d.name); h.id = d.id; context.insert(h); return h }) else { continue }
            h.name = d.name; h.homeTypeRaw = d.homeType; h.addressLine = d.addressLine; h.notes = d.notes; h.sortIndex = d.sortIndex; h.createdAt = d.createdAt; h.updatedAt = d.updatedAt
        }
        for d in archive.rooms {
            guard let r = target(&rooms, id: d.id, backupUpdated: nil, localUpdated: { _ in nil }, make: { let r = Room(name: d.name); r.id = d.id; context.insert(r); return r }) else { continue }
            r.name = d.name; r.symbolName = d.symbolName; r.sortIndex = d.sortIndex; r.createdAt = d.createdAt; r.home = d.homeID.flatMap { homes[$0] }
        }
        for d in archive.assets {
            guard let a = target(&assets, id: d.id, backupUpdated: d.updatedAt, localUpdated: { $0.updatedAt }, make: { let a = Asset(name: d.name); a.id = d.id; context.insert(a); return a }) else { continue }
            a.name = d.name; a.category = d.category; a.brand = d.brand; a.modelNumber = d.modelNumber; a.serialNumber = d.serialNumber; a.barcode = d.barcode
            a.purchaseDate = d.purchaseDate; a.purchasePriceCents = d.purchasePriceCents; a.retailer = d.retailer
            a.warrantyStart = d.warrantyStart; a.warrantyExpiration = d.warrantyExpiration; a.warrantyIsEstimated = d.warrantyIsEstimated
            a.warrantyProvider = d.warrantyProvider; a.warrantyNotes = d.warrantyNotes; a.warrantyRemindersEnabled = d.warrantyRemindersEnabled
            a.warrantyReminderOffsets = d.warrantyReminderOffsets; a.conditionRaw = d.condition; a.notes = d.notes
            a.replacementValueCents = d.replacementValueCents; a.quantity = d.quantity; a.isArchived = d.isArchived
            a.createdAt = d.createdAt; a.updatedAt = d.updatedAt
            a.home = d.homeID.flatMap { homes[$0] }; a.room = d.roomID.flatMap { rooms[$0] }
        }
        for d in archive.photos where photos[d.id] == nil {
            let p = AssetPhoto(fileName: d.fileName, sortIndex: d.sortIndex, asset: d.assetID.flatMap { assets[$0] })
            p.id = d.id; p.createdAt = d.createdAt
            context.insert(p)
            report.inserted += 1
        }
        for d in archive.tasks {
            guard let t = target(&tasks, id: d.id, backupUpdated: d.updatedAt, localUpdated: { $0.updatedAt }, make: { let t = MaintenanceTask(title: d.title, dueDate: d.dueDate); t.id = d.id; context.insert(t); return t }) else { continue }
            t.title = d.title; t.details = d.details; t.dueDate = d.dueDate; t.recurrenceUnitRaw = d.recurrenceUnit; t.recurrenceInterval = d.recurrenceInterval
            t.recurrenceBasisRaw = d.recurrenceBasis; t.priorityRaw = d.priority; t.estimatedCostCents = d.estimatedCostCents; t.remindersEnabled = d.remindersEnabled
            t.reminderDaysBefore = d.reminderDaysBefore; t.isArchived = d.isArchived; t.templateKey = d.templateKey; t.createdAt = d.createdAt; t.updatedAt = d.updatedAt
            t.recurrenceAnchor = d.recurrenceAnchor
            t.home = d.homeID.flatMap { homes[$0] }; t.room = d.roomID.flatMap { rooms[$0] }; t.asset = d.assetID.flatMap { assets[$0] }
        }
        for d in archive.logs where logs[d.id] == nil {
            let l = MaintenanceLog(date: d.date, kind: MaintenanceLogKind(rawValue: d.kind) ?? .completed, note: d.note, costCents: d.costCents, dueDateResolved: d.dueDateResolved, task: d.taskID.flatMap { tasks[$0] })
            l.id = d.id
            context.insert(l)
            report.inserted += 1
        }
        for d in archive.services {
            guard let s = target(&services, id: d.id, backupUpdated: d.updatedAt, localUpdated: { $0.updatedAt }, make: { let s = ServiceRecord(title: d.title); s.id = d.id; context.insert(s); return s }) else { continue }
            s.title = d.title; s.kindRaw = d.kind; s.date = d.date; s.details = d.details; s.vendor = d.vendor; s.costCents = d.costCents
            s.followUpDate = d.followUpDate; s.followUpNote = d.followUpNote; s.createdAt = d.createdAt; s.updatedAt = d.updatedAt
            s.home = d.homeID.flatMap { homes[$0] }; s.asset = d.assetID.flatMap { assets[$0] }; s.task = d.taskID.flatMap { tasks[$0] }
        }
        for d in archive.documents {
            guard let doc = target(&docs, id: d.id, backupUpdated: d.updatedAt, localUpdated: { $0.updatedAt }, make: {
                let doc = DocumentRecord(title: d.title, kind: .other, fileName: d.fileName, contentType: .pdf); doc.id = d.id; context.insert(doc); return doc
            }) else { continue }
            doc.title = d.title; doc.kindRaw = d.kind; doc.fileName = d.fileName; doc.originalFileName = d.originalFileName; doc.contentTypeRaw = d.contentType
            doc.fileSize = d.fileSize; doc.documentDate = d.documentDate; doc.vendor = d.vendor; doc.amountCents = d.amountCents; doc.notes = d.notes
            doc.recognizedText = d.recognizedText; doc.createdAt = d.createdAt; doc.updatedAt = d.updatedAt
            doc.home = d.homeID.flatMap { homes[$0] }; doc.asset = d.assetID.flatMap { assets[$0] }; doc.serviceRecord = d.serviceRecordID.flatMap { services[$0] }
        }
        var expenseMap = expenses
        for d in archive.expenses {
            guard let e = target(&expenseMap, id: d.id, backupUpdated: d.updatedAt, localUpdated: { $0.updatedAt }, make: { let e = Expense(title: d.title, amountCents: d.amountCents); e.id = d.id; context.insert(e); return e }) else { continue }
            e.title = d.title; e.date = d.date; e.amountCents = d.amountCents; e.categoryRaw = d.category; e.vendor = d.vendor; e.notes = d.notes
            e.createdAt = d.createdAt; e.updatedAt = d.updatedAt
            e.home = d.homeID.flatMap { homes[$0] }; e.asset = d.assetID.flatMap { assets[$0] }
            e.serviceRecord = d.serviceRecordID.flatMap { services[$0] }; e.receipt = d.receiptID.flatMap { docs[$0] }
        }
        for d in archive.categories where categories[d.id] == nil && !categories.values.contains(where: { $0.name == d.name }) {
            let c = CustomCategory(name: d.name, symbolName: d.symbolName)
            c.id = d.id; c.createdAt = d.createdAt
            context.insert(c)
            report.inserted += 1
        }
    }

    static var safetyBackupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Safety Backups", isDirectory: true)
    }
}
