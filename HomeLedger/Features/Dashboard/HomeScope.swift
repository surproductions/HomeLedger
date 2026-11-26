import Foundation

/// Filters records to the selected home. Records not linked to any home (e.g. documents kept
/// after a home was deleted) are included everywhere so nothing becomes invisible.
struct HomeScope {
    let home: Home?

    func includes(_ recordHome: Home?) -> Bool {
        guard let home, let recordHome else { return true }
        return recordHome.id == home.id
    }

    func assets(_ all: [Asset], includeArchived: Bool = false) -> [Asset] {
        all.filter { includes($0.home) && (includeArchived || !$0.isArchived) }
    }
    func documents(_ all: [DocumentRecord]) -> [DocumentRecord] { all.filter { includes($0.home ?? $0.asset?.home) } }
    func tasks(_ all: [MaintenanceTask]) -> [MaintenanceTask] { all.filter { includes($0.home ?? $0.asset?.home) } }
    func services(_ all: [ServiceRecord]) -> [ServiceRecord] { all.filter { includes($0.home ?? $0.asset?.home) } }
    func expenses(_ all: [Expense]) -> [Expense] { all.filter { includes($0.home ?? $0.asset?.home) } }
}

struct ActivityItem: Identifiable {
    let id: String
    let date: Date
    let symbol: String
    let tint: ActivityTint
    let title: String
    let subtitle: String
    let ref: RecordRef

    enum ActivityTint { case blue, green, orange, purple }

    static func build(assets: [Asset], documents: [DocumentRecord], tasks: [MaintenanceTask], services: [ServiceRecord], limit: Int = 50) -> [ActivityItem] {
        var items: [ActivityItem] = []
        for a in assets {
            items.append(ActivityItem(id: "a-\(a.id)", date: a.createdAt, symbol: "shippingbox.fill", tint: .blue, title: "Added \(a.name)", subtitle: a.room?.name ?? a.categoryInfo.name, ref: .asset(a)))
        }
        for d in documents {
            items.append(ActivityItem(id: "d-\(d.id)", date: d.createdAt, symbol: "doc.fill", tint: .purple, title: "Saved \(d.title)", subtitle: d.kind.label, ref: .document(d)))
        }
        for t in tasks {
            for log in t.logs ?? [] where log.kind == .completed {
                items.append(ActivityItem(id: "l-\(log.id)", date: log.date, symbol: "checkmark.circle.fill", tint: .green, title: "Completed \(t.title)", subtitle: "Maintenance", ref: .task(t)))
            }
        }
        for s in services {
            items.append(ActivityItem(id: "s-\(s.id)", date: s.date, symbol: "wrench.adjustable.fill", tint: .orange, title: s.title, subtitle: [s.kind.label, s.asset?.name].compactMap { $0 }.joined(separator: " · "), ref: .service(s)))
        }
        return Array(items.filter { $0.date <= Date.now.addingTimeInterval(60) }.sorted { $0.date > $1.date }.prefix(limit))
    }
}
