import XCTest

/// Launch speed (quality gate 3). Numbers land in the .xcresult; scripts/perf_gate.py fails
/// a ship whose median is >1.5x the median of the last 5 passing ships. Simulator numbers
/// catch regressions, not real-world times — those come from MetricKit (Metrics.swift).
final class PerformanceTests: XCTestCase {
    func testLaunch() throws {
        let opts = XCTMeasureOptions(); opts.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: opts) {
            let app = XCUIApplication(); app.launchArguments = ["-paused", "YES"]
            app.launch()
        }
    }

    /// Launch until the ride card shows the next stop: the wait a rider actually sees.
    func testLaunchToRideReady() throws {
        let app = XCUIApplication(); app.launchArguments = ["-paused", "YES"]
        let opts = XCTMeasureOptions(); opts.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: opts) {
            app.launch()
            XCTAssertTrue(app.staticTexts["next-stop"].waitForExistence(timeout: 30))
            app.terminate()
        }
    }
}
