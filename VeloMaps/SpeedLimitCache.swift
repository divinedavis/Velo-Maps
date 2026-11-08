import Foundation
import CoreLocation

/// On-device cache of OSM roads with posted speed limits, by 0.01° tile (~1.1 km × 0.85 km in
/// NYC), kept 30 days (limits rarely change). An empty tile is cached too ("no tagged roads
/// here"). Owner, 11/8: "cant we cache speed limits?"
actor SpeedLimitCache {
    static let shared = SpeedLimitCache()

    struct Tile: Hashable, Comparable {
        let lat: Int, lon: Int                              // floor(coord / size)
        static let size = 0.01
        init(_ c: CLLocationCoordinate2D) {
            lat = Int(floor(c.latitude / Tile.size)); lon = Int(floor(c.longitude / Tile.size))
        }
        init(lat: Int, lon: Int) { self.lat = lat; self.lon = lon }
        var key: String { "\(lat)_\(lon)" }
        var bounds: (south: Double, west: Double, north: Double, east: Double) {
            (Double(lat) * Tile.size, Double(lon) * Tile.size, Double(lat + 1) * Tile.size, Double(lon + 1) * Tile.size)
        }
        /// Tile grown by ~30 m, so a road just outside the edge still counts for routes in it.
        func contains(_ p: OverpassPoint, margin: Double = 0.0003) -> Bool {
            let b = bounds
            return p.lat >= b.south - margin && p.lat <= b.north + margin && p.lon >= b.west - margin && p.lon <= b.east + margin
        }
        static func < (a: Tile, b: Tile) -> Bool { (a.lat, a.lon) < (b.lat, b.lon) }
    }

    private struct Stored: Codable { let fetchedAt: Date; let ways: [OverpassWay] }

    let directory: URL
    let maxAge: TimeInterval
    let batchSize = 12
    private var busy = false

    init(directory: URL? = nil, maxAge: TimeInterval = 30 * 24 * 3600) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("speedlimits", isDirectory: true)
        self.maxAge = maxAge
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Tiles a route passes through (sampled every 20 m, so a corner clipped briefly counts).
    static func tiles(along route: Route) -> [Tile] {
        var set = Set<Tile>()
        for d in stride(from: 0.0, through: route.length, by: 20) { set.insert(Tile(route.position(at: d).0)) }
        set.insert(Tile(route.position(at: route.length).0))
        return set.sorted()
    }

    /// Tagged roads along the route: cached tiles from disk, missing/expired ones fetched in
    /// batches through `fetch` and stored.
    /// Tagged roads along the route: cached tiles from disk, missing/expired ones fetched in
    /// batches through `fetch` (tile → its roads; a tile left out = couldn't get it) and stored.
    func ways(along route: Route, fetch: ([Tile]) async -> [Tile: [OverpassWay]]) async -> [OverpassWay] {
        // One lookup at a time (actors are re-entrant across awaits): the preview prefetch and
        // Start can ask for the same tiles; the second then reads what the first stored.
        while busy { try? await Task.sleep(for: .milliseconds(100)) }
        busy = true
        defer { busy = false }
        let tiles = Self.tiles(along: route)
        var ways: [OverpassWay] = []
        var missing: [Tile] = []
        for t in tiles {
            if let cached = read(t) { ways += cached } else { missing.append(t) }
        }
        for start in stride(from: 0, to: missing.count, by: batchSize) {
            let batch = Array(missing[start..<min(start + batchSize, missing.count)])
            for (t, got) in await fetch(batch) where batch.contains(t) {
                let inTile = got.filter { ($0.geometry ?? []).contains { t.contains($0) } }
                write(t, inTile)
                ways += inTile
            }
        }
        return ways
    }

    func read(_ t: Tile) -> [OverpassWay]? {
        let url = directory.appendingPathComponent("\(t.key).json")
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Stored.self, from: data),
              Date().timeIntervalSince(s.fetchedAt) < maxAge else { return nil }
        return s.ways
    }

    func write(_ t: Tile, _ ways: [OverpassWay], at date: Date = Date()) {
        let url = directory.appendingPathComponent("\(t.key).json")
        if let data = try? JSONEncoder().encode(Stored(fetchedAt: date, ways: ways)) { try? data.write(to: url, options: .atomic) }
    }
}
