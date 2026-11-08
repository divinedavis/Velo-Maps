import XCTest

final class RideScreenUITests: XCTestCase {
    /// The ride screen (Hero card) shows the map, destination, next stop, and the hold button.
    func testRideScreenShowsMapCardAndHoldButton() {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "bus", "-paused", "YES"]
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
        app.launchArguments += ["-demo", "bus", "-paused", "YES", "-mode", "walk", "-walkStyle", "2"]
        app.launch()

        XCTAssertTrue(app.staticTexts["You're off the M10"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start walking"].exists)
    }

    /// Swiping the ride card up reveals navigation settings.
    func testSwipeUpCardShowsNavigationSettings() {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "bus", "-paused", "YES"]
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
        app.launchArguments += ["-demo", "bus", "-paused", "YES", "-progress", "0.25", "-resetSettings", "YES"]
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
        app.launchArguments += ["-demo", "bus", "-paused", "YES", "-turnAhead", "60", "-turnStyle", "1"]
        app.launch()

        let banner = app.descendants(matching: .any)["turn-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.label.contains("W 96 St"), "banner label was: \(banner.label)")
    }

    /// The "+" button opens the report menu (police, accident, …) and confirms a report.
    func testPlusMenuReportsPolice() {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "bus", "-paused", "YES"]
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
        // ...it must stay on the right edge, clear of the road and the vehicle (owner, 11/7)...
        let width = app.windows.firstMatch.frame.width
        for id in ["report-Pothole", "report-Police", "report-Accident", "report-Road closed"] {
            // The vehicle and its lane sit at the centre of the screen.
            XCTAssertGreaterThan(app.buttons[id].frame.minX, width * 0.6, "\(id) reaches into the road")
            XCTAssertLessThanOrEqual(app.buttons[id].frame.maxX, width, "\(id) runs off the screen")
        }
        XCTAssertFalse(app.buttons["report-Heavy traffic"].exists || app.buttons["report-Hazard"].exists
                       || app.buttons["report-Crowded bus"].exists, "removed report types are back")
        // ...and its top item must be below the turn banner, not hidden under it.
        let banner = app.descendants(matching: .any)["turn-banner"]
        if banner.exists {
            XCTAssertGreaterThanOrEqual(app.buttons["report-Pothole"].frame.minY, banner.frame.maxY, "report menu runs under the turn banner")
        }
        police.tap()
        XCTAssertTrue(app.staticTexts["Police reported for all riders"].waitForExistence(timeout: 3))
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
            app.launchArguments += ["-demo", "bus", "-paused", "YES"] + args
            app.launch()
            let road = app.descendants(matching: .any)["current-road"]
            XCTAssertTrue(road.waitForExistence(timeout: 10))
            XCTAssertEqual(road.label, expected)
            let card = app.descendants(matching: .any)["trip-card"]
            XCTAssertLessThanOrEqual(road.frame.maxY, card.frame.minY, "road label must sit above the card")
            app.terminate()
        }
    }

    /// The turn banner only appears within ~12 s of a city turn at the current speed, and
    /// goes away once the turn is made (owner, 11/7).
    func testTurnBannerIsTimedByDistanceAndSpeed() {
        let cases: [([String], Bool, String)] = [
            (["-turnAhead", "400"], false, "400 m out at 9 m/s is too early"),
            (["-turnAhead", "60"], true, "60 m out is inside the window"),
            (["-turnAhead", "200", "-speed", "20"], true, "faster driving opens the window earlier"),
            (["-turnPassed", "30"], false, "after the turn the banner goes away"),
        ]
        for (args, visible, why) in cases {
            let app = XCUIApplication()
            app.launchArguments += ["-demo", "bus", "-paused", "YES"] + args
            app.launch()
            XCTAssertTrue(app.staticTexts["next-stop"].waitForExistence(timeout: 10))
            let banner = app.descendants(matching: .any)["turn-banner"]
            if visible {
                XCTAssertTrue(banner.waitForExistence(timeout: 3), why)
            } else {
                XCTAssertFalse(banner.waitForExistence(timeout: 2), why)
            }
            app.terminate()
        }
    }

    /// Turning off "Show reported potholes" removes the Pothole-ahead alert.
    func testShowReportedPotholesToggleWorks() {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "bus", "-paused", "YES", "-progress", "0.25", "-resetSettings", "YES"]
        app.launch()
        let ahead = app.descendants(matching: .any)["pothole-ahead"]
        XCTAssertTrue(ahead.waitForExistence(timeout: 10))
        let grabber = app.descendants(matching: .any)["card-grabber"]
        grabber.tap()
        let toggle = app.switches["setting-potholes"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        grabber.tap()
        XCTAssertFalse(ahead.waitForExistence(timeout: 2), "alert should be gone with the setting off")
        app.terminate()
        // Leave the simulator on default settings for other tests.
        let reset = XCUIApplication(); reset.launchArguments += ["-demo", "bus", "-paused", "YES", "-resetSettings", "YES"]; reset.launch(); reset.terminate()
    }

    /// The walking screen's End returns to the ride.
    func testEndWalkReturnsToTheRide() {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "bus", "-paused", "YES", "-mode", "walk"]
        app.launch()
        let end = app.buttons["end-walk"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        XCTAssertTrue(app.staticTexts["next-stop"].waitForExistence(timeout: 5))
    }

    /// Share trip progress opens the iPhone share sheet.
    func testShareTripProgressOpensTheShareSheet() {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "bus", "-paused", "YES", "-expanded", "YES"]
        app.launch()
        let share = app.buttons["share-trip"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)
                      || app.buttons["Copy"].waitForExistence(timeout: 2), "share sheet did not open")
    }

    /// The posted speed limit shows top-left under the turn banner (25 on CPW, 50 on the parkway).
    func testSpeedLimitShowsThePostedLimit() {
        for (args, expected) in [(["-demo", "bus", "-progress", "0.25"], "Speed limit 25 miles per hour"),
                                 (["-demo", "drive", "-progress", "0.6"], "Speed limit 50 miles per hour")] {
            let app = XCUIApplication()
            app.launchArguments += args + ["-paused", "YES", "-speedStyle", "1"]
            app.launch()
            let sign = app.descendants(matching: .any)["speed-limit"]
            XCTAssertTrue(sign.waitForExistence(timeout: 10))
            XCTAssertEqual(sign.label, expected)
            XCTAssertLessThan(sign.frame.midX, app.windows.firstMatch.frame.width / 2, "should be on the left")
            app.terminate()
        }
    }

    /// The speed-limit sign stays put whether or not a turn banner is showing (owner, 11/8).
    func testSpeedLimitSignDoesNotMoveWithTheBanner() {
        var tops: [CGFloat] = []
        for args in [["-turnAhead", "60"], ["-turnAhead", "600"], ["-demo", "drive", "-signAhead", "60", "-signIndex", "1"]] {
            let app = XCUIApplication()
            app.launchArguments += ["-demo", "bus", "-paused", "YES"] + args
            app.launch()
            let sign = app.descendants(matching: .any)["speed-limit"]
            XCTAssertTrue(sign.waitForExistence(timeout: 10))
            let banner = app.descendants(matching: .any)["turn-banner"]
            if banner.exists { XCTAssertGreaterThanOrEqual(sign.frame.minY, banner.frame.maxY, "sign under the banner") }
            tops.append(sign.frame.minY)
            app.terminate()
        }
        XCTAssertEqual(Set(tops.map { Int($0.rounded()) }).count, 1, "sign moved: \(tops)")
    }
}
