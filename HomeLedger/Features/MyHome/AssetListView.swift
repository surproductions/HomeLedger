import SwiftData
import SwiftUI

enum AssetSort: String, CaseIterable, Identifiable {
    case name = "Name", recent = "Recently added", purchaseDate = "Purchase date", value = "Value", warranty = "Warranty end"
    var id: String { rawValue }
}

enum AssetGrouping: String, CaseIterable, Identifiable {
    case none = "None", room = "Room", category = "Category"
    var id: String { rawValue }
}

struct AssetListView: View {
    let filter: AssetListFilter
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query private var allAssets: [Asset]

    @State private var searchText = ""
    @State private var sort: AssetSort = .name
    @State private var grouping: AssetGrouping = .none
    @State private var showArchived = false
    @State private var pendingDelete: Asset?
    @State private var movingAsset: Asset?

    init(filter: AssetListFilter) {
        self.filter = filter
        _showArchived = State(initialValue: filter.showArchived)
        _sort = State(initialValue: filter.recentOnly ? .recent : .name)
    }

    private var filtered: [Asset] {
        let scope = HomeScope(home: app.currentHome(in: homes))
        var items = scope.assets(allAssets, includeArchived: true).filter { showArchived ? $0.isArchived : !$0.isArchived }
        if let roomID = filter.roomID { items = items.filter { $0.room?.id == roomID } }
        if let key = filter.categoryKey { items = items.filter { $0.category == key } }
        if filter.unassignedOnly { items = items.filter { $0.room == nil } }
        let terms = SearchService.tokens(searchText)
        if !terms.isEmpty {
            items = items.filter { a in
                let hay = SearchService.normalize([a.name, a.brand, a.modelNumber, a.serialNumber, a.barcode, a.retailer, a.room?.name ?? "", a.categoryInfo.name, a.notes].joined(separator: " "))
                return terms.allSatisfy { hay.contains($0) }
            }
        }
        switch sort {
        case .name: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent: items.sort { $0.createdAt > $1.createdAt }
        case .purchaseDate: items.sort { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
        case .value: items.sort { ($0.replacementValueCents ?? $0.purchasePriceCents ?? 0) > ($1.replacementValueCents ?? $1.purchasePriceCents ?? 0) }
        case .warranty: items.sort { ($0.warrantyExpiration ?? .distantFuture) < ($1.warrantyExpiration ?? .distantFuture) }
        }
        if filter.recentOnly { items = Array(items.prefix(30)) }
        return items
    }

    struct AssetGroup: Identifiable { let title: String; let items: [Asset]; var id: String { title } }

    private var groups: [AssetGroup] {
        let items = filtered
        switch grouping {
        case .none: return [AssetGroup(title: "", items: items)]
        case .room:
            return Dictionary(grouping: items) { $0.room?.name ?? "Unassigned" }
                .map { AssetGroup(title: $0.key, items: $0.value) }.sorted { $0.title < $1.title }
        case .category:
            return Dictionary(grouping: items) { $0.categoryInfo.name }
                .map { AssetGroup(title: $0.key, items: $0.value) }.sorted { $0.title < $1.title }
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyStateView(symbol: showArchived ? "archivebox" : "shippingbox",
                               title: searchText.isEmpty ? (showArchived ? "No archived items" : "No items yet") : "No matches",
                               message: searchText.isEmpty ? "Items you add will appear here." : "Try a different name, brand or serial number.",
                               actionTitle: searchText.isEmpty && !showArchived ? "Add item" : nil) { addItem() }
                    .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { asset in
                        NavigationLink(value: AppRoute.asset(asset)) { AssetRow(asset: asset, showRoom: grouping != .room) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { pendingDelete = asset } label: { Label("Delete", systemImage: "trash") }
                                Button { toggleArchive(asset) } label: { Label(asset.isArchived ? "Restore" : "Archive", systemImage: "archivebox") }
                                    .tint(Theme.inkSecondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button { movingAsset = asset } label: { Label("Move", systemImage: "arrow.right.square") }.tint(Theme.brand)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle(filter.title)
        .searchable(text: $searchText, prompt: "Name, brand, serial…")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sort) { ForEach(AssetSort.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Group by", selection: $grouping) { ForEach(AssetGrouping.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Show archived", isOn: $showArchived)
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .accessibilityLabel("Sort and filter")
                Button { addItem() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add item")
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "item")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete item", role: .destructive) {
                if let asset = pendingDelete {
                    DataService(context: context).deleteAsset(asset)
                    try? context.save()
                    app.syncReminders(context)
                }
                pendingDelete = nil
            }
        } message: {
            Text("Its photos will be deleted. Linked documents, repair history and expenses are kept. Consider archiving instead if you sold or gave it away.")
        }
        .sheet(item: $movingAsset) { asset in MoveAssetSheet(asset: asset) }
    }

    private func addItem() {
        if DataService(context: context).canAddAsset(entitlements: app.entitlement) { app.present(.newAsset(roomID: filter.roomID)) } else { app.present(.paywall(.unlimitedItems)) }
    }

    private func toggleArchive(_ asset: Asset) {
        if asset.isArchived && !DataService(context: context).canAddAsset(entitlements: app.entitlement) {
            app.present(.paywall(.unlimitedItems))
            return
        }
        DataService(context: context).setArchived(asset, !asset.isArchived)
        try? context.save()
        app.syncReminders(context)
        app.showToast(asset.isArchived ? "Archived" : "Restored")
    }
}

struct MoveAssetSheet: View {
    @Bindable var asset: Asset
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Home.sortIndex) private var homes: [Home]

    var body: some View {
        NavigationStack {
            List {
                ForEach(homes) { home in
                    Section(home.name) {
                        ForEach(home.sortedRooms) { room in
                            Button { move(to: room, home: home) } label: {
                                HStack {
                                    Label(room.name, systemImage: room.symbolName).foregroundStyle(Theme.ink)
                                    Spacer()
                                    if asset.room?.id == room.id { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
                                }
                            }
                        }
                        Button { move(to: nil, home: home) } label: {
                            HStack {
                                Label("Unassigned", systemImage: "tray").foregroundStyle(Theme.ink)
                                Spacer()
                                if asset.room == nil && asset.home?.id == home.id { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move \(asset.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(to room: Room?, home: Home) {
        DataService(context: context).move(asset, to: room)
        asset.home = home
        try? context.save()
        dismiss()
    }
}

// MARK: - Homes management

struct HomesManagerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @State private var pendingDelete: Home?
    @State private var roomEditor: (RoomEditorTarget, Home)?

    var body: some View {
        List {
            ForEach(homes) { home in
                Section {
                    Button { app.present(.editHome(home)) } label: {
                        RecordRow(symbol: home.homeType.symbol, tint: Theme.brand, title: home.name,
                                  subtitle: "\(home.homeType.label) · \(home.activeAssets.count) items",
                                  pill: app.currentHome(in: homes)?.id == home.id ? ("Current", .brand) : nil)
                    }
                    .buttonStyle(.plain)
                    ForEach(home.sortedRooms) { room in
                        Label(room.name, systemImage: room.symbolName)
                            .swipeActions {
                                Button(role: .destructive) {
                                    DataService(context: context).deleteRoom(room)
                                    try? context.save()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    .onMove { from, to in
                        var rooms = home.sortedRooms
                        rooms.move(fromOffsets: from, toOffset: to)
                        DataService(context: context).reorderRooms(rooms)
                        try? context.save()
                    }
                    Button { roomEditor = (.new, home) } label: { Label("Add room", systemImage: "plus") }
                    if app.currentHome(in: homes)?.id != home.id {
                        Button("Switch to this home") { app.selectedHomeID = home.id }
                    }
                    Button("Delete home…", role: .destructive) { pendingDelete = home }
                } header: {
                    Text(home.name)
                } footer: {
                    Text("Swipe a room to delete it. Its items become Unassigned.")
                }
            }
            Section {
                Button {
                    if app.entitlement.canAddHome(currentCount: homes.count) { app.present(.newHome) } else { app.present(.paywall(.multipleHomes)) }
                } label: {
                    Label(app.entitlement.canAddHome(currentCount: homes.count) ? "Add home" : "Add home (Premium)", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Homes & rooms")
        .toolbar { EditButton() }
        .sheet(isPresented: Binding(get: { roomEditor != nil }, set: { if !$0 { roomEditor = nil } })) {
            if let roomEditor { RoomEditorView(target: roomEditor.0, home: roomEditor.1) }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "home")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete home and its items", role: .destructive) {
                if let home = pendingDelete {
                    DataService(context: context).deleteHome(home)
                    try? context.save()
                    if app.selectedHomeID == home.id { app.selectedHomeID = nil }
                    app.syncReminders(context)
                }
                pendingDelete = nil
            }
        } message: {
            if let home = pendingDelete {
                let s = DataService(context: context).deletionSummary(for: home)
                Text("This deletes \(s.assets) items (with their photos), the rooms and \(s.tasks) maintenance tasks. \(s.documents) documents, \(s.services) repair records and \(s.expenses) expenses are kept and remain in Documents and Expenses. Make a backup first if you're unsure.")
            }
        }
    }
}

struct HomeEditorView: View {
    let home: Home?
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: HomeType = .house
    @State private var address = ""
    @State private var notes = ""
    @State private var selectedRooms: Set<String> = RoomSuggestions.defaults

    var body: some View {
        NavigationStack {
            Form {
                Section("Home") {
                    TextField("Name (e.g. Our House)", text: $name).accessibilityIdentifier("home.name")
                    Picker("Type", selection: $type) { ForEach(HomeType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                    TextField("Address or nickname (optional)", text: $address)
                }
                if home == nil {
                    Section {
                        ForEach(RoomSuggestions.all, id: \.name) { s in
                            Toggle(isOn: Binding(get: { selectedRooms.contains(s.name) }, set: { if $0 { selectedRooms.insert(s.name) } else { selectedRooms.remove(s.name) } })) {
                                Label(s.name, systemImage: s.symbol)
                            }
                        }
                    } header: { Text("Rooms") } footer: { Text("Optional — you can add, rename or remove rooms anytime.") }
                }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle(home == nil ? "New home" : "Edit home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("home.save")
                }
            }
            .onAppear {
                if let home { name = home.name; type = home.homeType; address = home.addressLine; notes = home.notes }
            }
        }
    }

    private func save() {
        if let home {
            home.name = name.trimmingCharacters(in: .whitespaces)
            home.homeType = type
            home.addressLine = address
            home.notes = notes
            home.updatedAt = .now
        } else {
            let rooms = RoomSuggestions.all.filter { selectedRooms.contains($0.name) }.map { ($0.name, $0.symbol) }
            let created = DataService(context: context).createHome(name: name, type: type, roomNames: rooms)
            created.addressLine = address
            created.notes = notes
            app.selectedHomeID = created.id
        }
        try? context.save()
        dismiss()
    }
}
