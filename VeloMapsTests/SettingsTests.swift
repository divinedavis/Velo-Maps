import Testing
import Foundation
@testable import VeloMaps

/// The settings card and report buttons must actually do something (owner, 11/8: "none of
/// the buttons work").
@Suite("Settings and buttons")
@MainActor
struct SettingsTests {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let d = UserDefaults(suiteName: "velo-tests-\(UUID())")!
        values.forEach { d.set($0.value, forKey: $0.key) }
        return d
    }

    @Test func voiceSpeaksTheTurnWhenItsBannerAppears() {
        let trip = Trip(defaults: defaults(["turnAhead": "200"]))
        var said: [String] = []
        trip.speak = { said.append($0.fallback) }
        trip.advance(by: 12)                       // 108 m at 9 m/s: now inside the 108 m window
        #expect(trip.bannerManeuver != nil)
        #expect(said.contains { $0.hasPrefix("In ") && $0.hasSuffix("turn left onto W 96 St") }, "said: \(said)")
    }

    @Test func voiceOffStaysQuiet() {
        let trip = Trip(defaults: defaults(["turnAhead": "200", SettingKey.voice: false]))
        var said: [String] = []
        trip.speak = { said.append($0.fallback) }
        trip.advance(by: 12)
        #expect(trip.bannerManeuver != nil)
        #expect(said.isEmpty)
    }

    @Test func stopAlertOneStopBefore() {
        // Past CPW / W 96 St, the next stop is the rider's (Columbus Av / W 96 St).
        let trip = Trip(defaults: defaults(["turnPassed": "30"]))
        #expect(trip.announcement?.text == "Your stop is next: Columbus Av / W 96 St")
    }

    @Test func stopAlertOffAndAtMyStop() {
        #expect(Trip(defaults: defaults(["turnPassed": "30", SettingKey.stopAlert: "Off"])).announcement == nil)
        #expect(Trip(defaults: defaults(["turnPassed": "30", SettingKey.stopAlert: "At my stop"])).announcement == nil)
        let near = Trip(defaults: defaults(["progress": "0.99", SettingKey.stopAlert: "At my stop"]))
        #expect(near.announcement?.text.hasPrefix("Arriving at your stop") == true)
    }

    @Test func reportsDropMarkersAndEndWalkReturnsToTheRide() {
        let trip = Trip(defaults: defaults(["progress": "0.3"]))
        trip.report(.police)
        trip.report(.closure)
        #expect(trip.reports.map(\.kind) == [.police, .closure])
        trip.endRide()
        #expect(trip.walking)
        trip.endWalk()
        #expect(!trip.walking && trip.progress == 0)
    }

    @Test func shareTextSaysWhereAndWhen() {
        let text = Trip(defaults: defaults([:])).shareText
        #expect(text.contains("on the M10 to Columbus Av / W 96 St"))
        #expect(text.contains("min away"))
    }

    @Test(arguments: [("Auto", false, nil), ("Day", false, .light), ("Night", false, .dark), ("Day", true, .dark)] as [(String, Bool, ColorSchemeTag?)])
    func appearanceSetting(_ setting: String, _ forced: Bool, _ expected: ColorSchemeTag?) {
        #expect(resolvedScheme(appearance: setting, forcedNight: forced).map(ColorSchemeTag.init) == expected)
    }
}

/// ColorScheme isn't Sendable-friendly as a test argument; compare by tag.
enum ColorSchemeTag: Sendable, Equatable {
    case light, dark
    init(_ s: SwiftUI.ColorScheme) { self = s == .dark ? .dark : .light }
}

import SwiftUI
