import XCTest

/// The real app: the Apple Maps-style sheet → pick a place → route preview → Start → live
/// navigation. Uses a fixed test location (no permission prompt) and the network for search
/// and routing.
final class HomeUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-mockLocation", "40.7836,-73.9800", "-resetSettings", "YES"] + extra
        app.launch()
        return app
    }

    func testSearchPreviewAndStartNavigation() {
        let app = launch()
        let field = app.textFields["where-to"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "home screen should open on Where to?")
        XCTAssertFalse(app.descendants(matching: .any)["trip-card"].exists, "no demo ride on launch")
        XCTAssertFalse(app.staticTexts["Turn on Location for Velo Maps in Settings to navigate."].exists)
        field.tap()
        field.typeText("Symphony Space")
        let result = app.buttons["search-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no search results")
        result.tap()

        let start = app.buttons["start-navigation"]
        XCTAssertTrue(start.waitForExistence(timeout: 25), "no route preview")
        XCTAssertTrue(app.descendants(matching: .any)["route-preview"].exists)
        // Start is on screen on the half sheet, not pushed below it by a Look Around image (11/22).
        XCTAssertTrue(start.isHittable, "Start should be visible without dragging the sheet up")
        XCTAssertFalse(app.descendants(matching: .any)["look-around"].exists)
        // The search is remembered under Recents.
        app.buttons["cancel-preview"].tap()
        XCTAssertTrue(app.buttons["recent-row"].firstMatch.waitForExistence(timeout: 5), "search not in Recents")
        app.buttons["recent-row"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 25), "recent did not route")
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip-card"].waitForExistence(timeout: 10), "navigation did not start")
    }

    func testPlacesRowRoutesHome() {
        let app = launch(["-demoPlaces", "YES"])
        let home = app.buttons["place-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "no Places row")
        XCTAssertTrue(app.buttons["place-work"].exists)
        XCTAssertTrue(app.buttons["place-pinned"].exists)
        home.tap()
        XCTAssertTrue(app.buttons["start-navigation"].waitForExistence(timeout: 25), "Home did not route")
        XCTAssertTrue(app.buttons["save-place"].exists)
    }

    func testSettingHomeFromSearch() {
        let app = launch()
        let home = app.buttons["place-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertEqual(home.label, "Add Home")
        home.tap()
        XCTAssertTrue(app.staticTexts["picking-hint"].waitForExistence(timeout: 5))
        app.textFields["where-to"].typeText("Symphony Space")
        let result = app.buttons["search-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no search results")
        result.tap()
        let set = NSPredicate(format: "label BEGINSWITH 'Home, '")
        expectation(for: set, evaluatedWith: home)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.buttons["start-navigation"].exists, "setting Home must not start a route")
    }

    func testMapModesSwitchToSatellite() {
        let app = launch()
        let modes = app.buttons["map-modes"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        modes.tap()
        let satellite = app.buttons["map-mode-satellite"]
        XCTAssertTrue(satellite.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map-mode-explore"].isSelected, "Explore is the default")
        satellite.tap()
        XCTAssertTrue(satellite.isSelected)
        XCTAssertTrue(app.switches["traffic-toggle"].exists)
        app.buttons["close-map-modes"].tap()
        XCTAssertTrue(app.buttons["toggle-3d"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["locate"].exists)
    }
}

/// The search screen before typing (owner, 11/9, from Apple Maps): categories, Recents with
/// the full list, Suggested Places.
final class SearchScreenUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-mockLocation", "40.7836,-73.9800", "-resetSettings", "YES", "-demoPlaces", "YES"]
        app.launch()
        return app
    }

    func testRecentsListGroupsAndClears() {
        let app = launch()
        let field = app.textFields["where-to"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.buttons["category-gas"].waitForExistence(timeout: 5), "no category buttons")
        XCTAssertTrue(app.buttons["recent-search"].firstMatch.exists)
        app.buttons["recents-all"].tap()
        XCTAssertTrue(app.staticTexts["This Week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This Month"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "recents-list-row").count, 3)
        app.buttons["Clear This Month"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "recents-list-row").count, 2)
        app.buttons["close-recents"].tap()
    }

    func testCategoryFindsNearbyPlacesAndRoutes() {
        let app = launch()
        let field = app.textFields["where-to"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        let coffee = app.buttons["category-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        coffee.tap()
        let result = app.buttons["category-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no coffee nearby")
        result.tap()
        XCTAssertTrue(app.buttons["start-navigation"].waitForExistence(timeout: 25), "category result did not route")
    }
}
