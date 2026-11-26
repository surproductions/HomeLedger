import StoreKitTest
import SwiftData
import XCTest
@testable import HomeLedger

@MainActor
final class BackupTests: HomeLedgerTestCase {
    private func seed() throws -> Asset {
        let home = makeHome("Backup Home", rooms: ["Kitchen"])
        let asset = makeAsset("Dishwasher", in: home, room: home.sortedRooms[0])
        asset.serialNumber = "DW-1"
        asset.purchasePriceCents = 104_900
        asset.warrantyExpiration = date(2027, 1, 1)
        asset.warrantyReminderOffsets = [30, 7]
        service.addPhoto(fileName: try files.save(pngData(), fileExtension: "png"), to: asset)
        let doc = DocumentRecord(title: "Manual", kind: .manual, fileName: try files.save(Data("%PDF-1.4 manual".utf8), fileExtension: "pdf"), contentType: .pdf, home: home, asset: asset)
        doc.recognizedText = "Clean filter monthly"
        context.insert(doc)
        let task = MaintenanceTask(title: "Clean filter", dueDate: date(2025, 2, 1), recurrence: .every(1, .month, basis: .completion), home: home)
        task.asset = asset
        context.insert(task)
        service.complete(task, on: date(2025, 2, 1))
        let repair = ServiceRecord(title: "Pump", home: home, asset: asset)
        repair.costCents = 9_900
        context.insert(repair)
        service.syncExpense(for: repair)
        context.insert(CustomCategory(name: "Heirlooms"))
        try context.save()
        return asset
    }

    func testRoundTripReplaceRestoresEverything() throws {
        _ = try seed()
        let data = try BackupService(context: context, files: files).exportData()

        // Restore into a brand-new store with empty file storage (simulates a new phone).
        let freshContainer = try PersistenceController.makeContainer(inMemory: true)
        let freshDir = FileManager.default.temporaryDirectory.appendingPathComponent("HLRestore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: freshDir) }
        let freshFiles = FileStore(baseURL: freshDir)
        let validation = try BackupService.validate(data)
        XCTAssertTrue(validation.warnings.isEmpty, "\(validation.warnings)")
        let report = try BackupService(context: freshContainer.mainContext, files: freshFiles)
            .restore(validation.archive, mode: .replace, safetyBackupDirectory: freshDir.appendingPathComponent("safety"))

        let ctx = freshContainer.mainContext
        let assets = try ctx.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(assets.count, 1)
        let a = try XCTUnwrap(assets.first)
        XCTAssertEqual(a.serialNumber, "DW-1")
        XCTAssertEqual(a.purchasePriceCents, 104_900)
        XCTAssertEqual(a.warrantyExpiration, date(2027, 1, 1))
        XCTAssertEqual(Set(a.warrantyReminderOffsets), [30, 7])
        XCTAssertEqual(a.room?.name, "Kitchen")
        XCTAssertEqual(a.home?.name, "Backup Home")
        XCTAssertEqual(a.sortedPhotos.count, 1)
        XCTAssertTrue(freshFiles.exists(a.sortedPhotos[0].fileName))
        XCTAssertEqual(a.sortedDocuments.first?.recognizedText, "Clean filter monthly")
        XCTAssertEqual(freshFiles.data(for: a.sortedDocuments[0].fileName), Data("%PDF-1.4 manual".utf8))
        let task = try XCTUnwrap(try ctx.fetch(FetchDescriptor<MaintenanceTask>()).first)
        XCTAssertEqual(task.recurrence, .every(1, .month, basis: .completion))
        XCTAssertEqual(task.sortedLogs.count, 1)
        XCTAssertEqual(task.asset?.id, a.id)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Expense>()).first?.serviceRecord?.title, "Pump")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<CustomCategory>()).map(\.name), ["Heirlooms"])
        XCTAssertGreaterThan(report.inserted, 5)
        XCTAssertEqual(report.filesRestored, 2)
        XCTAssertNil(report.safetyBackupURL, "nothing to protect in an empty store")
    }

    func testReplaceWritesSafetyBackupFirst() throws {
        _ = try seed()
        let svc = BackupService(context: context, files: files)
        let archive = try BackupService.validate(try svc.exportData()).archive
        let safetyDir = FileManager.default.temporaryDirectory.appendingPathComponent("HLSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: safetyDir) }
        let report = try svc.restore(archive, mode: .replace, safetyBackupDirectory: safetyDir)
        let safety = try XCTUnwrap(report.safetyBackupURL)
        XCTAssertNoThrow(try BackupService.validate(Data(contentsOf: safety)), "safety backup is itself a valid backup")
        XCTAssertEqual(fetch(Asset.self).count, 1)
        XCTAssertEqual(fetch(Home.self).count, 1, "replace does not duplicate")
    }

    func testMergeAddsMissingAndNeverOverwritesNewerLocalData() throws {
        let asset = try seed()
        let svc = BackupService(context: context, files: files)
        let archive = try BackupService.validate(try svc.exportData()).archive

        // Local edit after the backup was taken.
        asset.name = "Dishwasher (renamed)"
        asset.updatedAt = Date.now.addingTimeInterval(60)
        // A record created after the backup must survive the merge.
        makeAsset("New lamp", in: asset.home!, category: .decor)
        // A record deleted locally is re-added by merge.
        let repair = fetch(ServiceRecord.self).first!
        service.deleteServiceRecord(repair)
        try context.save()

        let report = try svc.restore(archive, mode: .merge)
        XCTAssertEqual(asset.name, "Dishwasher (renamed)", "newer local data is kept")
        XCTAssertEqual(Set(fetch(Asset.self).map(\.name)), ["Dishwasher (renamed)", "New lamp"])
        XCTAssertEqual(fetch(ServiceRecord.self).count, 1)
        XCTAssertEqual(fetch(Home.self).count, 1)
        XCTAssertGreaterThan(report.skipped, 0)
    }

    func testFailedReplaceRollsBackAndKeepsExistingData() throws {
        _ = try seed()
        let svc = BackupService(context: context, files: files)
        var archive = svc.makeArchive()
        archive.files.append(BackupArchive.FileBlob(name: "missing-folder/unwritable.png", data: pngData()))
        let filesBefore = Set(files.allFileNames())

        let safetyDir = FileManager.default.temporaryDirectory.appendingPathComponent("HLSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: safetyDir) }
        XCTAssertThrowsError(try svc.restore(archive, mode: .replace, safetyBackupDirectory: safetyDir))

        XCTAssertEqual(fetch(Asset.self).map(\.serialNumber), ["DW-1"], "existing records survive a failed restore")
        XCTAssertEqual(fetch(Home.self).count, 1)
        XCTAssertEqual(fetch(MaintenanceTask.self).count, 1)
        XCTAssertTrue(filesBefore.isSubset(of: Set(files.allFileNames())), "no existing files were removed")
    }

    func testValidationRejectsBadFiles() throws {
        XCTAssertThrowsError(try BackupService.validate(Data("{\"hello\":1}".utf8))) { e in
            guard case BackupError.notABackup = e else { return XCTFail("\(e)") }
        }
        XCTAssertThrowsError(try BackupService.validate(Data("not json".utf8)))
        let future = "{\"format\":\"\(BackupArchive.formatIdentifier)\",\"formatVersion\":99}"
        XCTAssertThrowsError(try BackupService.validate(Data(future.utf8))) { e in
            guard case BackupError.unsupportedVersion(99) = e else { return XCTFail("\(e)") }
        }
        let truncated = "{\"format\":\"\(BackupArchive.formatIdentifier)\",\"formatVersion\":1,\"homes\":[]}"
        XCTAssertThrowsError(try BackupService.validate(Data(truncated.utf8))) { e in
            guard case BackupError.corrupt = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(fetch(Asset.self).count, 0, "validation never changes data")
    }

    func testMissingFilesProduceWarningNotFailure() throws {
        _ = try seed()
        var archive = BackupService(context: context, files: files).makeArchive()
        archive.files.removeAll()
        let data = try BackupService.encoder.encode(archive)
        let validation = try BackupService.validate(data)
        XCTAssertFalse(validation.warnings.isEmpty)
    }
}

@MainActor
final class SearchAndAssistantTests: HomeLedgerTestCase {
    private var corpus: SearchCorpus {
        SearchCorpus(assets: fetch(Asset.self), rooms: fetch(Room.self), documents: fetch(DocumentRecord.self),
                     tasks: fetch(MaintenanceTask.self), services: fetch(ServiceRecord.self), expenses: fetch(Expense.self))
    }

    override func setUp() async throws {
        try await super.setUp()
        SampleDataService(context: context, files: files, now: date(2025, 6, 15), calendar: calendar).seed()
    }

    func testGlobalSearchFindsBySerialRoomAndRecognizedText() {
        let s = SearchService()
        XCTAssertEqual(s.search("0B9K4BAR", in: corpus).first?.results.first?.title, "Refrigerator")
        XCTAssertTrue(s.search("kitchen", in: corpus).contains { $0.title == "Rooms" })
        let docHits = s.search("drain pump", in: corpus).first { $0.title == "Documents" }
        XCTAssertEqual(docHits?.results.first?.title, "Washer repair invoice", "searches recognized text")
        XCTAssertTrue(s.search("zzzz-nothing", in: corpus).isEmpty)
        XCTAssertTrue(s.search("   ", in: corpus).isEmpty)
    }

    func testSearchIsDiacriticAndCaseInsensitive() {
        let home = fetch(Home.self).first!
        makeAsset("Crème Brûlée Torch", in: home, category: .kitchen)
        XCTAssertFalse(SearchService().search("CREME brulee", in: corpus).isEmpty)
    }

    func testAssistantAnswersPurchaseQuestionWithSupportingRecords() {
        let answer = QueryEngine(now: date(2025, 6, 15), calendar: calendar, currencyCode: "USD").answer("When did I buy the refrigerator?", corpus: corpus)
        XCTAssertTrue(answer.found)
        XCTAssertTrue(answer.text.contains("Refrigerator"))
        XCTAssertTrue(answer.text.contains("Best Buy"))
        XCTAssertTrue(answer.text.contains("$2,199.00"))
        XCTAssertEqual(answer.records.first?.title, "Refrigerator")
        XCTAssertTrue(answer.records.contains { $0.kindLabel == "Document" }, "links the receipt")
        let fridge = QueryEngine(now: date(2025, 6, 15), calendar: calendar).answer("when did we buy the fridge", corpus: corpus)
        XCTAssertEqual(fridge.records.first?.title, "Refrigerator", "synonyms")
    }

    func testAssistantRepairSpending() {
        let answer = QueryEngine(now: date(2025, 6, 15), calendar: calendar, currencyCode: "USD").answer("How much have I spent repairing the washing machine?", corpus: corpus)
        XCTAssertTrue(answer.found)
        XCTAssertTrue(answer.text.contains("$185.00"), answer.text)
    }

    func testAssistantFindsManual() {
        let answer = QueryEngine(now: date(2025, 6, 15), calendar: calendar).answer("Find the manual for my dishwasher", corpus: corpus)
        XCTAssertTrue(answer.found)
        XCTAssertEqual(answer.records.first?.title, "Dishwasher owner's manual")
        let missing = QueryEngine(now: date(2025, 6, 15), calendar: calendar).answer("Find the manual for my dryer", corpus: corpus)
        XCTAssertFalse(missing.found)
        XCTAssertTrue(missing.text.contains("couldn't find"))
    }

    func testAssistantWarrantiesExpiringSoon() {
        // Sample data is generated relative to `now`, so use the same reference date.
        let answer = QueryEngine(now: Date.now, calendar: .current).answer("Show appliances with warranties expiring soon", corpus: corpus)
        XCTAssertTrue(answer.records.allSatisfy { if case .asset(let a) = $0 { return a.category == AssetCategory.appliance.rawValue } else { return false } })
    }

    func testAssistantMaintenanceDueAndUnknownQuestions() {
        let engine = QueryEngine(now: Date.now, calendar: .current)
        let due = engine.answer("What maintenance is due this month?", corpus: corpus)
        XCTAssertTrue(due.records.allSatisfy { if case .task = $0 { return true } else { return false } })
        let overdue = engine.answer("what's overdue", corpus: corpus)
        XCTAssertTrue(overdue.found, "sample data includes an overdue detector test")

        let nonsense = engine.answer("what is the meaning of life", corpus: corpus)
        XCTAssertFalse(nonsense.found)
        XCTAssertTrue(nonsense.records.isEmpty, "never fabricates an answer")
    }

    func testAssistantUsesWholeWordsAndRoutesValueQuestions() throws {
        let home = try XCTUnwrap(fetch(Home.self).first)
        context.insert(Room(name: "Den", home: home))
        let engine = QueryEngine(now: Date.now, calendar: .current, currencyCode: "USD")

        let tv = engine.answer("Is my smart TV under warranty?", corpus: corpus)
        XCTAssertEqual(tv.records.first?.title, "65\" OLED TV", "'smart' must not be read as the Art category")

        let garden = engine.answer("What's in the garden?", corpus: corpus)
        XCTAssertFalse(garden.records.contains { if case .room(let r) = $0 { return r.name == "Den" } else { return false } }, "'den' must not match 'garden'")

        let worth = engine.answer("How much is everything worth?", corpus: corpus)
        XCTAssertTrue(worth.text.hasPrefix("Your recorded items total"), worth.text)

        let unknown = engine.answer("Find the manual for my hovercraft", corpus: corpus)
        XCTAssertFalse(unknown.found)
        XCTAssertTrue(unknown.records.isEmpty, "doesn't return unrelated manuals for an item that doesn't exist")

        let all = engine.answer("Show all receipts", corpus: corpus)
        XCTAssertTrue(all.found)
    }

    func testAssistantRoomContents() {
        let answer = QueryEngine().answer("What's in the kitchen?", corpus: corpus)
        XCTAssertTrue(answer.found)
        XCTAssertTrue(answer.text.contains("Kitchen"))
        XCTAssertTrue(answer.records.contains { $0.title == "Dishwasher" })
    }
}

final class StoreTests: XCTestCase {
    func testResolverGrantsLifetimeAndActiveSubscriptionOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(EntitlementResolver.resolve([], now: now).isPremium)
        XCTAssertEqual(EntitlementResolver.resolve([.init(productID: StoreConfiguration.lifetimeProductID)], now: now).source, .lifetime)
        let active = EntitlementResolver.resolve([.init(productID: StoreConfiguration.yearlyProductID, expirationDate: now.addingTimeInterval(86_400))], now: now)
        XCTAssertTrue(active.isPremium)
        XCTAssertFalse(EntitlementResolver.resolve([.init(productID: StoreConfiguration.yearlyProductID, expirationDate: now.addingTimeInterval(-1))], now: now).isPremium, "expired")
        XCTAssertFalse(EntitlementResolver.resolve([.init(productID: StoreConfiguration.lifetimeProductID, revocationDate: now)], now: now).isPremium, "refunded/revoked")
        XCTAssertFalse(EntitlementResolver.resolve([.init(productID: "com.other.app.product")], now: now).isPremium, "unknown products")
    }

    func testFreeLimits() {
        XCTAssertTrue(EntitlementState.free.canAddHome(currentCount: 0))
        XCTAssertFalse(EntitlementState.free.canAddHome(currentCount: 1))
        XCTAssertTrue(EntitlementState(source: .lifetime).canAddHome(currentCount: 5))
        XCTAssertFalse(EntitlementState.free.canAddAsset(currentActiveCount: 25))
        XCTAssertTrue(EntitlementState.free.canAddAsset(currentActiveCount: 24))
    }

    func testProductIDsAreConfiguredInOnePlace() throws {
        let url = try XCTUnwrap(Bundle(for: StoreTests.self).url(forResource: "HomeLedger", withExtension: "storekit"))
        let json = try String(contentsOf: url, encoding: .utf8)
        for id in StoreConfiguration.allProductIDs { XCTAssertTrue(json.contains(id), "\(id) missing from StoreKit config") }
    }

    @MainActor
    func testPurchaseAndRefreshWithStoreKitTestSession() async throws {
        let session = try SKTestSession(configurationFileNamed: "HomeLedger")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let store = StoreManager(listenForUpdates: false)
        await store.refreshEntitlements()
        XCTAssertFalse(store.isPremium, "no fake entitlement before purchase")

        await store.loadProducts()
        XCTAssertEqual(Set(store.products.map(\.id)), Set(StoreConfiguration.allProductIDs))
        let lifetime = try XCTUnwrap(store.lifetime)
        let outcome = await store.purchase(lifetime)
        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(store.isPremium)
        XCTAssertEqual(store.entitlement.source, .lifetime)

        session.clearTransactions()
        await store.refreshEntitlements()
        XCTAssertFalse(store.isPremium, "entitlement follows StoreKit, not a cached flag")
    }
}
