import XCTest
@testable import HomeLedger

final class SmokeTests: XCTestCase {
    func testMoneyRoundTrip() {
        XCTAssertEqual(Money.cents(from: Decimal(string: "12.345")!), 1235)
    }
}
