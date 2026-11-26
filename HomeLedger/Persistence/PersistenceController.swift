import Foundation
import SwiftData

enum PersistenceError: LocalizedError {
    case storeUnavailable(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable(let error):
            "HomeLedger couldn't open its database (\(error.localizedDescription))."
        }
    }
}

/// Creates the SwiftData container. Failures are surfaced to the UI instead of silently resetting.
enum PersistenceController {
    static var schema: Schema { Schema(versionedSchema: HomeLedgerSchemaV1.self) }

    static var storeDirectory: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("HomeLedger/Store", isDirectory: true)
    }

    static var storeURL: URL { storeDirectory.appendingPathComponent("HomeLedger.store") }

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let target = url ?? storeURL
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            configuration = ModelConfiguration(schema: schema, url: target, cloudKitDatabase: .none)
        }
        do {
            return try ModelContainer(for: schema, migrationPlan: HomeLedgerMigrationPlan.self, configurations: [configuration])
        } catch {
            throw PersistenceError.storeUnavailable(underlying: error)
        }
    }

    /// Moves an unreadable store aside (never deletes it) so the user can start fresh while
    /// keeping the old files for recovery or support.
    @discardableResult
    static func moveStoreAside() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let destination = storeDirectory.deletingLastPathComponent().appendingPathComponent("Store-recovered-\(stamp)", isDirectory: true)
        try FileManager.default.moveItem(at: storeDirectory, to: destination)
        return destination
    }

    /// Used only by UI tests and screenshot automation (`-ResetData`).
    static func resetForTesting() {
        try? FileManager.default.removeItem(at: storeDirectory)
        FileStore.shared.deleteAll()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}
