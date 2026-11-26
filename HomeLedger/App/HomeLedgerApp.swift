import SwiftData
import SwiftUI

@main
struct HomeLedgerApp: App {
    @State private var app = AppModel()

    init() {
        LaunchOptions.current.applyBeforeLaunch()
        ExportFiles.cleanUp()
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environment(app)
                .tint(Theme.brand)
        }
    }
}

/// Opens the database. If it can't be opened, shows a recovery screen instead of discarding data.
struct AppBootstrapView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.appearanceKey) private var appearance: String = AppearanceMode.system.rawValue
    @State private var container: ModelContainer?
    @State private var loadError: Error?
    @State private var recoveryMessage: String?

    var body: some View {
        Group {
            if let container {
                RootView()
                    .modelContainer(container)
            } else if let loadError {
                StoreRecoveryView(error: loadError, message: recoveryMessage, retry: load, startFresh: startFresh)
            } else {
                LaunchView()
            }
        }
        .task { if container == nil && loadError == nil { load() } }
        .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
    }

    private func load() {
        do {
            let c = try PersistenceController.makeContainer()
            if LaunchOptions.current.seedSampleData {
                let context = c.mainContext
                if (try? context.fetchCount(FetchDescriptor<Home>())) == 0 {
                    SampleDataService(context: context).seed()
                }
                UserDefaults.standard.set(true, forKey: Preferences.onboardingCompleteKey)
            }
            container = c
            loadError = nil
        } catch {
            loadError = error
        }
    }

    private func startFresh() {
        do {
            let moved = try PersistenceController.moveStoreAside()
            recoveryMessage = "Your previous data was kept at \(moved.lastPathComponent) for recovery."
            load()
        } catch {
            recoveryMessage = "Couldn't move the old data: \(error.localizedDescription)"
        }
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 14) {
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                Text("HomeLedger").font(.title2.weight(.semibold)).foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct StoreRecoveryView: View {
    let error: Error
    let message: String?
    let retry: () -> Void
    let startFresh: () -> Void
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            IconBadge(systemName: "externaldrive.badge.exclamationmark", tint: Theme.warning, size: 64)
            Text("HomeLedger couldn't open your data").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text("Nothing has been deleted. Try again first — if the problem continues you can set the damaged data aside and start fresh. The old files are kept on this iPhone.")
                .font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            Text(error.localizedDescription).font(.caption).foregroundStyle(Theme.inkTertiary).multilineTextAlignment(.center)
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.ink).multilineTextAlignment(.center) }
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
            Button("Set data aside and start fresh") { confirm = true }.foregroundStyle(Theme.danger)
            Spacer()
        }
        .padding(24)
        .canvasBackground()
        .confirmationDialog("Start fresh?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Set aside and start fresh", role: .destructive, action: startFresh)
        } message: {
            Text("Your current data will be moved to a recovery folder, not deleted. You can restore from a backup afterwards.")
        }
    }
}
