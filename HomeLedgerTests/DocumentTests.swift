import PDFKit
import XCTest
@testable import HomeLedger

@MainActor
final class DocumentTests: HomeLedgerTestCase {
    var parser: ReceiptParser { ReceiptParser(calendar: calendar, monthFirst: true) }

    let receipt = """
    BEST BUY
    Store #1182  Tel 555-0100
    Date: 03/14/2025
    Samsung 28 cu ft French Door Refrigerator
    Model: RF28T5001SR
    Serial No: 0B9K4BAR600123
    Subtotal 2,039.00
    Tax 160.00
    Total $2,199.00
    2-year limited warranty
    Thank you for shopping
    """

    func testParsesReceiptFieldsWithConfidence() {
        let r = parser.parse(receipt)
        XCTAssertEqual(r.merchant?.value, "Best Buy")
        XCTAssertEqual(r.merchant?.confidence, .inferred, "merchant is always a guess")
        XCTAssertEqual(r.purchaseDate?.value, date(2025, 3, 14))
        XCTAssertEqual(r.purchaseDate?.confidence, .detected)
        XCTAssertEqual(r.totalCents?.value, 219_900)
        XCTAssertEqual(r.totalCents?.confidence, .detected)
        XCTAssertEqual(r.modelNumber?.value, "RF28T5001SR")
        XCTAssertEqual(r.serialNumber?.value, "0B9K4BAR600123")
        XCTAssertEqual(r.warrantyMonths?.value, 24)
        XCTAssertNil(r.warrantyExpiration, "no explicit end date is printed, so none is reported")
        XCTAssertEqual(r.productName?.value, "Samsung 28 cu ft French Door Refrigerator")
        XCTAssertEqual(r.suggestedKind, .receipt)
    }

    func testExplicitWarrantyExpiration() {
        let text = """
        Protection Plan Certificate
        Coverage valid through: December 31, 2027
        Serial: XYZ98765
        """
        let r = parser.parse(text)
        XCTAssertEqual(r.warrantyExpiration?.value, date(2027, 12, 31))
        XCTAssertEqual(r.warrantyExpiration?.confidence, .detected)
        XCTAssertNil(r.purchaseDate, "an expiry date is never reused as the purchase date")
        XCTAssertEqual(r.serialNumber?.value, "XYZ98765")
    }

    func testNeverInventsValuesFromUnrelatedText() {
        let r = parser.parse("Remember to water the plants\nCall mom on Sunday")
        XCTAssertNil(r.purchaseDate)
        XCTAssertNil(r.totalCents)
        XCTAssertNil(r.serialNumber)
        XCTAssertNil(r.modelNumber)
        XCTAssertNil(r.warrantyMonths)
        XCTAssertNil(r.warrantyExpiration)
        XCTAssertTrue(parser.parse("").isEmpty)
    }

    func testLabelsWithoutIdentifiersAreNotMistakenForValues() {
        let r = parser.parse("Serial number: see label on back\nModel number: see manual")
        XCTAssertNil(r.serialNumber)
        XCTAssertNil(r.modelNumber)
    }

    func testFallbackTotalIsMarkedAsGuess() {
        let r = parser.parse("Coffee 3.50\nMuffin 4.25")
        XCTAssertEqual(r.totalCents?.value, 425)
        XCTAssertEqual(r.totalCents?.confidence, .inferred)
    }

    func testAmountAndDateFormats() {
        XCTAssertEqual(parser.amounts(in: "Grand Total: 1,234.56"), [123_456])
        XCTAssertEqual(parser.amounts(in: "Total 2 199,00 €"), [219_900])
        XCTAssertEqual(parser.amounts(in: "Store #42"), [])
        XCTAssertEqual(parser.dates(in: "Order date 2025-01-05").first, date(2025, 1, 5))
        XCTAssertEqual(parser.dates(in: "Purchased Jan 5, 2025").first, date(2025, 1, 5))
        XCTAssertEqual(parser.dates(in: "5 January 2025").first, date(2025, 1, 5))
        XCTAssertEqual(parser.dates(in: "31/12/2024").first, date(2024, 12, 31), "day-first fallback when month > 12")
        XCTAssertTrue(parser.dates(in: "02/30/2025").isEmpty, "invalid dates are rejected")
    }

    func testReviewDraftLabelsCalculatedWarrantyAsEstimate() {
        let draft = DocumentReviewDraft(extraction: parser.parse(receipt), fallbackTitle: "Scan", calendar: calendar)
        XCTAssertEqual(draft.vendor, "Best Buy")
        XCTAssertEqual(draft.amountCents, 219_900)
        XCTAssertEqual(draft.warrantyEndConfidence, .inferred)
        XCTAssertNotNil(draft.warrantyEndCalculatedFrom)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: draft.warrantyEnd!), DateComponents(year: 2027, month: 3, day: 13))
        XCTAssertEqual(draft.kind, .receipt)
    }

    func testImporterSniffsTypesAndCombinesScannedPages() throws {
        XCTAssertEqual(DocumentImporter.sniff(Data("%PDF-1.7".utf8)), .pdf)
        XCTAssertEqual(DocumentImporter.sniff(pngData()), .png)
        XCTAssertNil(DocumentImporter.sniff(Data("hello".utf8)))

        let page = UIImage(data: pngData())!
        let file = try DocumentImporter.importScannedPages([page, page, page], store: files)
        XCTAssertEqual(file.contentType, .pdf)
        XCTAssertEqual(PDFDocument(url: files.url(for: file.fileName))?.pageCount, 3, "every scanned page is preserved")
        file.discard(store: files)
        XCTAssertFalse(files.exists(file.fileName))
    }

    func testImportFromFileURLRejectsUnsupported() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID()).txt")
        try Data("just text".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try DocumentImporter.importFile(at: tmp, store: files)) { error in
            guard case FileStoreError.unsupportedFormat = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testPDFTextExtractionAndOCRPipelineOnDevice() async throws {
        let data = SampleDataService.makeTextPDF(lines: receipt.components(separatedBy: "\n"))!
        let name = try files.save(data, fileExtension: "pdf")
        let text = try await OCRService.extractText(from: files.url(for: name), contentType: .pdf)
        XCTAssertTrue(text.contains("RF28T5001SR"))
        let r = parser.parse(text)
        XCTAssertEqual(r.totalCents?.value, 219_900)
    }

    func testVisionOCRReadsRenderedImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            ("TOTAL 45.99" as NSString).draw(at: CGPoint(x: 40, y: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.black])
        }
        let text = try await OCRService.recognizeText(in: image)
        XCTAssertTrue(text.uppercased().contains("45.99") || text.uppercased().contains("45,99"), "Recognized: \(text)")
    }

    func testDeletingDocumentRemovesFileAndUnlinksExpense() throws {
        let name = try files.save(Data("%PDF-1.4".utf8), fileExtension: "pdf")
        let doc = DocumentRecord(title: "R", kind: .receipt, fileName: name, contentType: .pdf)
        context.insert(doc)
        let e = Expense(title: "E", amountCents: 100)
        e.receipt = doc
        context.insert(e)
        try context.save()
        service.deleteDocument(doc)
        try context.save()
        XCTAssertFalse(files.exists(name))
        XCTAssertEqual(fetch(Expense.self).count, 1)
        XCTAssertNil(fetch(Expense.self).first?.receipt)
    }
}
