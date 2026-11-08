import Foundation
import CoreLocation

/// A reported pothole: where it is and how far along the route.
struct Pothole: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let at: CLLocationDistance
    let mine: Bool
}

/// Simulated ride along the route. The map's display link advances `distance` every frame;
/// the card reads the coarse values below, which are published a few times a second.
@MainActor
final class Trip: ObservableObject {
    @Published private(set) var route: Route
    @Published private(set) var nextStop: Int = 1
    @Published private(set) var minutesLeft: Int = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var progress: Double = 0
    @Published var paused: Bool
    /// Ride → walk handoff: holding "end" switches to walking directions for the last leg.
    @Published private(set) var walking: Bool

    /// Preview switches: -cardStyle 0…5 (0 = original card, 1–5 = Liquid Glass designs)
    /// and -night YES for the dark map.
    let cardStyle: Int
    /// -mode walk -walkStyle 1…5 opens straight onto a walking design.
    let walkStyle: Int
    /// Preview states: -expanded YES (card swiped up), -potholeTapped YES (pothole button
    /// pressed once at launch), -turnStyle 1…5 (turn banner design), -turnAhead 120 (start
    /// the bus this many metres before the next turn).
    let startExpanded: Bool
    /// Ride card swiped up to settings (shared so the screen can tidy around it).
    @Published var cardExpanded = false
    let startPotholeTap: Bool
    let turnStyle: Int
    /// -signStyle 0…5: highway sign design inside the turn banner (0 = flat green sign).
    let signStyle: Int
    /// -reportMenu YES opens the "+" report menu ~1.5 s after launch (for screenshots/video).
    let startReportMenu: Bool
    let night: Bool

    /// Demo tuning, overridable from launch arguments for screenshot passes:
    /// -progress 0.35  -paused YES  -cameraDistance 330  -cameraPitch 50  -cameraLead -0.05  -speed 9
    let cameraDistance: Double
    let cameraPitch: Double
    /// How far ahead of the bus the camera aims, as a fraction of camera distance. Negative
    /// aims behind it, which pushes the bus up the screen, clear of the card.
    let cameraLead: Double
    /// Points between the bus marker's centre and the top of the card (-busGap).
    let busGap: Double
    let speed: Double              // metres per second of simulated travel
    private(set) var distance: CLLocationDistance

    private var startedAt = Date()
    private var lastPublish = Date.distantPast

    init(route: Route? = nil, defaults: UserDefaults = .standard) {
        // -demo drive: the Henry Hudson Parkway drive with highway entrance/exit signs.
        let route = route ?? (defaults.string(forKey: "demo") == "drive" ? Route.hhDrive : Route.m10)
        self.route = route
        let progress = defaults.number("progress") ?? 0.08
        distance = route.length * min(max(progress, 0), 1)
        paused = defaults.bool(forKey: "paused")
        cameraDistance = defaults.number("cameraDistance") ?? 330
        cameraPitch = defaults.number("cameraPitch") ?? 50
        cameraLead = defaults.number("cameraLead") ?? -0.05
        busGap = defaults.number("busGap") ?? 90
        speed = defaults.number("speed") ?? 9
        // Hero (4) chosen by the owner 11/7; other designs stay reachable for comparison.
        cardStyle = defaults.number("cardStyle").map(Int.init) ?? 4
        night = defaults.bool(forKey: "night")
        walking = defaults.string(forKey: "mode") == "walk"
        startExpanded = defaults.bool(forKey: "expanded")
        cardExpanded = startExpanded
        startPotholeTap = defaults.bool(forKey: "potholeTapped")
        // Lanes (2) chosen by the owner 11/7.
        turnStyle = defaults.number("turnStyle").map(Int.init) ?? 2
        signStyle = defaults.number("signStyle").map(Int.init) ?? 0
        startReportMenu = defaults.bool(forKey: "reportMenu")
        // Glance (4) chosen by the owner 11/7 for the walking leg.
        walkStyle = defaults.number("walkStyle").map(Int.init) ?? 4
        if let ahead = defaults.number("turnAhead"), let turn = route.maneuvers.first {
            distance = max(0, turn.at - ahead)
        }
        // -signAhead 150 -signIndex 0|1: start this far before a ramp with a highway sign.
        let signs = route.maneuvers.filter { $0.sign != nil }
        if let ahead = defaults.number("signAhead"), !signs.isEmpty {
            let i = min(Int(defaults.number("signIndex") ?? 0), signs.count - 1)
            distance = max(0, signs[i].at - ahead)
        }
        // Reports other riders already made on this route (demo data; the real app would load
        // these from a shared server).
        potholes = [700, 1450].map { Pothole(coordinate: route.position(at: $0).0, at: $0, mine: false) }
        publish(force: true)
    }

    // MARK: Potholes

    @Published private(set) var potholes: [Pothole] = []

    /// One tap: drop a pothole where the bus is right now.
    func reportPothole() {
        let (coord, _) = route.position(at: distance)
        potholes.append(Pothole(coordinate: coord, at: distance, mine: true))
    }

    /// Closest pothole still ahead on the route, if within `range` metres.
    func potholeAhead(within range: Double = 250) -> (Pothole, Double)? {
        let d = progress * route.length
        return potholes
            .map { ($0, $0.at - d) }
            .filter { $0.1 > 5 && $0.1 <= range }
            .min { $0.1 < $1.1 }
    }

    func advance(by dt: TimeInterval) {
        guard !paused, route.length > 0 else { return }
        distance += speed * dt
        if distance >= route.length { restart() }
        publish(force: false)
    }

    func endRide() { walking = true }

    /// Switch demo route (settings): start over at the beginning with fresh demo reports.
    func useRoute(_ newRoute: Route) {
        route = newRoute
        distance = 0
        startedAt = Date()
        potholes = [700, 1450].map { Pothole(coordinate: newRoute.position(at: $0).0, at: $0, mine: false) }
        publish(force: true)
    }

    func restart() {
        distance = 0
        startedAt = Date()
        publish(force: true)
    }

    private func publish(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublish) > 0.25 else { return }
        lastPublish = now
        let next = route.nextStopIndex(at: distance)
        if next != nextStop { nextStop = next }
        // Real buses average ~3–4 m/s in Manhattan including stops; use that for the ETA, not the demo speed.
        let mins = Int(((route.length - distance) / route.etaSpeed / 60).rounded(.up))
        if mins != minutesLeft { minutesLeft = mins }
        elapsed = now.timeIntervalSince(startedAt)
        progress = route.length > 0 ? distance / route.length : 0
    }
}

extension UserDefaults {
    /// Launch arguments (-progress 0.25) land in UserDefaults as strings, while values set in
    /// code are numbers; accept both.
    func number(_ key: String) -> Double? {
        switch object(forKey: key) {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
