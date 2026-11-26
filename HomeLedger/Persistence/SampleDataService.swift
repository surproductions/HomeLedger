import Foundation
import SwiftData
import UIKit

/// Creates a realistic demo household. Every record is flagged `isSample` so
/// "Remove sample data" deletes exactly these records and nothing the user created.
@MainActor
struct SampleDataService {
    let context: ModelContext
    var files: FileStore = .shared
    var now: Date = .now
    var calendar: Calendar = .current

    static let sampleAddressNote = "Sample data — remove anytime in Settings"

    private func days(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: now) ?? now }
    private func months(_ n: Int) -> Date { calendar.date(byAdding: .month, value: n, to: now) ?? now }

    @discardableResult
    func seed() -> Home {
        let home = Home(name: "Maple Street House", type: .house, sortIndex: 0, isSample: true)
        home.addressLine = Self.sampleAddressNote
        context.insert(home)

        let roomSpecs: [(String, String)] = [("Kitchen", "refrigerator"), ("Living Room", "sofa"), ("Laundry", "washer"),
                                             ("Garage", "car"), ("Office", "desktopcomputer"), ("Utility Room", "wrench.and.screwdriver")]
        var rooms: [String: Room] = [:]
        for (i, spec) in roomSpecs.enumerated() {
            let room = Room(name: spec.0, symbolName: spec.1, sortIndex: i, home: home, isSample: true)
            context.insert(room)
            rooms[spec.0] = room
        }

        func asset(_ name: String, _ category: AssetCategory, room: String, brand: String, model: String, serial: String = "",
                   bought: Date?, price: Int?, retailer: String = "", warrantyMonths: Int? = nil, warrantyEnds: Date? = nil,
                   replacement: Int? = nil, color: UIColor, symbol: String) -> Asset {
            let a = Asset(name: name, category: category, home: home, room: rooms[room], isSample: true)
            a.brand = brand; a.modelNumber = model; a.serialNumber = serial
            a.purchaseDate = bought; a.purchasePriceCents = price; a.retailer = retailer
            a.replacementValueCents = replacement
            a.condition = .good
            if let bought, let warrantyMonths {
                a.warrantyStart = bought
                a.warrantyExpiration = WarrantyMath.expiration(start: bought, months: warrantyMonths, calendar: calendar)
                a.warrantyProvider = brand
            }
            if let warrantyEnds { a.warrantyExpiration = warrantyEnds; a.warrantyStart = bought; a.warrantyProvider = brand }
            a.createdAt = bought ?? now
            context.insert(a)
            if let image = Self.placeholderPhoto(symbol: symbol, color: color), let name = try? files.saveImage(image, maxDimension: 900) {
                let p = AssetPhoto(fileName: name, sortIndex: 0, asset: a)
                p.isSample = true
                context.insert(p)
            }
            return a
        }

        let blue = UIColor(red: 0.18, green: 0.33, blue: 0.78, alpha: 1)
        let teal = UIColor(red: 0.12, green: 0.55, blue: 0.55, alpha: 1)
        let indigo = UIColor(red: 0.36, green: 0.31, blue: 0.80, alpha: 1)
        let slate = UIColor(red: 0.30, green: 0.35, blue: 0.45, alpha: 1)
        let amber = UIColor(red: 0.80, green: 0.50, blue: 0.15, alpha: 1)

        let fridge = asset("Refrigerator", .appliance, room: "Kitchen", brand: "Samsung", model: "RF28T5001SR", serial: "0B9K4BAR600123",
                           bought: months(-11), price: 219_900, retailer: "Best Buy", warrantyEnds: days(34), replacement: 249_900, color: blue, symbol: "refrigerator")
        fridge.createdAt = days(-2)
        let dishwasher = asset("Dishwasher", .appliance, room: "Kitchen", brand: "Bosch", model: "SHPM65Z55N", serial: "FD9905 01234",
                               bought: months(-20), price: 104_900, retailer: "Home Depot", warrantyMonths: 24, replacement: 115_000, color: teal, symbol: "dishwasher")
        let washer = asset("Washing Machine", .appliance, room: "Laundry", brand: "LG", model: "WM4000HWA", serial: "203KWAB4F567",
                           bought: months(-38), price: 89_999, retailer: "Lowe's", warrantyMonths: 12, replacement: 95_000, color: indigo, symbol: "washer")
        _ = asset("Dryer", .appliance, room: "Laundry", brand: "LG", model: "DLEX4000W", bought: months(-38), price: 84_999, retailer: "Lowe's",
                  warrantyMonths: 12, color: indigo, symbol: "dryer")
        let furnace = asset("Furnace", .hvac, room: "Utility Room", brand: "Carrier", model: "59SC5A060E17", serial: "4021A23456",
                            bought: months(-50), price: 385_000, retailer: "Comfort Air Co.", warrantyMonths: 120, color: amber, symbol: "heater.vertical")
        let waterHeater = asset("Water Heater", .plumbing, room: "Utility Room", brand: "Rheem", model: "XE50T10H45U0",
                                bought: months(-30), price: 74_900, warrantyMonths: 72, color: slate, symbol: "flame")
        _ = asset("Sectional Sofa", .furniture, room: "Living Room", brand: "Article", model: "Sven", bought: months(-14), price: 189_900,
                  retailer: "Article", replacement: 199_900, color: slate, symbol: "sofa")
        let tv = asset("65\" OLED TV", .electronics, room: "Living Room", brand: "LG", model: "OLED65C3PUA", serial: "301MXAB12345",
                       bought: months(-7), price: 169_999, retailer: "Costco", warrantyEnds: days(52), replacement: 159_999, color: blue, symbol: "tv")
        tv.createdAt = days(-5)
        _ = asset("Laptop", .electronics, room: "Office", brand: "Apple", model: "MacBook Air 13\"", serial: "C02FX1Y2Q6L4",
                  bought: months(-4), price: 109_900, retailer: "Apple", warrantyMonths: 12, color: slate, symbol: "laptopcomputer")
        _ = asset("Lawn Mower", .outdoor, room: "Garage", brand: "EGO", model: "LM2135SP", bought: nil, price: nil, color: teal, symbol: "leaf")
        let drill = asset("Cordless Drill", .tools, room: "Garage", brand: "DeWalt", model: "DCD791D2", bought: months(-26), price: 17_900,
                          retailer: "Home Depot", warrantyMonths: 36, color: amber, symbol: "wrench.and.screwdriver")
        drill.createdAt = days(-1)

        // Documents (generated PDFs with real text so search and OCR review work offline)
        func document(_ title: String, _ kind: DocumentKind, asset: Asset?, lines: [String], vendor: String = "", amount: Int? = nil, date: Date? = nil) {
            guard let data = Self.makeTextPDF(lines: lines), let name = try? files.save(data, fileExtension: "pdf") else { return }
            let d = DocumentRecord(title: title, kind: kind, fileName: name, contentType: .pdf, home: home, asset: asset)
            d.originalFileName = "\(title).pdf"
            d.fileSize = data.count
            d.vendor = vendor
            d.amountCents = amount
            d.documentDate = date
            d.recognizedText = lines.joined(separator: "\n")
            d.isSample = true
            d.createdAt = date ?? now
            context.insert(d)
        }
        let fridgeDate = fridge.purchaseDate ?? now
        document("Refrigerator receipt", .receipt, asset: fridge, lines: [
            "BEST BUY", "Store #1182", "Date: \(fridgeDate.formatted(date: .numeric, time: .omitted))",
            "Samsung 28 cu ft French Door Refrigerator", "Model: RF28T5001SR", "Serial No: 0B9K4BAR600123",
            "Subtotal 2,039.00", "Tax 160.00", "Total $2,199.00", "Thank you for shopping"], vendor: "Best Buy", amount: 219_900, date: fridgeDate)
        document("Dishwasher owner's manual", .manual, asset: dishwasher, lines: [
            "Bosch 500 Series Dishwasher", "Owner's Manual & Installation Instructions", "Model SHPM65Z55N",
            "Clean the filter regularly for best results."], vendor: "Bosch", date: dishwasher.purchaseDate)
        document("Washer repair invoice", .invoice, asset: washer, lines: [
            "Appliance Pros LLC", "Invoice #4471", "Date: \(months(-4).formatted(date: .numeric, time: .omitted))",
            "Replaced drain pump, LG WM4000HWA", "Labor 95.00", "Parts 90.00", "Total Due $185.00"], vendor: "Appliance Pros LLC", amount: 18_500, date: months(-4))
        document("Homeowners insurance policy", .insurance, asset: nil, lines: [
            "Sample Mutual Insurance", "Homeowners Policy Declarations", "Policy number SMP-000000",
            "This is sample data for demonstration only."], vendor: "Sample Mutual", date: months(-6))

        // Repairs & service history (with linked expenses)
        let svc = DataService(context: context, files: files)
        func service(_ title: String, _ kind: ServiceKind, asset: Asset, date: Date, vendor: String, cost: Int, details: String) {
            let s = ServiceRecord(title: title, kind: kind, date: date, home: home, asset: asset)
            s.vendor = vendor; s.costCents = cost; s.details = details; s.isSample = true
            context.insert(s)
            svc.syncExpense(for: s)
        }
        service("Drain pump replaced", .repair, asset: washer, date: months(-4), vendor: "Appliance Pros LLC", cost: 18_500, details: "Washer stopped draining mid-cycle. Pump replaced under labor-only charge.")
        service("Annual furnace tune-up", .service, asset: furnace, date: months(-10), vendor: "Comfort Air Co.", cost: 12_900, details: "Cleaned burners, checked heat exchanger, replaced filter.")
        service("Thermostat wiring fix", .repair, asset: furnace, date: days(-20), vendor: "Comfort Air Co.", cost: 9_500, details: "Loose C-wire at the control board.")
        service("Anode rod inspection", .inspection, asset: waterHeater, date: months(-2), vendor: "Self", cost: 0, details: "Rod about 40% depleted. Re-check next year.")

        // Maintenance tasks
        func task(_ template: String, due: Date, asset: Asset? = nil, room: String? = nil, priority: MaintenancePriority = .normal, completedAgo: [Int] = []) {
            guard let t = MaintenanceTemplate.template(forKey: template) else { return }
            let task = MaintenanceTask(title: t.title, dueDate: due, recurrence: t.recurrence, priority: priority, home: home, isSample: true)
            task.details = t.details
            task.templateKey = t.key
            task.asset = asset
            task.room = room.flatMap { rooms[$0] }
            context.insert(task)
            for d in completedAgo {
                let log = MaintenanceLog(date: days(-d), kind: .completed, task: task)
                log.isSample = true
                context.insert(log)
            }
        }
        task("hvac-filter", due: days(4), asset: furnace, room: "Utility Room", priority: .high, completedAgo: [86, 178])
        task("smoke-test", due: days(-2), priority: .high, completedAgo: [32, 63])
        task("dishwasher-filter", due: days(11), asset: dishwasher, room: "Kitchen", completedAgo: [19])
        task("fridge-water-filter", due: days(23), asset: fridge, room: "Kitchen")
        task("gutters", due: days(41), room: "Outdoor")
        task("water-heater", due: days(95), asset: waterHeater, room: "Utility Room", completedAgo: [270])
        task("dryer-vent", due: days(16), room: "Laundry")

        // Other expenses spread over the year
        func expense(_ title: String, _ cents: Int, _ category: ExpenseCategory, daysAgo: Int, vendor: String = "", asset: Asset? = nil) {
            let e = Expense(title: title, amountCents: cents, date: days(-daysAgo), category: category, home: home, asset: asset)
            e.vendor = vendor; e.isSample = true
            context.insert(e)
        }
        expense("HVAC filters (6-pack)", 5_498, .maintenance, daysAgo: 86, vendor: "Amazon", asset: furnace)
        expense("Refrigerator water filter", 4_999, .maintenance, daysAgo: 160, vendor: "Samsung", asset: fridge)
        expense("Gutter cleaning service", 17_500, .maintenance, daysAgo: 320, vendor: "ClearFlow Gutters")
        expense("Smoke detector batteries", 1_899, .maintenance, daysAgo: 63, vendor: "Target")
        expense("Paint for living room", 23_450, .improvement, daysAgo: 140, vendor: "Sherwin-Williams")
        expense("Homeowners insurance (annual)", 142_000, .insurance, daysAgo: 180, vendor: "Sample Mutual")
        expense("Plumber — kitchen faucet leak", 21_000, .repair, daysAgo: 45, vendor: "Rapid Rooter")
        expense("Garden supplies", 8_634, .other, daysAgo: 12, vendor: "Local nursery")

        try? context.save()
        return home
    }

    // MARK: Generated assets

    static func placeholderPhoto(symbol: String, color: UIColor) -> UIImage? {
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [color.withAlphaComponent(0.95).cgColor, color.withAlphaComponent(0.65).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .light)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?.withTintColor(.white.withAlphaComponent(0.92), renderingMode: .alwaysOriginal) {
                let g = glyph.size
                glyph.draw(in: CGRect(x: (size.width - g.width) / 2, y: (size.height - g.height) / 2, width: g.width, height: g.height))
            }
        }
    }

    static func makeTextPDF(lines: [String]) -> Data? {
        let rect = CGRect(x: 0, y: 0, width: 420, height: 595)
        return UIGraphicsPDFRenderer(bounds: rect).pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            for (i, line) in lines.enumerated() {
                let font = i == 0 ? UIFont.boldSystemFont(ofSize: 18) : UIFont.systemFont(ofSize: 12)
                (line as NSString).draw(at: CGPoint(x: 36, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                y += i == 0 ? 30 : 20
            }
        }
    }
}
