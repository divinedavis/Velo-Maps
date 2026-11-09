import Foundation
import CoreLocation
import MapKit

/// Real driving routes for live navigation (owner, 11/8: "i have to test it in real time").
///
/// Each request asks for the best route plus up to 2 alternatives and the app takes the fastest
/// (owner, 11/9). Sources, in order:
///  1. Our droplet's /route proxy → Mapbox driving-traffic: live traffic and incidents, and the
///     same OSRM-style steps (sign wording, exits, lanes). Daily request cap on the server;
///     503 until a Mapbox token is configured, 429 over the cap.
///  2. The public OSRM demo server (no traffic; testing only, rate-limited).
///  3. Apple's MKDirections (traffic-aware times, but no sign wording or lanes).
/// Requests are bounded: one per Start, reroutes ≥ 15 s apart, faster-route checks ≥ 4 min apart.
enum Router {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let osrmBase = "https://router.project-osrm.org"
    static let trafficBase = URL(string: "https://velomaps.104.236.120.144.sslip.io/route")!

    /// The fastest route (what Start and reroutes use).
    static func drive(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, name: String) async throws -> Route {
        guard let best = try await routes(from: from, to: to, name: name).first else { throw Failure(message: "No route found") }
        return best
    }

    /// The best route and up to 2 alternatives, fastest first.
    static func routes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, name: String) async throws -> [Route] {
        if trafficEnabled, let r = try? await traffic(from: from, to: to, name: name), !r.isEmpty { return r }
        if let r = try? await osrm(from: from, to: to, name: name), !r.isEmpty { return r }
        return try await apple(from: from, to: to, name: name)
    }

    /// Off under tests, the scripted demo and fixed-location UI tests (tests must never spend
    /// the Mapbox allowance), and without the app token.
    static var trafficEnabled: Bool {
        let d = UserDefaults.standard
        return !AppSecrets.voiceToken.isEmpty && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && d.string(forKey: "demo") == nil && d.string(forKey: "mockLocation") == nil
    }

    // MARK: Live traffic (our proxy → Mapbox)

    static func traffic(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, name: String) async throws -> [Route] {
        var c = URLComponents(url: trafficBase, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "from", value: String(format: "%.6f,%.6f", from.latitude, from.longitude)),
                        URLQueryItem(name: "to", value: String(format: "%.6f,%.6f", to.latitude, to.longitude))]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 8
        req.setValue(AppSecrets.voiceToken, forHTTPHeaderField: "X-Velo-App")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "Traffic routing unavailable") }
        return try parseRoutes(data, destination: name)
    }

    // MARK: OSRM

    static func osrm(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, name: String) async throws -> [Route] {
        let coords = String(format: "%.6f,%.6f;%.6f,%.6f", from.longitude, from.latitude, to.longitude, to.latitude)
        var req = URLRequest(url: URL(string: "\(osrmBase)/route/v1/driving/\(coords)?alternatives=2&overview=full&geometries=geojson&steps=true")!)
        req.setValue("VeloMaps/1.0 (iOS navigation prototype)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "Routing service unavailable") }
        return try parseRoutes(data, destination: name)
    }

    /// OSRM/Mapbox JSON → every route in it, fastest first.
    static func parseRoutes(_ data: Data, destination: String) throws -> [Route] {
        let json = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard json.code == "Ok" else { throw Failure(message: "No route found") }
        let routes = json.routes.compactMap { try? route(from: $0, destination: destination) }
        guard !routes.isEmpty else { throw Failure(message: "No route found") }
        return routes.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
    }

    /// OSRM JSON → its first route. Separate so it can be tested with a saved response.
    static func parseOSRM(_ data: Data, destination: String) throws -> Route {
        let json = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard json.code == "Ok", let r = json.routes.first else { throw Failure(message: "No route found") }
        return try route(from: r, destination: destination)
    }

    static func route(from r: OSRMRoute, destination: String) throws -> Route {
        guard r.geometry.coordinates.count >= 2 else { throw Failure(message: "No route found") }
        let points = r.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        let steps = r.legs.flatMap(\.steps)
        var turns: [TurnSpec] = []
        var roads: [RoadSpec] = []
        var longest: (String, Double) = ("", 0)
        for (i, s) in steps.enumerated() {
            let loc = CLLocationCoordinate2D(latitude: s.maneuver.location[1], longitude: s.maneuver.location[0])
            let type = s.maneuver.type, mod = s.maneuver.modifier ?? "straight"
            let street = !(s.name ?? "").isEmpty ? s.name! : (s.ref ?? "")
            // Highways: OSRM's motorway class when present; otherwise a route number (NY 9A,
            // I 87) or a highway-style name. These are one-way carriageways in OSM.
            let highwayName = street.range(of: #"\b(Parkway|Expressway|Freeway|Turnpike|Thruway|Highway|Interstate)\b"#,
                                           options: .regularExpression) != nil
            let motorway = (s.intersections?.contains { ($0.classes ?? []).contains("motorway") } ?? false)
                || highwayName || !(s.ref ?? "").isEmpty
            let ramp = type == "on ramp" || type == "off ramp"
            // Road segment for the current-road label and lanes.
            if type != "arrive" {
                let label = !street.isEmpty ? street
                    : ramp ? (type == "off ramp" ? "Exit" : "Ramp") + ((s.destinations ?? "").isEmpty ? "" : " to \(HighwaySign(kind: .exit, osrmDestinations: s.destinations!).shields.first ?? HighwaySign(kind: .exit, osrmDestinations: s.destinations!).destinations.first ?? "")")
                    : "Road"
                let laneCounts = (s.intersections ?? []).dropFirst().compactMap { $0.lanes?.count }
                    + ((i + 1 < steps.count) ? [steps[i + 1].intersections?.first?.lanes?.count].compactMap { $0 } : [])
                let lanes = laneCounts.max() ?? (motorway ? 2 : 1)
                roads.append(RoadSpec(coordinate: loc, name: label, ref: s.ref?.components(separatedBy: ";").first,
                                      lanes: lanes, twoWay: !(motorway || ramp)))
                if s.distance > longest.1, !street.isEmpty { longest = (street, s.distance) }
            }
            // Maneuver for the turn banner and voice.
            guard let spec = turnSpec(type: type, modifier: mod, street: street, step: s, at: loc) else { continue }
            turns.append(spec)
        }
        var route = Route(line: "Drive", destination: destination, kind: .drive, via: longest.0.isEmpty ? nil : longest.0,
                          stops: [Stop(id: 0, name: "Start", coordinate: points[0]),
                                  Stop(id: 1, name: destination, coordinate: points[points.count - 1])],
                          turns: turns, roads: roads, points: points)
        route.duration = r.duration
        return route
    }

    private static func turnSpec(type: String, modifier mod: String, street: String,
                                 step s: OSRMStep, at loc: CLLocationCoordinate2D) -> TurnSpec? {
        let side = mod.contains("left") ? "left" : mod.contains("right") ? "right" : ""
        let icon: String = {
            switch mod {
            case "left", "sharp left": return "arrow.turn.up.left"
            case "right", "sharp right": return "arrow.turn.up.right"
            case "slight left": return "arrow.up.left"
            case "slight right": return "arrow.up.right"
            case "uturn": return "arrow.uturn.down"
            default: return "arrow.up"
            }
        }()
        let onto = street.isEmpty ? "" : street
        switch type {
        case "depart", "arrive":
            return nil
        case "on ramp", "off ramp":
            let dest = s.destinations ?? ""
            if !dest.isEmpty {
                let sign = HighwaySign(kind: type == "off ramp" ? .exit : .entrance, exitNumber: s.exits, osrmDestinations: dest)
                return TurnSpec(coordinate: loc, icon: side == "left" ? "arrow.up.left" : "arrow.up.right", verb: "", street: "", sign: sign)
            }
            let base = type == "off ramp" ? "Take the exit" : "Take the ramp"
            return TurnSpec(coordinate: loc, icon: side == "left" ? "arrow.up.left" : "arrow.up.right",
                            verb: onto.isEmpty ? base : "\(base) onto", street: onto)
        case "turn", "end of road":
            guard side != "" || mod == "uturn" else { return nil }
            if mod == "uturn" { return TurnSpec(coordinate: loc, icon: icon, verb: onto.isEmpty ? "Make a U-turn" : "Make a U-turn onto", street: onto) }
            return TurnSpec(coordinate: loc, icon: icon, verb: onto.isEmpty ? "Turn \(side)" : "Turn \(side) onto", street: onto)
        case "fork":
            return TurnSpec(coordinate: loc, icon: icon, verb: onto.isEmpty ? "Keep \(side)" : "Keep \(side) onto", street: onto)
        case "merge":
            return TurnSpec(coordinate: loc, icon: icon, verb: onto.isEmpty ? "Merge" : "Merge onto", street: onto)
        case "roundabout", "rotary":
            let n = s.maneuver.exit.map { "take exit \($0)" } ?? "take the exit"
            return TurnSpec(coordinate: loc, icon: "arrow.triangle.turn.up.right.circle",
                            verb: "At the roundabout, \(n)\(onto.isEmpty ? "" : " onto")", street: onto)
        case "continue", "new name":
            guard side != "" else { return nil }
            return TurnSpec(coordinate: loc, icon: icon, verb: onto.isEmpty ? "Keep \(side)" : "Keep \(side) onto", street: onto)
        default:
            guard side != "" else { return nil }
            return TurnSpec(coordinate: loc, icon: icon, verb: onto.isEmpty ? "Turn \(side)" : "Turn \(side) onto", street: onto)
        }
    }

    // MARK: Apple fallback

    static func apple(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, name: String) async throws -> [Route] {
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        req.transportType = .automobile
        req.requestsAlternateRoutes = true
        let routes = try await MKDirections(request: req).calculate().routes
            .prefix(3).compactMap { apple($0, name: name) }
            .sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
        guard !routes.isEmpty else { throw Failure(message: "No route found") }
        return routes
    }

    private static func apple(_ r: MKRoute, name: String) -> Route? {
        let pl = r.polyline
        guard pl.pointCount >= 2 else { return nil }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pl.pointCount)
        pl.getCoordinates(&coords, range: NSRange(location: 0, length: pl.pointCount))
        var turns: [TurnSpec] = []
        for st in r.steps where !st.instructions.isEmpty {
            let t = st.instructions, lower = t.lowercased()
            guard !lower.contains("destination"), st.polyline.pointCount > 0 else { continue }
            let at = st.polyline.points()[0].coordinate
            let icon = lower.contains("left") ? "arrow.turn.up.left" : lower.contains("right") ? "arrow.turn.up.right" : "arrow.up"
            turns.append(TurnSpec(coordinate: at, icon: icon, verb: t, street: ""))
        }
        var route = Route(line: "Drive", destination: name, kind: .drive, via: r.name.isEmpty ? nil : r.name,
                          stops: [Stop(id: 0, name: "Start", coordinate: coords[0]),
                                  Stop(id: 1, name: name, coordinate: coords[coords.count - 1])],
                          turns: turns, roads: [RoadSpec(coordinate: coords[0], name: r.name.isEmpty ? name : r.name)],
                          points: coords)
        route.duration = r.expectedTravelTime
        return route
    }
}

// MARK: OSRM JSON

struct OSRMResponse: Decodable {
    let code: String
    let routes: [OSRMRoute]
}
struct OSRMRoute: Decodable {
    let distance: Double
    let duration: Double
    let geometry: OSRMGeometry
    let legs: [OSRMLeg]
}
struct OSRMGeometry: Decodable { let coordinates: [[Double]] }
struct OSRMLeg: Decodable { let steps: [OSRMStep] }
struct OSRMStep: Decodable {
    let distance: Double
    let name: String?
    let ref: String?
    let destinations: String?
    let exits: String?
    let maneuver: OSRMManeuver
    let intersections: [OSRMIntersection]?
}
struct OSRMManeuver: Decodable {
    let type: String
    let modifier: String?
    let location: [Double]
    let exit: Int?
}
struct OSRMIntersection: Decodable {
    let classes: [String]?
    let lanes: [OSRMLane]?
}
struct OSRMLane: Decodable { let valid: Bool }
