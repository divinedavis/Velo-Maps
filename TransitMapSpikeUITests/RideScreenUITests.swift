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

    /// Swiping the ride card up reveals navigation settings.
    func testSwipeUpCardShowsNavigationSettings() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES"]
        app.launch()

        let next = app.staticTexts["next-stop"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["nav-settings"].exists)
        // A finger-speed drag up from the card (XCUITest's swipeUp is a very fast flick).
        let start = next.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)))
        XCTAssertTrue(app.staticTexts["nav-settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Voice guidance"].exists)
    }

    /// The pothole button opens the report sheet; reporting closes it and confirms.
    func testPotholeButtonReportsAndConfirms() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES"]
        app.launch()

        let button = app.buttons["report-pothole"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        let send = app.buttons["send-pothole-report"]
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        send.tap()
        XCTAssertTrue(app.staticTexts["Pothole reported. Thanks!"].waitForExistence(timeout: 3))
    }

    /// The "+" button opens the report menu (police, accident, …) and confirms a report.
    func testPlusMenuReportsPolice() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["report-pothole"].waitForExistence(timeout: 10), "pothole button should stay separate")
        let plus = app.buttons["report-menu"]
        XCTAssertTrue(plus.exists)
        plus.tap()
        let police = app.buttons["report-Police"]
        XCTAssertTrue(police.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["report-Accident"].exists)
        police.tap()
        XCTAssertTrue(app.staticTexts["Police reported. Thanks!"].waitForExistence(timeout: 3))
    }
}
