import XCTest

final class RideScreenUITests: XCTestCase {
    /// The ride screen (Hero card) shows the map, destination, next stop, and the hold button.
    func testRideScreenShowsMapCardAndHoldButton() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES"]
        app.launch()

        XCTAssertTrue(app.otherElements["transit-map"].waitForExistence(timeout: 10) || app.maps.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["trip-destination"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["next-stop"].label, "Next: CPW / W 77 St", "next stop missing from the card")
        // The glass button's texts surface separately (not as one "hold-to-end" element), so
        // accept either until VoiceOver support for the hold gesture is built.
        XCTAssertTrue(app.descendants(matching: .any)["hold-to-end"].exists || app.staticTexts["Hold to end ride"].exists)
    }

    /// Opening straight onto the walking handoff shows the drop-off and the walk offer.
    func testWalkHandoffOffersWalkingDirections() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES", "-mode", "walk", "-walkStyle", "2"]
        app.launch()

        XCTAssertTrue(app.staticTexts["You're off the M10"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start walking"].exists)
    }
}
