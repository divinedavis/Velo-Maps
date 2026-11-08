import Testing
import CoreLocation
@testable import VeloMaps

@Suite("Speed limits")
struct SpeedLimitTests {
    @Test(arguments: [("25 mph", 25), ("50 mph", 50), ("40", 25), ("100", 60), ("none", nil), ("signals", nil)] as [(String, Int?)])
    func parsesOSMMaxspeed(_ raw: String, _ mph: Int?) {
        #expect(SpeedLimits.parse(raw) == mph)
    }

    @Test func demoRoadsCarryTheirPostedLimits() {
        let r = Route.hhDrive
        #expect(r.speedLimit(at: 10) == 25)                      // Broadway
        #expect(r.speedLimit(at: r.length * 0.6) == 50)          // Henry Hudson Parkway
        #expect(Route.m10.speedLimit(at: 600) == 25)             // Central Park West
    }

    @Test func liveMatchUsesTheRoadGoingYourWayNotTheCrossStreet() {
        let r = Route.m10
        let p = r.position(at: 600).0, h = r.vehicleHeading(at: 600)
        // Our road (same direction, 30 mph) and a cross street (90°, 15 mph) both within reach.
        let along = OverpassWay(tags: ["maxspeed": "30 mph"], geometry: [
            p.offset(by: 200, bearing: h + 180), p.offset(by: 200, bearing: h)].map { OverpassPoint(lat: $0.latitude, lon: $0.longitude) })
        let cross = OverpassWay(tags: ["maxspeed": "15 mph"], geometry: [
            p.offset(by: 50, bearing: h + 90), p.offset(by: 50, bearing: h - 90)].map { OverpassPoint(lat: $0.latitude, lon: $0.longitude) })
        var live = r
        live.limitChanges = SpeedLimits.match(r, ways: [cross, along])
        #expect(live.speedLimit(at: 600) == 30)
    }
}
