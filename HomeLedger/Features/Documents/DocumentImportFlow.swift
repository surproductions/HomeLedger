import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Values shown on the review screen. Every field starts from what was found on the page
/// (never invented) and stays editable. `confidence` drives the "Detected" / "Best guess" labels.
struct DocumentReviewDraft {
    var title = ""
    var kind: DocumentKind = .receipt
    var vendor = ""
    var vendorConfidence: FieldConfidence?
    var date: Date?
    var dateConfidence: FieldConfidence?
    var amountCents: Int?
    var amountConfidence: FieldConfidence?
    var productName = ""
    var productConfidence: FieldConfidence?
    var modelNumber = ""
    var modelConfidence: FieldConfidence?
    var serialNumber = ""
    var serialConfidence: FieldConfidence?
    var warrantyEnd: Date?
    var warrantyEndConfidence: FieldConfidence?
    /// Set when the end date was calculated from a stated period (e.g. "2-year warranty").
    var warrantyEndCalculatedFrom: String?
    var notes = ""

    init() {}

    init(extraction r: ExtractionResult, fallbackTitle: String, calendar: Calendar = .current) {
        kind = r.suggestedKind ?? .receipt
        vendor = r.merchant?.value ?? ""; vendorConfidence = r.merchant?.confidence
        date = r.purchaseDate?.value; dateConfidence = r.purchaseDate?.confidence
        amountCents = r.totalCents?.value; amountConfidence = r.totalCents?.confidence
        productName = r.productName?.value ?? ""; productConfidence = r.productName?.confidence
        modelNumber = r.modelNumber?.value ?? ""; modelConfidence = r.modelNumber?.confidence
        serialNumber = r.serialNumber?.value ?? ""; serialConfidence = r.serialNumber?.confidence
        if let explicit = r.warrantyExpiration {
            warrantyEnd = explicit.value; warrantyEndConfidence = explicit.confidence
        } else if let months = r.warrantyMonths?.value, let start = r.purchaseDate?.value {
            warrantyEnd = WarrantyMath.expiration(start: start, months: months, calendar: calendar)
            warrantyEndConfidence = .inferred
            let period: String = months % 12 == 0 ? "\(months / 12)-year" : "\(months)-month"
            warrantyEndCalculatedFrom = period + " coverage stated on the document"
        }
        let base = [vendor, kind.label].filter { !$0.isEmpty }.joined(separator: " ")
        title = productName.isEmpty ? (base.isEmpty ? fallbackTitle : base) : "\(productName) \(kind.label.lowercased())"
    }
}

struct DocumentImportFlow: View {
    let source: DocumentSource
    let assetID: UUID?

    enum Stage: Equatable { case choose, processing, review }

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \Asset.name) private var assets: [Asset]

    @State private var stage: Stage = .choose
    @State private var imported: ImportedFile?
    @State private var draft = DocumentReviewDraft()
    @State private var recognizedText = ""
    @State private var ocrMessage: String?
    @State private var errorMessage: String?
    @State private var linkAssetID: UUID?
    @State private var createNewAsset = false
    @State private var applyToAsset = true
    @State private var logExpense = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var autoStarted = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose: chooser
                case .processing: processing
                case .review: review
                }
            }
            .navigationTitle(stage == .review ? "Review details" : "Add document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() }.accessibilityIdentifier("import.cancel") }
                if stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("import.save")
                    }
                }
            }
        }
        .interactiveDismissDisabled(stage != .choose)
        .onAppear {
            linkAssetID = assetID
            guard !autoStarted else { return }
            autoStarted = true
            switch source {
            case .camera: if DocumentScannerView.isAvailable { showScanner = true }
            case .photos: showPhotos = true
            case .files: showFiles = true
            case .chooser: break
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                process { try DocumentImporter.importScannedPages(pages) }
            } onCancel: { showScanner = false }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: DocumentImporter.supportedTypes) { result in
            switch result {
            case .success(let url): process { try DocumentImporter.importFile(at: url) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { errorMessage = "That photo couldn't be loaded."; return }
                process { try DocumentImporter.importImageData(data) }
                photoItem = nil
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Stages

    private var chooser: some View {
        List {
            Section {
                Button { showScanner = true } label: {
                    sourceRow("Scan with camera", "Edge detection, multi-page, saved as PDF", "doc.viewfinder")
                }
                .disabled(!DocumentScannerView.isAvailable)
                Button { showPhotos = true } label: { sourceRow("Choose a photo", "From your photo library", "photo.on.rectangle") }
                    .accessibilityIdentifier("import.photos")
                Button { showFiles = true } label: { sourceRow("Choose a file", "PDF, JPEG, PNG or HEIC from Files", "folder") }
                    .accessibilityIdentifier("import.files")
                #if DEBUG
                if app.launch.isUITesting {
                    Button { useTestReceipt() } label: { sourceRow("Use test receipt", "UI testing only", "testtube.2") }
                        .accessibilityIdentifier("import.testReceipt")
                }
                #endif
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !DocumentScannerView.isAvailable { Text("Document scanning isn't available on this device.") }
                    Label("Text is recognized on this iPhone with Apple's Vision framework. Documents are never uploaded.", systemImage: "lock.shield")
                }
            }
        }
    }

    private func sourceRow(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        RecordRow(symbol: symbol, tint: Theme.brand, title: title, subtitle: subtitle)
    }

    private var processing: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Reading text on your iPhone…").font(.headline)
            Text("Nothing leaves your device.").font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var review: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    if let imported {
                        Group {
                            if imported.contentType.isImage, let img = FileStore.shared.thumbnail(for: imported.fileName, maxPixel: 200) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Image(systemName: "doc.richtext").font(.title2).foregroundStyle(Theme.tintPurple).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.tintPurple.opacity(0.1))
                            }
                        }
                        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(imported.originalFileName).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(imported.fileSize), countStyle: .file)).font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                if let ocrMessage {
                    Label(ocrMessage, systemImage: "info.circle").font(.footnote).foregroundStyle(Theme.inkSecondary)
                        .accessibilityIdentifier("import.ocrMessage")
                }
            } footer: {
                Text("Check each value against the original. Fields marked “Best guess” were inferred and are more likely to be wrong. Empty fields weren't found — nothing is filled in automatically.")
            }

            Section("Document") {
                TextField("Title", text: $draft.title).accessibilityIdentifier("import.title")
                Picker("Type", selection: $draft.kind) { ForEach(DocumentKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
            }

            Section("Extracted details") {
                reviewField("Vendor", confidence: draft.vendorConfidence) { TextField("Vendor", text: $draft.vendor).accessibilityIdentifier("import.vendor") }
                reviewField("Date", confidence: draft.dateConfidence) { OptionalDatePicker(title: "Date", date: $draft.date) }
                reviewField("Amount", confidence: draft.amountConfidence) { MoneyField(title: "Amount", cents: $draft.amountCents).accessibilityIdentifier("import.amount") }
                reviewField("Item", confidence: draft.productConfidence) { TextField("Product or item name", text: $draft.productName) }
                reviewField("Model", confidence: draft.modelConfidence) { TextField("Model", text: $draft.modelNumber).textInputAutocapitalization(.characters).autocorrectionDisabled() }
                reviewField("Serial number", confidence: draft.serialConfidence) { TextField("Serial number", text: $draft.serialNumber).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("import.serial") }
                reviewField("Warranty ends", confidence: draft.warrantyEndConfidence) {
                    VStack(alignment: .leading, spacing: 4) {
                        OptionalDatePicker(title: "Warranty ends", date: $draft.warrantyEnd)
                        if let from = draft.warrantyEndCalculatedFrom, draft.warrantyEnd != nil {
                            Text("Estimated from the \(from).").font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }
            }

            Section {
                Picker("Link to item", selection: $linkAssetID) {
                    Text("None").tag(UUID?.none)
                    ForEach(assets.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                }
                .disabled(createNewAsset)
                .accessibilityIdentifier("import.linkAsset")
                Toggle("Create a new item from this", isOn: $createNewAsset)
                    .onChange(of: createNewAsset) { _, on in if on { linkAssetID = nil } }
                    .accessibilityIdentifier("import.createAsset")
                if linkAssetID != nil || createNewAsset {
                    Toggle("Fill empty item fields with these details", isOn: $applyToAsset)
                }
                if draft.amountCents != nil && (draft.kind == .receipt || draft.kind == .invoice || draft.kind == .service) {
                    Toggle("Also record as an expense", isOn: $logExpense).accessibilityIdentifier("import.logExpense")
                }
            } header: { Text("Use these details") } footer: {
                Text("Existing values on an item are never overwritten. You can edit everything later.")
            }

            Section("Notes") { TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...5) }

            if !recognizedText.isEmpty {
                Section("Recognized text") {
                    Text(recognizedText).font(.caption.monospaced()).foregroundStyle(Theme.inkSecondary).lineLimit(12).textSelection(.enabled)
                }
            }
        }
    }

    private func reviewField<Content: View>(_ label: String, confidence: FieldConfidence?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            if let confidence {
                Label(confidence.label, systemImage: confidence == .detected ? "checkmark.seal" : "questionmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(confidence == .detected ? Theme.success : Theme.warning)
                    .accessibilityIdentifier("import.confidence.\(label)")
            }
        }
    }

    // MARK: Processing

    private func process(_ importer: @escaping () throws -> ImportedFile) {
        do {
            let file = try importer()
            imported = file
            stage = .processing
            Task { await recognize(file) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recognize(_ file: ImportedFile) async {
        let fallback = (file.originalFileName as NSString).deletingPathExtension
        do {
            let text = try await OCRService.extractText(from: FileStore.shared.url(for: file.fileName), contentType: file.contentType)
            recognizedText = text
            let result = ReceiptParser().parse(text)
            draft = DocumentReviewDraft(extraction: result, fallbackTitle: fallback)
            ocrMessage = result.isEmpty ? "Text was found but no details could be identified. Enter them below." : "Found \(result.fieldCount) detail\(result.fieldCount == 1 ? "" : "s") on the page."
        } catch {
            draft = DocumentReviewDraft()
            draft.title = fallback
            draft.kind = .other
            ocrMessage = (error as? LocalizedError)?.errorDescription ?? "Text couldn't be read. Enter details manually."
        }
        if let id = linkAssetID, let asset = assets.first(where: { $0.id == id }), draft.title == fallback || draft.title.isEmpty {
            draft.title = "\(asset.name) \(draft.kind.label.lowercased())"
        }
        stage = .review
    }

    #if DEBUG
    private func useTestReceipt() {
        let lines = ["HOMEGOODS DEPOT", "Store #42", "Date: 03/14/2025", "Bosch 800 Series Dishwasher", "Model: SHX78CM5N", "Serial No: FD0112 99887",
                     "2-year limited warranty", "Subtotal 1,149.00", "Tax 91.92", "Total $1,240.92"]
        process {
            guard let data = SampleDataService.makeTextPDF(lines: lines) else { throw FileStoreError.unreadableImage }
            let name = try FileStore.shared.save(data, fileExtension: "pdf")
            return ImportedFile(fileName: name, originalFileName: "Test receipt.pdf", contentType: .pdf, fileSize: data.count)
        }
    }
    #endif

    // MARK: Save / cancel

    private func cancel() {
        if !saved { imported?.discard() }
        dismiss()
    }

    private func save() {
        guard let imported else { return }
        let svc = DataService(context: context)
        let home = app.currentHome(in: homes)
        var asset = linkAssetID.flatMap { id in assets.first { $0.id == id } }

        if createNewAsset {
            guard svc.canAddAsset(entitlements: app.entitlement) else {
                errorMessage = DataServiceError.assetLimitReached(limit: EntitlementState.freeAssetLimit).localizedDescription
                    + " You can still save the document and link it to an existing item."
                return
            }
            let name = draft.productName.isEmpty ? draft.title : draft.productName
            let created = Asset(name: name, category: .other, home: home)
            context.insert(created)
            asset = created
        }

        let doc = DocumentRecord(title: draft.title.trimmingCharacters(in: .whitespaces), kind: draft.kind, fileName: imported.fileName,
                                 contentType: imported.contentType, home: asset?.home ?? home, asset: asset)
        doc.originalFileName = imported.originalFileName
        doc.fileSize = imported.fileSize
        doc.vendor = draft.vendor
        doc.documentDate = draft.date
        doc.amountCents = draft.amountCents
        doc.notes = draft.notes
        doc.recognizedText = recognizedText
        context.insert(doc)

        if let asset, applyToAsset || createNewAsset {
            if asset.retailer.isEmpty && !draft.vendor.isEmpty && (draft.kind == .receipt || draft.kind == .invoice) { asset.retailer = draft.vendor }
            if asset.purchaseDate == nil && (draft.kind == .receipt || draft.kind == .invoice) { asset.purchaseDate = draft.date }
            if asset.purchasePriceCents == nil && (draft.kind == .receipt || draft.kind == .invoice) { asset.purchasePriceCents = draft.amountCents }
            if asset.modelNumber.isEmpty { asset.modelNumber = draft.modelNumber }
            if asset.serialNumber.isEmpty { asset.serialNumber = draft.serialNumber }
            if asset.warrantyExpiration == nil, let end = draft.warrantyEnd {
                asset.warrantyExpiration = end
                asset.warrantyStart = asset.warrantyStart ?? draft.date
                asset.warrantyIsEstimated = draft.warrantyEndConfidence != .detected
            }
            asset.touch()
        }

        if logExpense, let cents = draft.amountCents, cents > 0 {
            let category: ExpenseCategory = draft.kind == .service ? .repair : .purchase
            let expense = Expense(title: draft.title, amountCents: cents, date: draft.date ?? .now, category: category, home: asset?.home ?? home, asset: asset)
            expense.vendor = draft.vendor
            expense.receipt = doc
            context.insert(expense)
        }

        do {
            try context.save()
            saved = true
            if asset?.warrantyExpiration != nil {
                app.requestPermissionAndSyncReminders(context)
            } else {
                app.syncReminders(context)
            }
            app.showToast("Document saved")
            dismiss()
        } catch {
            context.rollback()
            errorMessage = "The document couldn't be saved: \(error.localizedDescription)"
        }
    }
}
