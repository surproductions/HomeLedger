import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Preferences.displayNameKey) private var displayName = ""
    @AppStorage(Preferences.currencyCodeKey) private var currencyCode = Locale.current.currency?.identifier ?? "USD"
    @AppStorage(Preferences.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(Preferences.reminderHourKey) private var reminderHour = 9
    @AppStorage(Preferences.onboardingCompleteKey) private var onboardingComplete = true
    @AppStorage(Preferences.appearanceKey) private var appearance: String = AppearanceMode.system.rawValue

    @State private var confirmRemoveSample = false
    @State private var confirmDeleteAll = false
    @State private var deleteAllText = ""
    @State private var showDeleteAllField = false
    @State private var storageText = ""
    @State private var hasSample = false
    @State private var authorized = true

    private static let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "NZD", "JPY", "CHF", "SEK", "NOK", "DKK", "INR", "MXN", "BRL", "ZAR", "SGD", "HKD"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    premiumRow
                } header: { Text("HomeLedger Premium") }

                Section("Profile") {
                    TextField("Your name (optional)", text: $displayName)
                        .textContentType(.givenName)
                    NavigationLink { HomesManagerView() } label: { Label("Homes & rooms", systemImage: "house.and.flag") }
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.appearance")
                } header: { Text("Appearance") } footer: {
                    Text("System follows your iPhone's Light or Dark setting.")
                }

                Section {
                    Toggle("Reminders", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, on in
                            Task {
                                if on { authorized = await NotificationService.shared.requestPermission() }
                                await NotificationService.shared.sync(context: context)
                            }
                        }
                    Picker("Reminder time", selection: $reminderHour) {
                        ForEach([7, 8, 9, 10, 12, 17, 18, 19, 20], id: \.self) { h in
                            Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)?.formatted(date: .omitted, time: .shortened) ?? "\(h):00").tag(h)
                        }
                    }
                    .onChange(of: reminderHour) { _, _ in app.syncReminders(context) }
                    if notificationsEnabled && !authorized {
                        Button("Allow notifications in iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } header: { Text("Notifications") } footer: {
                    Text("Reminders are scheduled locally on this iPhone. Warranty reminder intervals are set per item.")
                }

                Section("Format") {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(Array(Set(Self.currencies + [currencyCode])).sorted(), id: \.self) { code in
                            Text("\(code) — \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                        }
                    }
                    Text("Dates follow your iPhone's region settings.").font(.footnote).foregroundStyle(Theme.inkSecondary)
                }

                Section {
                    NavigationLink { BackupView() } label: { Label("Back up & restore", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard") }
                        .accessibilityIdentifier("settings.backup")
                    Button { app.present(.report) } label: { Label("Inventory report (PDF)", systemImage: "doc.richtext") }
                } header: { Text("Your data") } footer: {
                    Text("On this iPhone: \(storageText). Backups and reports are full copies of your records — keep them somewhere you trust.")
                }

                Section("Privacy") {
                    NavigationLink { PrivacyView() } label: { Label("How your data is handled", systemImage: "lock.shield") }
                    LabeledContent("iCloud sync", value: "Not available yet")
                    LabeledContent("Household sharing", value: "Not available yet")
                }

                Section("Help") {
                    NavigationLink { HelpView() } label: { Label("Help & tips", systemImage: "questionmark.circle") }
                    Button { openURL(URL(string: "https://github.com/surproductions/HomeLedger/issues")!) } label: { Label("Send feedback", systemImage: "envelope") }
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                }

                Section {
                    if hasSample {
                        Button("Remove sample data") { confirmRemoveSample = true }
                            .accessibilityIdentifier("settings.removeSample")
                    }
                    Button("Delete all data…", role: .destructive) { showDeleteAllField = true }
                        .accessibilityIdentifier("settings.deleteAll")
                } header: { Text("Data control") }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                refreshStats()
                authorized = await NotificationService.shared.isAuthorized()
            }
            .confirmationDialog("Remove sample data?", isPresented: $confirmRemoveSample, titleVisibility: .visible) {
                Button("Remove sample data", role: .destructive) {
                    DataService(context: context).removeSampleData()
                    try? context.save()
                    app.selectedHomeID = nil
                    app.syncReminders(context)
                    refreshStats()
                    app.showToast("Sample data removed")
                }
            } message: { Text("Only the demo home and its records are removed. Anything you added yourself is kept.") }
            .alert("Delete all data?", isPresented: $showDeleteAllField) {
                TextField("Type DELETE", text: $deleteAllText)
                Button("Delete everything", role: .destructive) {
                    guard deleteAllText == "DELETE" else { deleteAllText = ""; return }
                    try? DataService(context: context).deleteAllData()
                    deleteAllText = ""
                    app.selectedHomeID = nil
                    app.syncReminders(context)
                    onboardingComplete = false
                    dismiss()
                }
                Button("Cancel", role: .cancel) { deleteAllText = "" }
            } message: {
                Text("This permanently deletes every home, item, photo, document, task and expense on this iPhone. It can't be undone. Export a backup first. Type DELETE to confirm.")
            }
        }
    }

    private var premiumRow: some View {
        Group {
            if app.isPremium {
                HStack {
                    IconBadge(systemName: "checkmark.seal.fill", tint: Theme.success)
                    VStack(alignment: .leading) {
                        Text("Premium is active").font(.headline)
                        if case .subscription(let exp) = app.entitlement.source, let exp {
                            Text("Renews or ends \(exp.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.inkSecondary)
                        } else if case .lifetime = app.entitlement.source {
                            Text("Lifetime purchase").font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                Button("Manage subscription") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                }
            } else {
                Button { app.present(.paywall(nil)) } label: {
                    HStack {
                        IconBadge(systemName: "sparkles", tint: Theme.tintPurple)
                        VStack(alignment: .leading) {
                            Text("Upgrade to Premium").font(.headline).foregroundStyle(Theme.ink)
                            Text("Unlimited items, multiple homes, photo reports").font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
            Button("Restore purchases") { Task { await app.store.restore(); if let m = app.store.lastMessage { app.showToast(m) } } }
        }
    }

    private func refreshStats() {
        let svc = DataService(context: context)
        hasSample = svc.hasSampleData
        let assets = svc.fetchAll(Asset.self).count
        let docs = svc.fetchAll(DocumentRecord.self).count
        storageText = "\(assets) items, \(docs) documents, \(ByteCountFormatter.string(fromByteCount: Int64(FileStore.shared.totalSize()), countStyle: .file)) of photos & files"
    }
}

// MARK: - Backup & restore

struct BackupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var shareItem: ShareableFile?
    @State private var showImporter = false
    @State private var pending: BackupValidation?
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var working = false
    @State private var localBackups: [URL] = []
    @State private var confirmReplace = false

    static var backupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Backups", isDirectory: true)
    }

    var body: some View {
        Form {
            Section {
                Button { exportBackup() } label: {
                    HStack { Label("Export backup", systemImage: "square.and.arrow.up"); Spacer(); if working { ProgressView() } }
                }
                .disabled(working)
                .accessibilityIdentifier("backup.export")
            } header: { Text("Export") } footer: {
                Text("Creates one file with all records, photos and documents (format v\(BackupArchive.currentVersion)). A copy is kept in Files › On My iPhone › HomeLedger › Backups. The file isn't encrypted — store it somewhere private.")
            }

            Section {
                Button { showImporter = true } label: { Label("Restore from a file…", systemImage: "square.and.arrow.down") }
                ForEach(localBackups, id: \.self) { url in
                    Button { validate(url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.deletingPathExtension().lastPathComponent).foregroundStyle(Theme.ink)
                            Text(fileInfo(url)).font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .accessibilityIdentifier("backup.local.\(url.lastPathComponent)")
                }
                .onDelete { idx in
                    for i in idx { try? FileManager.default.removeItem(at: localBackups[i]) }
                    loadLocal()
                }
            } header: { Text("Restore") } footer: {
                Text("The file is checked before anything changes. You can merge it with your current data or replace everything.")
            }

            if let resultMessage {
                Section { Label(resultMessage, systemImage: "checkmark.circle").accessibilityIdentifier("backup.result") }
            }
        }
        .navigationTitle("Back up & restore")
        .onAppear(perform: loadLocal)
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { validate(url) } else if case .failure(let e) = result { errorMessage = e.localizedDescription }
        }
        .confirmationDialog(pending.map { "Restore backup from \($0.archive.createdAt.formatted(date: .abbreviated, time: .shortened))?" } ?? "",
                            isPresented: Binding(get: { pending != nil && !confirmReplace }, set: { if !$0 && !confirmReplace { pending = nil } }), titleVisibility: .visible) {
            Button("Merge with current data") { restore(.merge) }
                .accessibilityIdentifier("backup.merge")
            Button("Replace all current data…", role: .destructive) { confirmReplace = true }
                .accessibilityIdentifier("backup.replace")
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let p = pending { Text(([p.summary] + p.warnings).joined(separator: "\n")) }
        }
        .alert("Replace everything?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) { restore(.replace) }
                .accessibilityIdentifier("backup.confirmReplace")
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("All current data on this iPhone will be replaced by the backup. A safety backup of your current data is saved first in Files › HomeLedger › Safety Backups.")
        }
        .alert("Backup problem", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func fileInfo(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attrs?[.modificationDate] as? Date)?.formatted(date: .abbreviated, time: .shortened) ?? ""
        return "\(date) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
    }

    private func loadLocal() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        localBackups = urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func exportBackup() {
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let data = try BackupService(context: context).exportData()
                let name = BackupService.suggestedFileName()
                try FileManager.default.createDirectory(at: Self.backupDirectory, withIntermediateDirectories: true)
                var localName = name
                var n = 2
                while FileManager.default.fileExists(atPath: Self.backupDirectory.appendingPathComponent(localName).path) {
                    localName = name.replacingOccurrences(of: ".json", with: " (\(n)).json"); n += 1
                }
                let local = Self.backupDirectory.appendingPathComponent(localName)
                try data.write(to: local, options: [.atomic, .completeFileProtection])
                loadLocal()
                resultMessage = "Backup saved (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))."
                if !app.launch.isUITesting { shareItem = ShareableFile(url: local) }
            } catch {
                errorMessage = "The backup couldn't be created: \(error.localizedDescription)"
            }
        }
    }

    private func validate(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pending = try BackupService.validate(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ mode: RestoreMode) {
        guard let archive = pending?.archive else { return }
        defer { pending = nil; confirmReplace = false }
        do {
            let report = try BackupService(context: context).restore(archive, mode: mode)
            app.selectedHomeID = nil
            app.syncReminders(context)
            resultMessage = "Restored: \(report.inserted) added, \(report.updated) updated, \(report.skipped) unchanged, \(report.filesRestored) files." + (report.safetyBackupURL != nil ? " A safety backup was saved first." : "")
            UserDefaults.standard.set(true, forKey: Preferences.onboardingCompleteKey)
        } catch {
            errorMessage = "The restore didn't complete and your current data was left unchanged. (\(error.localizedDescription))"
        }
    }
}

// MARK: - Privacy & help

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Stored on this iPhone") {
                Text("Homes, rooms, items, photos, documents, recognized text, maintenance, repairs and expenses are stored only in HomeLedger's private storage on this iPhone, protected by iOS Data Protection when your device is locked.")
            }
            Section("What leaves your device") {
                Text("Nothing, unless you choose to share or export a report or backup. HomeLedger has no account, no analytics and no advertising SDKs.")
                Text("Purchases are handled by Apple through the App Store; HomeLedger only learns whether Premium is active.")
            }
            Section("Text recognition") {
                Text("Document text is read on-device with Apple's Vision framework. Documents are never sent to an AI service.")
            }
            Section("iCloud & sharing") {
                Text("HomeLedger doesn't sync with iCloud yet. Your iPhone's own iCloud or computer backup may include HomeLedger's data as part of a normal device backup. Use Back up & restore to move data to a new device.")
            }
            Section("Deleting your data") {
                Text("Delete individual records anytime, or use Settings › Delete all data. Deleting the app also removes its data from this iPhone.")
            }
        }
        .navigationTitle("Privacy")
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section("Getting started") {
                Label("Add items with the + button. Only a name is required.", systemImage: "plus.circle")
                Label("Scan receipts from Documents. Check the extracted details before saving.", systemImage: "doc.viewfinder")
                Label("Use maintenance suggestions as a starting point, then adjust the schedule.", systemImage: "calendar")
            }
            Section("Warranties") {
                Label("Status is based only on the end date you record. Unknown means no date was entered.", systemImage: "checkmark.shield")
                Label("“Estimated” dates were calculated from a stated coverage length — confirm them with the warranty terms.", systemImage: "questionmark.circle")
            }
            Section("Recurring tasks") {
                Label("Fixed schedule: the next date stays on the calendar rhythm (e.g. every 1st of the quarter).", systemImage: "calendar.badge.clock")
                Label("Count from completion: the next date is one interval after you complete it.", systemImage: "checkmark.circle")
            }
            Section("Reports") {
                Label("Inventory reports are personal records, not appraisals or proof of coverage.", systemImage: "doc.richtext")
            }
        }
        .navigationTitle("Help")
    }
}
