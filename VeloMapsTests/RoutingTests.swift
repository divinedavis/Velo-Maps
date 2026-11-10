import Testing
import Foundation
import CoreLocation
@testable import VeloMaps

private final class BundleToken {}

/// Alternatives and faster-route switching (owner, 11/9).
@Suite("Routing alternatives")
@MainActor
struct RoutingTests {
    private func fixtureData() throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "osrm_hh_drive", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    /// The rest of `r` from `d` on, as a fresh route with the given travel time.
    private func rest(of r: Route, from d: Double, duration: Double, shiftedBy metres: Double = 0) -> Route {
        let pts = zip(r.points, r.cumulative).filter { $0.1 >= d }.map { $0.0.offset(by: metres, bearing: 90) }
        var out = Route(line: "Drive", destination: r.destination, kind: .drive,
                        stops: [Stop(id: 0, name: "Start", coordinate: pts[0]), Stop(id: 1, name: r.destination, coordinate: pts[pts.count - 1])],
                        points: pts)
        out.duration = duration
        return out
    }

    @Test func everyRouteInTheResponseIsKeptFastestFirst() throws {
        var json = try #require(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
        var routes = try #require(json["routes"] as? [[String: Any]])
        let first = try #require(routes.first?["duration"] as? Double)
        var faster = routes[0]
        faster["duration"] = first / 2
        routes.append(faster)
        json["routes"] = routes
        let parsed = try Router.parseRoutes(JSONSerialization.data(withJSONObject: json), destination: "West 96th Street")
        #expect(parsed.count == 2)
        #expect(parsed[0].duration == first / 2 && parsed[1].duration == first)
        #expect(parsed[0].maneuvers.contains { $0.sign != nil }, "alternatives keep sign wording")
    }

    @Test func switchesOnlyForAClearlyFasterRoute() throws {
        let current = try Router.parseOSRM(fixtureData(), destination: "West 96th Street")
        let at = 300.0
        let same = rest(of: current, from: at, duration: 600)
        #expect(FasterRoute.follows(same, current, from: at))
        let other = { (t: Double) in self.rest(of: current, from: at, duration: t, shiftedBy: 300) }
        #expect(!FasterRoute.follows(other(400), current, from: at))

        let pick = FasterRoute.pick(current: current, at: at, candidates: [same, other(400)])
        #expect(pick?.saves == 200)
        #expect(pick.map { !FasterRoute.follows($0.route, current, from: at) } == true)
        // 10 minutes left: 8% is 48 s, so a minute is worth it and 40 s is not.
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same, other(540)])?.saves == 60)
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same, other(560)]) == nil, "40 s isn't worth a switch")
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same]) == nil)
        #expect(FasterRoute.pick(current: current, at: current.length - 200, candidates: [same, other(100)]) == nil, "too close to the end")
    }

    /// The saving needed grows with the time left (owner's report, 11/10: short NYC trips never
    /// switched under the flat 2 min / 10% rule).
    @Test func theSavingNeededScalesWithTheTimeLeft() {
        #expect(FasterRoute.threshold(forTimeLeft: 300) == 45, "never under 45 s")
        #expect(FasterRoute.threshold(forTimeLeft: 540) == 45)
        #expect(FasterRoute.threshold(forTimeLeft: 900) == 72, "15 minutes left: 72 s")
        #expect(FasterRoute.threshold(forTimeLeft: 1_499) > 119)
        #expect(FasterRoute.threshold(forTimeLeft: 1_500) == 150, "25 minutes and up: the long-trip 10%")
        #expect(FasterRoute.threshold(forTimeLeft: 1_000) == 80)
        #expect(FasterRoute.threshold(forTimeLeft: 2_400) == 240)
    }

    @Test func longTripsStillNeedTwoMinutesAndTenPercent() throws {
        let current = try Router.parseOSRM(fixtureData(), destination: "West 96th Street")
        let same = rest(of: current, from: 300, duration: 1_800)
        let other = { (t: Double) in self.rest(of: current, from: 300, duration: t, shiftedBy: 300) }
        #expect(FasterRoute.pick(current: current, at: 300, candidates: [same, other(1_680)]) == nil, "2 min of 30 is under 10%")
        #expect(FasterRoute.pick(current: current, at: 300, candidates: [same, other(1_600)])?.saves == 200)
    }

    @Test func checksGetMoreFrequentAsTheTripGetsShorter() {
        let far = FasterRoute.Policy.forRemaining(20_000), mid = FasterRoute.Policy.forRemaining(5_000)
        let near = FasterRoute.Policy.forRemaining(2_000)
        #expect(far == FasterRoute.Policy(checkEvery: 180, minRemaining: 1_000, maxSwitches: 1))
        #expect(mid == FasterRoute.Policy(checkEvery: 120, minRemaining: 500, maxSwitches: 2))
        #expect(near == FasterRoute.Policy(checkEvery: 60, minRemaining: 300, maxSwitches: 2))
        // Every policy waits at least a minute, so a route is never swapped in its first 45 s.
        #expect([far, mid, near].allSatisfy { $0.checkEvery >= 60 })
    }

    /// A policy passed in overrides the cutoff (the 300 m floor of the short-trip policy).
    @Test func theCutoffComesFromThePolicy() throws {
        let current = try Router.parseOSRM(fixtureData(), destination: "West 96th Street")
        let at = current.length - 400
        let same = rest(of: current, from: at, duration: 300)
        let other = rest(of: current, from: at, duration: 100, shiftedBy: 300)
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same, other]) != nil, "400 m left is past the 300 m cutoff")
        let long = FasterRoute.Policy(checkEvery: 180, minRemaining: 1_000, maxSwitches: 1)
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same, other], policy: long) == nil)
    }

    /// Reroutes from a moving car say which way it is heading, so the new route can't begin
    /// with a U-turn. Stopped, or no GPS course: nothing is sent.
    @Test func aMovingCarSendsItsHeading() throws {
        #expect(Router.Moving(course: -1, speed: 10) == nil)
        #expect(Router.Moving(course: 90, speed: 1) == nil)
        let city = try #require(Router.Moving(course: 359.6, speed: 8))
        #expect(city.bearing == 0 && city.clear == 50)
        #expect(Router.Moving(course: 181.2, speed: 20)?.clear == 100)
        let a = CLLocationCoordinate2D(latitude: 40.78, longitude: -73.98), b = CLLocationCoordinate2D(latitude: 40.69, longitude: -73.99)
        let moving = Router.trafficURL(from: a, to: b, moving: Router.Moving(course: 181.2, speed: 20)).absoluteString
        #expect(moving.hasSuffix("&bearing=181&clear=100"))
        #expect(!Router.trafficURL(from: a, to: b, moving: nil).absoluteString.contains("bearing"))
    }

    @Test func switchingSaysHowMuchTimeItSaves() throws {
        let r = try Router.parseOSRM(fixtureData(), destination: "West 96th Street")
        let trip = Trip(route: r, defaults: UserDefaults(suiteName: "velo-tests-\(UUID())")!, live: true)
        var said: [String] = []
        trip.speak = { said.append($0.fallback) }
        trip.update(fix: CLLocation(coordinate: r.position(at: 500).0, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                    course: 0, speed: 12, timestamp: Date()))
        trip.switchToFaster(rest(of: r, from: 500, duration: 300, shiftedBy: 300), saves: 185)
        #expect(trip.distance == 0 && !trip.offRoute)
        #expect(trip.announcement?.text == "Faster route found. Saves 3 minutes")
        #expect(said == ["Faster route found. Saves 3 minutes"])
    }
}
