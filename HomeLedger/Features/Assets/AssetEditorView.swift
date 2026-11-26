import PhotosUI
import SwiftData
import SwiftUI

/// Editable copy of an asset so Cancel never leaves half-applied changes.
struct AssetDraft {
    var name = ""
    var category = AssetCategory.other.rawValue
    var homeID: UUID?
    var roomID: UUID?
    var brand = ""
    var modelNumber = ""
    var serialNumber = ""
    var barcode = ""
    var purchaseDate: Date?
    var purchasePriceCents: Int?
    var retailer = ""
    var replacementValueCents: Int?
    var quantity = 1
    var condition: AssetCondition = .good
    var warrantyStart: Date?
    var warrantyExpiration: Date?
    var warrantyIsEstimated = false
    var warrantyProvider = ""
    var warrantyNotes = ""
    var warrantyRemindersEnabled = true
    var warrantyReminderOffsets: [Int] = Preferences.defaultWarrantyOffsets
    var notes = ""

    init() {}

    init(_ a: Asset) {
        name = a.name; category = a.category; homeID = a.home?.id; roomID = a.room?.id
        brand = a.brand; modelNumber = a.modelNumber; serialNumber = a.serialNumber; barcode = a.barcode
        purchaseDate = a.purchaseDate; purchasePriceCents = a.purchasePriceCents; retailer = a.retailer
        replacementValueCents = a.replacementValueCents; quantity = a.quantity; condition = a.condition
        warrantyStart = a.warrantyStart; warrantyExpiration = a.warrantyExpiration; warrantyIsEstimated = a.warrantyIsEstimated
        warrantyProvider = a.warrantyProvider; warrantyNotes = a.warrantyNotes
        warrantyRemindersEnabled = a.warrantyRemindersEnabled; warrantyReminderOffsets = a.warrantyReminderOffsets; notes = a.notes
    }

    func apply(to a: Asset, homes: [Home]) {
        a.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        a.category = category
        let home = homes.first { $0.id == homeID }
        a.home = home
        a.room = home?.rooms?.first { $0.id == roomID }
        a.brand = brand.trimmingCharacters(in: .whitespaces)
        a.modelNumber = modelNumber.trimmingCharacters(in: .whitespaces)
        a.serialNumber = serialNumber.trimmingCharacters(in: .whitespaces)
        a.barcode = barcode.trimmingCharacters(in: .whitespaces)
        a.purchaseDate = purchaseDate
        a.purchasePriceCents = purchasePriceCents
        a.retailer = retailer.trimmingCharacters(in: .whitespaces)
        a.replacementValueCents = replacementValueCents
        a.quantity = max(1, quantity)
        a.condition = condition
        a.warrantyStart = warrantyStart
        a.warrantyExpiration = warrantyExpiration
        a.warrantyIsEstimated = warrantyExpiration == nil ? false : warrantyIsEstimated
        a.warrantyProvider = warrantyProvider
        a.warrantyNotes = warrantyNotes
        a.warrantyRemindersEnabled = warrantyRemindersEnabled
        a.warrantyReminderOffsets = Array(Set(warrantyReminderOffsets)).sorted(by: >)
        a.notes = notes
        a.touch()
    }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct AssetEditorView: View {
    let asset: Asset?
    let initialRoomID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]

    @State private var draft = AssetDraft()
    @State private var newPhotoFiles: [String] = []
    @State private var removedPhotos: Set<UUID> = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var confirmDiscard = false

    private var isNew: Bool { asset == nil }
    private var selectedHome: Home? { homes.first { $0.id == draft.homeID } }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                Section("Basics") {
                    TextField("Name (required)", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("asset.name")
                    Picker("Category", selection: $draft.category) {
                        ForEach(AssetCategory.allCases) { Label($0.info.name, systemImage: $0.info.symbol).tag($0.rawValue) }
                        ForEach(customCategories) { c in Label(c.name, systemImage: c.symbolName).tag(CategoryInfo.customPrefix + c.name) }
                    }
                    Button("New category…") { showNewCategory = true }
                    if homes.count > 1 {
                        Picker("Home", selection: $draft.homeID) {
                            ForEach(homes) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    Picker("Room", selection: $draft.roomID) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(selectedHome?.sortedRooms ?? []) { Label($0.name, systemImage: $0.symbolName).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("asset.room")
                    Stepper("Quantity: \(draft.quantity)", value: $draft.quantity, in: 1...999)
                    Picker("Condition", selection: $draft.condition) { ForEach(AssetCondition.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    TextField("Brand", text: $draft.brand)
                    TextField("Model", text: $draft.modelNumber).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Serial number", text: $draft.serialNumber).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityIdentifier("asset.serial")
                    HStack {
                        TextField("Barcode / QR", text: $draft.barcode).autocorrectionDisabled()
                        if BarcodeScannerView.isAvailable {
                            Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                                .accessibilityLabel("Scan barcode")
                        }
                    }
                } header: { Text("Identification") } footer: {
                    if !BarcodeScannerView.isAvailable { Text("Barcode scanning needs a camera-equipped iPhone XS or later. You can type the code instead.") }
                }
                Section("Purchase") {
                    OptionalDatePicker(title: "Purchase date", date: $draft.purchaseDate)
                    MoneyField(title: "Price", cents: $draft.purchasePriceCents)
                    TextField("Retailer / vendor", text: $draft.retailer)
                    MoneyField(title: "Est. replacement value", cents: $draft.replacementValueCents)
                }
                warrantySection
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle(isNew ? "New item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if newPhotoFiles.isEmpty && !hasEdits { cancel() } else { confirmDiscard = true } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!draft.isValid).accessibilityIdentifier("asset.save")
                }
            }
            .onAppear(perform: load)
            .onChange(of: pickerItems) { _, items in Task { await importPicked(items) } }
            .onChange(of: draft.homeID) { _, _ in
                if !(selectedHome?.rooms ?? []).contains(where: { $0.id == draft.roomID }) { draft.roomID = nil }
            }
            .sheet(isPresented: $showCamera) { CameraPicker { addImage($0) }.ignoresSafeArea() }
            .sheet(isPresented: $showScanner) { BarcodeScannerSheet { draft.barcode = $0 } }
            .alert("New category", isPresented: $showNewCategory) {
                TextField("Name", text: $newCategoryName)
                Button("Add") { addCategory() }
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { cancel() }
            }
            .interactiveDismissDisabled(!newPhotoFiles.isEmpty || hasEdits)
        }
    }

    private var hasEdits: Bool { loaded && (isNew ? !draft.name.isEmpty : false) }

    // MARK: Sections

    private var existingPhotos: [AssetPhoto] { (asset?.sortedPhotos ?? []).filter { !removedPhotos.contains($0.id) } }

    private var photosSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(existingPhotos) { photo in
                        photoThumb(fileName: photo.fileName) { removedPhotos.insert(photo.id) }
                    }
                    ForEach(newPhotoFiles, id: \.self) { name in
                        photoThumb(fileName: name) {
                            FileStore.shared.delete(name)
                            newPhotoFiles.removeAll { $0 == name }
                        }
                    }
                    if CameraPicker.isAvailable {
                        addTile(symbol: "camera", title: "Camera") { showCamera = true }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                        addTileLabel(symbol: "photo.on.rectangle", title: "Library")
                    }
                    .accessibilityIdentifier("asset.photoLibrary")
                    #if DEBUG
                    if app.launch.isUITesting {
                        addTile(symbol: "photo.badge.plus", title: "Test photo") {
                            if let img = SampleDataService.placeholderPhoto(symbol: "shippingbox", color: .systemBlue) { addImage(img) }
                        }
                        .accessibilityIdentifier("asset.testPhoto")
                    }
                    #endif
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("Photos")
        } footer: {
            Text("Photos are stored only on this iPhone.")
        }
    }

    private func photoThumb(fileName: String, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = FileStore.shared.thumbnail(for: fileName, maxPixel: 240) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)).font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove photo")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo")
    }

    private func addTile(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { addTileLabel(symbol: symbol, title: title) }.buttonStyle(.plain)
    }

    private func addTileLabel(symbol: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(Theme.brand)
        .frame(width: 84, height: 84)
        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var warrantySection: some View {
        Section {
            OptionalDatePicker(title: "Coverage starts", date: $draft.warrantyStart, defaultDate: draft.purchaseDate ?? .now)
            OptionalDatePicker(title: "Coverage ends", date: $draft.warrantyExpiration, defaultDate: Calendar.current.date(byAdding: .year, value: 1, to: draft.warrantyStart ?? draft.purchaseDate ?? .now) ?? .now)
                .accessibilityIdentifier("asset.warrantyEnd")
            Menu {
                ForEach([6, 12, 24, 36, 60, 120], id: \.self) { months in
                    Button(months % 12 == 0 ? "\(months / 12) year\(months == 12 ? "" : "s")" : "\(months) months") { applyWarrantyLength(months) }
                }
            } label: {
                Label("Set end date from coverage length", systemImage: "calendar.badge.clock")
            }
            .disabled(draft.warrantyStart == nil && draft.purchaseDate == nil)
            if draft.warrantyExpiration != nil {
                Toggle("End date is an estimate", isOn: $draft.warrantyIsEstimated)
            }
            TextField("Provider (e.g. manufacturer, retailer plan)", text: $draft.warrantyProvider)
            Toggle("Expiry reminders", isOn: $draft.warrantyRemindersEnabled)
                .accessibilityIdentifier("asset.warrantyReminders")
            if draft.warrantyRemindersEnabled {
                if app.isPremium {
                    ForEach([90, 60, 30, 14, 7, 1], id: \.self) { d in
                        Toggle("\(d) day\(d == 1 ? "" : "s") before", isOn: Binding(
                            get: { draft.warrantyReminderOffsets.contains(d) },
                            set: { on in if on { draft.warrantyReminderOffsets.append(d) } else { draft.warrantyReminderOffsets.removeAll { $0 == d } } }))
                    }
                } else {
                    HStack {
                        Text("Reminds 30, 14 and 7 days before").foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Button("Customize") { app.present(.paywall(.customReminders)) }.font(.subheadline)
                    }
                }
            }
            TextField("Warranty notes", text: $draft.warrantyNotes, axis: .vertical).lineLimit(1...4)
        } header: {
            Text("Warranty")
        } footer: {
            Text("Leave dates empty if you don't know them — HomeLedger will show the warranty as Unknown rather than guess.")
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        if let asset {
            draft = AssetDraft(asset)
        } else {
            let home = app.currentHome(in: homes)
            draft.homeID = home?.id
            if let initialRoomID, let room = homes.flatMap({ $0.rooms ?? [] }).first(where: { $0.id == initialRoomID }) {
                draft.roomID = room.id
                draft.homeID = room.home?.id ?? home?.id
            }
        }
        loaded = true
    }

    private func applyWarrantyLength(_ months: Int) {
        let start = draft.warrantyStart ?? draft.purchaseDate ?? .now
        draft.warrantyStart = start
        draft.warrantyExpiration = WarrantyMath.expiration(start: start, months: months)
        draft.warrantyIsEstimated = false
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                addImage(image)
            } else {
                errorMessage = "One photo couldn't be imported. Try exporting it from Photos first."
            }
        }
        pickerItems = []
    }

    private func addImage(_ image: UIImage) {
        do { newPhotoFiles.append(try FileStore.shared.saveImage(image)) } catch { errorMessage = error.localizedDescription }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !customCategories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            context.insert(CustomCategory(name: name))
        }
        draft.category = CategoryInfo.customPrefix + name
        newCategoryName = ""
    }

    private func cancel() {
        for name in newPhotoFiles { FileStore.shared.delete(name) }
        dismiss()
    }

    private func save() {
        let svc = DataService(context: context)
        let target: Asset
        if let asset {
            target = asset
        } else {
            guard svc.canAddAsset(entitlements: app.entitlement) else {
                errorMessage = DataServiceError.assetLimitReached(limit: EntitlementState.freeAssetLimit).localizedDescription
                return
            }
            target = Asset(name: draft.name)
            context.insert(target)
        }
        draft.apply(to: target, homes: homes)
        for photo in (asset?.photos ?? []) where removedPhotos.contains(photo.id) { svc.deletePhoto(photo) }
        for name in newPhotoFiles { svc.addPhoto(fileName: name, to: target) }
        newPhotoFiles = []
        do {
            try context.save()
            app.syncReminders(context)
            app.showToast(isNew ? "Item added" : "Changes saved")
            dismiss()
            if isNew { app.navigate(.asset(target)) }
        } catch {
            errorMessage = "Your changes couldn't be saved: \(error.localizedDescription)"
        }
    }
}
