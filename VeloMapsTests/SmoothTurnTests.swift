import Testing
import CoreLocation
@testable import VeloMaps

/// The vehicle must turn smoothly through corners (owner, 11/8: "the turn is not smooth,
/// the car does not turn properly").
@Suite("Smooth turns")
struct SmoothTurnTests {
    private let a = CLLocationCoordinate2D(latitude: 40.7800, longitude: -73.9800)

    /// Max change in vehicle heading over each 1 m step along `route` in [from, to).
    private func maxHeadingStep(_ route: Route, from: Double, to: Double) -> Double {
        var worst = 0.0
        var prev = route.vehicleHeading(at: from)
        var d = from + 1
        while d < to {
            let h = route.vehicleHeading(at: d)
            worst = max(worst, abs(TransitMapView.Coordinator.shortestTurn(from: prev, to: h)))
            prev = h; d += 1
        }
        return worst
    }

    @Test func squareCornerBecomesAnArcAndKeepsItsEnds() {
        let corner = a.offset(by: 100, bearing: 0)
        let end = corner.offset(by: 100, bearing: 90)
        let rounded = Route.roundCorners([a, corner, end])
        #expect(rounded.count > 3)
        #expect(rounded.first!.distance(to: a) < 0.01 && rounded.last!.distance(to: end) < 0.01)
        // The arc never strays more than the fillet's sagitta (~3 m at r = 10 m) from the corner.
        let nearest = rounded.map { $0.distance(to: corner) }.min()!
        #expect(nearest > 1 && nearest < 6)
    }

    @Test func gentleBendsAreLeftAlone() {
        let mid = a.offset(by: 100, bearing: 0)
        let end = mid.offset(by: 100, bearing: 8)   // 8° bend: below the 12° threshold
        #expect(Route.roundCorners([a, mid, end]).count == 3)
    }

    @Test func driveTurnsGraduallyAtBroadwayAndWest79th() {
        let r = Route.hhDrive
        let turn = r.maneuvers[0].at          // left onto West 79th Street
        #expect(maxHeadingStep(r, from: max(0, turn - 30), to: turn + 30) < 12)
        let total = abs(TransitMapView.Coordinator.shortestTurn(from: r.vehicleHeading(at: max(4, turn - 25)),
                                                                to: r.vehicleHeading(at: turn + 25)))
        #expect(total > 60, "it is still a real left turn")
    }

    @Test func busTurnOntoWest96thIsGradual() {
        let r = Route.m10
        let turn = r.maneuvers[0].at
        #expect(maxHeadingStep(r, from: turn - 30, to: turn + 30) < 12)
    }

    @Test(arguments: [(350.0, 10.0, 20.0), (10.0, 350.0, -20.0), (90.0, 270.0, 180.0), (0.0, 0.0, 0.0)])
    @MainActor func cameraTakesTheShortWayRound(_ from: Double, _ to: Double, _ expected: Double) {
        #expect(abs(TransitMapView.Coordinator.shortestTurn(from: from, to: to)) == abs(expected))
    }
}
