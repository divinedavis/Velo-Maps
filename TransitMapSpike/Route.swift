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

/// A route line plus the stops on it. Distances are cumulative metres along the line.
struct Route {
    let line: String
    let destination: String
    let stops: [Stop]
    private(set) var points: [CLLocationCoordinate2D]
    private(set) var cumulative: [CLLocationDistance] = []
    private(set) var stopDistances: [CLLocationDistance] = []

    var length: CLLocationDistance { cumulative.last ?? 0 }

    init(line: String, destination: String, stops: [Stop], points: [CLLocationCoordinate2D]) {
        self.line = line
        self.destination = destination
        self.stops = stops
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
    /// intersections; the line between them is replaced by Apple's road-following directions
    /// at launch when those are available (see RouteLoader).
    static let m10 = Route(
        line: "M10",
        destination: "CPW / W 96 St",
        stops: [
            Stop(id: 0, name: "CPW / W 72 St", coordinate: .init(latitude: 40.77630, longitude: -73.97620)),
            Stop(id: 1, name: "CPW / W 77 St", coordinate: .init(latitude: 40.77955, longitude: -73.97383)),
            Stop(id: 2, name: "CPW / W 81 St", coordinate: .init(latitude: 40.78215, longitude: -73.97195)),
            Stop(id: 3, name: "CPW / W 86 St", coordinate: .init(latitude: 40.78530, longitude: -73.96965)),
            Stop(id: 4, name: "CPW / W 90 St", coordinate: .init(latitude: 40.78790, longitude: -73.96778)),
            Stop(id: 5, name: "CPW / W 96 St", coordinate: .init(latitude: 40.79165, longitude: -73.96505)),
        ],
        points: [
            .init(latitude: 40.77630, longitude: -73.97620),
            .init(latitude: 40.77955, longitude: -73.97383),
            .init(latitude: 40.78215, longitude: -73.97195),
            .init(latitude: 40.78530, longitude: -73.96965),
            .init(latitude: 40.78790, longitude: -73.96778),
            .init(latitude: 40.79165, longitude: -73.96505),
        ]
    )
}

/// Snaps the route line to real roads with MKDirections, one hop per stop pair. A hop is kept
/// only if Apple's path is close to the straight-line distance (i.e. it stayed on the avenue);
/// otherwise the straight segment stays.
enum RouteLoader {
    @MainActor
    static func snapped(_ route: Route) async -> Route {
        var out: [CLLocationCoordinate2D] = [route.stops[0].coordinate]
        for (a, b) in zip(route.stops, route.stops.dropFirst()) {
            let req = MKDirections.Request()
            req.source = mapItem(a.coordinate)
            req.destination = mapItem(b.coordinate)
            req.transportType = .automobile
            let straight = a.coordinate.distance(to: b.coordinate)
            if let r = try? await MKDirections(request: req).calculate().routes.first,
               r.distance < straight * 1.3 {
                let pl = r.polyline
                var coords = [CLLocationCoordinate2D](repeating: .init(), count: pl.pointCount)
                pl.getCoordinates(&coords, range: NSRange(location: 0, length: pl.pointCount))
                out.append(contentsOf: coords.dropFirst())
            } else {
                out.append(b.coordinate)
            }
        }
        var r = route
        r.replacePoints(out)
        return r
    }

    private static func mapItem(_ c: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26, *) {
            return MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude), address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: c))
    }
}
