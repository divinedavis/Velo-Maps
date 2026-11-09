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
        #expect(current.length - at >= FasterRoute.minRemaining)
        let same = rest(of: current, from: at, duration: 600)
        #expect(FasterRoute.follows(same, current, from: at))
        let other = { (t: Double) in self.rest(of: current, from: at, duration: t, shiftedBy: 300) }
        #expect(!FasterRoute.follows(other(400), current, from: at))

        let pick = FasterRoute.pick(current: current, at: at, candidates: [same, other(400)])
        #expect(pick?.saves == 200)
        #expect(pick.map { !FasterRoute.follows($0.route, current, from: at) } == true)
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same, other(540)]) == nil, "1 min isn't worth a switch")
        #expect(FasterRoute.pick(current: current, at: at, candidates: [same]) == nil)
        #expect(FasterRoute.pick(current: current, at: current.length - 500, candidates: [same, other(100)]) == nil, "too close to the end")
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
