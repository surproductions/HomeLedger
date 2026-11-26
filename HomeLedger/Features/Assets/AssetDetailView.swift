import PhotosUI
import SwiftData
import SwiftUI

struct AssetDetailView: View {
    @Bindable var asset: Asset
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var confirmDelete = false
    @State private var showMove = false
    @State private var photoToDelete: AssetPhoto?
    @State private var viewingPhoto: AssetPhoto?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gallery
                header
                actionRow
                if !asset.missingInfoSuggestions.isEmpty && !asset.isArchived { suggestions }
                detailsCard
                purchaseCard
                warrantyCard
                documentsSection
                serviceSection
                tasksSection
                timelineSection
                if !asset.notes.isEmpty {
                    SectionHeader(title: "Notes")
                    Text(asset.notes).font(.body).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading).card()
                }
            }
            .padding(Theme.gutter)
        }
        .canvasBackground()
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { app.present(.editAsset(asset)) }.accessibilityIdentifier("asset.edit")
                Menu {
                    Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { showMove = true } label: { Label("Move to room", systemImage: "arrow.right.square") }
                    Button { toggleArchive() } label: { Label(asset.isArchived ? "Restore from archive" : "Archive", systemImage: "archivebox") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More actions")
                .accessibilityIdentifier("asset.more")
            }
        }
        .onChange(of: pickerItems) { _, items in Task { await addPicked(items) } }
        .sheet(isPresented: $showMove) { MoveAssetSheet(asset: asset) }
        .sheet(item: $viewingPhoto) { photo in PhotoViewer(fileName: photo.fileName) }
        .confirmationDialog("Delete \(asset.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete item", role: .destructive) {
                DataService(context: context).deleteAsset(asset)
                try? context.save()
                app.syncReminders(context)
                dismiss()
            }
        } message: {
            Text("Its \((asset.photos ?? []).count) photo(s) will be deleted. \((asset.documents ?? []).count) document(s), repair history and expenses are kept. Archive instead if you sold or gave it away.")
        }
        .confirmationDialog("Remove this photo?", isPresented: Binding(get: { photoToDelete != nil }, set: { if !$0 { photoToDelete = nil } }), titleVisibility: .visible) {
            Button("Remove photo", role: .destructive) {
                if let p = photoToDelete { DataService(context: context).deletePhoto(p); try? context.save() }
                photoToDelete = nil
            }
        }
    }

    // MARK: Gallery

    @ViewBuilder
    private var gallery: some View {
        let photos = asset.sortedPhotos
        if photos.isEmpty {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                VStack(spacing: 10) {
                    Image(systemName: asset.categoryInfo.symbol).font(.system(size: 40, weight: .light))
                    Text("Add photos").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
            }
        } else {
            TabView {
                ForEach(photos) { photo in
                    Button { viewingPhoto = photo } label: {
                        Group {
                            if let img = FileStore.shared.thumbnail(for: photo.fileName, maxPixel: 1200) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else { Theme.brandSoft }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { photoToDelete = photo } label: { Label("Remove photo", systemImage: "trash") }
                    }
                    .accessibilityLabel("Photo of \(asset.name)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
            .accessibilityIdentifier("asset.gallery")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(asset.name).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(asset.displaySubtitle).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 6) {
                if let room = asset.room { StatusPill(text: room.name, tone: .brand, symbol: room.symbolName) }
                StatusPill(text: "Warranty: \(asset.warrantyStatus.label)", tone: asset.warrantyStatus.tone, symbol: asset.warrantyStatus.symbol)
                if asset.isArchived { StatusPill(text: "Archived", tone: .neutral, symbol: "archivebox") }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                actionLabel("Photo", "camera")
            }
            .accessibilityLabel("Add photo")
            Button { app.present(.importDocument(.chooser, assetID: asset.id)) } label: { actionLabel("Document", "doc.badge.plus") }
                .accessibilityIdentifier("asset.attachDocument")
            Button { app.present(.newService(assetID: asset.id)) } label: { actionLabel("Repair", "wrench.adjustable") }
                .accessibilityIdentifier("asset.logRepair")
            Button { app.present(.newTask(assetID: asset.id)) } label: { actionLabel("Task", "calendar.badge.plus") }
                .accessibilityIdentifier("asset.addTask")
        }
        .buttonStyle(PressableStyle())
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.brand)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusS + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusS + 2, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private var suggestions: some View {
        Button { app.present(.editAsset(asset)) } label: {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: "lightbulb", tint: Theme.info, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make this record more complete").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(asset.missingInfoSuggestions.prefix(3).joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text("Optional").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Cards

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Details")
            VStack(spacing: 0) {
                DetailRow(label: "Category", value: asset.categoryInfo.name)
                Divider().overlay(Theme.hairline)
                DetailRow(label: "Location", value: [asset.home?.name, asset.room?.name ?? "Unassigned"].compactMap { $0 }.joined(separator: " › "))
                if !asset.brand.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Brand", value: asset.brand) }
                if !asset.modelNumber.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Model", value: asset.modelNumber, copyable: true) }
                Divider().overlay(Theme.hairline)
                DetailRow(label: "Serial number", value: asset.serialNumber.isEmpty ? "Not recorded" : asset.serialNumber,
                          valueTone: asset.serialNumber.isEmpty ? Theme.inkTertiary : Theme.ink, copyable: !asset.serialNumber.isEmpty)
                if !asset.barcode.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Barcode", value: asset.barcode, copyable: true) }
                Divider().overlay(Theme.hairline)
                DetailRow(label: "Condition", value: asset.condition.label)
                if asset.quantity > 1 { Divider().overlay(Theme.hairline); DetailRow(label: "Quantity", value: "\(asset.quantity)") }
            }
            .card(padding: 14)
        }
    }

    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Purchase & value")
            VStack(spacing: 0) {
                DetailRow(label: "Purchased", value: asset.purchaseDate?.formatted(date: .long, time: .omitted) ?? "Not recorded",
                          valueTone: asset.purchaseDate == nil ? Theme.inkTertiary : Theme.ink)
                Divider().overlay(Theme.hairline)
                DetailRow(label: "Price", value: asset.purchasePriceCents.map { Money.format(cents: $0) } ?? "Not recorded",
                          valueTone: asset.purchasePriceCents == nil ? Theme.inkTertiary : Theme.ink)
                if !asset.retailer.isEmpty { Divider().overlay(Theme.hairline); DetailRow(label: "Retailer", value: asset.retailer) }
                if let r = asset.replacementValueCents { Divider().overlay(Theme.hairline); DetailRow(label: "Est. replacement", value: Money.format(cents: r)) }
                if !(asset.expenses ?? []).isEmpty || asset.purchasePriceCents != nil {
                    Divider().overlay(Theme.hairline)
                    NavigationLink(value: AppRoute.expenses) {
                        DetailRow(label: "Lifetime cost", value: Money.format(cents: asset.lifetimeCostCents), valueTone: Theme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 14)
        }
    }

    private var warrantyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Warranty", actionTitle: "Edit") { app.present(.editAsset(asset)) }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    StatusPill(text: asset.warrantyStatus.label, tone: asset.warrantyStatus.tone, symbol: asset.warrantyStatus.symbol)
                    Spacer()
                    if let days = asset.warrantyDaysRemaining, days >= 0 {
                        Text("\(days) days left").font(.subheadline.weight(.semibold)).foregroundStyle(asset.warrantyStatus.tone.color)
                    }
                }
                .padding(.bottom, 6)
                if asset.warrantyStatus == .unknown {
                    Text("No end date recorded. Add it from your receipt or warranty card to get reminders.")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.vertical, 6)
                } else {
                    if let start = asset.warrantyStart { DetailRow(label: "Starts", value: start.formatted(date: .long, time: .omitted)); Divider().overlay(Theme.hairline) }
                    if let end = asset.warrantyExpiration {
                        DetailRow(label: "Ends", value: end.formatted(date: .long, time: .omitted) + (asset.warrantyIsEstimated ? " (estimated)" : ""))
                        Divider().overlay(Theme.hairline)
                    }
                    if !asset.warrantyProvider.isEmpty { DetailRow(label: "Provider", value: asset.warrantyProvider); Divider().overlay(Theme.hairline) }
                    DetailRow(label: "Reminders", value: asset.warrantyRemindersEnabled ? asset.warrantyReminderOffsets.sorted(by: >).map { "\($0)d" }.joined(separator: ", ") + " before" : "Off")
                }
                if !asset.warrantyNotes.isEmpty { Text(asset.warrantyNotes).font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.top, 6) }
                let warrantyDocs = asset.sortedDocuments.filter { $0.kind == .warranty }
                ForEach(warrantyDocs) { doc in
                    NavigationLink(value: AppRoute.document(doc)) {
                        Label(doc.title, systemImage: "doc.text").font(.subheadline.weight(.medium)).foregroundStyle(Theme.brand).padding(.top, 8)
                    }
                }
            }
            .card(padding: 14)
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Documents", actionTitle: "Attach") { app.present(.importDocument(.chooser, assetID: asset.id)) }
            if asset.sortedDocuments.isEmpty {
                ListCard { EmptyStateView(symbol: "doc.badge.plus", title: "No documents", message: "Attach the receipt, manual or warranty card.") }
            } else {
                ListCard {
                    ForEach(Array(asset.sortedDocuments.enumerated()), id: \.element.id) { i, doc in
                        if i > 0 { RowDivider() }
                        NavigationLink(value: AppRoute.document(doc)) {
                            RecordRow(symbol: doc.kind.symbol, tint: Theme.tintPurple, title: doc.title, subtitle: doc.kind.label,
                                      trailingDetail: doc.createdAt.formatted(date: .abbreviated, time: .omitted))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Repair & service history", actionTitle: "Log") { app.present(.newService(assetID: asset.id)) }
            if asset.sortedServiceRecords.isEmpty {
                ListCard { EmptyStateView(symbol: "wrench.adjustable", title: "No repairs logged", message: "Keep a record of repairs, servicing and who did the work.") }
            } else {
                ListCard {
                    ForEach(Array(asset.sortedServiceRecords.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { RowDivider() }
                        NavigationLink(value: AppRoute.service(s)) {
                            RecordRow(symbol: s.kind.symbol, tint: Theme.tintOrange, title: s.title,
                                      subtitle: [s.date.formatted(date: .abbreviated, time: .omitted), s.vendor].filter { !$0.isEmpty }.joined(separator: " · "),
                                      trailing: s.costCents.map { Money.format(cents: $0) })
                        }
                        .buttonStyle(.plain)
                    }
                }
                if asset.repairCostCents > 0 {
                    Text("Total repair cost: \(Money.format(cents: asset.repairCostCents))").font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        let tasks = (asset.tasks ?? []).filter { !$0.isArchived }.sorted { $0.dueDate < $1.dueDate }
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Maintenance")
                ListCard {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { RowDivider() }
                        TaskRow(task: t, showComplete: true)
                    }
                }
            }
        }
    }

    private var timelineSection: some View {
        let events = AssetTimeline.events(for: asset)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Timeline")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle().fill(event.tone.color).frame(width: 10, height: 10).padding(.top, 5)
                            if index < events.count - 1 { Rectangle().fill(Theme.hairline).frame(width: 2).frame(maxHeight: .infinity) }
                        }
                        .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                            Text(event.date.formatted(date: .abbreviated, time: .omitted) + (event.detail.isEmpty ? "" : " · \(event.detail)"))
                                .font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.bottom, 14)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card(padding: 14)
        }
    }

    // MARK: Actions

    private func addPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let svc = DataService(context: context)
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let name = try? FileStore.shared.saveImageData(data) {
                svc.addPhoto(fileName: name, to: asset)
            }
        }
        pickerItems = []
        try? context.save()
    }

    private func duplicate() {
        let svc = DataService(context: context)
        guard svc.canAddAsset(entitlements: app.entitlement) else { app.present(.paywall(.unlimitedItems)); return }
        let copy = svc.duplicate(asset)
        try? context.save()
        app.showToast("Duplicated")
        app.present(.editAsset(copy))
    }

    private func toggleArchive() {
        let svc = DataService(context: context)
        if asset.isArchived && !svc.canAddAsset(entitlements: app.entitlement) { app.present(.paywall(.unlimitedItems)); return }
        svc.setArchived(asset, !asset.isArchived)
        try? context.save()
        app.syncReminders(context)
        app.showToast(asset.isArchived ? "Archived — reminders paused" : "Restored")
    }
}

struct PhotoViewer: View {
    let fileName: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            StoredFilePreview(fileName: fileName, contentType: .jpeg)
                .background(Color.black.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: FileStore.shared.url(for: fileName)) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }
}

/// Builds a chronological history for an asset from every linked record.
enum AssetTimeline {
    struct Event: Identifiable {
        let id: String
        let date: Date
        let title: String
        let detail: String
        let tone: StatusTone
    }

    static func events(for asset: Asset, now: Date = .now) -> [Event] {
        var events: [Event] = [Event(id: "created", date: asset.createdAt, title: "Added to HomeLedger", detail: "", tone: .neutral)]
        if let d = asset.purchaseDate {
            events.append(Event(id: "purchase", date: d, title: "Purchased", detail: [asset.retailer, asset.purchasePriceCents.map { Money.format(cents: $0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), tone: .brand))
        }
        if let w = asset.warrantyExpiration {
            events.append(Event(id: "warranty", date: w, title: w < now ? "Warranty ended" : "Warranty ends", detail: asset.warrantyIsEstimated ? "Estimated" : "", tone: w < now ? .danger : .warning))
        }
        for doc in asset.documents ?? [] {
            events.append(Event(id: "doc-\(doc.id)", date: doc.createdAt, title: "\(doc.kind.label) saved", detail: doc.title, tone: .info))
        }
        for s in asset.serviceRecords ?? [] {
            events.append(Event(id: "svc-\(s.id)", date: s.date, title: s.title, detail: [s.kind.label, s.costCents.map { Money.format(cents: $0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), tone: .warning))
        }
        for t in asset.tasks ?? [] {
            for log in t.logs ?? [] where log.kind == .completed {
                events.append(Event(id: "log-\(log.id)", date: log.date, title: "\(t.title) completed", detail: log.note, tone: .success))
            }
        }
        return events.sorted { $0.date > $1.date }
    }
}
