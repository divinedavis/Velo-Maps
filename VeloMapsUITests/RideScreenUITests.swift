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

    /// Pothole lives in the "+" menu (first item) and reports straight away, no form.
    func testPotholeIsReportedFromThePlusMenu() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES", "-progress", "0.25"]
        app.launch()

        // At 25% a demo report from another rider is ~140 m ahead: the alert is up.
        let ahead = app.descendants(matching: .any)["pothole-ahead"]
        XCTAssertTrue(ahead.waitForExistence(timeout: 10))
        XCTAssertTrue(ahead.label.hasPrefix("Pothole ahead"), "alert label was: \(ahead.label)")
        XCTAssertFalse(app.buttons["report-pothole"].exists, "Pothole should no longer be a separate button")
        let plus = app.buttons["report-menu"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        let pothole = app.buttons["report-Pothole"]
        XCTAssertTrue(pothole.waitForExistence(timeout: 3))
        pothole.tap()
        XCTAssertTrue(app.staticTexts["Pothole reported for all riders"].waitForExistence(timeout: 3))
    }

    /// Approaching the turn shows the turn banner with the street name.
    func testTurnBannerShowsUpcomingTurn() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES", "-turnAhead", "120", "-turnStyle", "1"]
        app.launch()

        let banner = app.descendants(matching: .any)["turn-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.label.contains("W 96 St"), "banner label was: \(banner.label)")
    }

    /// The "+" button opens the report menu (police, accident, …) and confirms a report.
    func testPlusMenuReportsPolice() {
        let app = XCUIApplication()
        app.launchArguments += ["-paused", "YES"]
        app.launch()

        let plus = app.buttons["report-menu"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        let police = app.buttons["report-Police"]
        XCTAssertTrue(police.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["report-Accident"].exists)
        // The open menu must sit entirely above the trip card, never over it.
        let card = app.descendants(matching: .any)["trip-card"]
        let lowestItem = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'report-' AND identifier != 'report-menu' AND identifier != 'report-toast'"))
            .allElementsBoundByIndex.max { $0.frame.maxY < $1.frame.maxY }!
        XCTAssertLessThan(lowestItem.frame.maxY, card.frame.minY, "report menu overlaps the trip card")
        XCTAssertLessThan(lowestItem.frame.maxY, plus.frame.minY, "report menu covers the + / × button")
        // ...and its top item must be below the turn banner, not hidden under it.
        let banner = app.descendants(matching: .any)["turn-banner"]
        if banner.exists {
            XCTAssertGreaterThanOrEqual(app.buttons["report-Pothole"].frame.minY, banner.frame.maxY, "report menu runs under the turn banner")
        }
        police.tap()
        XCTAssertTrue(app.staticTexts["Police reported. Thanks!"].waitForExistence(timeout: 3))
    }

    /// Highway ramps show the sign's own wording (from OpenStreetMap), entrance and exit.
    func testHighwaySignsUseTheExactSignWording() {
        for (index, expected) in [(0, "Highway sign: NY 9A North, Henry Hudson Parkway"), (1, "Highway sign: West 96th Street")] {
            let app = XCUIApplication()
            app.launchArguments += ["-paused", "YES", "-demo", "drive", "-signAhead", "60", "-signIndex", "\(index)"]
            app.launch()
            let sign = app.descendants(matching: .any)["highway-sign"]
            XCTAssertTrue(sign.waitForExistence(timeout: 10), "no highway sign before ramp \(index)")
            XCTAssertEqual(sign.label, expected)
            app.terminate()
        }
    }

    /// The road the vehicle is on shows above the card and follows the route.
    func testCurrentRoadLabelFollowsTheRoute() {
        for (args, expected) in [(["-progress", "0.25"], "Now on Central Park West"),
                                 (["-demo", "drive", "-progress", "0.6"], "Now on Henry Hudson Parkway")] {
            let app = XCUIApplication()
            app.launchArguments += ["-paused", "YES"] + args
            app.launch()
            let road = app.descendants(matching: .any)["current-road"]
            XCTAssertTrue(road.waitForExistence(timeout: 10))
            XCTAssertEqual(road.label, expected)
            let card = app.descendants(matching: .any)["trip-card"]
            XCTAssertLessThanOrEqual(road.frame.maxY, card.frame.minY, "road label must sit above the card")
            app.terminate()
        }
    }
}
