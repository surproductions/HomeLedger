import Foundation

struct MonthTotal: Identifiable, Equatable {
    let month: Int // 1...12
    let cents: Int
    var id: Int { month }
    var label: String { Calendar.current.shortMonthSymbols[month - 1] }
}

struct CategoryTotal: Identifiable, Equatable {
    let category: ExpenseCategory
    let cents: Int
    var id: String { category.rawValue }
}

struct YearTotal: Identifiable, Equatable {
    let year: Int
    let cents: Int
    var id: Int { year }
}

/// Pure expense aggregation. All sums use integer cents, so totals are exact.
struct ExpenseCalculator {
    var calendar: Calendar = .current

    struct Filter: Equatable {
        var range: ClosedRange<Date>?
        var category: ExpenseCategory?
        var homeID: UUID?
        var assetID: UUID?
    }

    func filter(_ expenses: [Expense], _ filter: Filter) -> [Expense] {
        expenses.filter { e in
            if let range = filter.range, !range.contains(e.date) { return false }
            if let category = filter.category, e.category != category { return false }
            if let homeID = filter.homeID, e.home?.id != homeID { return false }
            if let assetID = filter.assetID, e.asset?.id != assetID { return false }
            return true
        }
    }

    func total(_ expenses: [Expense]) -> Int { expenses.map(\.amountCents).reduce(0, +) }

    func monthly(_ expenses: [Expense], year: Int) -> [MonthTotal] {
        var buckets = Array(repeating: 0, count: 12)
        for e in expenses {
            let comps = calendar.dateComponents([.year, .month], from: e.date)
            guard comps.year == year, let m = comps.month else { continue }
            buckets[m - 1] += e.amountCents
        }
        return buckets.enumerated().map { MonthTotal(month: $0.offset + 1, cents: $0.element) }
    }

    func yearly(_ expenses: [Expense]) -> [YearTotal] {
        var map: [Int: Int] = [:]
        for e in expenses { map[calendar.component(.year, from: e.date), default: 0] += e.amountCents }
        return map.map { YearTotal(year: $0.key, cents: $0.value) }.sorted { $0.year < $1.year }
    }

    func byCategory(_ expenses: [Expense]) -> [CategoryTotal] {
        var map: [ExpenseCategory: Int] = [:]
        for e in expenses { map[e.category, default: 0] += e.amountCents }
        return map.map { CategoryTotal(category: $0.key, cents: $0.value) }
            .filter { $0.cents != 0 }
            .sorted { $0.cents == $1.cents ? $0.category.rawValue < $1.category.rawValue : $0.cents > $1.cents }
    }

    func monthRange(containing date: Date) -> ClosedRange<Date>? {
        guard let i = calendar.dateInterval(of: .month, for: date) else { return nil }
        return i.start...i.end.addingTimeInterval(-0.001)
    }

    func yearRange(_ year: Int) -> ClosedRange<Date>? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        return start...end.addingTimeInterval(-0.001)
    }

    /// Average monthly spend over months that have elapsed in the given year (never extrapolates into the future).
    func averageMonthly(_ expenses: [Expense], year: Int, now: Date = .now) -> Int {
        let currentYear = calendar.component(.year, from: now)
        let months: Int
        if year < currentYear { months = 12 } else if year == currentYear { months = calendar.component(.month, from: now) } else { return 0 }
        let total = monthly(expenses, year: year).map(\.cents).reduce(0, +)
        return months > 0 ? Int((Double(total) / Double(months)).rounded()) : 0
    }
}
