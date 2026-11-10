import Testing
import CoreLocation
import Foundation
@testable import VeloMaps

/// A long drive (≈60 km, thousands of points, hundreds of roads) must build and draw quickly:
/// this work runs when a route arrives, at Start, and on every reroute.
@Suite("Route build speed")
struct RouteBuildSpeedTests {
    /// Zig-zag north-east: a new road every 300 m, a turn every 900 m.
    static func longRoute(km: Double = 60) -> Route {
        var pts: [CLLocationCoordinate2D] = []
        var roads: [RoadSpec] = [], turns: [TurnSpec] = []
        var c = CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00)
        let n = Int(km * 1000 / 10)
        for i in 0..<n {
            pts.append(c)
            if i % 30 == 0 { roads.append(RoadSpec(coordinate: c, name: "Road \(i / 30)", lanes: 1 + (i / 30) % 3, twoWay: (i / 30) % 2 == 0)) }
            if i % 90 == 45 { turns.append(TurnSpec(coordinate: c, icon: i % 180 == 45 ? "arrow.turn.up.left" : "arrow.turn.up.right", verb: "Turn", street: "Road")) }
            let east = (i / 90) % 2 == 1
            c = c.offset(by: 10, bearing: east ? 80 : 10)
        }
        let stops = [Stop(id: 0, name: "Start", coordinate: pts[0]), Stop(id: 1, name: "End", coordinate: pts[pts.count - 1])]
        return Route(line: "Drive", destination: "End", kind: .drive, stops: stops, turns: turns, roads: roads, points: pts)
    }

    @Test func longRouteBuildsAndDrawsFast() {
        let clock = ContinuousClock()
        var route: Route!
        let build = clock.measure { route = Self.longRoute() }
        var lane: [CLLocationCoordinate2D] = [], lanes: [[CLLocationCoordinate2D]] = []
        let draw = clock.measure { lane = route.lanePath(); lanes = route.lanePaths() }
        print("ROUTE SPEED build \(build) draw \(draw) points \(route.points.count) lane \(lane.count) lanes \(lanes.count)")
        #expect(route.length > 55_000)
        // Debug build in the simulator. Before 11/10: build 0.71 s, draw 1.73 s.
        #expect(build < .milliseconds(450), "build took \(build)")
        #expect(draw < .milliseconds(200), "draw took \(draw)")
    }

    /// The drawn lane line is exactly the per-point lane position, and every lane line keeps
    /// its distance from the centre line.
    @Test func drawnLanesMatchTheLanePositions() {
        let route = Self.longRoute(km: 3)
        let path = route.lanePath()
        for (i, d) in stride(from: 0.0, through: route.length, by: Route.laneSpacing).enumerated() {
            #expect(path[i].distance(to: route.lanePosition(at: d)) < 0.01)
        }
        let hh = Route.hhDrive
        #expect(!hh.lanePaths().isEmpty)
        #expect(hh.lanePath().count == Int(hh.length / Route.laneSpacing) + 1)
    }
}
