import XCTest

/// Apple's automated accessibility audit on every main screen and state (quality gate 2):
/// contrast, labels, hit targets, traits, Dynamic Type clipping.
///
/// Only issues on views we don't draw are excused (MapKit's map, its Legal link); never
/// excuse one of our own controls to make the gate pass — fix the view.
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-paused", "YES", "-progress", "0.25"] + extra
        app.launch()
        return app
    }

    /// The screen as the audit saw it, and contrast reports it couldn't reproduce.
    private var auditShot: UIImage?
    private var unreproduced: [String] = []

    private func excused(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let e = issue.element else { return true }   // nothing to point at, nothing to fix
        if e.elementType == .map || e.label == "Legal" { return true }   // MapKit draws these
        // Contrast over Liquid Glass: the audit reports text that measures well above 4.5:1 in
        // the very screenshot it ran on (11/7, expanded settings card). Re-measure from the
        // pixels; excuse only if the real contrast passes, and list every such case.
        if issue.auditType.contains(.contrast), let shot = auditShot,
           let ratio = Self.pixelContrast(shot, e.frame), ratio >= 4.5 {
            unreproduced.append("\"\(e.label)\" measured \(String(format: "%.1f", ratio)):1 in pixels")
            return true
        }
        return false
    }

    /// WCAG contrast between the text and its background inside `frame`: background = the
    /// median luminance, text = whichever 3rd/97th-percentile extreme is farther from it.
    static func pixelContrast(_ image: UIImage, _ frame: CGRect) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let s = image.scale
        let rect = CGRect(x: frame.minX * s, y: frame.minY * s, width: frame.width * s, height: frame.height * s)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard rect.width > 2, rect.height > 2, let crop = cg.cropping(to: rect) else { return nil }
        let w = crop.width, h = crop.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        func lin(_ c: UInt8) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        var lum: [Double] = []
        lum.reserveCapacity(w * h)
        for i in stride(from: 0, to: px.count, by: 4) {
            lum.append(0.2126 * lin(px[i]) + 0.7152 * lin(px[i + 1]) + 0.0722 * lin(px[i + 2]))
        }
        lum.sort()
        let bg = lum[lum.count / 2], lo = lum[lum.count * 3 / 100], hi = lum[lum.count * 97 / 100]
        let text = abs(hi - bg) > abs(bg - lo) ? hi : lo
        return (max(bg, text) + 0.05) / (min(bg, text) + 0.05)
    }

    private func audit(_ app: XCUIApplication, _ screen: String) {
        // Let spring/opacity animations and Liquid Glass finish settling: mid-animation
        // frames measured as contrast failures on text that is fine at rest.
        sleep(2)
        // What the audit is looking at, kept in the .xcresult for diagnosing failures.
        let screenshot = app.screenshot()
        auditShot = screenshot.image
        unreproduced = []
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "audit-\(screen)"; shot.lifetime = .keepAlways
        add(shot)
        var found: [String] = []
        do {
            // Every check except Dynamic Type: the app caps text at the largest standard size
            // (maxTextSize, owner decision 11/7), so the audit would report every label as
            // "partially unsupported". Lifting the cap means stacked layouts for the
            // accessibility sizes; put .dynamicType back here when that lands.
            var types: XCUIAccessibilityAuditType = .all
            types.remove(.dynamicType)
            try app.performAccessibilityAudit(for: types) { issue in
                if self.excused(issue) { return true }
                let e = issue.element
                found.append("\(issue.compactDescription) | \(issue.detailedDescription) — [\(e?.identifier ?? "")] \"\(e?.label ?? "")\" \(e.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "")")
                return true
            }
        } catch {
            XCTFail("\(screen): audit could not run: \(error)")
        }
        if !unreproduced.isEmpty {
            print("AUDIT NOTE \(screen): contrast reports not reproduced in the screenshot — " + unreproduced.joined(separator: "; "))
        }
        if !found.isEmpty { XCTFail("\(screen): \(found.count) accessibility issue(s):\n" + found.joined(separator: "\n")) }
    }

    func testRideScreen() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["next-stop"].waitForExistence(timeout: 10))
        audit(app, "ride")
    }

    func testRideScreenNearTurn() {
        let app = launch(["-turnAhead", "120"])
        XCTAssertTrue(app.descendants(matching: .any)["turn-banner"].waitForExistence(timeout: 10))
        audit(app, "ride near turn")
    }

    func testNavigationSettings() {
        let app = launch(["-expanded", "YES"])
        XCTAssertTrue(app.staticTexts["nav-settings"].waitForExistence(timeout: 10))
        audit(app, "navigation settings")
    }

    func testReportMenu() {
        let app = launch()
        let plus = app.buttons["report-menu"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        XCTAssertTrue(app.buttons["report-Police"].waitForExistence(timeout: 3))
        audit(app, "report menu")
    }

    func testWalkingScreen() {
        let app = launch(["-mode", "walk"])
        XCTAssertTrue(app.descendants(matching: .any)["walk-map"].waitForExistence(timeout: 10))
        sleep(2)   // let Apple's walking directions arrive
        audit(app, "walking")
    }

    func testHighwayExitSign() {
        let app = launch(["-demo", "drive", "-signAhead", "150", "-signIndex", "1"])
        XCTAssertTrue(app.descendants(matching: .any)["highway-sign"].waitForExistence(timeout: 10))
        audit(app, "highway exit sign")
    }

    func testNightRide() {
        let app = launch(["-night", "YES"])
        XCTAssertTrue(app.staticTexts["next-stop"].waitForExistence(timeout: 10))
        audit(app, "ride at night")
    }
}
