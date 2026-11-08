import Testing
import Foundation
import CoreLocation
@testable import VeloMaps

private final class BundleToken {}

/// Live navigation (owner, 11/8: "i have to test it in real time").
@Suite("Live navigation")
@MainActor
struct LiveNavigationTests {
    private func fixture() throws -> Route {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "osrm_hh_drive", withExtension: "json"))
        return try Router.parseOSRM(Data(contentsOf: url), destination: "West 96th Street")
    }

    private func fix(_ c: CLLocationCoordinate2D, speed: Double = 12) -> CLLocation {
        CLLocation(coordinate: c, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                   course: 0, speed: speed, timestamp: Date())
    }

    @Test func osrmRouteKeepsSignsTurnsAndRoads() throws {
        let r = try fixture()
        #expect(r.points.count > 50 && r.length > 2_500)
        #expect(r.duration != nil)
        let signs = r.maneuvers.compactMap(\.sign)
        #expect(signs.contains { $0.kind == .entrance && $0.shields == ["NY 9A North"] && $0.destinations == ["Henry Hudson Parkway"] })
        #expect(signs.contains { $0.kind == .exit && $0.destinations == ["West 96th Street"] })
        let words = r.maneuvers.map(\.instruction)
        #expect(words.contains("Turn left onto West 79th Street"), "\(words)")
        #expect(r.roads.contains { $0.name == "Henry Hudson Parkway" && !$0.twoWay })
        #expect(r.maneuvers.last?.instruction == "Arrive at West 96th Street")
    }

    @Test func gpsSnapsOntoTheRouteAndNoticesLeavingIt() throws {
        let r = try fixture()
        let on = r.position(at: 1_200).0
        let snapped = r.snap(on, near: 1_000)
        #expect(abs(snapped.distance - 1_200) < 5 && snapped.offBy < 2)
        let off = on.offset(by: 120, bearing: r.vehicleHeading(at: 1_200) + 90)
        #expect(r.snap(off, near: 1_200).offBy > 100)
    }

    @Test func liveTripFollowsFixesReroutesAndArrives() throws {
        let r = try fixture()
        let trip = Trip(route: r, defaults: UserDefaults(suiteName: "velo-tests-\(UUID())")!, live: true)
        var said: [String] = []
        trip.speak = { said.append($0.fallback) }
        trip.update(fix: fix(r.position(at: 800).0))
        for _ in 0..<120 { trip.advance(by: 1.0 / 60) }      // 2 s of frames
        #expect(abs(trip.distance - 800) < 60, "distance \(trip.distance)")
        #expect(trip.currentSpeed == 12)

        let away = r.position(at: 820).0.offset(by: 250, bearing: r.vehicleHeading(at: 820) - 90)   // 250 m off, away from the parkway
        trip.update(fix: fix(away))
        for _ in 0..<120 { trip.advance(by: 1.0 / 60) }   // finish easing to the last good fix
        let before = trip.distance
        for _ in 0..<120 { trip.advance(by: 1.0 / 60) }
        #expect(trip.distance - before < 2, "kept gliding down the route while off it")
        for _ in 0..<2 { trip.update(fix: fix(away)) }
        #expect(trip.offRoute)
        trip.reroute(r)
        #expect(!trip.offRoute && trip.distance == 0)

        trip.update(fix: fix(r.position(at: r.length - 5).0))
        for _ in 0..<60 { trip.advance(by: 1.0 / 60) }
        #expect(trip.announcement?.text == "You have arrived at West 96th Street")
        trip.endRide()
        #expect(trip.ended)
    }
}
