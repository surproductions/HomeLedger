import Foundation
import UIKit

struct ReportOptions: Equatable {
    var title: String = "Home Inventory"
    var homeName: String = ""
    var preparedBy: String = ""
    var includePhotos: Bool = true
    var includeSerialNumbers: Bool = true
    var includePurchaseDetails: Bool = true
    var includeReplacementValues: Bool = true
    var includeNotes: Bool = false
    var groupByRoom: Bool = true
}

/// Generates a printable PDF inventory with native UIKit drawing. Runs entirely on device.
struct InventoryReportBuilder {
    static let disclaimer = "This report is a personal record created by the owner with HomeLedger. It is not an appraisal, a valuation, or proof of insurance coverage. Values are as entered by the owner. Whether an insurer accepts this document is determined by the insurer."

    var files: FileStore = .shared
    var currencyCode: String = Preferences.currencyCode
    var now: Date = .now

    private let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72 dpi
    private let margin: CGFloat = 40
    private var contentWidth: CGFloat { pageRect.width - margin * 2 }

    private let ink = UIColor(red: 0.07, green: 0.08, blue: 0.17, alpha: 1)
    private let muted = UIColor(red: 0.42, green: 0.44, blue: 0.52, alpha: 1)
    private let brand = UIColor(red: 0.12, green: 0.25, blue: 0.64, alpha: 1)
    private let hairline = UIColor(red: 0.88, green: 0.89, blue: 0.93, alpha: 1)

    func makePDF(assets: [Asset], options: ReportOptions) -> Data {
        let sorted = assets.sorted { lhs, rhs in
            let l = (lhs.room?.sortIndex ?? Int.max, lhs.room?.name ?? "", lhs.name)
            let r = (rhs.room?.sortIndex ?? Int.max, rhs.room?.name ?? "", rhs.name)
            return l < r
        }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(options.title) — \(options.homeName)",
            kCGPDFContextCreator as String: "HomeLedger"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            var page = 0
            var y: CGFloat = 0

            func newPage() {
                ctx.beginPage()
                page += 1
                drawFooter(page: page)
                y = margin
            }
            func ensureSpace(_ height: CGFloat) {
                if y + height > pageRect.height - margin - 30 { newPage() }
            }

            newPage()
            y = drawCover(assets: sorted, options: options, top: y)

            var currentGroup: String?
            for asset in sorted {
                let group = options.groupByRoom ? (asset.room?.name ?? "Unassigned") : "Items"
                if group != currentGroup {
                    ensureSpace(90)
                    y += 14
                    y = drawText(group.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: brand, at: CGPoint(x: margin, y: y), width: contentWidth, kern: 1.2)
                    y += 6
                    hairline.setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75))
                    y += 8
                    currentGroup = group
                }
                let height = itemHeight(asset, options: options)
                ensureSpace(height)
                drawItem(asset, options: options, top: y)
                y += height
            }

            if sorted.isEmpty {
                y += 20
                _ = drawText("No items match the selected filters.", font: .systemFont(ofSize: 12), color: muted, at: CGPoint(x: margin, y: y), width: contentWidth)
            }
        }
    }

    // MARK: Sections

    private func drawCover(assets: [Asset], options: ReportOptions, top: CGFloat) -> CGFloat {
        var y = top
        brand.setFill()
        UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: 110), cornerRadius: 14).fill()
        _ = drawText("HOMELEDGER", font: .systemFont(ofSize: 9, weight: .semibold), color: UIColor.white.withAlphaComponent(0.75), at: CGPoint(x: margin + 20, y: y + 18), width: contentWidth - 40, kern: 1.5)
        _ = drawText(options.title, font: .systemFont(ofSize: 24, weight: .bold), color: .white, at: CGPoint(x: margin + 20, y: y + 34), width: contentWidth - 40)
        let sub = [options.homeName, "Generated \(now.formatted(date: .long, time: .shortened))", options.preparedBy.isEmpty ? nil : "Prepared by \(options.preparedBy)"]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        _ = drawText(sub, font: .systemFont(ofSize: 11), color: UIColor.white.withAlphaComponent(0.9), at: CGPoint(x: margin + 20, y: y + 72), width: contentWidth - 40)
        y += 126

        let purchaseTotal = assets.compactMap(\.purchasePriceCents).reduce(0, +)
        let replacementTotal = assets.compactMap(\.replacementValueCents).reduce(0, +)
        var stats: [(String, String)] = [("Items", "\(assets.count)"), ("With photos", "\(assets.filter { !($0.photos ?? []).isEmpty }.count)")]
        if options.includePurchaseDetails { stats.append(("Purchase value", Money.format(cents: purchaseTotal, currencyCode: currencyCode, showCents: false))) }
        if options.includeReplacementValues { stats.append(("Est. replacement", Money.format(cents: replacementTotal, currencyCode: currencyCode, showCents: false))) }
        let w = contentWidth / CGFloat(stats.count)
        for (i, stat) in stats.enumerated() {
            let x = margin + CGFloat(i) * w
            _ = drawText(stat.0, font: .systemFont(ofSize: 9, weight: .medium), color: muted, at: CGPoint(x: x, y: y), width: w - 8)
            _ = drawText(stat.1, font: .systemFont(ofSize: 16, weight: .semibold), color: ink, at: CGPoint(x: x, y: y + 13), width: w - 8)
        }
        y += 46

        let box = CGRect(x: margin, y: y, width: contentWidth, height: 0)
        let text = NSAttributedString(string: Self.disclaimer, attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: muted])
        let h = text.boundingRect(with: CGSize(width: contentWidth - 24, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height
        UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: box.minX, y: y, width: contentWidth, height: h + 20), cornerRadius: 8).fill()
        text.draw(with: CGRect(x: margin + 12, y: y + 10, width: contentWidth - 24, height: h + 2), options: [.usesLineFragmentOrigin], context: nil)
        return y + h + 28
    }

    private func detailLines(_ asset: Asset, options: ReportOptions) -> [String] {
        var lines: [String] = []
        let identity = [asset.categoryInfo.name, asset.brand, asset.modelNumber.isEmpty ? nil : "Model \(asset.modelNumber)"].compactMap { $0 }.filter { !$0.isEmpty }
        lines.append(identity.joined(separator: " · "))
        if options.includeSerialNumbers && !asset.serialNumber.isEmpty { lines.append("Serial: \(asset.serialNumber)") }
        if options.includePurchaseDetails {
            var p: [String] = []
            if let d = asset.purchaseDate { p.append("Purchased \(d.formatted(date: .abbreviated, time: .omitted))") }
            if !asset.retailer.isEmpty { p.append(asset.retailer) }
            if let c = asset.purchasePriceCents { p.append(Money.format(cents: c, currencyCode: currencyCode)) }
            if !p.isEmpty { lines.append(p.joined(separator: " · ")) }
        }
        if options.includeReplacementValues, let r = asset.replacementValueCents {
            lines.append("Estimated replacement value: \(Money.format(cents: r, currencyCode: currencyCode))")
        }
        var extra = ["Condition: \(asset.condition.label)"]
        if asset.quantity > 1 { extra.append("Quantity: \(asset.quantity)") }
        if let w = asset.warrantyExpiration { extra.append("Warranty until \(w.formatted(date: .abbreviated, time: .omitted))\(asset.warrantyIsEstimated ? " (est.)" : "")") }
        lines.append(extra.joined(separator: " · "))
        if options.includeNotes && !asset.notes.isEmpty { lines.append(String(asset.notes.prefix(300))) }
        return lines
    }

    private func itemHeight(_ asset: Asset, options: ReportOptions) -> CGFloat {
        let textWidth = contentWidth - (options.includePhotos ? 96 : 0)
        var h = measure(asset.name, font: .systemFont(ofSize: 13, weight: .semibold), width: textWidth) + 4
        for line in detailLines(asset, options: options) { h += measure(line, font: .systemFont(ofSize: 10), width: textWidth) + 2 }
        let photoHeight: CGFloat = options.includePhotos ? 84 : 0
        return max(h, photoHeight) + 16
    }

    private func drawItem(_ asset: Asset, options: ReportOptions, top: CGFloat) {
        var x = margin
        if options.includePhotos {
            let rect = CGRect(x: margin, y: top, width: 84, height: 84)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            if let photo = asset.sortedPhotos.first, let image = files.thumbnail(for: photo.fileName, maxPixel: 400) {
                UIGraphicsGetCurrentContext()?.saveGState()
                path.addClip()
                let scale = max(rect.width / image.size.width, rect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
                UIGraphicsGetCurrentContext()?.restoreGState()
            } else {
                UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill()
                path.fill()
                _ = drawText("No photo", font: .systemFont(ofSize: 8), color: muted, at: CGPoint(x: rect.minX, y: rect.midY - 5), width: rect.width, alignment: .center)
            }
            x += 96
        }
        let width = contentWidth - (x - margin)
        var y = drawText(asset.name, font: .systemFont(ofSize: 13, weight: .semibold), color: ink, at: CGPoint(x: x, y: top), width: width) + 4
        for line in detailLines(asset, options: options) {
            y = drawText(line, font: .systemFont(ofSize: 10), color: muted, at: CGPoint(x: x, y: y), width: width) + 2
        }
    }

    private func drawFooter(page: Int) {
        let y = pageRect.height - margin + 6
        _ = drawText("HomeLedger inventory · personal record, not an appraisal or proof of coverage", font: .systemFont(ofSize: 7.5), color: muted, at: CGPoint(x: margin, y: y), width: contentWidth - 60)
        _ = drawText("Page \(page)", font: .systemFont(ofSize: 7.5, weight: .medium), color: muted, at: CGPoint(x: margin, y: y), width: contentWidth, alignment: .right)
    }

    // MARK: Text helpers

    private func measure(_ string: String, font: UIFont, width: CGFloat) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    @discardableResult
    private func drawText(_ string: String, font: UIFont, color: UIColor, at point: CGPoint, width: CGFloat, alignment: NSTextAlignment = .left, kern: CGFloat = 0) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern])
        let height = ceil(attr.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        attr.draw(with: CGRect(x: point.x, y: point.y, width: width, height: height + 1), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return point.y + height
    }
}

/// Writes exports to a private temporary folder for sharing; cleaned up on next launch.
enum ExportFiles {
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true) }

    static func write(_ data: Data, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent(safe)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
