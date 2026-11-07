import Foundation
import CoreLocation

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
    /// Preview states: -expanded YES (card swiped up), -pothole YES (report sheet open),
    /// -potholeDone YES (confirmation showing).
    let startExpanded: Bool
    let startPotholeSheet: Bool
    let startPotholeToast: Bool
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

    init(route: Route = .m10, defaults: UserDefaults = .standard) {
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
        startPotholeSheet = defaults.bool(forKey: "pothole")
        startPotholeToast = defaults.bool(forKey: "potholeDone")
        startReportMenu = defaults.bool(forKey: "reportMenu")
        // Glance (4) chosen by the owner 11/7 for the walking leg.
        walkStyle = defaults.number("walkStyle").map(Int.init) ?? 4
        publish(force: true)
    }

    func advance(by dt: TimeInterval) {
        guard !paused, route.length > 0 else { return }
        distance += speed * dt
        if distance >= route.length { restart() }
        publish(force: false)
    }

    func endRide() { walking = true }

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
        let mins = Int(((route.length - distance) / 3.5 / 60).rounded(.up))
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
