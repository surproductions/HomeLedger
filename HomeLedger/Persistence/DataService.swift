import Foundation
import SwiftData

enum DataServiceError: LocalizedError {
    case assetLimitReached(limit: Int)
    case homeLimitReached
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .assetLimitReached(let limit): "The free plan includes up to \(limit) active items. Archive an item or upgrade to HomeLedger Premium for unlimited items."
        case .homeLimitReached: "Multiple homes are part of HomeLedger Premium."
        case .validation(let message): message
        }
    }
}

/// All multi-record mutations go through here so deletion rules and side effects
/// (files, reminders, linked expenses) are applied consistently.
@MainActor
struct DataService {
    let context: ModelContext
    var files: FileStore = .shared

    // MARK: Fetching

    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    func homes() -> [Home] { fetchAll(Home.self).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) } }
    func activeAssetCount() -> Int { fetchAll(Asset.self).filter { !$0.isArchived }.count }

    func save() throws {
        if context.hasChanges { try context.save() }
    }

    // MARK: Homes & rooms

    @discardableResult
    func createHome(name: String, type: HomeType, roomNames: [(String, String)] = []) -> Home {
        let home = Home(name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type, sortIndex: homes().count)
        context.insert(home)
        for (index, room) in roomNames.enumerated() {
            let r = Room(name: room.0, symbolName: room.1, sortIndex: index, home: home)
            context.insert(r)
        }
        return home
    }

    @discardableResult
    func addRoom(named name: String, symbol: String, to home: Home) -> Room {
        let room = Room(name: name, symbolName: symbol, sortIndex: (home.rooms ?? []).count, home: home)
        context.insert(room)
        home.updatedAt = .now
        return room
    }

    /// Deleting a room keeps its items — they become "Unassigned" within the same home.
    func deleteRoom(_ room: Room) {
        for asset in room.assets ?? [] { asset.room = nil; asset.touch() }
        for task in room.tasks ?? [] { task.room = nil }
        context.delete(room)
    }

    func reorderRooms(_ rooms: [Room]) {
        for (index, room) in rooms.enumerated() { room.sortIndex = index }
    }

    func reorderHomes(_ homes: [Home]) {
        for (index, home) in homes.enumerated() { home.sortIndex = index }
    }

    struct HomeDeletionSummary { let assets: Int; let tasks: Int; let documents: Int; let expenses: Int; let services: Int }

    func deletionSummary(for home: Home) -> HomeDeletionSummary {
        HomeDeletionSummary(assets: (home.assets ?? []).count, tasks: (home.tasks ?? []).count,
                            documents: (home.documents ?? []).count, expenses: (home.expenses ?? []).count,
                            services: (home.serviceRecords ?? []).count)
    }

    /// Deletes a home, its rooms, items (and their photos) and maintenance tasks.
    /// Documents, repair history and expenses are preserved and simply unlinked from the home.
    func deleteHome(_ home: Home) {
        for asset in home.assets ?? [] { deleteAsset(asset) }
        for task in home.tasks ?? [] { context.delete(task) }
        for doc in home.documents ?? [] { doc.home = nil }
        for expense in home.expenses ?? [] { expense.home = nil }
        for record in home.serviceRecords ?? [] { record.home = nil }
        context.delete(home)
    }

    // MARK: Assets

    func canAddAsset(entitlements: EntitlementState) -> Bool {
        entitlements.isPremium || activeAssetCount() < EntitlementState.freeAssetLimit
    }

    /// Deletes an item and its photos. Documents, repair history, expenses and tasks are kept and unlinked.
    func deleteAsset(_ asset: Asset) {
        for photo in asset.photos ?? [] { files.delete(photo.fileName) }
        for doc in asset.documents ?? [] { doc.asset = nil }
        for record in asset.serviceRecords ?? [] { record.asset = nil }
        for task in asset.tasks ?? [] { task.asset = nil }
        for expense in asset.expenses ?? [] { expense.asset = nil }
        context.delete(asset)
    }

    func setArchived(_ asset: Asset, _ archived: Bool) {
        asset.isArchived = archived
        asset.touch()
    }

    func move(_ asset: Asset, to room: Room?) {
        asset.room = room
        if let home = room?.home { asset.home = home }
        asset.touch()
    }

    /// Duplicates descriptive fields and photos. Serial numbers, barcodes and documents are
    /// intentionally not copied because they identify one specific item.
    @discardableResult
    func duplicate(_ asset: Asset) -> Asset {
        let copy = Asset(name: asset.name + " (copy)", category: .other, home: asset.home, room: asset.room)
        copy.category = asset.category
        copy.brand = asset.brand
        copy.modelNumber = asset.modelNumber
        copy.purchaseDate = asset.purchaseDate
        copy.purchasePriceCents = asset.purchasePriceCents
        copy.retailer = asset.retailer
        copy.warrantyStart = asset.warrantyStart
        copy.warrantyExpiration = asset.warrantyExpiration
        copy.warrantyIsEstimated = asset.warrantyIsEstimated
        copy.warrantyProvider = asset.warrantyProvider
        copy.warrantyNotes = asset.warrantyNotes
        copy.warrantyReminderOffsets = asset.warrantyReminderOffsets
        copy.warrantyRemindersEnabled = asset.warrantyRemindersEnabled
        copy.conditionRaw = asset.conditionRaw
        copy.notes = asset.notes
        copy.replacementValueCents = asset.replacementValueCents
        copy.quantity = asset.quantity
        context.insert(copy)
        for photo in asset.sortedPhotos {
            if let data = files.data(for: photo.fileName),
               let name = try? files.save(data, fileExtension: (photo.fileName as NSString).pathExtension.isEmpty ? "jpg" : (photo.fileName as NSString).pathExtension) {
                let p = AssetPhoto(fileName: name, sortIndex: photo.sortIndex, asset: copy)
                context.insert(p)
            }
        }
        return copy
    }

    func addPhoto(fileName: String, to asset: Asset) {
        let photo = AssetPhoto(fileName: fileName, sortIndex: (asset.photos ?? []).count, asset: asset)
        photo.isSample = asset.isSample
        context.insert(photo)
        asset.touch()
    }

    func deletePhoto(_ photo: AssetPhoto) {
        files.delete(photo.fileName)
        photo.asset?.touch()
        context.delete(photo)
    }

    // MARK: Documents

    func deleteDocument(_ document: DocumentRecord) {
        files.delete(document.fileName)
        for expense in document.expenses ?? [] { expense.receipt = nil }
        context.delete(document)
    }

    // MARK: Maintenance

    /// Records completion and advances the same task to its next due date. Never creates a new
    /// task, so completing or editing a recurring task cannot produce duplicates.
    @discardableResult
    func complete(_ task: MaintenanceTask, on date: Date = .now, note: String = "", costCents: Int? = nil,
                  logExpense: Bool = false, calculator: RecurrenceCalculator = RecurrenceCalculator()) -> MaintenanceLog {
        let log = MaintenanceLog(date: date, kind: .completed, note: note, costCents: costCents, dueDateResolved: task.dueDate, task: task)
        log.isSample = task.isSample
        context.insert(log)
        if logExpense, let costCents, costCents > 0 {
            let expense = Expense(title: task.title, amountCents: costCents, date: date, category: .maintenance, home: task.home, asset: task.asset)
            expense.notes = note
            context.insert(expense)
        }
        advance(task, from: date, calculator: calculator)
        return log
    }

    /// Skipping moves past the current occurrence as if it had happened on time, so a task skipped
    /// early isn't pulled forward and one skipped late isn't left overdue.
    func skip(_ task: MaintenanceTask, on date: Date = .now, calculator: RecurrenceCalculator = RecurrenceCalculator()) {
        let log = MaintenanceLog(date: date, kind: .skipped, dueDateResolved: task.dueDate, task: task)
        log.isSample = task.isSample
        context.insert(log)
        advance(task, from: max(date, task.dueDate), calculator: calculator)
    }

    private func advance(_ task: MaintenanceTask, from date: Date, calculator: RecurrenceCalculator) {
        let anchor = task.recurrenceAnchor ?? task.dueDate
        if let next = calculator.nextDueDate(currentDue: task.dueDate, completedOn: date, recurrence: task.recurrence, anchor: anchor) {
            // Completion-based schedules restart from each completion, so the new date becomes the anchor.
            task.recurrenceAnchor = task.recurrence.basis == .schedule ? anchor : next
            task.dueDate = next
        } else {
            task.isArchived = true // one-time task is done; kept in history
        }
        task.updatedAt = .now
    }

    /// Postpones only this occurrence; the schedule's rhythm (anchor) is preserved.
    func snooze(_ task: MaintenanceTask, days: Int, now: Date = .now, calendar: Calendar = .current) {
        if task.recurrenceAnchor == nil { task.recurrenceAnchor = task.dueDate }
        let base = max(task.dueDate, calendar.startOfDay(for: now))
        task.dueDate = calendar.date(byAdding: .day, value: days, to: base) ?? task.dueDate
        task.updatedAt = .now
    }

    func reopen(_ task: MaintenanceTask) {
        task.isArchived = false
        task.updatedAt = .now
    }

    // MARK: Service records

    /// Keeps a single linked expense in sync with the service record's cost.
    func syncExpense(for record: ServiceRecord) {
        let existing = (record.expenses ?? []).first
        guard let cost = record.costCents, cost > 0 else {
            if let existing { context.delete(existing) }
            return
        }
        let expense = existing ?? {
            let e = Expense(title: record.title, amountCents: cost)
            context.insert(e)
            e.serviceRecord = record
            return e
        }()
        expense.title = record.title
        expense.amountCents = cost
        expense.date = record.date
        expense.category = record.kind.expenseCategory
        expense.vendor = record.vendor
        expense.asset = record.asset
        expense.home = record.home ?? record.asset?.home
        expense.isSample = record.isSample
        expense.updatedAt = .now
    }

    func deleteServiceRecord(_ record: ServiceRecord, deleteLinkedExpense: Bool = true) {
        if deleteLinkedExpense { for e in record.expenses ?? [] { context.delete(e) } }
        for doc in record.documents ?? [] { doc.serviceRecord = nil }
        context.delete(record)
    }

    // MARK: Bulk data control

    /// Removes demo records only. If the user added their own records to the sample home (or its
    /// rooms), those containers are kept and become regular records so nothing of theirs is orphaned.
    func removeSampleData() {
        for doc in fetchAll(DocumentRecord.self) where doc.isSample { deleteDocument(doc) }
        for asset in fetchAll(Asset.self) where asset.isSample { deleteAsset(asset) }
        for e in fetchAll(Expense.self) where e.isSample { context.delete(e) }
        for r in fetchAll(ServiceRecord.self) where r.isSample { deleteServiceRecord(r, deleteLinkedExpense: false) }
        for t in fetchAll(MaintenanceTask.self) where t.isSample { context.delete(t) }
        for room in fetchAll(Room.self) where room.isSample {
            let inUse = (room.assets ?? []).contains { !$0.isSample } || (room.tasks ?? []).contains { !$0.isSample }
            if inUse { room.isSample = false } else { context.delete(room) }
        }
        for home in fetchAll(Home.self) where home.isSample {
            let inUse = (home.assets ?? []).contains { !$0.isSample } || (home.tasks ?? []).contains { !$0.isSample }
                || (home.documents ?? []).contains { !$0.isSample } || (home.expenses ?? []).contains { !$0.isSample }
                || (home.serviceRecords ?? []).contains { !$0.isSample }
                || (home.rooms ?? []).contains { !$0.isSample }
            if inUse {
                home.isSample = false
                if home.addressLine == SampleDataService.sampleAddressNote { home.addressLine = "" }
            } else {
                context.delete(home)
            }
        }
    }

    var hasSampleData: Bool { fetchAll(Home.self).contains { $0.isSample } || fetchAll(Asset.self).contains { $0.isSample } }

    func deleteAllData() throws {
        deleteAllRecords()
        try context.save()
        files.deleteAll()
    }

    /// Marks every record for deletion without saving or touching files (used by restore so the
    /// whole replace can be rolled back if anything fails).
    func deleteAllRecords() {
        // Delete object-by-object so relationship rules are honoured (batch deletes can fail with relationships).
        fetchAll(Expense.self).forEach { context.delete($0) }
        fetchAll(MaintenanceLog.self).forEach { context.delete($0) }
        fetchAll(MaintenanceTask.self).forEach { context.delete($0) }
        fetchAll(ServiceRecord.self).forEach { context.delete($0) }
        fetchAll(DocumentRecord.self).forEach { context.delete($0) }
        fetchAll(AssetPhoto.self).forEach { context.delete($0) }
        fetchAll(Asset.self).forEach { context.delete($0) }
        fetchAll(Room.self).forEach { context.delete($0) }
        fetchAll(Home.self).forEach { context.delete($0) }
        fetchAll(CustomCategory.self).forEach { context.delete($0) }
    }

    /// Referenced file names, or nil if the store couldn't be read (callers must then not delete files).
    func referencedFileNamesIfReadable() -> Set<String>? {
        do {
            var names = Set(try context.fetch(FetchDescriptor<AssetPhoto>()).map(\.fileName))
            names.formUnion(try context.fetch(FetchDescriptor<DocumentRecord>()).map(\.fileName))
            names.remove("")
            return names
        } catch {
            return nil
        }
    }

    /// All file names referenced by records (for backups).
    func referencedFileNames() -> Set<String> {
        var names = Set(fetchAll(AssetPhoto.self).map(\.fileName))
        names.formUnion(fetchAll(DocumentRecord.self).map(\.fileName))
        names.remove("")
        return names
    }
}
