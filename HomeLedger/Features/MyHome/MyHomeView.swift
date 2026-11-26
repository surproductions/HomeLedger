import SwiftData
import SwiftUI

struct MyHomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query private var allAssets: [Asset]
    @Query private var categories: [CustomCategory]

    @State private var mode: Mode = .rooms
    @State private var searchText = ""
    @State private var roomEditor: RoomEditorTarget?

    enum Mode: String, CaseIterable, Identifiable { case rooms = "Rooms", categories = "Categories"; var id: String { rawValue } }

    private var home: Home? { app.currentHome(in: homes) }
    private var assets: [Asset] { HomeScope(home: home).assets(allAssets) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let home {
                    shortcuts
                    if !searchText.isEmpty {
                        searchResults
                    } else {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("myhome.mode")
                        if mode == .rooms { roomsGrid(home) } else { categoryList }
                    }
                } else {
                    ListCard { EmptyStateView(symbol: "house", title: "No home yet", message: "Create a home to organize rooms and items.", actionTitle: "Create home") { app.present(.newHome) } }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle(home?.name ?? "My Home")
        .searchable(text: $searchText, prompt: "Search items in this home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { addItem() } label: { Label("Add item", systemImage: "plus") }
                    Button { roomEditor = .new } label: { Label("Add room", systemImage: "square.split.bottomrightquarter") }
                    Divider()
                    Button { app.navigate(.homes, in: .myHome) } label: { Label("Manage homes & rooms", systemImage: "house.and.flag") }
                    Button { app.present(.report) } label: { Label("Inventory report", systemImage: "doc.richtext") }
                    Button { app.navigate(.assets(AssetListFilter(title: "Archived", showArchived: true)), in: .myHome) } label: { Label("Archived items", systemImage: "archivebox") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("My Home options")
                .accessibilityIdentifier("myhome.menu")
            }
        }
        .sheet(item: $roomEditor) { target in
            if let home { RoomEditorView(target: target, home: home) }
        }
    }

    private func addItem() {
        if DataService(context: context).canAddAsset(entitlements: app.entitlement) { app.present(.newAsset(roomID: nil)) } else { app.present(.paywall(.unlimitedItems)) }
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            shortcut("All items", "\(assets.count)", "shippingbox", Theme.tintBlue, .assets(AssetListFilter(title: "All items")), id: "shortcut.items")
            shortcut("Warranties", "\(assets.filter { $0.warrantyExpiration != nil }.count)", "checkmark.shield", Theme.tintGreen, .warranties(nil), id: "shortcut.warranties")
            shortcut("Repairs", nil, "wrench.adjustable", Theme.tintOrange, .repairs, id: "shortcut.repairs")
            shortcut("Expenses", nil, "chart.bar", Theme.tintPurple, .expenses, id: "shortcut.expenses")
        }
    }

    private func shortcut(_ title: String, _ value: String?, _ symbol: String, _ tint: Color, _ route: AppRoute, id: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                IconBadge(systemName: symbol, tint: tint, size: 34)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let value { Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSecondary) }
            }
            .card(padding: 10, radius: Theme.radiusS + 2)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(id)
    }

    private func roomsGrid(_ home: Home) -> some View {
        let unassigned = assets.filter { $0.room == nil }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(home.sortedRooms) { room in
                NavigationLink(value: AppRoute.room(room)) { RoomCard(name: room.name, symbol: room.symbolName, assets: room.activeAssets) }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button { roomEditor = .edit(room) } label: { Label("Edit room", systemImage: "pencil") }
                    }
            }
            if !unassigned.isEmpty {
                NavigationLink(value: AppRoute.assets(AssetListFilter(title: "Unassigned", unassignedOnly: true))) {
                    RoomCard(name: "Unassigned", symbol: "tray", assets: unassigned)
                }
                .buttonStyle(PressableStyle())
            }
            Button { roomEditor = .new } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus").font(.title3.weight(.semibold))
                    Text("Add room").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: .infinity, minHeight: 128)
                .background(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).strokeBorder(Theme.brand.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .accessibilityIdentifier("myhome.addRoom")
        }
    }

    private var categoryList: some View {
        let keys = Set(assets.map(\.category))
        let infos = keys.map(CategoryInfo.resolve).sorted { $0.name < $1.name }
        return Group {
            if infos.isEmpty {
                ListCard { EmptyStateView(symbol: "square.grid.2x2", title: "No items yet", message: "Categories appear as you add items.", actionTitle: "Add item") { addItem() } }
            } else {
                ListCard {
                    ForEach(Array(infos.enumerated()), id: \.element.id) { index, info in
                        if index > 0 { RowDivider() }
                        let items = assets.filter { $0.category == info.key }
                        NavigationLink(value: AppRoute.assets(AssetListFilter(title: info.name, categoryKey: info.key))) {
                            RecordRow(symbol: info.symbol, tint: Theme.tintBlue, title: info.name, subtitle: "\(items.count) item\(items.count == 1 ? "" : "s")",
                                      trailing: Money.format(cents: items.compactMap(\.purchasePriceCents).reduce(0, +), showCents: false))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        let terms = SearchService.tokens(searchText)
        let matches = assets.filter { a in
            let hay = SearchService.normalize([a.name, a.brand, a.modelNumber, a.serialNumber, a.room?.name ?? "", a.categoryInfo.name, a.notes].joined(separator: " "))
            return terms.allSatisfy { hay.contains($0) }
        }
        return Group {
            if matches.isEmpty {
                ListCard { EmptyStateView(symbol: "magnifyingglass", title: "No matching items", message: "Try a brand, model, serial number or room.") }
            } else {
                ListCard {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, asset in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: AppRoute.asset(asset)) { AssetRow(asset: asset) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct RoomCard: View {
    let name: String
    let symbol: String
    let assets: [Asset]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(systemName: symbol, tint: Theme.brand, size: 38)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
            }
            Spacer(minLength: 0)
            Text(name).font(.headline).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
            Text("\(assets.count) item\(assets.count == 1 ? "" : "s") · \(Money.format(cents: assets.compactMap(\.purchasePriceCents).reduce(0, +), showCents: false))")
                .font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens room")
    }
}

// MARK: - Room detail

struct RoomDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var room: Room
    @State private var editing: RoomEditorTarget?
    @State private var confirmDelete = false

    var body: some View {
        let items = room.activeAssets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let tasks = (room.tasks ?? []).filter { !$0.isArchived }.sorted { $0.dueDate < $1.dueDate }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    IconBadge(systemName: room.symbolName, tint: .white, size: 52, filled: false)
                        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")").font(.headline).foregroundStyle(Theme.ink)
                        Text("Recorded value \(Money.format(cents: items.compactMap(\.purchasePriceCents).reduce(0, +), showCents: false))")
                            .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                }
                .card()

                SectionHeader(title: "Items", actionTitle: "Add") { addItem() }
                if items.isEmpty {
                    ListCard { EmptyStateView(symbol: "shippingbox", title: "Nothing here yet", message: "Add items in \(room.name) to build your inventory.", actionTitle: "Add item") { addItem() } }
                } else {
                    ListCard {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 { RowDivider() }
                            NavigationLink(value: AppRoute.asset(asset)) { AssetRow(asset: asset, showRoom: false) }.buttonStyle(.plain)
                        }
                    }
                }
                if !tasks.isEmpty {
                    SectionHeader(title: "Maintenance")
                    ListCard {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { RowDivider() }
                            TaskRow(task: task, showComplete: true)
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle(room.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { addItem() } label: { Label("Add item here", systemImage: "plus") }
                    Button { editing = .edit(room) } label: { Label("Edit room", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete room", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Room options")
            }
        }
        .sheet(item: $editing) { target in
            if let home = room.home { RoomEditorView(target: target, home: home) }
        }
        .confirmationDialog("Delete \(room.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete room", role: .destructive) {
                DataService(context: context).deleteRoom(room)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("The \(items.count) item\(items.count == 1 ? "" : "s") in this room will be kept and marked Unassigned. No documents are deleted.")
        }
    }

    private func addItem() {
        if DataService(context: context).canAddAsset(entitlements: app.entitlement) { app.present(.newAsset(roomID: room.id)) } else { app.present(.paywall(.unlimitedItems)) }
    }
}

// MARK: - Room editor

enum RoomEditorTarget: Identifiable {
    case new
    case edit(Room)
    var id: String {
        switch self {
        case .new: "new"
        case .edit(let r): r.id.uuidString
        }
    }
}

struct RoomEditorView: View {
    let target: RoomEditorTarget
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "square.split.bottomrightquarter"

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Kitchen", text: $name)
                        .accessibilityIdentifier("room.name")
                }
                Section("Suggestions") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(RoomSuggestions.all, id: \.name) { s in
                                FilterChip(title: s.name, symbol: s.symbol, isSelected: name == s.name) { name = s.name; symbol = s.symbol }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(RoomSuggestions.symbolChoices, id: \.self) { s in
                            Button { symbol = s } label: {
                                IconBadge(systemName: s, tint: symbol == s ? .white : Theme.brand, size: 44, filled: false)
                                    .background(symbol == s ? Theme.brand : .clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(symbol == s ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(isNew ? "New room" : "Edit room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("room.save")
                }
            }
            .onAppear {
                if case .edit(let room) = target { name = room.name; symbol = room.symbolName }
            }
        }
    }

    private var isNew: Bool { if case .new = target { return true }; return false }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .new: DataService(context: context).addRoom(named: trimmed, symbol: symbol, to: home)
        case .edit(let room): room.name = trimmed; room.symbolName = symbol
        }
        try? context.save()
        dismiss()
    }
}
