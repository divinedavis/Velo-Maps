import Foundation
import CoreLocation

/// Posted speed limits along a live route, from OpenStreetMap `maxspeed` tags (Overpass API):
/// one request per route (Start / reroute). Each 30 m of the route takes the limit of the
/// tagged road within 18 m that runs the same way (so a cross street at an intersection
/// doesn't count). Where OSM has no limit, nothing is shown. The public Overpass servers are
/// sometimes at capacity — then the sign just stays hidden.
enum SpeedLimits {
    static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    static func lookup(_ route: Route) async -> [(start: Double, mph: Int)] {
        let samples = stride(from: 0.0, through: route.length, by: 150).map { route.position(at: $0).0 }
            + [route.position(at: route.length).0]
        let line = samples.map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }.joined(separator: ",")
        let query = "[out:json][timeout:20];way[highway][maxspeed](around:20,\(line));out tags geom;"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("VeloMaps/1.0 (iOS navigation prototype)", forHTTPHeaderField: "User-Agent")
        req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".data(using: .utf8)
        req.timeoutInterval = 25
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { return [] }
        return match(route, ways: json.elements)
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
            if out.last?.mph != mph { out.append((d, mph)) }
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

struct OverpassResponse: Decodable { let elements: [OverpassWay] }
struct OverpassWay: Decodable {
    let tags: [String: String]
    let geometry: [OverpassPoint]?
}
struct OverpassPoint: Decodable { let lat: Double; let lon: Double }
