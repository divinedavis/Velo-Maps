import Testing
import CoreLocation
@testable import VeloMaps

/// The route is drawn in the lane to be in (owner, 11/8).
@Suite("Lanes")
struct LaneTests {
    let w = Route.laneWidth

    @Test func busKeepsTheCurbLaneOnCentralParkWest() {
        let r = Route.m10
        // CPW: two-way, 2 lanes each way → curb lane centre is 1.5 lane widths right of centre.
        #expect(abs(r.laneOffset(at: 600) - 1.5 * w) < 0.01)
    }

    @Test func busMovesToTheLeftLaneBeforeTheLeftTurn() {
        let r = Route.m10
        let turn = r.maneuvers[0].at
        #expect(abs(r.laneOffset(at: turn - 20) - 0.5 * w) < 0.01, "inner lane before turning left")
    }

    @Test func carUsesTheMiddleParkwayLaneThenTheRightLaneForTheExit() {
        let r = Route.hhDrive
        let exit = r.maneuvers.last { $0.sign?.kind == .exit }!.at
        #expect(abs(r.laneOffset(at: exit - 900)) < 0.01, "middle of 3 one-way lanes")
        #expect(abs(r.laneOffset(at: exit - 100) - 1.0 * w) < 0.01, "rightmost of 3 before the exit")
    }

    /// What a rider sees: the drawn lane path never jumps sideways. Points are 4 m apart
    /// along the road; a sideways jump would stretch a gap well past that.
    @Test(arguments: [Route.m10, Route.hhDrive])
    func lanePathHasNoSidewaysJumps(_ r: Route) {
        let pts = r.lanePath()
        let gaps = zip(pts, pts.dropFirst()).map { $0.distance(to: $1) }
        #expect((gaps.max() ?? 0) <= 5.5, "largest gap \(gaps.max() ?? 0) m")
    }
}
