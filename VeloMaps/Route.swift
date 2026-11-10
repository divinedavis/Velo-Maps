import CoreLocation
import MapKit

/// One bus stop on the test route.
struct Stop: Identifiable, Hashable {
    let id: Int
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (a: Stop, b: Stop) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A turn at a point on the line. Ramps carry the wording of their highway sign.
struct TurnSpec {
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let verb: String
    let street: String
    var sign: HighwaySign? = nil
}

enum RouteKind { case bus, drive }

/// Where a road starts along the line, its name and route number (from OSM via OSRM).
/// Unnamed ramps are labelled from their own sign ("Ramp to NY 9A North").
struct RoadSpec {
    let coordinate: CLLocationCoordinate2D
    let name: String
    var ref: String? = nil
    /// Lanes in the direction of travel (OSM lanes:forward, or lanes / 2 on two-way roads).
    var lanes: Int = 1
    /// Two-way road: the OSM line is the middle of the road, our lanes are to its right.
    /// One-way (motorways, ramps, dual carriageways): the line is the middle of our lanes.
    var twoWay: Bool = true
    /// Posted limit in mph (OSM maxspeed); nil = not known.
    var speedLimit: Int? = nil
}

/// The text on a highway entrance or exit sign, taken verbatim from OpenStreetMap:
/// `junction:ref` (exit number), `destination:ref` (route shields, e.g. "NY 9A North") and
/// `destination` (the destination lines). Nothing here is reworded; when OSM has no exit
/// number, none is shown.
struct HighwaySign: Equatable {
    enum Kind { case entrance, exit }
    let kind: Kind
    let exitNumber: String?
    let shields: [String]
    let destinations: [String]

    init(kind: Kind, exitNumber: String? = nil, shields: [String], destinations: [String]) {
        self.kind = kind
        self.exitNumber = exitNumber
        self.shields = shields
        self.destinations = destinations
    }

    /// OSRM's step `destinations` string: "NY 9A North: Henry Hudson Parkway" (refs before
    /// the colon, names after; multiple values comma-separated).
    init(kind: Kind, exitNumber: String? = nil, osrmDestinations text: String) {
        let parts = text.components(separatedBy: ": ")
        let refs = parts.count > 1 ? parts[0] : ""
        let names = parts.count > 1 ? parts.dropFirst().joined(separator: ": ") : text
        func split(_ s: String) -> [String] {
            s.components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        self.init(kind: kind, exitNumber: exitNumber, shields: split(refs), destinations: split(names))
    }

    /// Raw OSM tags on the ramp way (and its motorway_junction node's `ref`).
    init(kind: Kind, osmTags t: [String: String]) {
        func split(_ s: String?) -> [String] {
            (s ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        self.init(kind: kind, exitNumber: t["junction:ref"] ?? t["ref"],
                  shields: split(t["destination:ref"]), destinations: split(t["destination"] ?? t["exit_to"]))
    }

    /// Banner line, built only from the sign's own words.
    var instruction: String {
        let to = shields.first ?? destinations.first ?? ""
        switch kind {
        case .entrance: return "Take the ramp to \(to)"
        case .exit: return exitNumber.map { "Take exit \($0) to \(to)" } ?? "Take the exit to \(to)"
        }
    }

    /// What VoiceOver reads: the sign, top to bottom.
    var spoken: String {
        ([exitNumber.map { "Exit \($0)" }].compactMap { $0 } + shields + destinations).joined(separator: ", ")
    }
}

/// A route line plus the stops on it. Distances are cumulative metres along the line.
struct Route {
    let line: String
    let destination: String
    let kind: RouteKind
    let via: String?
    let stops: [Stop]
    let turns: [TurnSpec]
    let roads: [RoadSpec]
    private(set) var points: [CLLocationCoordinate2D]
    private(set) var cumulative: [CLLocationDistance] = []
    private(set) var stopDistances: [CLLocationDistance] = []
    /// Where each road starts along the line.
    private(set) var roadStarts: [CLLocationDistance] = []
    /// Road indices ordered by where they start (ties keep list order), for binary search.
    private var roadOrder: [Int] = []
    private(set) var maneuverList: [Maneuver] = []
    /// The centre line sampled every `laneSpacing` metres, and the bearing pointing to its
    /// right there. Worked out once per route: the lane line, every faint lane and the lane
    /// offsets all read these instead of searching the line again (a 60 km route took 1.7 s
    /// to draw on the main thread before, 11/10).
    private var sampleCentres: [CLLocationCoordinate2D] = []
    private var sampleRight: [CLLocationDirection] = []
    /// Expected travel time for the whole route (seconds), from the router; nil = estimate.
    var duration: Double?
    /// Live routes: posted limits along the route (SpeedLimits); empty = use the roads' own.
    var limitChanges: [(start: Double, mph: Int)] = []

    /// Posted speed limit (mph) at `distance`, if known.
    func speedLimit(at distance: CLLocationDistance) -> Int? {
        if !limitChanges.isEmpty {
            return limitChanges.last { $0.start <= distance + 1 }?.mph
        }
        return road(at: distance)?.speedLimit
    }
    /// Lateral offset (metres right of the OSM line) of the lane to drive in, every 4 m.
    private(set) var laneOffsets: [Double] = []
    static let laneSpacing = 4.0
    static let laneWidth = 3.3

    var length: CLLocationDistance { cumulative.last ?? 0 }

    /// Average real-world speed for the ETA (not the demo playback speed): Manhattan buses
    /// ~3.5 m/s including stops; a parkway drive with city streets ~9 m/s.
    var etaSpeed: Double { kind == .drive ? 9 : 3.5 }

    init(line: String, destination: String, kind: RouteKind = .bus, via: String? = nil,
         stops: [Stop], turns: [TurnSpec] = [], roads: [RoadSpec] = [], points: [CLLocationCoordinate2D]) {
        self.line = line
        self.destination = destination
        self.kind = kind
        self.via = via
        self.stops = stops
        self.turns = turns
        self.roads = roads
        self.points = Route.roundCorners(points)
        recompute()
    }

    mutating func replacePoints(_ newPoints: [CLLocationCoordinate2D]) {
        guard newPoints.count >= 2 else { return }
        points = Route.roundCorners(newPoints)
        recompute()
    }

    /// Street data has square corners; a vehicle drives an arc. Every vertex that turns more
    /// than 12° becomes a circular fillet (radius up to `radius`, never more than 45% of either
    /// neighbouring segment), so the vehicle's heading changes smoothly through a turn instead
    /// of snapping (owner, 11/8: "the turn is not smooth, the car does not turn properly").
    static func roundCorners(_ pts: [CLLocationCoordinate2D], radius: Double = 10) -> [CLLocationCoordinate2D] {
        guard pts.count > 2 else { return pts }
        var out: [CLLocationCoordinate2D] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = pts[i - 1], b = pts[i], c = pts[i + 1]
            // Local metres around the corner.
            let mx = 111_320 * cos(b.latitude * .pi / 180), my = 110_540.0
            func local(_ p: CLLocationCoordinate2D) -> (Double, Double) { ((p.longitude - b.longitude) * mx, (p.latitude - b.latitude) * my) }
            func geo(_ x: Double, _ y: Double) -> CLLocationCoordinate2D { .init(latitude: b.latitude + y / my, longitude: b.longitude + x / mx) }
            let (ax, ay) = local(a), (cx, cy) = local(c)
            let la = hypot(ax, ay), lc = hypot(cx, cy)
            guard la > 0.5, lc > 0.5 else { out.append(b); continue }
            let u1 = (ax / la, ay / la), u2 = (cx / lc, cy / lc)
            let cosTheta = max(-1, min(1, u1.0 * u2.0 + u1.1 * u2.1))
            let theta = acos(cosTheta)                 // interior angle at the corner
            let turn = Double.pi - theta
            guard turn > 12 * .pi / 180 else { out.append(b); continue }
            var t = radius / tan(theta / 2)            // tangent length for the wanted radius
            t = min(t, 0.45 * min(la, lc))
            let r = t * tan(theta / 2)
            let p1 = (u1.0 * t, u1.1 * t), p2 = (u2.0 * t, u2.1 * t)
            let bis = (u1.0 + u2.0, u1.1 + u2.1), bl = hypot(bis.0, bis.1)
            guard bl > 1e-6 else { out.append(b); continue }
            let d = r / sin(theta / 2)
            let o = (bis.0 / bl * d, bis.1 / bl * d)  // arc centre
            let a1 = atan2(p1.1 - o.1, p1.0 - o.0)
            let a2 = atan2(p2.1 - o.1, p2.0 - o.0)
            var sweep = a2 - a1
            while sweep > .pi { sweep -= 2 * .pi }
            while sweep < -.pi { sweep += 2 * .pi }
            let n = max(3, Int(turn * 180 / .pi / 8))
            for k in 0...n {
                let ang = a1 + sweep * Double(k) / Double(n)
                out.append(geo(o.0 + r * cos(ang), o.1 + r * sin(ang)))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    /// The vehicle's direction of travel at `distance`: the chord across ±4 m of the (rounded)
    /// line, so it turns continuously through a corner.
    func vehicleHeading(at distance: CLLocationDistance) -> CLLocationDirection {
        let d = min(max(distance, 4), max(length - 4, 4))
        let (a, _) = position(at: d - 4)
        let (b, _) = position(at: d + 4)
        return a.bearing(to: b)
    }

    private mutating func recompute() {
        var total: CLLocationDistance = 0
        cumulative = [0]
        for i in 1..<points.count {
            total += points[i - 1].distance(to: points[i])
            cumulative.append(total)
        }
        stopDistances = stops.map { distanceAlong(nearest: $0.coordinate) }
        roadStarts = roads.map { distanceAlong(nearest: $0.coordinate) }
        roadOrder = roads.indices.sorted { (roadStarts[$0], $0) < (roadStarts[$1], $1) }
        maneuverList = computeManeuvers()
        let n = total > 0 ? Int(total / Route.laneSpacing) + 1 : 0
        sampleCentres = []; sampleRight = []
        sampleCentres.reserveCapacity(n); sampleRight.reserveCapacity(n)
        for i in 0..<n {
            let d = Double(i) * Route.laneSpacing
            sampleCentres.append(position(at: d).0)
            sampleRight.append(vehicleHeading(at: d) + 90)
        }
        laneOffsets = computeLaneOffsets()
    }

    /// Which lane to be in, as metres right of the OSM line, sampled every 4 m and smoothed
    /// so lane changes are gradual S-curves. Lane choice (owner, 11/8: "show the red line in
    /// the lane that a user is supposed to be in"): before a left turn the leftmost lane,
    /// before a right turn or an exit/entrance ramp the rightmost; otherwise the bus keeps the
    /// curb lane and a car the right lane in town or the middle lane on a highway.
    private func computeLaneOffsets() -> [Double] {
        guard !roads.isEmpty, length > 0 else { return [] }
        let ms = maneuvers
        let n = Int(length / Route.laneSpacing) + 1
        var desired = [Double](repeating: 0, count: n)
        var mi = 0   // first maneuver still ahead; d only grows, so this only moves forward
        for i in 0..<n {
            let d = Double(i) * Route.laneSpacing
            let r = road(at: d) ?? roads[0]
            let fwd = max(1, r.lanes)
            var k: Int = kind == .bus ? fwd - 1 : (r.twoWay ? fwd - 1 : fwd / 2)
            while mi < ms.count, ms[mi].at <= d { mi += 1 }
            if mi < ms.count {
                let next = ms[mi]
                let window: Double = next.sign != nil ? 600 : 150
                if next.at - d <= window {
                    if next.icon.contains("left") { k = 0 }
                    else if next.icon.contains("right") || next.sign != nil { k = fwd - 1 }
                }
            }
            let w = Route.laneWidth
            desired[i] = r.twoWay ? (Double(k) + 0.5) * w : (Double(k) + 0.5 - Double(fwd) / 2) * w
        }
        // Lane changes take ~40 m: a trailing moving average turns steps into S-curves.
        // The window starts full of the first lane, so the start doesn't swing.
        let span = 10
        var out = [Double](repeating: 0, count: n)
        var sum = desired[0] * Double(span)
        for i in 0..<n {
            sum += desired[i] - desired[max(0, i - span)]
            out[i] = sum / Double(span)
        }
        return out
    }

    /// Lateral lane offset at `distance` (metres right of the OSM line).
    func laneOffset(at distance: CLLocationDistance) -> Double {
        guard !laneOffsets.isEmpty else { return 0 }
        let x = min(max(distance / Route.laneSpacing, 0), Double(laneOffsets.count - 1))
        let i = Int(x), f = x - Double(i)
        return i + 1 < laneOffsets.count ? laneOffsets[i] * (1 - f) + laneOffsets[i + 1] * f : laneOffsets[i]
    }

    /// Point in the chosen lane at `distance`.
    func lanePosition(at distance: CLLocationDistance) -> CLLocationCoordinate2D {
        let (c, _) = position(at: distance)
        let off = laneOffset(at: distance)
        return off == 0 ? c : c.offset(by: off, bearing: vehicleHeading(at: distance) + 90)
    }

    /// The lane path as points every 4 m (for drawing), or every lane `k` of the road for
    /// the all-lanes design (nil where the road has fewer lanes).
    func lanePath() -> [CLLocationCoordinate2D] {
        guard laneOffsets.count == sampleCentres.count else {   // no road data: the centre line
            return sampleCentres
        }
        return sampleCentres.indices.map { i in
            laneOffsets[i] == 0 ? sampleCentres[i] : sampleCentres[i].offset(by: laneOffsets[i], bearing: sampleRight[i])
        }
    }

    func lanePaths(allLanesUpTo maxLanes: Int = 4) -> [[CLLocationCoordinate2D]] {
        guard !roads.isEmpty else { return [] }
        // The road under each sample, looked up once and shared by every lane.
        let under = sampleCentres.indices.map { road(at: Double($0) * Route.laneSpacing) ?? roads[0] }
        var paths: [[CLLocationCoordinate2D]] = []
        for k in 0..<maxLanes {
            var current: [CLLocationCoordinate2D] = []
            for i in sampleCentres.indices {
                let r = under[i]
                if k < max(1, r.lanes) {
                    let off = r.twoWay ? (Double(k) + 0.5) * Route.laneWidth
                                       : (Double(k) + 0.5 - Double(max(1, r.lanes)) / 2) * Route.laneWidth
                    current.append(sampleCentres[i].offset(by: off, bearing: sampleRight[i]))
                } else if current.count > 1 {
                    paths.append(current); current = []
                } else { current = [] }
            }
            if current.count > 1 { paths.append(current) }
        }
        return paths
    }

    /// Position and travel heading at `distance` metres along the route.
    func position(at distance: CLLocationDistance) -> (CLLocationCoordinate2D, CLLocationDirection) {
        let d = min(max(distance, 0), length)
        // First index with cumulative >= d (binary search: live routes have thousands of points).
        var lo = 0, hi = cumulative.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if cumulative[mid] < d { lo = mid + 1 } else { hi = mid } }
        let i = max(lo, 1)
        let a = points[i - 1], b = points[i]
        let seg = cumulative[i] - cumulative[i - 1]
        let t = seg > 0 ? (d - cumulative[i - 1]) / seg : 0
        let coord = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t)
        return (coord, a.bearing(to: b))
    }

    /// Smoothed heading: average of the bearings over the next `window` metres, so the camera
    /// eases into turns instead of snapping at each vertex.
    func smoothedHeading(at distance: CLLocationDistance, window: CLLocationDistance = 120) -> CLLocationDirection {
        var x = 0.0, y = 0.0
        let steps = 8
        for s in 0...steps {
            let (_, h) = position(at: distance + window * Double(s) / Double(steps) - window * 0.25)
            x += cos(h * .pi / 180); y += sin(h * .pi / 180)
        }
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    /// Turns along the route plus the final arrival, in order.
    var maneuvers: [Maneuver] { maneuverList }

    private func computeManeuvers() -> [Maneuver] {
        var out: [Maneuver] = turns.enumerated().map { i, t in
            Maneuver(id: i, at: distanceAlong(nearest: t.coordinate), icon: t.icon, verb: t.verb, street: t.street, sign: t.sign)
        }
        out.sort { $0.at < $1.at }
        out = out.enumerated().map { i, m in Maneuver(id: i, at: m.at, icon: m.icon, verb: m.verb, street: m.street, sign: m.sign) }
        out.append(Maneuver(id: out.count, at: length, icon: "mappin.circle.fill", verb: "Arrive at", street: destination))
        return out
    }

    /// Live GPS → route: the closest point on the line within a window around the last known
    /// distance (so a route that doubles back can't jump), and how far off the line the fix is.
    func snap(_ c: CLLocationCoordinate2D, near last: CLLocationDistance,
              behind: Double = 150, ahead: Double = 600) -> (distance: CLLocationDistance, offBy: Double) {
        let mx = 111_320 * cos(c.latitude * .pi / 180), my = 110_540.0
        var best = (d: last, off: Double.infinity)
        for i in 1..<points.count {
            if cumulative[i] < last - behind { continue }
            if cumulative[i - 1] > last + ahead { break }
            let a = points[i - 1], b = points[i]
            let ax = (a.longitude - c.longitude) * mx, ay = (a.latitude - c.latitude) * my
            let bx = (b.longitude - c.longitude) * mx, by = (b.latitude - c.latitude) * my
            let vx = bx - ax, vy = by - ay, len2 = vx * vx + vy * vy
            let t = len2 > 0 ? max(0, min(1, -(ax * vx + ay * vy) / len2)) : 0
            let px = ax + vx * t, py = ay + vy * t
            let off = (px * px + py * py).squareRoot()
            if off < best.off { best = (cumulative[i - 1] + (cumulative[i] - cumulative[i - 1]) * t, off) }
        }
        return (best.d, best.off)
    }

    /// Distance along the line of the vertex nearest to `c`.
    func distanceAlong(nearest c: CLLocationCoordinate2D) -> CLLocationDistance {
        let cosLat = cos(c.latitude * .pi / 180)
        var best = 0, bestD = Double.infinity
        // Runs once per stop, road and turn of a route: a plain indexed loop over the buffer.
        points.withUnsafeBufferPointer { pts in
            for i in 0..<pts.count {
                let dy = pts[i].latitude - c.latitude, dx = (pts[i].longitude - c.longitude) * cosLat
                let d = dx * dx + dy * dy
                if d < bestD { bestD = d; best = i }
            }
        }
        return cumulative[best]
    }

    /// Lane arrows for a plain turn (illustrative: left/right lane highlighted). Ramps show
    /// their highway sign instead, so no lanes are guessed for them.
    func lanes(for m: Maneuver) -> [Lane] {
        if m.icon.contains("left") {
            return [Lane(id: 0, icon: m.icon, active: true), Lane(id: 1, icon: "arrow.up", active: false), Lane(id: 2, icon: "arrow.up", active: false)]
        }
        if m.icon.contains("right") {
            return [Lane(id: 0, icon: "arrow.up", active: false), Lane(id: 1, icon: "arrow.up", active: false), Lane(id: 2, icon: m.icon, active: true)]
        }
        return [Lane(id: 0, icon: "arrow.up", active: true)]
    }

    /// The road under the vehicle at `distance` metres along the line.
    func road(at distance: CLLocationDistance) -> RoadSpec? {
        guard !roads.isEmpty else { return nil }
        // Last road (in start order) that has started by here; none yet = the first road.
        var lo = 0, hi = roadOrder.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if roadStarts[roadOrder[mid]] <= distance + 1 { lo = mid + 1 } else { hi = mid }
        }
        return roads[lo > 0 ? roadOrder[lo - 1] : 0]
    }

    /// Index of the next stop the bus has not yet passed.
    func nextStopIndex(at distance: CLLocationDistance) -> Int {
        stopDistances.firstIndex { $0 > distance + 5 } ?? (stops.count - 1)
    }
}

extension CLLocationCoordinate2D {
    /// The point `metres` away along compass `bearing` (flat-earth; fine for camera offsets).
    func offset(by metres: Double, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
        let b = bearing * .pi / 180
        return .init(latitude: latitude + metres * cos(b) / 110_540,
                     longitude: longitude + metres * sin(b) / (111_320 * cos(latitude * .pi / 180)))
    }

    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    func bearing(to other: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }
}

extension Route {
    /// M10 northbound along Central Park West, W 72 St → W 96 St. Stop coordinates are the
    /// intersections; the line is the avenue's real centreline.
    static let m10 = Route(
        line: "M10",
        destination: "Columbus Av / W 96 St",
        stops: [
            Stop(id: 0, name: "CPW / W 72 St", coordinate: .init(latitude: 40.77630, longitude: -73.97620)),
            Stop(id: 1, name: "CPW / W 77 St", coordinate: .init(latitude: 40.77955, longitude: -73.97383)),
            Stop(id: 2, name: "CPW / W 81 St", coordinate: .init(latitude: 40.78215, longitude: -73.97195)),
            Stop(id: 3, name: "CPW / W 86 St", coordinate: .init(latitude: 40.78530, longitude: -73.96965)),
            Stop(id: 4, name: "CPW / W 90 St", coordinate: .init(latitude: 40.78790, longitude: -73.96778)),
            Stop(id: 5, name: "CPW / W 96 St", coordinate: .init(latitude: 40.79165, longitude: -73.96505)),
            Stop(id: 6, name: "Columbus Av / W 96 St", coordinate: .init(latitude: 40.7928760, longitude: -73.9675451)),
        ],
        turns: [
            TurnSpec(coordinate: .init(latitude: 40.7916758, longitude: -73.9646940),
                     icon: "arrow.turn.up.left", verb: "Turn left onto", street: "W 96 St"),
        ],
        roads: [   // OSM names
            RoadSpec(coordinate: .init(latitude: 40.7762266, longitude: -73.9759630), name: "Central Park West", lanes: 2, speedLimit: 25),
            RoadSpec(coordinate: .init(latitude: 40.7917254, longitude: -73.9648118), name: "West 96th Street", lanes: 2, speedLimit: 25),
        ],
        // Central Park West centreline from OpenStreetMap (© OpenStreetMap contributors, ODbL).
        points: [
            .init(latitude: 40.7762266, longitude: -73.9759630),
            .init(latitude: 40.7763121, longitude: -73.9758997),
            .init(latitude: 40.7765182, longitude: -73.9757504),
            .init(latitude: 40.7768546, longitude: -73.9755068),
            .init(latitude: 40.7769031, longitude: -73.9754712),
            .init(latitude: 40.7769426, longitude: -73.9754419),
            .init(latitude: 40.7774869, longitude: -73.9750388),
            .init(latitude: 40.7775416, longitude: -73.9749993),
            .init(latitude: 40.7775922, longitude: -73.9749628),
            .init(latitude: 40.7781184, longitude: -73.9745824),
            .init(latitude: 40.7781744, longitude: -73.9745417),
            .init(latitude: 40.7782297, longitude: -73.9745019),
            .init(latitude: 40.7785507, longitude: -73.9742700),
            .init(latitude: 40.7787616, longitude: -73.9741176),
            .init(latitude: 40.7788134, longitude: -73.9740803),
            .init(latitude: 40.7788725, longitude: -73.9740373),
            .init(latitude: 40.7793764, longitude: -73.9736737),
            .init(latitude: 40.7794104, longitude: -73.9736486),
            .init(latitude: 40.7794865, longitude: -73.9735934),
            .init(latitude: 40.7795660, longitude: -73.9735358),
            .init(latitude: 40.7798151, longitude: -73.9733542),
            .init(latitude: 40.7807149, longitude: -73.9726981),
            .init(latitude: 40.7809834, longitude: -73.9725008),
            .init(latitude: 40.7813224, longitude: -73.9722516),
            .init(latitude: 40.7816180, longitude: -73.9720367),
            .init(latitude: 40.7819198, longitude: -73.9718126),
            .init(latitude: 40.7820388, longitude: -73.9717224),
            .init(latitude: 40.7821384, longitude: -73.9716479),
            .init(latitude: 40.7824229, longitude: -73.9714456),
            .init(latitude: 40.7826372, longitude: -73.9712933),
            .init(latitude: 40.7826689, longitude: -73.9712708),
            .init(latitude: 40.7827163, longitude: -73.9712370),
            .init(latitude: 40.7827717, longitude: -73.9711974),
            .init(latitude: 40.7833020, longitude: -73.9708126),
            .init(latitude: 40.7833528, longitude: -73.9707756),
            .init(latitude: 40.7834159, longitude: -73.9707295),
            .init(latitude: 40.7839304, longitude: -73.9703541),
            .init(latitude: 40.7839869, longitude: -73.9703125),
            .init(latitude: 40.7840515, longitude: -73.9702639),
            .init(latitude: 40.7842861, longitude: -73.9700939),
            .init(latitude: 40.7845721, longitude: -73.9698866),
            .init(latitude: 40.7846230, longitude: -73.9698495),
            .init(latitude: 40.7846848, longitude: -73.9698012),
            .init(latitude: 40.7848398, longitude: -73.9696855),
            .init(latitude: 40.7852035, longitude: -73.9694094),
            .init(latitude: 40.7852965, longitude: -73.9693444),
            .init(latitude: 40.7854012, longitude: -73.9692709),
            .init(latitude: 40.7859234, longitude: -73.9688909),
            .init(latitude: 40.7859742, longitude: -73.9688537),
            .init(latitude: 40.7860311, longitude: -73.9688136),
            .init(latitude: 40.7865517, longitude: -73.9684311),
            .init(latitude: 40.7866050, longitude: -73.9683927),
            .init(latitude: 40.7866638, longitude: -73.9683486),
            .init(latitude: 40.7869227, longitude: -73.9681638),
            .init(latitude: 40.7871816, longitude: -73.9679789),
            .init(latitude: 40.7872350, longitude: -73.9679404),
            .init(latitude: 40.7872934, longitude: -73.9678961),
            .init(latitude: 40.7878081, longitude: -73.9675140),
            .init(latitude: 40.7878716, longitude: -73.9674683),
            .init(latitude: 40.7879373, longitude: -73.9674218),
            .init(latitude: 40.7881763, longitude: -73.9672511),
            .init(latitude: 40.7884375, longitude: -73.9670646),
            .init(latitude: 40.7885002, longitude: -73.9670210),
            .init(latitude: 40.7885487, longitude: -73.9669851),
            .init(latitude: 40.7886992, longitude: -73.9668738),
            .init(latitude: 40.7890673, longitude: -73.9666014),
            .init(latitude: 40.7891218, longitude: -73.9665628),
            .init(latitude: 40.7891735, longitude: -73.9665257),
            .init(latitude: 40.7894158, longitude: -73.9663475),
            .init(latitude: 40.7896838, longitude: -73.9661503),
            .init(latitude: 40.7897447, longitude: -73.9661041),
            .init(latitude: 40.7897946, longitude: -73.9660676),
            .init(latitude: 40.7903238, longitude: -73.9656836),
            .init(latitude: 40.7903702, longitude: -73.9656483),
            .init(latitude: 40.7904251, longitude: -73.9656070),
            .init(latitude: 40.7906542, longitude: -73.9654397),
            .init(latitude: 40.7909467, longitude: -73.9652262),
            .init(latitude: 40.7909985, longitude: -73.9651883),
            .init(latitude: 40.7910513, longitude: -73.9651495),
            .init(latitude: 40.7915874, longitude: -73.9647609),
            .init(latitude: 40.7916758, longitude: -73.9646940),
            // Left onto W 96 St, west to Columbus Av (OpenStreetMap way 5672068).
            .init(latitude: 40.7917254, longitude: -73.9648118),
            .init(latitude: 40.7927485, longitude: -73.9672421),
            .init(latitude: 40.7928147, longitude: -73.9673993),
            .init(latitude: 40.7928760, longitude: -73.9675451),
        ]
    )
}
