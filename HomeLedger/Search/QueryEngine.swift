import Foundation

struct AssistantAnswer: Identifiable {
    let id = UUID()
    let question: String
    let text: String
    let records: [RecordRef]
    /// False when the answer is "I couldn't find that" — the UI styles these differently.
    let found: Bool
}

/// A local, rule-based question answering engine. It recognises a set of common question
/// patterns and answers strictly from stored records, always returning the supporting records.
/// This is not a language model and the UI says so.
struct QueryEngine {
    var now: Date = .now
    var calendar: Calendar = .current
    var currencyCode: String = Preferences.currencyCode

    static let examples = [
        "When did I buy the refrigerator?",
        "Show appliances with warranties expiring soon",
        "What maintenance is due this month?",
        "How much have I spent repairing the washing machine?",
        "Find the manual for my dishwasher",
        "What's in the kitchen?"
    ]

    private static let stopWords: Set<String> = ["the", "my", "a", "an", "i", "did", "do", "does", "when", "what", "whats", "what's", "is", "was", "for", "of", "on", "in", "to", "have", "has", "how", "much", "many", "show", "me", "find", "where", "buy", "bought", "purchase", "purchased", "get", "got", "spent", "spend", "repairing", "repair", "repairs", "fixing", "manual", "receipt", "warranty", "warranties", "invoice", "with", "that", "are", "under", "this", "month", "year", "week", "all", "and", "or", "it", "our", "we", "s", "doc", "document", "documents", "expiring", "soon", "due", "maintenance", "cost", "costs", "paid", "pay", "on", "total", "items", "item", "inside", "room", "whats", "there"]

    private static let synonyms: [String: [String]] = [
        "fridge": ["refrigerator"], "refrigerator": ["fridge"],
        "washer": ["washing machine", "washer"], "washing": ["washer"],
        "dryer": ["dryer", "tumble"], "tv": ["television", "tv"], "television": ["tv"],
        "ac": ["air conditioner", "a/c"], "aircon": ["air conditioner"],
        "furnace": ["furnace", "heater"], "heater": ["furnace", "heater"],
        "dishwasher": ["dish washer"], "laptop": ["macbook", "notebook"], "couch": ["sofa"], "sofa": ["couch"]
    ]

    func answer(_ question: String, corpus: SearchCorpus) -> AssistantAnswer {
        let q = SearchService.normalize(question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return AssistantAnswer(question: question, text: "Ask a question about your home records.", records: [], found: false)
        }
        let activeAssets = corpus.assets.filter { !$0.isArchived }

        // 1. Purchase date
        if (q.contains("when") || q.contains("date")) && (q.contains("buy") || q.contains("bought") || q.contains("purchase")) {
            guard let asset = bestAsset(for: q, in: activeAssets) else { return notFound(question, "I couldn't find an item matching that in your records.") }
            if let date = asset.purchaseDate {
                var text = "You bought \(asset.name) on \(date.formatted(date: .long, time: .omitted))"
                if !asset.retailer.isEmpty { text += " from \(asset.retailer)" }
                if let price = asset.purchasePriceCents { text += " for \(Money.format(cents: price, currencyCode: currencyCode))" }
                let receipts = asset.sortedDocuments.filter { $0.kind == .receipt || $0.kind == .invoice }
                return AssistantAnswer(question: question, text: text + ".", records: [.asset(asset)] + receipts.map(RecordRef.document), found: true)
            }
            return AssistantAnswer(question: question, text: "\(asset.name) doesn't have a purchase date recorded yet.", records: [.asset(asset)], found: false)
        }

        // 2. Spending
        if q.contains("how much") || q.contains("spent") || q.contains("spend") || (q.contains("cost") && !q.contains("estimated")) {
            let repairOnly = q.contains("repair") || q.contains("fix")
            let periodRange = period(in: q)
            var expenses = corpus.expenses
            var subject = "in total"
            if let asset = bestAsset(for: q, in: corpus.assets) {
                expenses = expenses.filter { $0.asset?.id == asset.id }
                subject = "on \(asset.name)"
                if repairOnly { expenses = expenses.filter { $0.category == .repair } }
                if let periodRange { expenses = expenses.filter { periodRange.range.contains($0.date) } }
                let total = expenses.map(\.amountCents).reduce(0, +)
                let what = repairOnly ? "repairing \(asset.name)" : "on \(asset.name)"
                if expenses.isEmpty {
                    return AssistantAnswer(question: question, text: "There are no \(repairOnly ? "repair " : "")expenses recorded for \(asset.name)\(periodRange.map { " \($0.label)" } ?? "").", records: [.asset(asset)], found: false)
                }
                return AssistantAnswer(question: question,
                                       text: "You've recorded \(Money.format(cents: total, currencyCode: currencyCode)) spent \(what)\(periodRange.map { " \($0.label)" } ?? "") across \(expenses.count) expense\(expenses.count == 1 ? "" : "s").",
                                       records: [.asset(asset)] + expenses.sorted { $0.date > $1.date }.map(RecordRef.expense), found: true)
            }
            if repairOnly { expenses = expenses.filter { $0.category == .repair }; subject = "on repairs" }
            if let periodRange { expenses = expenses.filter { periodRange.range.contains($0.date) } }
            guard !expenses.isEmpty else { return notFound(question, "No matching expenses are recorded\(periodRange.map { " \($0.label)" } ?? "").") }
            let total = expenses.map(\.amountCents).reduce(0, +)
            return AssistantAnswer(question: question,
                                   text: "You've recorded \(Money.format(cents: total, currencyCode: currencyCode)) \(subject)\(periodRange.map { " \($0.label)" } ?? "") across \(expenses.count) expense\(expenses.count == 1 ? "" : "s").",
                                   records: expenses.sorted { $0.date > $1.date }.prefix(20).map(RecordRef.expense), found: true)
        }

        // 3. Documents
        if let kind = documentKind(in: q), q.contains("find") || q.contains("where") || q.contains("show") || q.contains("open") || q.contains(kind.rawValue) {
            let asset = bestAsset(for: q, in: corpus.assets)
            var docs = corpus.documents.filter { $0.kind == kind }
            if let asset { docs = docs.filter { $0.asset?.id == asset.id } }
            if docs.isEmpty {
                let what = asset.map { "for \($0.name)" } ?? "in your records"
                return AssistantAnswer(question: question, text: "I couldn't find a \(kind.label.lowercased()) \(what).", records: asset.map { [.asset($0)] } ?? [], found: false)
            }
            let text = docs.count == 1 ? "Here's the \(kind.label.lowercased())\(asset.map { " for \($0.name)" } ?? "")." : "Found \(docs.count) \(kind.pluralLabel.lowercased())\(asset.map { " for \($0.name)" } ?? "")."
            return AssistantAnswer(question: question, text: text, records: docs.map(RecordRef.document), found: true)
        }

        // 4. Warranties
        if q.contains("warrant") {
            let category = assetCategory(in: q)
            if let asset = bestAsset(for: q, in: activeAssets), category == nil || asset.category == category?.rawValue {
                let status = asset.warrantyStatus
                let text: String
                switch status {
                case .unknown: text = "There's no warranty end date recorded for \(asset.name)."
                case .expired: text = "The warranty for \(asset.name) ended on \(asset.warrantyExpiration!.formatted(date: .long, time: .omitted))."
                case .active, .expiringSoon:
                    let days = asset.warrantyDaysRemaining ?? 0
                    text = "\(asset.name) is covered until \(asset.warrantyExpiration!.formatted(date: .long, time: .omitted)) (\(days) days left)\(asset.warrantyIsEstimated ? ", based on an estimated date" : "")."
                }
                return AssistantAnswer(question: question, text: text, records: [.asset(asset)], found: status != .unknown)
            }
            var assets = activeAssets.filter { $0.warrantyExpiration != nil }
            if let category { assets = assets.filter { $0.category == category.rawValue } }
            let wantsExpired = q.contains("expired")
            let wantsSoon = q.contains("soon") || q.contains("expiring") || q.contains("ending") || q.contains("upcoming")
            if wantsExpired { assets = assets.filter { $0.warrantyStatus == .expired } }
            else if wantsSoon { assets = assets.filter { $0.warrantyStatus == .expiringSoon } }
            else { assets = assets.filter { $0.warrantyStatus != .expired } }
            assets.sort { ($0.warrantyExpiration ?? .distantFuture) < ($1.warrantyExpiration ?? .distantFuture) }
            let scope = category.map { " \($0.info.name.lowercased())" } ?? ""
            if assets.isEmpty {
                return notFound(question, wantsSoon ? "No\(scope) warranties are expiring in the next 60 days." : "No matching\(scope) warranties were found.")
            }
            let label = wantsExpired ? "expired" : (wantsSoon ? "expiring within 60 days" : "active")
            return AssistantAnswer(question: question, text: "\(assets.count)\(scope) warrant\(assets.count == 1 ? "y is" : "ies are") \(label).", records: assets.map(RecordRef.asset), found: true)
        }

        // 5. Maintenance due
        if q.contains("maintenance") || q.contains("due") || q.contains("task") || q.contains("overdue") || q.contains("to do") || q.contains("todo") {
            var tasks = corpus.tasks.filter { !$0.isArchived }
            var label = "coming up"
            if q.contains("overdue") {
                tasks = tasks.filter { TaskDueState.evaluate(due: $0.dueDate, now: now, calendar: calendar).isOverdue }
                label = "overdue"
            } else if let p = period(in: q) {
                tasks = tasks.filter { $0.dueDate < p.range.upperBound && ($0.dueDate >= p.range.lowerBound || TaskDueState.evaluate(due: $0.dueDate, now: now, calendar: calendar).isOverdue) }
                label = "due \(p.label)"
            } else {
                let horizon = calendar.date(byAdding: .day, value: 30, to: now) ?? now
                tasks = tasks.filter { $0.dueDate <= horizon }
                label = "due in the next 30 days"
            }
            tasks.sort { $0.dueDate < $1.dueDate }
            if tasks.isEmpty { return notFound(question, "Nothing is \(label).") }
            let overdueCount = tasks.filter { TaskDueState.evaluate(due: $0.dueDate, now: now, calendar: calendar).isOverdue }.count
            var text = "\(tasks.count) task\(tasks.count == 1 ? " is" : "s are") \(label)"
            if overdueCount > 0 && label != "overdue" { text += ", including \(overdueCount) overdue" }
            return AssistantAnswer(question: question, text: text + ".", records: tasks.map(RecordRef.task), found: true)
        }

        // 6. Room contents
        if let room = bestRoom(for: q, in: corpus.rooms), q.contains("in the") || q.contains("in my") || q.contains("room") || q.contains("what") {
            let items = room.activeAssets.sorted { $0.name < $1.name }
            if items.isEmpty { return AssistantAnswer(question: question, text: "\(room.name) has no items yet.", records: [.room(room)], found: false) }
            return AssistantAnswer(question: question, text: "\(room.name) has \(items.count) item\(items.count == 1 ? "" : "s").", records: [.room(room)] + items.map(RecordRef.asset), found: true)
        }

        // 7. Counts & value
        if q.contains("how many") {
            let category = assetCategory(in: q)
            let items = category.map { c in activeAssets.filter { $0.category == c.rawValue } } ?? activeAssets
            return AssistantAnswer(question: question, text: "You have \(items.count) \(category?.info.name.lowercased() ?? "items") recorded.", records: items.prefix(30).map(RecordRef.asset), found: !items.isEmpty)
        }
        if q.contains("worth") || q.contains("value") {
            let total = activeAssets.map(\.recordedValueCents).reduce(0, +)
            let missing = activeAssets.filter { $0.replacementValueCents == nil && $0.purchasePriceCents == nil }.count
            var text = "Your recorded items total \(Money.format(cents: total, currencyCode: currencyCode)), using replacement value where available and purchase price otherwise."
            if missing > 0 { text += " \(missing) item\(missing == 1 ? " has" : "s have") no value recorded." }
            return AssistantAnswer(question: question, text: text, records: activeAssets.sorted { $0.recordedValueCents > $1.recordedValueCents }.prefix(10).map(RecordRef.asset), found: !activeAssets.isEmpty)
        }

        // Fallback: keyword search
        let groups = SearchService().search(question, in: corpus, limitPerGroup: 8)
        let records = groups.flatMap(\.results)
        if records.isEmpty { return notFound(question, "I couldn't find anything about that in your records.") }
        return AssistantAnswer(question: question, text: "I didn't recognise that as a question I can answer directly, but these records match.", records: Array(records.prefix(20)), found: true)
    }

    // MARK: Helpers

    private func notFound(_ question: String, _ text: String) -> AssistantAnswer {
        AssistantAnswer(question: question, text: text, records: [], found: false)
    }

    func keywords(in q: String) -> [String] {
        SearchService.tokens(q).filter { !Self.stopWords.contains($0) && $0.count > 1 }
    }

    func bestAsset(for q: String, in assets: [Asset]) -> Asset? {
        let words = keywords(in: q)
        guard !words.isEmpty else { return nil }
        var expanded = Set(words)
        for w in words { for s in Self.synonyms[w] ?? [] { expanded.insert(s) } }
        let scored = assets.map { asset -> (Asset, Int) in
            let name = SearchService.normalize(asset.name)
            let other = SearchService.normalize([asset.brand, asset.modelNumber, asset.categoryInfo.name].joined(separator: " "))
            var score = 0
            for term in expanded {
                if name == term { score += 10 }
                else if name.contains(term) { score += term.count >= 4 ? 5 : 3 }
                else if term.count >= 4 && term.hasSuffix("s") && name.contains(String(term.dropLast())) { score += 4 }
                else if other.contains(term) { score += 2 }
            }
            return (asset, score)
        }.filter { $0.1 >= 3 }
        return scored.max { a, b in a.1 == b.1 ? a.0.createdAt > b.0.createdAt : a.1 < b.1 }?.0
    }

    private func bestRoom(for q: String, in rooms: [Room]) -> Room? {
        rooms.first { room in
            let name = SearchService.normalize(room.name)
            return !name.isEmpty && q.contains(name)
        }
    }

    private func documentKind(in q: String) -> DocumentKind? {
        if q.contains("manual") || q.contains("instructions") || q.contains("user guide") { return .manual }
        if q.contains("receipt") { return .receipt }
        if q.contains("invoice") { return .invoice }
        if q.contains("insurance") || q.contains("policy") { return .insurance }
        if q.contains("warranty") && (q.contains("document") || q.contains("card") || q.contains("certificate") || q.contains("paperwork")) { return .warranty }
        return nil
    }

    private func assetCategory(in q: String) -> AssetCategory? {
        let map: [(String, AssetCategory)] = [("appliance", .appliance), ("electronic", .electronics), ("furniture", .furniture),
                                              ("hvac", .hvac), ("heating", .hvac), ("cooling", .hvac), ("plumbing", .plumbing),
                                              ("tool", .tools), ("outdoor", .outdoor), ("garden", .outdoor), ("jewel", .jewelry),
                                              ("art", .art), ("vehicle", .vehicle), ("kitchenware", .kitchen)]
        return map.first { q.contains($0.0) }?.1
    }

    struct Period { let range: Range<Date>; let label: String }

    func period(in q: String) -> Period? {
        func interval(_ component: Calendar.Component, offset: Int = 0) -> Range<Date>? {
            guard let base = calendar.date(byAdding: component, value: offset, to: now),
                  let i = calendar.dateInterval(of: component, for: base) else { return nil }
            return i.start..<i.end
        }
        if q.contains("today") { return interval(.day).map { Period(range: $0, label: "today") } }
        if q.contains("this week") { return interval(.weekOfYear).map { Period(range: $0, label: "this week") } }
        if q.contains("next week") { return interval(.weekOfYear, offset: 1).map { Period(range: $0, label: "next week") } }
        if q.contains("this month") { return interval(.month).map { Period(range: $0, label: "this month") } }
        if q.contains("next month") { return interval(.month, offset: 1).map { Period(range: $0, label: "next month") } }
        if q.contains("last month") { return interval(.month, offset: -1).map { Period(range: $0, label: "last month") } }
        if q.contains("this year") { return interval(.year).map { Period(range: $0, label: "this year") } }
        if q.contains("last year") { return interval(.year, offset: -1).map { Period(range: $0, label: "last year") } }
        return nil
    }
}
