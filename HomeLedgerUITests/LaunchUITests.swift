import XCTest

final class LaunchUITests: XCTestCase {
    func testLaunchShowsOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ResetData"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 15))
    }
}
