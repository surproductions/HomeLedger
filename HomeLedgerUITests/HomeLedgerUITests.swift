import XCTest

/// End-to-end flows. Launch arguments reset storage for isolation; `-SeedSampleData` loads the
/// demo household. No launch argument unlocks purchases.
final class HomeLedgerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(sample: Bool) {
        app.launchArguments = ["-UITesting", "-ResetData"] + (sample ? ["-SeedSampleData"] : [])
        app.launch()
    }

    private func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    /// Any element whose accessibility label contains `text` (rows combine their children into one label).
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func clearAndType(_ field: XCUIElement, _ text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        field.typeText(text)
    }

    private func scrollTo(_ element: XCUIElement, in container: XCUIElement? = nil, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            (container ?? app).swipeUp()
            swipes += 1
        }
    }

    // 1. First launch and home creation
    func testFirstLaunchAndHomeCreation() {
        launch(sample: false)
        waitAndTap(app.buttons["onboarding.start"], timeout: 20)
        let name = app.textFields["onboarding.homeName"]
        waitAndTap(name)
        name.typeText("Cedar Cottage")
        app.buttons["onboarding.continue"].tap()
        waitAndTap(app.buttons["onboarding.rooms"])
        waitAndTap(app.buttons["onboarding.finish"])

        XCTAssertTrue(app.buttons["quick.addItem"].waitForExistence(timeout: 10), "dashboard is shown")
        XCTAssertTrue(element(containing: "Cedar Cottage").exists, "home name is shown")

        waitAndTap(app.buttons["tab.myHome"])
        XCTAssertTrue(element(containing: "Kitchen").waitForExistence(timeout: 5), "default rooms were created")
    }

    // 2. Add an asset with photos
    func testAddAssetWithPhotos() {
        launch(sample: true)
        waitAndTap(app.buttons["tab.add"], timeout: 20)
        waitAndTap(app.buttons["add.item"])
        let name = app.textFields["asset.name"]
        waitAndTap(name)
        name.typeText("Espresso Machine")
        waitAndTap(app.buttons["asset.testPhoto"])
        app.buttons["asset.testPhoto"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Remove photo'")).count, 2)
        waitAndTap(app.buttons["asset.save"])

        XCTAssertTrue(app.descendants(matching: .any)["asset.gallery"].waitForExistence(timeout: 10), "photos are shown on the new item")
        XCTAssertTrue(element(containing: "Espresso Machine").exists)
    }

    // 3. Attach a receipt and review extracted information
    func testAttachReceiptAndReviewExtraction() {
        launch(sample: true)
        waitAndTap(app.buttons["tab.documents"], timeout: 20)
        waitAndTap(app.buttons["documents.add"])
        waitAndTap(app.buttons["import.testReceipt"])

        let vendor = app.textFields["import.vendor"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 20), "review screen appears after on-device recognition")
        XCTAssertEqual(vendor.value as? String, "Homegoods Depot")
        XCTAssertTrue(element(containing: "Best guess").exists, "inferred fields are labelled")
        XCTAssertTrue(element(containing: "Detected").exists, "explicitly labelled fields are marked as detected")
        let serial = app.textFields["import.serial"]
        scrollTo(serial)
        XCTAssertEqual(serial.value as? String, "FD0112")

        // User corrects a field before saving.
        scrollTo(vendor)
        clearAndType(vendor, "HomeGoods Depot")

        let create = app.switches["import.createAsset"]
        scrollTo(create)
        if create.exists { create.tap() }
        waitAndTap(app.buttons["import.save"])

        XCTAssertTrue(element(containing: "Bosch 800 Series Dishwasher").waitForExistence(timeout: 10), "saved document appears in the library")
        XCTAssertTrue(element(containing: "HomeGoods Depot").exists, "the corrected vendor was saved")
    }

    // 4. Add a warranty and schedule a reminder
    func testAddWarrantyWithReminder() {
        launch(sample: true)
        waitAndTap(app.buttons["tab.myHome"], timeout: 20)
        waitAndTap(app.buttons["shortcut.items"])
        let mower = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lawn Mower'")).firstMatch
        scrollTo(mower)
        waitAndTap(mower)
        waitAndTap(app.buttons["asset.edit"])

        let end = app.buttons["asset.warrantyEnd"]
        scrollTo(end)
        waitAndTap(end)
        let reminders = app.switches["asset.warrantyReminders"]
        scrollTo(reminders)
        XCTAssertEqual(reminders.value as? String, "1", "reminders default to on")
        waitAndTap(app.buttons["asset.save"])

        XCTAssertTrue(element(containing: "Warranty: Active").waitForExistence(timeout: 5), "warranty is now active")
        let remindersRow = element(containing: "30d, 14d, 7d before")
        scrollTo(remindersRow)
        XCTAssertTrue(remindersRow.exists, "reminder schedule is shown on the item")
    }

    // 5. Create and complete a recurring maintenance task
    func testCreateAndCompleteRecurringTask() {
        launch(sample: true)
        waitAndTap(app.buttons["tab.maintenance"], timeout: 20)
        waitAndTap(app.buttons["maintenance.add"])
        let title = app.textFields["task.title"]
        waitAndTap(title)
        title.typeText("Descale kettle")
        let repeatPicker = app.buttons["task.repeat"]
        if repeatPicker.waitForExistence(timeout: 3) {
            repeatPicker.tap()
            waitAndTap(app.buttons["Months"].firstMatch)
        }
        waitAndTap(app.buttons["task.save"])

        let complete = app.buttons["task.complete.Descale kettle"]
        scrollTo(complete)
        waitAndTap(complete)
        waitAndTap(app.buttons["task.confirmComplete"])

        // Still exactly one task with this title (no duplicates) and it has moved forward.
        XCTAssertTrue(app.buttons["task.complete.Descale kettle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "task.complete.Descale kettle").count, 1)
        app.segmentedControls["maintenance.filter"].buttons["History"].tap()
        XCTAssertTrue(element(containing: "Descale kettle").waitForExistence(timeout: 5), "completion is recorded in history")
    }

    // 6. Generate and share an inventory PDF
    func testGenerateAndShareInventoryPDF() {
        launch(sample: true)
        waitAndTap(app.buttons["quick.report"], timeout: 20)
        let generate = app.buttons["report.generate"]
        scrollTo(generate)
        waitAndTap(generate)
        XCTAssertTrue(app.descendants(matching: .any)["report.preview"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.navigationBars.staticTexts.matching(NSPredicate(format: "label CONTAINS 'items'")).firstMatch.exists)
        waitAndTap(app.buttons["report.share"])
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 10) || app.collectionViews.cells.firstMatch.waitForExistence(timeout: 5), "share sheet is presented")
    }

    // 7. Export and restore a backup
    func testExportAndRestoreBackup() {
        launch(sample: true)
        waitAndTap(app.buttons["dashboard.settings"], timeout: 20)
        let backup = app.buttons["settings.backup"]
        scrollTo(backup)
        waitAndTap(backup)
        waitAndTap(app.buttons["backup.export"])
        XCTAssertTrue(element(containing: "Backup saved").waitForExistence(timeout: 20))

        let localBackup = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'backup.local.'")).firstMatch
        waitAndTap(localBackup)
        waitAndTap(app.buttons["Replace all current data…"])
        waitAndTap(app.alerts.buttons["Replace"])
        XCTAssertTrue(element(containing: "Restored:").waitForExistence(timeout: 20))
        XCTAssertTrue(element(containing: "safety backup").exists, "a safety backup was written before replacing")
    }
}
