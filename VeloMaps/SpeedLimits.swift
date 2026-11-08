import Foundation
import CoreLocation

/// Posted speed limits along a live route, from OpenStreetMap `maxspeed` tags (Overpass API),
/// cached on the phone by ~1 km tile for 30 days (SpeedLimitCache) so roads already driven
/// need no request. Each 30 m of the route takes the limit of the
/// tagged road within 18 m that runs the same way (so a cross street at an intersection
/// doesn't count). Where OSM has no limit, nothing is shown. The public Overpass servers are
/// sometimes at capacity — then the sign just stays hidden.
enum SpeedLimits {
    static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    /// Our own tiles (NYC, built from OSM by scripts/build_speed_limit_tiles.sh, served from
    /// the DigitalOcean droplet). Temporary sslip.io host until Velo Maps has a domain.
    static let tileServer = URL(string: "https://velomaps.104.236.120.144.sslip.io/speedlimits/v1/")!

    static func lookup(_ route: Route, cache: SpeedLimitCache = .shared) async -> [(start: Double, mph: Int)] {
        let ways = await cache.ways(along: route) { tiles in await fetch(tiles) }
        return match(route, ways: ways)
    }

    /// Our tile server first (NYC); any tile it doesn't have goes to the public Overpass API.
    static func fetch(_ tiles: [SpeedLimitCache.Tile]) async -> [SpeedLimitCache.Tile: [OverpassWay]] {
        var out: [SpeedLimitCache.Tile: [OverpassWay]] = [:]
        await withTaskGroup(of: (SpeedLimitCache.Tile, [OverpassWay]?).self) { group in
            for t in tiles { group.addTask { (t, await ownTile(t)) } }
            for await (t, ways) in group { if let ways { out[t] = ways } }
        }
        let rest = tiles.filter { out[$0] == nil }
        if !rest.isEmpty, let ways = await overpass(rest) {
            for t in rest { out[t] = ways }          // the cache keeps each tile's own roads
        }
        return out
    }

    /// One tile from our server: roads, [] for a covered tile with none, nil if not served.
    static func ownTile(_ t: SpeedLimitCache.Tile) async -> [OverpassWay]? {
        var req = URLRequest(url: tileServer.appendingPathComponent("\(t.key).json"))
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { return nil }
        return json.ways
    }

    /// One Overpass request for a batch of tiles; up to 3 tries (2 s, 5 s backoff) because the
    /// public servers are often "at capacity". nil = gave up (those tiles stay uncached).
    static func overpass(_ tiles: [SpeedLimitCache.Tile]) async -> [OverpassWay]? {
        let parts = tiles.map { t in
            let b = t.bounds
            return String(format: "way[highway][maxspeed](%.5f,%.5f,%.5f,%.5f);", b.south, b.west, b.north, b.east)
        }.joined()
        let query = "[out:json][timeout:25];(\(parts));out tags geom;"
        for (attempt, wait) in [0.0, 2, 5].enumerated() {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("VeloMaps/1.0 (iOS navigation prototype)", forHTTPHeaderField: "User-Agent")
            req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".data(using: .utf8)
            req.timeoutInterval = 30
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONDecoder().decode(OverpassResponse.self, from: data) {
                return json.elements
            }
            _ = attempt
        }
        return nil
    }

    /// Route + tagged ways → limit changes along the route. Separate for tests.
    static func match(_ route: Route, ways: [OverpassWay]) -> [(start: Double, mph: Int)] {
        let tagged: [(mph: Int, pts: [CLLocationCoordinate2D])] = ways.compactMap { w in
            guard let mph = parse(w.tags["maxspeed"] ?? ""), let g = w.geometry, g.count > 1 else { return nil }
            return (mph, g.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
        }
        var out: [(start: Double, mph: Int)] = []
        for d in stride(from: 0.0, through: route.length, by: 30) {
            let p = route.position(at: d).0
            let heading = route.vehicleHeading(at: d)
            var best: (mph: Int, dist: Double)?
            for w in tagged {
                for i in 1..<w.pts.count {
                    let a = w.pts[i - 1], b = w.pts[i]
                    let diff = abs(TransitMapView.Coordinator.shortestTurn(from: heading, to: a.bearing(to: b)))
                    guard min(diff, 180 - diff) < 35 else { continue }      // same road direction (either way)
                    let dist = distance(p, a, b)
                    if dist < 18, dist < (best?.dist ?? .infinity) { best = (w.mph, dist) }
                }
            }
            guard let mph = best?.mph else { continue }
            // The first known limit covers the route from its start (the first sample to match
            // can be 30 m in, and a car waiting at the start showed no sign — 11/8).
            if out.last?.mph != mph { out.append((out.isEmpty ? 0 : d, mph)) }
        }
        return out
    }

    /// "25 mph" → 25; "40" (km/h by OSM convention) → 25; "none"/"signals" → nil.
    static func parse(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = s.prefix { $0.isNumber }
        guard let n = Double(digits), n > 0 else { return nil }
        if s.contains("mph") { return Int(n) }
        return Int((n * 0.621371 / 5).rounded() * 5)
    }

    private static func distance(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let mx = 111_320 * cos(p.latitude * .pi / 180), my = 110_540.0
        let ax = (a.longitude - p.longitude) * mx, ay = (a.latitude - p.latitude) * my
        let bx = (b.longitude - p.longitude) * mx, by = (b.latitude - p.latitude) * my
        let vx = bx - ax, vy = by - ay, len2 = vx * vx + vy * vy
        let t = len2 > 0 ? max(0, min(1, -(ax * vx + ay * vy) / len2)) : 0
        let px = ax + vx * t, py = ay + vy * t
        return (px * px + py * py).squareRoot()
    }
}

/// Overpass replies with {"elements": […]}; our tile server with {"ways": […]}.
struct OverpassResponse: Decodable {
    let ways: [OverpassWay]
    var elements: [OverpassWay] { ways }
    private enum Keys: String, CodingKey { case elements, ways }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        ways = try c.decodeIfPresent([OverpassWay].self, forKey: .elements)
            ?? c.decode([OverpassWay].self, forKey: .ways)
    }
}
struct OverpassWay: Codable {
    let tags: [String: String]
    let geometry: [OverpassPoint]?
}
struct OverpassPoint: Codable { let lat: Double; let lon: Double }
