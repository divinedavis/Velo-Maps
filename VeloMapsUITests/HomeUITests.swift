import XCTest

/// The real app: "Where to?" → pick a place → route preview → Start → live navigation.
/// Uses a fixed test location (no permission prompt) and the network for search + routing.
final class HomeUITests: XCTestCase {
    func testSearchPreviewAndStartNavigation() {
        let app = XCUIApplication()
        app.launchArguments += ["-mockLocation", "40.7836,-73.9800", "-resetSettings", "YES"]
        app.launch()

        let field = app.textFields["where-to"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "home screen should open on Where to?")
        XCTAssertFalse(app.descendants(matching: .any)["trip-card"].exists, "no demo ride on launch")
        field.tap()
        field.typeText("Symphony Space")
        let result = app.buttons["search-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no search results")
        result.tap()

        let start = app.buttons["start-navigation"]
        XCTAssertTrue(start.waitForExistence(timeout: 25), "no route preview")
        XCTAssertTrue(app.descendants(matching: .any)["route-preview"].exists)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trip-card"].waitForExistence(timeout: 10), "navigation did not start")
    }
}
