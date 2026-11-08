import Testing
import CoreLocation
import Foundation
@testable import VeloMaps

/// Swift Testing suites for the route maths the ride and walk screens depend on.
@Suite("Route")
struct RouteTests {
    let route = Route.m10

    @Test func lengthIsAboutTheRealDistance() {
        // CPW W 72 St → W 96 St is ~1.95 km, plus one block of W 96 St to Columbus Av.
        #expect(route.length > 1_900 && route.length < 2_600, "length \(route.length)")
    }

    @Test func positionAtStartAndEndAreTheLineEnds() {
        let (start, _) = route.position(at: 0)
        let (end, _) = route.position(at: route.length)
        #expect(start.distance(to: route.points.first!) < 1)
        #expect(end.distance(to: route.points.last!) < 1)
    }

    @Test(arguments: [-50.0, 1e9])
    func positionClampsOutsideTheRoute(_ d: Double) {
        let (p, _) = route.position(at: d)
        let nearestEnd = min(p.distance(to: route.points.first!), p.distance(to: route.points.last!))
        #expect(nearestEnd < 1)
    }

    @Test func headingIsNorthOnCentralParkWest() {
        // CPW runs ~29° east of north.
        let h = route.smoothedHeading(at: 400)
        #expect(h > 15 && h < 45, "heading \(h)")
    }

    @Test func maneuversAreTheLeftTurnThenArrival() {
        let m = route.maneuvers
        #expect(m.count == 2)
        #expect(m[0].instruction == "Turn left onto W 96 St")
        #expect(m[0].at > 1_800 && m[0].at < route.length)
        #expect(m[1].verb == "Arrive at" && m[1].at == route.length)
    }

    @Test func stopsAreInOrderAlongTheLine() {
        #expect(route.stopDistances == route.stopDistances.sorted())
        #expect(route.nextStopIndex(at: 0) == 1)
        #expect(route.nextStopIndex(at: route.length) == route.stops.count - 1)
    }
}

@Suite("Formatting and settings")
struct FormattingTests {
    @Test(arguments: [(30.0, "100 ft"), (100.0, "330 ft"), (170.0, "0.1 mi"), (1609.34, "1.0 mi")])
    func walkDistanceUsesFeetThenMiles(_ metres: Double, _ expected: String) {
        #expect(walkDistance(metres) == expected)
    }

    @Test func launchArgumentNumbersParseFromStrings() {
        let d = UserDefaults(suiteName: "velo-tests-\(UUID())")!
        d.set("0.25", forKey: "progress")
        d.set(4, forKey: "cardStyle")
        #expect(d.number("progress") == 0.25)
        #expect(d.number("cardStyle") == 4)
        #expect(d.number("missing") == nil)
    }
}

@Suite("Potholes")
@MainActor
struct PotholeTests {
    @Test func oneTapAddsAPotholeAtTheBus() {
        let trip = Trip(defaults: UserDefaults(suiteName: "velo-tests-\(UUID())")!)
        let before = trip.potholes.count
        trip.reportPothole()
        #expect(trip.potholes.count == before + 1)
        #expect(trip.potholes.last?.mine == true)
    }

    @Test func aheadOnlyCountsPotholesInFrontWithinRange() {
        let d = UserDefaults(suiteName: "velo-tests-\(UUID())")!
        d.set("0.25", forKey: "progress")
        let trip = Trip(defaults: d)
        // Seeded reports sit at 700 m and 1450 m; at 25% the bus is ~550 m along.
        let ahead = trip.potholeAhead()
        #expect(ahead != nil)
        #expect((ahead?.1 ?? 0) > 0 && (ahead?.1 ?? 0) <= 250)
        #expect(trip.potholeAhead(within: 10) == nil)
    }
}
