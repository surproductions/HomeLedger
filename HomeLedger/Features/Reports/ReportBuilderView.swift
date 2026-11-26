import PDFKit
import SwiftData
import SwiftUI

struct ReportBuilderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.displayNameKey) private var displayName = ""
    @Query(sort: \Home.sortIndex) private var homes: [Home]
    @Query private var allAssets: [Asset]

    @State private var homeID: UUID?
    @State private var selectedRooms: Set<UUID> = []
    @State private var selectedCategories: Set<String> = []
    @State private var includeArchived = false
    @State private var options = ReportOptions()
    @State private var generated: GeneratedReport?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    struct GeneratedReport: Identifiable {
        let id = UUID()
        let url: URL
        let document: PDFDocument
        let itemCount: Int
    }

    private var home: Home? { homes.first { $0.id == homeID } ?? app.currentHome(in: homes) }

    private var selectedAssets: [Asset] {
        allAssets.filter { a in
            (home == nil || a.home?.id == home?.id) &&
                (includeArchived || !a.isArchived) &&
                (selectedRooms.isEmpty || (a.room.map { selectedRooms.contains($0.id) } ?? false)) &&
                (selectedCategories.isEmpty || selectedCategories.contains(a.category))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if homes.count > 1 {
                        Picker("Home", selection: Binding(get: { home?.id }, set: { homeID = $0; selectedRooms = [] })) {
                            ForEach(homes) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    TextField("Report title", text: $options.title)
                    TextField("Prepared by (optional)", text: $options.preparedBy)
                } header: { Text("Report") }

                Section {
                    ForEach(home?.sortedRooms ?? []) { room in
                        Toggle(isOn: Binding(get: { selectedRooms.contains(room.id) }, set: { if $0 { selectedRooms.insert(room.id) } else { selectedRooms.remove(room.id) } })) {
                            Label(room.name, systemImage: room.symbolName)
                        }
                    }
                } header: { Text("Rooms") } footer: { Text(selectedRooms.isEmpty ? "All rooms are included." : "\(selectedRooms.count) room(s) selected.") }

                Section {
                    let categoryKeys = Array(Set(allAssets.filter { $0.home?.id == home?.id }.map(\.category))).sorted()
                    ForEach(categoryKeys, id: \.self) { key in
                        let info = CategoryInfo.resolve(key)
                        Toggle(isOn: Binding(get: { selectedCategories.contains(key) }, set: { if $0 { selectedCategories.insert(key) } else { selectedCategories.remove(key) } })) {
                            Label(info.name, systemImage: info.symbol)
                        }
                    }
                } header: { Text("Categories") } footer: { Text(selectedCategories.isEmpty ? "All categories are included." : "\(selectedCategories.count) categor\(selectedCategories.count == 1 ? "y" : "ies") selected.") }

                Section {
                    Toggle("Photos", isOn: Binding(get: { options.includePhotos && app.isPremium }, set: { v in
                        if v && !app.isPremium { app.present(.paywall(.photoReports)) } else { options.includePhotos = v }
                    }))
                    Toggle("Serial numbers", isOn: $options.includeSerialNumbers)
                    Toggle("Purchase dates & prices", isOn: $options.includePurchaseDetails)
                    Toggle("Estimated replacement values", isOn: Binding(get: { options.includeReplacementValues && app.isPremium }, set: { v in
                        if v && !app.isPremium { app.present(.paywall(.photoReports)) } else { options.includeReplacementValues = v }
                    }))
                    Toggle("Notes", isOn: $options.includeNotes)
                    Toggle("Group by room", isOn: $options.groupByRoom)
                    Toggle("Include archived items", isOn: $includeArchived)
                } header: { Text("Include") } footer: {
                    if !app.isPremium { Text("Photos and replacement values in reports are part of Premium. The free report includes every other detail.") }
                }

                Section {
                    Button { generate() } label: {
                        HStack {
                            Spacer()
                            if isGenerating { ProgressView() } else { Label("Generate PDF (\(selectedAssets.count) items)", systemImage: "doc.richtext") }
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .disabled(isGenerating)
                    .accessibilityIdentifier("report.generate")
                } footer: {
                    Text(InventoryReportBuilder.disclaimer)
                }
            }
            .navigationTitle("Inventory report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(item: $generated) { report in ReportPreviewView(report: report) }
            .onAppear {
                options.homeName = home?.name ?? ""
                options.preparedBy = displayName
                if !app.isPremium { options.includePhotos = false; options.includeReplacementValues = false }
            }
            .alert("Couldn't create the report", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func generate() {
        isGenerating = true
        var opts = options
        opts.homeName = home?.name ?? ""
        if !app.isPremium { opts.includePhotos = false; opts.includeReplacementValues = false }
        let assets = selectedAssets
        // PDF drawing uses UIKit and the model objects, so it runs on the main actor; reports are small.
        Task { @MainActor in
            let data = InventoryReportBuilder().makePDF(assets: assets, options: opts)
            do {
                let stamp = Date.now.formatted(.iso8601.year().month().day())
                let url = try ExportFiles.write(data, named: "\(opts.homeName.isEmpty ? "Home" : opts.homeName) Inventory \(stamp).pdf")
                guard let pdf = PDFDocument(data: data) else { throw FileStoreError.unreadableImage }
                generated = GeneratedReport(url: url, document: pdf, itemCount: assets.count)
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

extension ReportBuilderView.GeneratedReport: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ReportPreviewView: View {
    let report: ReportBuilderView.GeneratedReport
    @State private var showShare = false
    @State private var showExporter = false
    @State private var savedMessage: String?
    @State private var exportCopy: URL?

    var body: some View {
        PDFKitView(document: report.document)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("\(report.itemCount) items · \(report.document.pageCount) page\(report.document.pageCount == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("report.preview")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { exportCopy = copyForExport(); showExporter = exportCopy != nil } label: { Image(systemName: "folder.badge.plus") }
                        .accessibilityLabel("Save to Files")
                        .accessibilityIdentifier("report.saveToFiles")
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share report")
                        .accessibilityIdentifier("report.share")
                }
            }
            .sheet(isPresented: $showShare) { ShareSheet(items: [report.url]).presentationDetents([.medium, .large]) }
            .fileMover(isPresented: $showExporter, file: exportCopy) { result in
                if case .success = result { savedMessage = "Saved to Files." }
            }
            .safeAreaInset(edge: .bottom) {
                Text(savedMessage ?? "Reports are created on this iPhone. Sharing sends a copy only where you choose.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
                    .padding(10).frame(maxWidth: .infinity).background(.bar)
            }
    }

    /// fileMover moves the file, so hand it a disposable copy and keep the original for sharing.
    private func copyForExport() -> URL? {
        let copy = report.url.deletingLastPathComponent().appendingPathComponent("Export-" + report.url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: report.url, to: copy)
        return copy
    }
}
