import Testing
@testable import VeloMaps

@Suite("Highway signs")
struct HighwaySignTests {
    @Test func osrmDestinationsSplitShieldsFromNames() {
        let s = HighwaySign(kind: .entrance, osrmDestinations: "NY 9A North: Henry Hudson Parkway")
        #expect(s.shields == ["NY 9A North"])
        #expect(s.destinations == ["Henry Hudson Parkway"])
        #expect(s.instruction == "Take the ramp to NY 9A North")
    }

    @Test func namesOnlyAndMultipleDestinations() {
        let s = HighwaySign(kind: .exit, osrmDestinations: "Boat Basin, Lincoln Center")
        #expect(s.shields.isEmpty)
        #expect(s.destinations == ["Boat Basin", "Lincoln Center"])
        #expect(s.instruction == "Take the exit to Boat Basin")
    }

    @Test func osmTagsKeepWordingAndExitNumber() {
        let s = HighwaySign(kind: .exit, osmTags: [
            "junction:ref": "28A", "destination:ref": "I 278 East;NY 27",
            "destination": "Brooklyn-Queens Expressway;Atlantic Avenue"])
        #expect(s.exitNumber == "28A")
        #expect(s.shields == ["I 278 East", "NY 27"])
        #expect(s.destinations == ["Brooklyn-Queens Expressway", "Atlantic Avenue"])
        #expect(s.instruction == "Take exit 28A to I 278 East")
        #expect(s.spoken == "Exit 28A, I 278 East, NY 27, Brooklyn-Queens Expressway, Atlantic Avenue")
    }

    @Test func noExitNumberIsInvented() {
        let s = HighwaySign(kind: .exit, osmTags: ["destination": "West 96th Street"])
        #expect(s.exitNumber == nil)
        #expect(s.instruction == "Take the exit to West 96th Street")
    }

    @Test func demoDriveHasTheRealEntranceThenExitSigns() {
        let signs = Route.hhDrive.maneuvers.compactMap(\.sign)
        #expect(signs.count == 2)
        #expect(signs[0] == HighwaySign(kind: .entrance, shields: ["NY 9A North"], destinations: ["Henry Hudson Parkway"]))
        #expect(signs[1] == HighwaySign(kind: .exit, shields: [], destinations: ["West 96th Street"]))
        let at = Route.hhDrive.maneuvers.filter { $0.sign != nil }.map(\.at)
        #expect(at == at.sorted() && at[0] > 0 && at[1] < Route.hhDrive.length)
    }
}
