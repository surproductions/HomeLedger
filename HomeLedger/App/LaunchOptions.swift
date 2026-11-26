import Foundation
import UIKit

/// Launch arguments used by UI tests and screenshot automation only.
/// None of these unlock purchases or alter entitlement logic.
struct LaunchOptions {
    let isUITesting: Bool
    let resetData: Bool
    let seedSampleData: Bool
    let startScreen: String?

    static let current: LaunchOptions = {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        return LaunchOptions(isUITesting: args.contains("-UITesting"),
                             resetData: args.contains("-ResetData"),
                             seedSampleData: args.contains("-SeedSampleData"),
                             startScreen: value(after: "-StartScreen"))
    }()

    func applyBeforeLaunch() {
        guard isUITesting else { return }
        if resetData { PersistenceController.resetForTesting() }
        UIView.setAnimationsEnabled(false)
        // Avoid system permission alerts interrupting automated tests.
        UserDefaults.standard.set(false, forKey: Preferences.notificationsEnabledKey)
    }
}
