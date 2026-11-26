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

    /// Polls until any of the elements exists (system UI differs between iOS versions).
    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if elements.contains(where: { $0.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
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

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    private func tabBarShown() -> Bool {
        let add = app.buttons["tab.add"]
        return add.exists && add.isHittable
    }

    // Floating tab bar hides when scrolling down and returns when scrolling up (root and pushed screens).
    func testTabBarHidesOnScrollAndReturns() {
        launch(sample: true)
        XCTAssertTrue(app.buttons["tab.add"].waitForExistence(timeout: 20))
        XCTAssertTrue(tabBarShown())
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(waitUntil { !self.tabBarShown() }, "bar hides while scrolling down")
        app.swipeDown()
        XCTAssertTrue(waitUntil { self.tabBarShown() }, "bar returns when scrolling up")

        waitAndTap(app.buttons["tab.myHome"])
        waitAndTap(app.buttons["shortcut.items"])
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cordless Drill'")).firstMatch
        waitAndTap(first)
        XCTAssertTrue(waitUntil { self.tabBarShown() }, "opening a screen shows the bar")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(waitUntil { !self.tabBarShown() }, "hides on pushed screens too")
        app.swipeDown()
        XCTAssertTrue(waitUntil { self.tabBarShown() })
    }

    // Appearance can be set to System, Light or Dark.
    func testAppearanceSetting() {
        launch(sample: true)
        waitAndTap(app.buttons["dashboard.settings"], timeout: 20)
        let picker = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["System"].isSelected, "defaults to System")
        picker.buttons["Dark"].tap()
        XCTAssertTrue(waitUntil { picker.buttons["Dark"].isSelected })
        picker.buttons["Light"].tap()
        XCTAssertTrue(waitUntil { picker.buttons["Light"].isSelected })
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

        // The user corrects a field before saving (done before scrolling, while the field is on screen).
        clearAndType(vendor, "HomeGoods Depot")

        let serial = app.textFields["import.serial"]
        scrollTo(serial)
        XCTAssertEqual(serial.value as? String, "FD0112")

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
        // The preview's title reads "N items · M page(s)" once the PDF has been generated.
        let previewTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' items · ' AND label CONTAINS 'page'")).firstMatch
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 30), "the generated PDF preview is shown")
        waitAndTap(app.buttons["report.share"])
        XCTAssertTrue(waitForAny([app.otherElements["ActivityListView"], app.buttons["Copy"], app.staticTexts["Copy"],
                                  app.collectionViews.cells.firstMatch, app.buttons["Save to Files"]], timeout: 15),
                      "the system share sheet is presented")
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
        // iOS 26 can expose the dialog's buttons twice (sheet + popover representation).
        waitAndTap(app.buttons["Replace all current data…"].firstMatch)
        waitAndTap(app.alerts.buttons["Replace"].firstMatch)
        XCTAssertTrue(element(containing: "Restored:").waitForExistence(timeout: 20))
        XCTAssertTrue(element(containing: "safety backup").exists, "a safety backup was written before replacing")
    }
}
