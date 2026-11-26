import Foundation
import SwiftData
import UIKit
import UserNotifications
import XCTest
@testable import HomeLedger

@MainActor
class HomeLedgerTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var files: FileStore!
    var filesDirectory: URL!

    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        filesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("HLTests-\(UUID().uuidString)", isDirectory: true)
        files = FileStore(baseURL: filesDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: filesDirectory)
        context = nil
        container = nil
        try await super.tearDown()
    }

    var service: DataService { DataService(context: context, files: files) }

    func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    @discardableResult
    func makeHome(_ name: String = "Test Home", rooms: [String] = ["Kitchen", "Garage"]) -> Home {
        service.createHome(name: name, type: .house, roomNames: rooms.map { ($0, "square") })
    }

    @discardableResult
    func makeAsset(_ name: String, in home: Home, room: Room? = nil, category: AssetCategory = .appliance) -> Asset {
        let asset = Asset(name: name, category: category, home: home, room: room)
        context.insert(asset)
        return asset
    }

    func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }
}

/// Records what NotificationService asks the system to do.
final class MockNotificationCenter: NotificationCenterClient {
    var pending: [String] = []
    var added: [PlannedReminder] = []
    var removed: [String] = []
    var status: UNAuthorizationStatus = .authorized

    func pendingIdentifiers() async -> [String] { pending }
    func removePending(identifiers: [String]) {
        removed.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0) }
    }
    func add(_ reminder: PlannedReminder, calendar: Calendar) async throws {
        added.append(reminder)
        pending.append(reminder.identifier)
    }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { status == .authorized }
}

