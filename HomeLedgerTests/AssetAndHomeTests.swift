import SwiftData
import XCTest
@testable import HomeLedger

@MainActor
final class AssetAndHomeTests: HomeLedgerTestCase {
    func testCreateHomeWithRoomsInOrder() throws {
        let home = makeHome("Lake House", rooms: ["Kitchen", "Den", "Garage"])
        try context.save()
        XCTAssertEqual(home.sortedRooms.map(\.name), ["Kitchen", "Den", "Garage"])
        XCTAssertTrue(home.sortedRooms.allSatisfy { $0.home?.id == home.id })
    }

    func testAssetCreationAndEditing() throws {
        let home = makeHome()
        let kitchen = home.sortedRooms[0]
        let asset = makeAsset("Fridge", in: home, room: kitchen)
        asset.purchasePrice = Decimal(string: "1999.99")
        asset.serialNumber = "SN-1"
        try context.save()

        XCTAssertEqual(asset.purchasePriceCents, 199_999)
        XCTAssertEqual(kitchen.activeAssets.count, 1)

        var draft = AssetDraft(asset)
        draft.name = "  Refrigerator  "
        draft.brand = "Samsung"
        draft.roomID = home.sortedRooms[1].id
        let before = asset.updatedAt
        draft.apply(to: asset, homes: [home])
        try context.save()

        XCTAssertEqual(asset.name, "Refrigerator", "names are trimmed")
        XCTAssertEqual(asset.brand, "Samsung")
        XCTAssertEqual(asset.room?.name, "Garage")
        XCTAssertGreaterThanOrEqual(asset.updatedAt, before)
    }

    func testArchiveExcludesFromActiveCountsAndRestores() throws {
        let home = makeHome()
        let a = makeAsset("Old TV", in: home)
        _ = makeAsset("New TV", in: home)
        try context.save()
        XCTAssertEqual(service.activeAssetCount(), 2)

        service.setArchived(a, true)
        XCTAssertEqual(service.activeAssetCount(), 1)
        XCTAssertEqual(home.activeAssets.map(\.name), ["New TV"])

        service.setArchived(a, false)
        XCTAssertEqual(service.activeAssetCount(), 2)
    }

    func testDeletingAssetRemovesPhotosButKeepsDocumentsRepairsAndExpenses() throws {
        let home = makeHome()
        let asset = makeAsset("Washer", in: home)
        let photoName = try files.save(pngData(), fileExtension: "png")
        service.addPhoto(fileName: photoName, to: asset)
        let docName = try files.save(Data("%PDF-1.4".utf8), fileExtension: "pdf")
        let doc = DocumentRecord(title: "Receipt", kind: .receipt, fileName: docName, contentType: .pdf, home: home, asset: asset)
        context.insert(doc)
        let repair = ServiceRecord(title: "Pump", home: home, asset: asset)
        repair.costCents = 10_000
        context.insert(repair)
        service.syncExpense(for: repair)
        try context.save()

        XCTAssertTrue(files.exists(photoName))
        service.deleteAsset(asset)
        try context.save()

        XCTAssertFalse(files.exists(photoName), "photo files are removed with the item")
        XCTAssertEqual(fetch(AssetPhoto.self).count, 0)
        XCTAssertEqual(fetch(DocumentRecord.self).count, 1, "documents are never deleted unexpectedly")
        XCTAssertTrue(files.exists(docName))
        XCTAssertNil(fetch(DocumentRecord.self).first?.asset)
        XCTAssertEqual(fetch(ServiceRecord.self).count, 1)
        XCTAssertEqual(fetch(Expense.self).count, 1)
    }

    func testDeletingRoomKeepsItemsAsUnassigned() throws {
        let home = makeHome()
        let garage = home.sortedRooms[1]
        let drill = makeAsset("Drill", in: home, room: garage, category: .tools)
        try context.save()

        service.deleteRoom(garage)
        try context.save()

        XCTAssertEqual(fetch(Asset.self).count, 1)
        XCTAssertNil(drill.room)
        XCTAssertEqual(drill.home?.id, home.id)
        XCTAssertEqual(home.sortedRooms.map(\.name), ["Kitchen"])
    }

    func testDeletingHomeDeletesItemsButKeepsDocumentsAndExpenses() throws {
        let home = makeHome()
        let other = makeHome("Other")
        let asset = makeAsset("Fridge", in: home)
        _ = makeAsset("Keep me", in: other)
        context.insert(DocumentRecord(title: "Policy", kind: .insurance, fileName: "", contentType: .pdf, home: home))
        context.insert(Expense(title: "Insurance", amountCents: 50_000, home: home))
        context.insert(MaintenanceTask(title: "Filter", dueDate: .now, home: home))
        _ = asset
        try context.save()

        let summary = service.deletionSummary(for: home)
        XCTAssertEqual(summary.assets, 1)
        XCTAssertEqual(summary.documents, 1)

        service.deleteHome(home)
        try context.save()

        XCTAssertEqual(fetch(Home.self).map(\.name), ["Other"])
        XCTAssertEqual(fetch(Asset.self).map(\.name), ["Keep me"])
        XCTAssertEqual(fetch(MaintenanceTask.self).count, 0)
        XCTAssertEqual(fetch(DocumentRecord.self).count, 1)
        XCTAssertNil(fetch(DocumentRecord.self).first?.home)
        XCTAssertEqual(fetch(Expense.self).count, 1)
        XCTAssertEqual(fetch(Room.self).count, 2, "only the other home's rooms remain")
    }

    func testDuplicateCopiesDescriptionAndPhotosButNotIdentifiers() throws {
        let home = makeHome()
        let asset = makeAsset("Chair", in: home, category: .furniture)
        asset.brand = "Herman Miller"
        asset.serialNumber = "UNIQUE-1"
        asset.barcode = "0123456789"
        asset.purchasePriceCents = 129_900
        let photo = try files.save(pngData(), fileExtension: "png")
        service.addPhoto(fileName: photo, to: asset)
        try context.save()

        let copy = service.duplicate(asset)
        try context.save()

        XCTAssertEqual(copy.name, "Chair (copy)")
        XCTAssertEqual(copy.brand, "Herman Miller")
        XCTAssertEqual(copy.purchasePriceCents, 129_900)
        XCTAssertEqual(copy.serialNumber, "")
        XCTAssertEqual(copy.barcode, "")
        XCTAssertNotEqual(copy.id, asset.id)
        XCTAssertEqual(copy.sortedPhotos.count, 1)
        XCTAssertNotEqual(copy.sortedPhotos.first?.fileName, photo, "photo files are copied, not shared")
        XCTAssertTrue(files.exists(copy.sortedPhotos.first!.fileName))
    }

    func testMoveBetweenRoomsAndHomes() throws {
        let a = makeHome("A", rooms: ["Kitchen"])
        let b = makeHome("B", rooms: ["Shed"])
        let asset = makeAsset("Mower", in: a, room: a.sortedRooms[0], category: .outdoor)
        service.move(asset, to: b.sortedRooms[0])
        try context.save()
        XCTAssertEqual(asset.room?.name, "Shed")
        XCTAssertEqual(asset.home?.name, "B")
    }

    func testFreeAssetLimitAndPremium() throws {
        let home = makeHome()
        for i in 0..<EntitlementState.freeAssetLimit { makeAsset("Item \(i)", in: home) }
        try context.save()
        XCTAssertFalse(service.canAddAsset(entitlements: .free))
        XCTAssertTrue(service.canAddAsset(entitlements: EntitlementState(source: .lifetime)))
        service.setArchived(fetch(Asset.self).first!, true)
        XCTAssertTrue(service.canAddAsset(entitlements: .free), "archived items don't count toward the limit")
    }

    func testMissingInfoSuggestionsAreOptionalHints() {
        let home = makeHome()
        let asset = makeAsset("Dishwasher", in: home, category: .appliance)
        XCTAssertTrue(asset.missingInfoSuggestions.contains("Add the serial number"))
        XCTAssertTrue(asset.missingInfoSuggestions.contains("Attach a receipt"))
        asset.serialNumber = "X"
        XCTAssertFalse(asset.missingInfoSuggestions.contains("Add the serial number"))
    }

    func testSampleDataRemovalKeepsUserRecords() throws {
        SampleDataService(context: context, files: files).seed()
        let mine = makeHome("Mine")
        makeAsset("My bike", in: mine, category: .sports)
        try context.save()
        XCTAssertTrue(service.hasSampleData)
        XCTAssertGreaterThan(fetch(Asset.self).count, 5)

        service.removeSampleData()
        try context.save()

        XCTAssertFalse(service.hasSampleData)
        XCTAssertEqual(fetch(Home.self).map(\.name), ["Mine"])
        XCTAssertEqual(fetch(Asset.self).map(\.name), ["My bike"])
        XCTAssertEqual(fetch(DocumentRecord.self).count, 0)
        XCTAssertEqual(fetch(Expense.self).count, 0)
        XCTAssertEqual(fetch(MaintenanceTask.self).count, 0)
        XCTAssertEqual(files.allFileNames().count, 0, "sample files are cleaned up")
    }

    func testRemovingSampleDataKeepsSampleHomeThatHoldsUserItems() throws {
        let sampleHome = SampleDataService(context: context, files: files).seed()
        let kitchen = try XCTUnwrap(sampleHome.sortedRooms.first { $0.name == "Kitchen" })
        makeAsset("My stand mixer", in: sampleHome, room: kitchen, category: .kitchen)
        try context.save()

        service.removeSampleData()
        try context.save()

        XCTAssertEqual(fetch(Asset.self).map(\.name), ["My stand mixer"])
        let home = try XCTUnwrap(fetch(Home.self).first)
        XCTAssertFalse(home.isSample, "the home is kept as a regular home")
        XCTAssertEqual(home.addressLine, "")
        XCTAssertEqual(home.sortedRooms.map(\.name), ["Kitchen"], "only rooms holding user items are kept")
        XCTAssertFalse(service.hasSampleData)
    }

    func testDeleteAllData() throws {
        SampleDataService(context: context, files: files).seed()
        try service.deleteAllData()
        XCTAssertEqual(fetch(Home.self).count, 0)
        XCTAssertEqual(fetch(Asset.self).count, 0)
        XCTAssertEqual(fetch(Expense.self).count, 0)
        XCTAssertEqual(files.allFileNames().count, 0)
    }

    func testPersistenceSurvivesRelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HLStore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Test.store")
        var id: UUID?
        do {
            let c1 = try PersistenceController.makeContainer(url: url)
            let ctx = c1.mainContext
            let home = Home(name: "Persisted")
            ctx.insert(home)
            let asset = Asset(name: "Piano", category: .furniture, home: home)
            asset.purchasePriceCents = 500_000
            ctx.insert(asset)
            id = asset.id
            try ctx.save()
        }
        let c2 = try PersistenceController.makeContainer(url: url)
        let assets = try c2.mainContext.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.id, id)
        XCTAssertEqual(assets.first?.home?.name, "Persisted")
        XCTAssertEqual(assets.first?.purchasePriceCents, 500_000)
    }

    func testSchemaIsVersioned() {
        XCTAssertEqual(HomeLedgerSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HomeLedgerMigrationPlan.schemas.count, 1)
        XCTAssertEqual(HomeLedgerSchemaV1.models.count, 10)
    }
}
