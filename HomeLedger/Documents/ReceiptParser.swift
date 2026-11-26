import Foundation

/// How a value was obtained. The review screen labels these differently and the user always confirms.
enum FieldConfidence: String, Equatable {
    /// Found next to an explicit label (e.g. "Serial No: ABC123", "Total $45.00").
    case detected
    /// A best guess from layout or context (e.g. the first line is probably the merchant).
    case inferred

    var label: String {
        switch self {
        case .detected: "Detected"
        case .inferred: "Best guess — please check"
        }
    }
}

struct ExtractedField<Value: Equatable>: Equatable {
    var value: Value
    var confidence: FieldConfidence
    /// The text line the value came from, shown to the user for context.
    var sourceLine: String
}

struct ExtractionResult: Equatable {
    var merchant: ExtractedField<String>?
    var purchaseDate: ExtractedField<Date>?
    var productName: ExtractedField<String>?
    var modelNumber: ExtractedField<String>?
    var serialNumber: ExtractedField<String>?
    var totalCents: ExtractedField<Int>?
    var warrantyMonths: ExtractedField<Int>?
    var warrantyExpiration: ExtractedField<Date>?
    var suggestedKind: DocumentKind?

    var isEmpty: Bool {
        merchant == nil && purchaseDate == nil && productName == nil && modelNumber == nil &&
            serialNumber == nil && totalCents == nil && warrantyMonths == nil && warrantyExpiration == nil
    }

    var fieldCount: Int {
        [merchant != nil, purchaseDate != nil, productName != nil, modelNumber != nil, serialNumber != nil,
         totalCents != nil, warrantyMonths != nil, warrantyExpiration != nil].filter { $0 }.count
    }
}

/// Rule-based, on-device parser for receipts, invoices and warranty cards.
/// It never fabricates values: when nothing matches, the field is left empty.
struct ReceiptParser {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// When true, ambiguous numeric dates like 03/04/2024 are read month-first (US style).
    var monthFirst: Bool = (Locale.current.region?.identifier ?? "US") == "US"

    func parse(_ text: String) -> ExtractionResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = ExtractionResult()
        guard !lines.isEmpty else { return result }

        result.serialNumber = firstCapture(in: lines, pattern: #"(?i)\b(?:serial\s*(?:no\.?|number|#)?|s/n|sn\b)\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-]{3,})"#)
            .map { ExtractedField(value: $0.value.uppercased(), confidence: .detected, sourceLine: $0.line) }
        result.modelNumber = firstCapture(in: lines, pattern: #"(?i)\b(?:model\b\s*(?:no\.?|number|#)?|mod\.|m/n)\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-./]{2,})"#)
            .flatMap { ["NUMBER", "NO", "NAME"].contains($0.value.uppercased()) ? nil : ExtractedField(value: $0.value.uppercased(), confidence: .detected, sourceLine: $0.line) }

        result.warrantyExpiration = warrantyExpiration(in: lines)
        result.warrantyMonths = warrantyPeriod(in: lines)
        result.purchaseDate = purchaseDate(in: lines)
        result.totalCents = total(in: lines)
        result.merchant = merchant(in: lines)
        result.productName = productName(in: lines, excluding: result.merchant?.value)
            ?? productNameNearModel(in: lines, modelLine: result.modelNumber?.sourceLine, merchantLine: result.merchant?.sourceLine)
        result.suggestedKind = suggestKind(text.lowercased())
        return result
    }

    // MARK: Dates

    func dates(in line: String) -> [Date] {
        var found: [(Int, Date)] = []
        let monthNames = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"

        for m in RegexHelper.matches(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#, in: line) {
            if let d = makeDate(year: Int(m.groups[0]), month: Int(m.groups[1]), day: Int(m.groups[2])) { found.append((m.location, d)) }
        }
        for m in RegexHelper.matches(#"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b"#, in: line) {
            guard let a = Int(m.groups[0]), let b = Int(m.groups[1]), var y = Int(m.groups[2]) else { continue }
            if y < 100 { y += 2000 }
            var month = monthFirst ? a : b
            var day = monthFirst ? b : a
            if month > 12 && day <= 12 { swap(&month, &day) }
            if let d = makeDate(year: y, month: month, day: day) { found.append((m.location, d)) }
        }
        for m in RegexHelper.matches("(?i)\\b(\(monthNames))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b", in: line) {
            if let month = monthNumber(m.groups[0]), let d = makeDate(year: Int(m.groups[2]), month: month, day: Int(m.groups[1])) { found.append((m.location, d)) }
        }
        for m in RegexHelper.matches("(?i)\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthNames))\\.?,?\\s+(\\d{4})\\b", in: line) {
            if let month = monthNumber(m.groups[1]), let d = makeDate(year: Int(m.groups[2]), month: month, day: Int(m.groups[0])) { found.append((m.location, d)) }
        }
        return found.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private func makeDate(year: Int?, month: Int?, day: Int?) -> Date? {
        guard let year, let month, let day, (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let comps = DateComponents(calendar: calendar, year: year, month: month, day: day, hour: 12)
        guard comps.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: comps)
    }

    private func monthNumber(_ name: String) -> Int? {
        let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let lower = name.lowercased()
        return prefixes.firstIndex { lower.hasPrefix($0) }.map { $0 + 1 }
    }

    private func isExpiryLine(_ lower: String) -> Bool {
        ["expir", "valid until", "valid through", "valid thru", "coverage end", "ends on", "warranty end", "return by", "return policy", "exp "].contains { lower.contains($0) }
    }

    private func purchaseDate(in lines: [String]) -> ExtractedField<Date>? {
        let labels = ["date of purchase", "purchase date", "purchased", "order date", "invoice date", "transaction date", "sale date", "date:", "date "]
        for line in lines {
            let lower = line.lowercased()
            guard !isExpiryLine(lower) else { continue }
            if labels.contains(where: { lower.contains($0) }), let d = dates(in: line).first {
                return ExtractedField(value: d, confidence: .detected, sourceLine: line)
            }
        }
        for line in lines where !isExpiryLine(line.lowercased()) {
            if let d = dates(in: line).first { return ExtractedField(value: d, confidence: .inferred, sourceLine: line) }
        }
        return nil
    }

    private func warrantyExpiration(in lines: [String]) -> ExtractedField<Date>? {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("warrant") || lower.contains("coverage") || lower.contains("protection plan") else { continue }
            guard isExpiryLine(lower) || lower.contains("until") || lower.contains("through") else { continue }
            if let d = dates(in: line).last { return ExtractedField(value: d, confidence: .detected, sourceLine: line) }
            // Label on one line, date on the next.
            if index + 1 < lines.count, let d = dates(in: lines[index + 1]).first {
                return ExtractedField(value: d, confidence: .detected, sourceLine: line + " " + lines[index + 1])
            }
        }
        return nil
    }

    private func warrantyPeriod(in lines: [String]) -> ExtractedField<Int>? {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10, "twelve": 12, "eighteen": 18, "twenty-four": 24, "thirty-six": 36]
        let numberPattern = #"(\d{1,3}|one|two|three|four|five|six|ten|twelve|eighteen|twenty-four|thirty-six)"#
        let patterns = [
            "(?i)\(numberPattern)[\\s\\-]*(year|yr|month|mo)s?\\.?[\\s\\-]*(?:limited\\s+|manufacturer'?s?\\s+|parts(?:\\s+and|\\s+&)?\\s+labou?r\\s+)?warrant",
            "(?i)warrant(?:y|ee)[^\\n]{0,30}?\(numberPattern)[\\s\\-]*(year|yr|month|mo)s?\\b"
        ]
        for line in lines {
            for pattern in patterns {
                guard let m = RegexHelper.matches(pattern, in: line).first else { continue }
                let rawNumber = m.groups[0].lowercased()
                guard let n = Int(rawNumber) ?? words[rawNumber], n > 0 else { continue }
                let unit = m.groups[1].lowercased()
                let months = unit.hasPrefix("y") ? n * 12 : n
                guard months <= 240 else { continue }
                return ExtractedField(value: months, confidence: .detected, sourceLine: line)
            }
        }
        return nil
    }

    // MARK: Amounts

    func amounts(in line: String) -> [Int] {
        RegexHelper.matches(#"(?<![\d.,])[$€£¥]?\s?(\d{1,3}(?:[,\s]\d{3})+|\d+)[.,](\d{2})(?![\d])"#, in: line).compactMap { m in
            let whole = m.groups[0].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
            guard let w = Int(whole), let c = Int(m.groups[1]) else { return nil }
            return w * 100 + c
        }
    }

    private func total(in lines: [String]) -> ExtractedField<Int>? {
        let strong = ["grand total", "total due", "amount due", "balance due", "total paid", "order total", "amount paid", "total"]
        let exclude = ["subtotal", "sub total", "sub-total", "total tax", "tax total", "total savings", "total discount", "items total", "total items"]
        var candidate: ExtractedField<Int>?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard strong.contains(where: { lower.contains($0) }), !exclude.contains(where: { lower.contains($0) }) else { continue }
            if let amount = amounts(in: line).last {
                candidate = ExtractedField(value: amount, confidence: .detected, sourceLine: line)
                if lower.contains("grand total") || lower.contains("amount due") || lower.contains("total due") { return candidate }
            } else if index + 1 < lines.count, let amount = amounts(in: lines[index + 1]).first {
                candidate = ExtractedField(value: amount, confidence: .detected, sourceLine: line + " " + lines[index + 1])
            }
        }
        if let candidate { return candidate }
        // Fallback: the largest amount on the page, clearly marked as a guess.
        var best: (Int, String)?
        for line in lines {
            for a in amounts(in: line) where a > (best?.0 ?? 0) { best = (a, line) }
        }
        return best.map { ExtractedField(value: $0.0, confidence: .inferred, sourceLine: $0.1) }
    }

    // MARK: Text fields

    private static let nonMerchantWords = ["receipt", "invoice", "welcome", "thank", "order", "customer", "copy", "store #", "tel", "phone", "www", "http", "date", "cashier", "transaction", "warranty", "certificate", "page", "bill to", "ship to", "sold to"]

    private func merchant(in lines: [String]) -> ExtractedField<String>? {
        for line in lines.prefix(6) {
            let lower = line.lowercased()
            let letters = line.filter(\.isLetter).count
            guard letters >= 3, Double(letters) / Double(max(line.count, 1)) > 0.6 else { continue }
            guard !Self.nonMerchantWords.contains(where: { lower.contains($0) }) else { continue }
            guard dates(in: line).isEmpty, amounts(in: line).isEmpty else { continue }
            return ExtractedField(value: line.trimmingCharacters(in: .punctuationCharacters).capitalizedIfShouting, confidence: .inferred, sourceLine: line)
        }
        return nil
    }

    private func productName(in lines: [String], excluding merchant: String?) -> ExtractedField<String>? {
        let skip = ["total", "tax", "subtotal", "change", "cash", "visa", "mastercard", "amex", "debit", "credit", "balance", "discount", "savings", "tender", "payment", "shipping", "fee", "tip"]
        for line in lines {
            let lower = line.lowercased()
            if let label = RegexHelper.matches(#"(?i)^(?:item|product|description|desc)\s*[:#]\s*(.{3,60})$"#, in: line).first?.groups.first {
                return ExtractedField(value: label.trimmingCharacters(in: .whitespaces), confidence: .detected, sourceLine: line)
            }
            guard !skip.contains(where: { lower.contains($0) }), line != (merchant ?? "") else { continue }
            guard !amounts(in: line).isEmpty else { continue }
            let text = line.replacingOccurrences(of: #"[$€£¥]?\s?\d[\d,\s]*[.,]\d{2}"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\b(?:qty|x)\s*\d+\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let letters = text.filter(\.isLetter).count
            if letters >= 4 { return ExtractedField(value: text.capitalizedIfShouting, confidence: .inferred, sourceLine: line) }
        }
        return nil
    }

    /// The line directly above "Model: …" is often the product description.
    private func productNameNearModel(in lines: [String], modelLine: String?, merchantLine: String?) -> ExtractedField<String>? {
        guard let modelLine, let index = lines.firstIndex(of: modelLine), index > 0 else { return nil }
        let candidate = lines[index - 1]
        guard candidate != merchantLine, dates(in: candidate).isEmpty, amounts(in: candidate).isEmpty,
              candidate.filter(\.isLetter).count >= 4,
              !Self.nonMerchantWords.contains(where: { candidate.lowercased().contains($0) }) else { return nil }
        return ExtractedField(value: candidate.capitalizedIfShouting, confidence: .inferred, sourceLine: candidate)
    }

    private func suggestKind(_ lower: String) -> DocumentKind? {
        if lower.contains("insurance") || lower.contains("policy number") || lower.contains("policyholder") { return .insurance }
        if lower.contains("owner's manual") || lower.contains("owners manual") || lower.contains("user guide") || lower.contains("user manual") || lower.contains("installation instructions") { return .manual }
        if lower.contains("warranty") && !lower.contains("total") { return .warranty }
        if lower.contains("technician") || lower.contains("service call") || lower.contains("labor") || lower.contains("labour") || lower.contains("work order") { return .service }
        if lower.contains("invoice") { return .invoice }
        if lower.contains("total") || lower.contains("receipt") || lower.contains("subtotal") { return .receipt }
        return nil
    }

    private func firstCapture(in lines: [String], pattern: String) -> (value: String, line: String)? {
        for line in lines {
            if let m = RegexHelper.matches(pattern, in: line).first, let value = m.groups.first, !value.isEmpty {
                return (value, line)
            }
        }
        return nil
    }
}

/// Small NSRegularExpression helper with cached compilation.
enum RegexHelper {
    struct Match { let location: Int; let groups: [String] }
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func matches(_ pattern: String, in text: String) -> [Match] {
        lock.lock()
        let regex: NSRegularExpression?
        if let cached = cache[pattern] {
            regex = cached
        } else {
            regex = try? NSRegularExpression(pattern: pattern)
            if let regex { cache[pattern] = regex }
        }
        lock.unlock()
        guard let regex else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { result in
            let groups = (1..<max(result.numberOfRanges, 1)).map { i -> String in
                let r = result.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            return Match(location: result.range.location, groups: groups)
        }
    }
}

extension String {
    /// "BEST BUY" → "Best Buy"; leaves mixed-case strings untouched.
    var capitalizedIfShouting: String {
        let letters = filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased() else { return self }
        return localizedCapitalized
    }
}
