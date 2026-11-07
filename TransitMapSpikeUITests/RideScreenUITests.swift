import XCTest

final class RideScreenUITests: XCTestCase {
    /// The ride screen shows the map, the trip card with its stop list, and the hold button.
    func testRideScreenShowsMapCardAndHoldButton() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES"]
        app.launch()

        XCTAssertTrue(app.otherElements["transit-map"].waitForExistence(timeout: 10) || app.maps.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["trip-destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CPW / W 77 St"].exists, "next stop missing from the card")
        XCTAssertTrue(app.descendants(matching: .any)["hold-to-end"].exists)
    }
}
