import PDFKit
import XCTest
@testable import HomeLedger

@MainActor
final class ExpenseAndReportTests: HomeLedgerTestCase {
    func testMoneyRoundingAndParsing() {
        XCTAssertEqual(Money.cents(from: Decimal(string: "12.345")!), 1235, "half-up rounding")
        XCTAssertEqual(Money.cents(from: Decimal(string: "12.344")!), 1234)
        XCTAssertEqual(Money.cents(from: Decimal(string: "0.1")! + Decimal(string: "0.2")!), 30, "no floating point drift")
        XCTAssertEqual(Money.parse("$1,299.99"), Decimal(string: "1299.99"))
        XCTAssertEqual(Money.parse("1.299,99"), Decimal(string: "1299.99"))
        XCTAssertEqual(Money.parse("45,5"), Decimal(string: "45.5"), "single comma with 1–2 digits is a decimal comma")
        XCTAssertEqual(Money.parse("12,50"), Decimal(string: "12.50"))
        XCTAssertEqual(Money.parse("1,000"), Decimal(1000))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse(""))
        XCTAssertEqual(Money.decimal(fromCents: 199_999), Decimal(string: "1999.99"))
    }

    func testMonthlyCategoryAndYearlyTotals() {
        let calc = ExpenseCalculator(calendar: calendar)
        let expenses = [
            Expense(title: "A", amountCents: 10_050, date: date(2025, 1, 5), category: .repair),
            Expense(title: "B", amountCents: 2_525, date: date(2025, 1, 28), category: .maintenance),
            Expense(title: "C", amountCents: 99_999, date: date(2025, 7, 4), category: .improvement),
            Expense(title: "D", amountCents: 1, date: date(2024, 12, 31), category: .repair)
        ]
        let monthly = calc.monthly(expenses, year: 2025)
        XCTAssertEqual(monthly.count, 12)
        XCTAssertEqual(monthly[0].cents, 12_575)
        XCTAssertEqual(monthly[6].cents, 99_999)
        XCTAssertEqual(monthly.map(\.cents).reduce(0, +), 112_574)

        let byCat = calc.byCategory(expenses)
        XCTAssertEqual(byCat.first?.category, .improvement)
        XCTAssertEqual(byCat.first { $0.category == .repair }?.cents, 10_051)

        XCTAssertEqual(calc.yearly(expenses).map(\.year), [2024, 2025])
        XCTAssertEqual(calc.total(calc.filter(expenses, .init(range: calc.yearRange(2025)))), 112_574)
        XCTAssertEqual(calc.total(calc.filter(expenses, .init(category: .repair))), 10_051)
        XCTAssertEqual(calc.averageMonthly(expenses, year: 2024, now: date(2025, 6, 1)), 0, "1 cent / 12 rounds to 0")
        XCTAssertEqual(calc.averageMonthly(expenses, year: 2025, now: date(2025, 7, 15)), Int((112_574.0 / 7).rounded()))
    }

    func testFilterByHomeAndAsset() throws {
        let h1 = makeHome("One"), h2 = makeHome("Two")
        let a = makeAsset("Washer", in: h1)
        let e1 = Expense(title: "x", amountCents: 100, home: h1, asset: a)
        let e2 = Expense(title: "y", amountCents: 200, home: h2)
        [e1, e2].forEach { context.insert($0) }
        let calc = ExpenseCalculator(calendar: calendar)
        XCTAssertEqual(calc.filter([e1, e2], .init(homeID: h1.id)).count, 1)
        XCTAssertEqual(calc.filter([e1, e2], .init(assetID: a.id)).first?.title, "x")
    }

    func testLifetimeCostDoesNotDoubleCountPurchase() throws {
        let home = makeHome()
        let asset = makeAsset("Washer", in: home)
        asset.purchasePriceCents = 80_000
        context.insert(Expense(title: "Purchase", amountCents: 80_000, category: .purchase, home: home, asset: asset))
        context.insert(Expense(title: "Repair", amountCents: 18_500, category: .repair, home: home, asset: asset))
        try context.save()
        XCTAssertEqual(asset.lifetimeCostCents, 98_500)
        XCTAssertEqual(asset.repairCostCents, 18_500)
        asset.purchasePriceCents = nil
        XCTAssertEqual(asset.lifetimeCostCents, 98_500, "falls back to the purchase expense when no price is recorded")
    }

    func testServiceRecordCostStaysInSyncWithSingleExpense() throws {
        let home = makeHome()
        let asset = makeAsset("Dryer", in: home)
        let record = ServiceRecord(title: "Belt", kind: .repair, home: home, asset: asset)
        record.costCents = 12_000
        context.insert(record)
        service.syncExpense(for: record)
        record.costCents = 15_000
        record.kind = .service
        service.syncExpense(for: record)
        try context.save()
        XCTAssertEqual(fetch(Expense.self).count, 1)
        XCTAssertEqual(fetch(Expense.self).first?.amountCents, 15_000)
        XCTAssertEqual(fetch(Expense.self).first?.category, .maintenance)
        record.costCents = nil
        service.syncExpense(for: record)
        try context.save()
        XCTAssertEqual(fetch(Expense.self).count, 0)
    }

    func testInventoryPDFContainsItemsAndDisclaimer() throws {
        let home = makeHome("Report Home", rooms: ["Kitchen", "Office"])
        let fridge = makeAsset("Refrigerator", in: home, room: home.sortedRooms[0])
        fridge.serialNumber = "SER-12345"
        fridge.purchasePriceCents = 219_900
        fridge.replacementValueCents = 249_900
        let photo = try files.save(pngData(), fileExtension: "png")
        service.addPhoto(fileName: photo, to: fridge)
        for i in 0..<30 { makeAsset("Book \(i)", in: home, room: home.sortedRooms[1], category: .other) }
        try context.save()

        var options = ReportOptions()
        options.homeName = home.name
        let data = InventoryReportBuilder(files: files, currencyCode: "USD").makePDF(assets: fetch(Asset.self), options: options)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1, "long inventories paginate")
        let text = pdf.string ?? ""
        XCTAssertTrue(text.contains("Refrigerator"))
        XCTAssertTrue(text.contains("SER-12345"))
        XCTAssertTrue(text.contains("not an appraisal"))
        XCTAssertTrue(text.contains("Report Home"))
        XCTAssertTrue(text.contains("$2,499.00"), "replacement value included when selected")

        options.includeSerialNumbers = false
        options.includeReplacementValues = false
        let lean = PDFDocument(data: InventoryReportBuilder(files: files, currencyCode: "USD").makePDF(assets: [fridge], options: options))?.string ?? ""
        XCTAssertFalse(lean.contains("SER-12345"), "users choose what is included")
        XCTAssertFalse(lean.contains("2,499.00"))
    }

    func testEmptyReportStillGenerates() {
        let data = InventoryReportBuilder(files: files).makePDF(assets: [], options: ReportOptions())
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
    }

    func testExportFileWriting() throws {
        let url = try ExportFiles.write(Data("x".utf8), named: "A/B:C.pdf")
        XCTAssertEqual(url.lastPathComponent, "A-B-C.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        ExportFiles.cleanUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
