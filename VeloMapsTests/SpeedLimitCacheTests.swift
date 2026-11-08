import Testing
import Foundation
import CoreLocation
@testable import VeloMaps

@Suite("Speed limit cache")
struct SpeedLimitCacheTests {
    private func tempCache(maxAge: TimeInterval = 30 * 24 * 3600) -> SpeedLimitCache {
        SpeedLimitCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("sl-\(UUID())"), maxAge: maxAge)
    }

    /// A tagged road along the start of the bus route.
    private func cpwWay() -> OverpassWay {
        let r = Route.m10
        return OverpassWay(tags: ["maxspeed": "25 mph"], geometry: stride(from: 0.0, through: 400, by: 50).map {
            let c = r.position(at: $0).0; return OverpassPoint(lat: c.latitude, lon: c.longitude) })
    }

    @Test func secondLookupOnTheSameRoadsMakesNoRequest() async {
        let cache = tempCache()
        var calls = 0, tilesAsked = 0
        let first = await cache.ways(along: .m10) { tiles in
            calls += 1; tilesAsked += tiles.count
            return Dictionary(uniqueKeysWithValues: tiles.map { ($0, [cpwWay()]) })
        }
        #expect(calls >= 1 && !first.isEmpty)
        let before = calls
        let second = await cache.ways(along: .m10) { _ in calls += 1; return [:] }
        #expect(calls == before, "cached tiles were fetched again")
        #expect(!second.isEmpty)
        #expect(tilesAsked == SpeedLimitCache.tiles(along: .m10).count)
    }

    @Test func expiredTilesAreFetchedAgain() async {
        let cache = tempCache(maxAge: 60)
        let tile = SpeedLimitCache.tiles(along: .m10)[0]
        await cache.write(tile, [cpwWay()], at: Date().addingTimeInterval(-120))
        #expect(await cache.read(tile) == nil)
    }

    @Test func failedFetchLeavesTilesUncached() async {
        let cache = tempCache()
        _ = await cache.ways(along: .m10) { _ in [:] }          // nothing could be fetched
        var calls = 0
        _ = await cache.ways(along: .m10) { _ in calls += 1; return [:] }
        #expect(calls >= 1, "a failed fetch must not be cached as 'no roads'")
    }

    @Test func routeTilesCoverTheWholeRoute() {
        let tiles = Set(SpeedLimitCache.tiles(along: .hhDrive))
        for d in stride(from: 0.0, through: Route.hhDrive.length, by: 25) {
            #expect(tiles.contains(SpeedLimitCache.Tile(Route.hhDrive.position(at: d).0)))
        }
    }

    @Test func oneTileFailingDoesNotMarkItsNeighboursEmpty() async {
        let cache = tempCache()
        let tiles = SpeedLimitCache.tiles(along: .m10)
        _ = await cache.ways(along: .m10) { asked in [asked[0]: [cpwWay()]] }   // only the first came back
        #expect(await cache.read(tiles[0]) != nil)
        if tiles.count > 1 { #expect(await cache.read(tiles[1]) == nil) }
    }

    @Test func serverTileJSONDecodes() throws {
        let json = #"{"ways":[{"tags":{"maxspeed":"25 mph"},"geometry":[{"lat":40.78,"lon":-73.97},{"lat":40.79,"lon":-73.96}]}]}"#
        let r = try JSONDecoder().decode(OverpassResponse.self, from: Data(json.utf8))
        #expect(r.ways.count == 1 && r.ways[0].tags["maxspeed"] == "25 mph")
    }
}
