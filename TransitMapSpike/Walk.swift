import Foundation
import MapKit

/// One instruction in the walking leg, with where it ends along the path.
struct WalkStep: Identifiable {
    let id: Int
    let instruction: String
    let length: CLLocationDistance
    let endsAt: CLLocationDistance

    var icon: String {
        let t = instruction.lowercased()
        if t.contains("destination") || t.contains("arrive") { return "mappin.circle.fill" }
        if t.contains("left") { return "arrow.turn.up.left" }
        if t.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// Walking leg from the stop where the rider got off to their destination. Uses Apple's
/// walking directions; a simulated walker moves along the path like the bus does.
@MainActor
final class Walk: ObservableObject {
    let destinationName = "Symphony Space"
    let destinationAddress = "2537 Broadway"
    /// Symphony Space, from OpenStreetMap / Nominatim.
    let destination = CLLocationCoordinate2D(latitude: 40.7939619, longitude: -73.9726618)

    @Published private(set) var path: Route?
    @Published private(set) var steps: [WalkStep] = []
    @Published private(set) var currentStep = 0
    @Published private(set) var metresLeft: CLLocationDistance = 0
    @Published private(set) var metresToTurn: CLLocationDistance = 0
    private(set) var distance: CLLocationDistance = 0
    private var lastPublish = Date.distantPast

    let paused: Bool
    let startProgress: Double
    let speed: Double        // demo walking speed, m/s
    /// Status-bar clock used for "Arrive 9:47" so screenshots agree with the 9:41 status bar.
    private let clockBase: Date?

    init(defaults: UserDefaults = .standard) {
        paused = defaults.bool(forKey: "paused")
        startProgress = defaults.object(forKey: "walkProgress") as? Double ?? 0.12
        speed = defaults.object(forKey: "walkSpeed") as? Double ?? 4
        if let s = defaults.string(forKey: "demoClock") {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            clockBase = parts.count == 2 ? Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) : nil
        } else {
            clockBase = nil
        }
    }

    var minutesLeft: Int { max(1, Int((metresLeft / 1.35 / 60).rounded(.up))) }

    var arrivalText: String {
        let arrive = (clockBase ?? Date()).addingTimeInterval(Double(minutesLeft) * 60)
        return arrive.formatted(date: .omitted, time: .shortened)
    }

    var current: WalkStep? { steps.indices.contains(currentStep) ? steps[currentStep] : nil }
    var following: WalkStep? { steps.indices.contains(currentStep + 1) ? steps[currentStep + 1] : nil }

    func load(from start: CLLocationCoordinate2D) async {
        guard path == nil else { return }
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        req.transportType = .walking
        guard let r = try? await MKDirections(request: req).calculate().routes.first else { return }
        let pl = r.polyline
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pl.pointCount)
        pl.getCoordinates(&coords, range: NSRange(location: 0, length: pl.pointCount))
        let route = Route(line: "walk", destination: destinationName,
                          stops: [Stop(id: 0, name: "start", coordinate: start),
                                  Stop(id: 1, name: destinationName, coordinate: destination)],
                          points: coords)
        var total: CLLocationDistance = 0
        var out: [WalkStep] = []
        for st in r.steps where !st.instructions.isEmpty {
            total += st.distance
            out.append(WalkStep(id: out.count, instruction: st.instructions, length: st.distance, endsAt: total))
        }
        // Steps' first entry often has zero length ("Proceed to the route"); drop it.
        steps = out.filter { $0.length > 0 || $0.instruction.lowercased().contains("destination") }
        path = route
        distance = route.length * startProgress
        publish(force: true)
    }

    func advance(by dt: TimeInterval) {
        guard !paused, let path else { return }
        distance = min(distance + speed * dt, path.length)
        publish(force: false)
    }

    private func publish(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublish) > 0.25, let path else { return }
        lastPublish = now
        metresLeft = path.length - distance
        let idx = steps.firstIndex { $0.endsAt > distance + 3 } ?? max(steps.count - 1, 0)
        if idx != currentStep { currentStep = idx }
        // Distance to the end of the current step = where the turn happens.
        metresToTurn = max(0, (current?.endsAt ?? path.length) - distance)
    }
}

/// US-style short distances: feet under ~0.1 mi, then tenths of a mile.
func walkDistance(_ m: CLLocationDistance) -> String {
    let feet = m * 3.28084
    if feet < 528 { return "\(max(10, Int((feet / 10).rounded()) * 10)) ft" }
    return String(format: "%.1f mi", m / 1609.34)
}
