import Foundation

/// A navigable reference to any record.
enum RecordRef: Hashable, Identifiable {
    case asset(Asset)
    case room(Room)
    case document(DocumentRecord)
    case task(MaintenanceTask)
    case service(ServiceRecord)
    case expense(Expense)

    var id: String {
        switch self {
        case .asset(let a): "asset-\(a.id)"
        case .room(let r): "room-\(r.id)"
        case .document(let d): "document-\(d.id)"
        case .task(let t): "task-\(t.id)"
        case .service(let s): "service-\(s.id)"
        case .expense(let e): "expense-\(e.id)"
        }
    }

    var kindLabel: String {
        switch self {
        case .asset: "Item"
        case .room: "Room"
        case .document: "Document"
        case .task: "Maintenance"
        case .service: "Repair & service"
        case .expense: "Expense"
        }
    }

    var title: String {
        switch self {
        case .asset(let a): a.name
        case .room(let r): r.name
        case .document(let d): d.title
        case .task(let t): t.title
        case .service(let s): s.title
        case .expense(let e): e.title
        }
    }

    var subtitle: String {
        switch self {
        case .asset(let a):
            return joinedParts([a.room?.name, a.displaySubtitle], separator: " · ")
        case .room(let r):
            return "\(r.activeAssets.count) items"
        case .document(let d):
            return joinedParts([d.kind.label, d.asset?.name], separator: " · ")
        case .task(let t):
            return t.isArchived ? "Completed" : TaskDueState.evaluate(due: t.dueDate).label
        case .service(let s):
            return joinedParts([s.date.formatted(date: .abbreviated, time: .omitted), s.asset?.name], separator: " · ")
        case .expense(let e):
            return "\(Money.format(cents: e.amountCents)) · \(e.date.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    var symbol: String {
        switch self {
        case .asset(let a): a.categoryInfo.symbol
        case .room(let r): r.symbolName
        case .document(let d): d.kind.symbol
        case .task: "wrench.and.screwdriver"
        case .service(let s): s.kind.symbol
        case .expense(let e): e.category.symbol
        }
    }
}

struct SearchCorpus {
    var assets: [Asset] = []
    var rooms: [Room] = []
    var documents: [DocumentRecord] = []
    var tasks: [MaintenanceTask] = []
    var services: [ServiceRecord] = []
    var expenses: [Expense] = []
}

struct SearchResultGroup: Identifiable {
    let title: String
    let results: [RecordRef]
    var id: String { title }
}

/// Fast, fully local search across every record type. All query tokens must match
/// (AND semantics); title matches rank above matches in notes or recognized text.
struct SearchService {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    static func tokens(_ query: String) -> [String] {
        normalize(query).split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "/" }.map(String.init).filter { !$0.isEmpty }
    }

    func search(_ query: String, in corpus: SearchCorpus, limitPerGroup: Int = 25) -> [SearchResultGroup] {
        let terms = Self.tokens(query)
        guard !terms.isEmpty else { return [] }

        func rank<T>(_ items: [T], title: (T) -> String, body: (T) -> String) -> [T] {
            items.compactMap { item -> (T, Int)? in
                let t = Self.normalize(title(item))
                let b = Self.normalize(body(item))
                var score = 0
                for term in terms {
                    if t.contains(term) { score += t.hasPrefix(term) ? 4 : 3 }
                    else if b.contains(term) { score += 1 }
                    else { return nil }
                }
                return (item, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limitPerGroup)
            .map { $0.0 }
        }

        var groups: [SearchResultGroup] = []
        let assets = rank(corpus.assets, title: { $0.name }, body: {
            [$0.brand, $0.modelNumber, $0.serialNumber, $0.barcode, $0.retailer, $0.categoryInfo.name, $0.room?.name ?? "", $0.notes, $0.warrantyProvider].joined(separator: " ")
        })
        if !assets.isEmpty { groups.append(SearchResultGroup(title: "Items", results: assets.map(RecordRef.asset))) }

        let rooms = rank(corpus.rooms, title: { $0.name }, body: { $0.home?.name ?? "" })
        if !rooms.isEmpty { groups.append(SearchResultGroup(title: "Rooms", results: rooms.map(RecordRef.room))) }

        let docs = rank(corpus.documents, title: { $0.title }, body: {
            [$0.kind.label, $0.vendor, $0.notes, $0.originalFileName, $0.asset?.name ?? "", $0.recognizedText].joined(separator: " ")
        })
        if !docs.isEmpty { groups.append(SearchResultGroup(title: "Documents", results: docs.map(RecordRef.document))) }

        let warranties = corpus.assets.filter { $0.hasWarrantyInfo }
        let warrantyMatches = terms.contains(where: { "warranty".hasPrefix($0) || $0.hasPrefix("warrant") })
            ? warranties : rank(warranties, title: { $0.warrantyProvider }, body: { $0.warrantyNotes })
        if !warrantyMatches.isEmpty { groups.append(SearchResultGroup(title: "Warranties", results: warrantyMatches.prefix(limitPerGroup).map(RecordRef.asset))) }

        let tasks = rank(corpus.tasks, title: { $0.title }, body: { [$0.details, $0.asset?.name ?? "", $0.room?.name ?? ""].joined(separator: " ") })
        if !tasks.isEmpty { groups.append(SearchResultGroup(title: "Maintenance", results: tasks.map(RecordRef.task))) }

        let services = rank(corpus.services, title: { $0.title }, body: { [$0.details, $0.vendor, $0.asset?.name ?? "", $0.kind.label].joined(separator: " ") })
        if !services.isEmpty { groups.append(SearchResultGroup(title: "Repairs & service", results: services.map(RecordRef.service))) }

        let expenses = rank(corpus.expenses, title: { $0.title }, body: { [$0.vendor, $0.notes, $0.category.label, $0.asset?.name ?? ""].joined(separator: " ") })
        if !expenses.isEmpty { groups.append(SearchResultGroup(title: "Expenses", results: expenses.map(RecordRef.expense))) }

        return groups
    }
}
