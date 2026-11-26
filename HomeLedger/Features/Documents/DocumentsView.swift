import SwiftData
import SwiftUI

struct DocumentsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \DocumentRecord.createdAt, order: .reverse) private var allDocuments: [DocumentRecord]
    @State private var kind: DocumentKind?
    @State private var searchText = ""

    private var documents: [DocumentRecord] {
        var docs = HomeScope(home: app.currentHome(in: homes)).documents(allDocuments)
        if let kind { docs = docs.filter { $0.kind == kind } }
        let terms = SearchService.tokens(searchText)
        if !terms.isEmpty {
            docs = docs.filter { d in
                let hay = SearchService.normalize([d.title, d.vendor, d.notes, d.asset?.name ?? "", d.kind.label, d.recognizedText].joined(separator: " "))
                return terms.allSatisfy { hay.contains($0) }
            }
        }
        return docs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                importCard
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: kind == nil) { kind = nil }
                        ForEach(DocumentKind.allCases) { k in
                            FilterChip(title: k.pluralLabel, symbol: k.symbol, isSelected: kind == k) { kind = kind == k ? nil : k }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 0, for: .scrollContent)
                .accessibilityIdentifier("documents.filters")

                if documents.isEmpty {
                    ListCard {
                        EmptyStateView(symbol: "doc.text.magnifyingglass",
                                       title: searchText.isEmpty ? "No documents yet" : "No matches",
                                       message: searchText.isEmpty ? "Scan receipts, manuals and warranty cards. Text is recognized on your iPhone so you can search it later." : "Search also looks inside recognized text.",
                                       actionTitle: searchText.isEmpty ? "Add document" : nil) { app.present(.importDocument(.chooser, assetID: nil)) }
                    }
                } else {
                    ListCard {
                        ForEach(Array(documents.enumerated()), id: \.element.id) { i, doc in
                            if i > 0 { RowDivider() }
                            NavigationLink(value: AppRoute.document(doc)) { DocumentRow(document: doc) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle("Documents")
        .searchable(text: $searchText, prompt: "Search titles, vendors and text")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.present(.importDocument(.chooser, assetID: nil)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add document")
                    .accessibilityIdentifier("documents.add")
            }
        }
    }

    private var importCard: some View {
        HStack(spacing: 10) {
            importButton("Scan", "doc.viewfinder", .camera, enabled: DocumentScannerView.isAvailable)
            importButton("Photos", "photo.on.rectangle", .photos, enabled: true)
            importButton("Files", "folder", .files, enabled: true)
        }
    }

    private func importButton(_ title: String, _ symbol: String, _ source: DocumentSource, enabled: Bool) -> some View {
        Button { app.present(.importDocument(enabled ? source : .chooser, assetID: nil)) } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Theme.heroGradient, in: Circle())
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 12)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("documents.import.\(source.rawValue)")
    }
}

struct DocumentRow: View {
    let document: DocumentRecord
    var body: some View {
        HStack(spacing: 12) {
            DocumentThumbnail(document: document, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                Text(joinedParts([document.kind.label, document.asset?.name, document.vendor.isEmpty ? nil : document.vendor], separator: " · "))
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let a = document.amountCents { Text(Money.format(cents: a)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
                Text((document.documentDate ?? document.createdAt).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DocumentThumbnail: View {
    let document: DocumentRecord
    var size: CGFloat = 46
    var body: some View {
        Group {
            if document.contentType.isImage, let img = FileStore.shared.thumbnail(for: document.fileName, maxPixel: size * 3) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: document.kind.symbol).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(Theme.tintPurple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.tintPurple.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct DocumentListView: View {
    let kind: DocumentKind?
    @Environment(AppModel.self) private var app
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query(sort: \DocumentRecord.createdAt, order: .reverse) private var allDocuments: [DocumentRecord]

    var body: some View {
        let docs = HomeScope(home: app.currentHome(in: homes)).documents(allDocuments).filter { kind == nil || $0.kind == kind }
        List {
            if docs.isEmpty {
                EmptyStateView(symbol: "doc", title: "No documents", message: "Add receipts, manuals and warranties.", actionTitle: "Add document") { app.present(.importDocument(.chooser, assetID: nil)) }
                    .listRowBackground(Color.clear)
            }
            ForEach(docs) { doc in NavigationLink(value: AppRoute.document(doc)) { DocumentRow(document: doc) } }
        }
        .navigationTitle(kind?.pluralLabel ?? "Documents")
    }
}

// MARK: - Detail

struct DocumentDetailView: View {
    @Bindable var document: DocumentRecord
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Asset.name) private var assets: [Asset]
    @State private var showPreview = false
    @State private var confirmDelete = false
    @State private var showText = false
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { showPreview = true } label: {
                    ZStack {
                        if document.contentType.isImage, let img = FileStore.shared.thumbnail(for: document.fileName, maxPixel: 1000) {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: document.contentType == .pdf ? "doc.richtext" : document.kind.symbol).font(.system(size: 44, weight: .light))
                                Text("Open \(document.contentType == .pdf ? "PDF" : "image")").font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Theme.tintPurple)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.tintPurple.opacity(0.1))
                        }
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open original document")
                .accessibilityIdentifier("document.preview")

                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    HStack { StatusPill(text: document.kind.label, tone: .info, symbol: document.kind.symbol); Text(fileSizeText).font(.caption).foregroundStyle(Theme.inkSecondary) }
                }

                VStack(spacing: 0) {
                    if !document.vendor.isEmpty { DetailRow(label: "Vendor", value: document.vendor); Divider().overlay(Theme.hairline) }
                    if let d = document.documentDate { DetailRow(label: "Date", value: d.formatted(date: .long, time: .omitted)); Divider().overlay(Theme.hairline) }
                    if let a = document.amountCents { DetailRow(label: "Amount", value: Money.format(cents: a)); Divider().overlay(Theme.hairline) }
                    Picker("Linked item", selection: Binding(get: { document.asset?.id }, set: { id in
                        document.asset = assets.first { $0.id == id }
                        document.updatedAt = .now
                        try? context.save()
                    })) {
                        Text("None").tag(UUID?.none)
                        ForEach(assets.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .padding(.vertical, 4)
                    Divider().overlay(Theme.hairline)
                    DetailRow(label: "Added", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if !document.originalFileName.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Original file", value: document.originalFileName) }
                }
                .card(padding: 14)

                if let asset = document.asset {
                    NavigationLink(value: AppRoute.asset(asset)) {
                        HStack { AssetRow(asset: asset); Image(systemName: "chevron.right").foregroundStyle(Theme.inkTertiary) }.card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }

                if !document.notes.isEmpty {
                    Text(document.notes).font(.body).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading).card()
                }

                if !document.recognizedText.isEmpty {
                    DisclosureGroup(isExpanded: $showText) {
                        Text(document.recognizedText).font(.footnote.monospaced()).foregroundStyle(Theme.inkSecondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } label: {
                        Label("Recognized text (on-device)", systemImage: "text.viewfinder").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                    .card(padding: 14)
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle(document.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: FileStore.shared.url(for: document.fileName)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share original")
                Menu {
                    Button { editing = true } label: { Label("Edit details", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete document", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                StoredFilePreview(fileName: document.fileName, contentType: document.contentType)
                    .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreview = false } } }
            }
        }
        .sheet(isPresented: $editing) { DocumentMetadataEditor(document: document) }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete document", role: .destructive) {
                DataService(context: context).deleteDocument(document)
                try? context.save()
                dismiss()
            }
        } message: { Text("The original file will be permanently removed from this iPhone. Linked items and expenses are kept.") }
    }

    private var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(max(document.fileSize, FileStore.shared.fileSize(document.fileName))), countStyle: .file)
    }
}

struct DocumentMetadataEditor: View {
    @Bindable var document: DocumentRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: DocumentKind = .other
    @State private var vendor = ""
    @State private var date: Date?
    @State private var amount: Int?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Type", selection: $kind) { ForEach(DocumentKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                TextField("Vendor", text: $vendor)
                OptionalDatePicker(title: "Date", date: $date)
                MoneyField(title: "Amount", cents: $amount)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
            }
            .navigationTitle("Edit document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        document.title = title.isEmpty ? document.title : title
                        document.kind = kind; document.vendor = vendor; document.documentDate = date
                        document.amountCents = amount; document.notes = notes; document.updatedAt = .now
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                title = document.title; kind = document.kind; vendor = document.vendor
                date = document.documentDate; amount = document.amountCents; notes = document.notes
            }
        }
    }
}
