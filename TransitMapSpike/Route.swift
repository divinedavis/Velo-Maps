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

/// A turn at a point on the line.
struct TurnSpec {
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let verb: String
    let street: String
}

/// A route line plus the stops on it. Distances are cumulative metres along the line.
struct Route {
    let line: String
    let destination: String
    let stops: [Stop]
    let turns: [TurnSpec]
    private(set) var points: [CLLocationCoordinate2D]
    private(set) var cumulative: [CLLocationDistance] = []
    private(set) var stopDistances: [CLLocationDistance] = []

    var length: CLLocationDistance { cumulative.last ?? 0 }

    init(line: String, destination: String, stops: [Stop], turns: [TurnSpec] = [],
         points: [CLLocationCoordinate2D]) {
        self.line = line
        self.destination = destination
        self.stops = stops
        self.turns = turns
        self.points = points
        recompute()
    }

    mutating func replacePoints(_ newPoints: [CLLocationCoordinate2D]) {
        guard newPoints.count >= 2 else { return }
        points = newPoints
        recompute()
    }

    private mutating func recompute() {
        var total: CLLocationDistance = 0
        cumulative = [0]
        for i in 1..<points.count {
            total += points[i - 1].distance(to: points[i])
            cumulative.append(total)
        }
        stopDistances = stops.map { stop in
            // Distance along the line of the vertex nearest to the stop.
            let nearest = points.indices.min { points[$0].distance(to: stop.coordinate) < points[$1].distance(to: stop.coordinate) } ?? 0
            return cumulative[nearest]
        }
    }

    /// Position and travel heading at `distance` metres along the route.
    func position(at distance: CLLocationDistance) -> (CLLocationCoordinate2D, CLLocationDirection) {
        let d = min(max(distance, 0), length)
        var i = cumulative.firstIndex { $0 >= d } ?? (points.count - 1)
        i = max(i, 1)
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
    var maneuvers: [Maneuver] {
        var out: [Maneuver] = turns.enumerated().map { i, t in
            let v = points.indices.min { points[$0].distance(to: t.coordinate) < points[$1].distance(to: t.coordinate) } ?? 0
            return Maneuver(id: i, at: cumulative[v], icon: t.icon, verb: t.verb, street: t.street)
        }
        out.append(Maneuver(id: out.count, at: length, icon: "mappin.circle.fill", verb: "Arrive at", street: destination))
        return out
    }

    /// Lanes on the approach to the next turn (demo data for the lane-guidance design).
    var lanesAtNextTurn: [Lane] {
        [Lane(id: 0, icon: "arrow.turn.up.left", active: true),
         Lane(id: 1, icon: "arrow.up", active: false),
         Lane(id: 2, icon: "arrow.up", active: false)]
    }

    /// Index of the next stop the bus has not yet passed.
    func nextStopIndex(at distance: CLLocationDistance) -> Int {
        stopDistances.firstIndex { $0 > distance + 5 } ?? (stops.count - 1)
    }
}

extension CLLocationCoordinate2D {
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
