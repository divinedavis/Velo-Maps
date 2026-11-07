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
    @Published var paused: Bool

    /// Demo tuning, overridable from launch arguments for screenshot passes:
    /// -progress 0.35  -paused YES  -cameraDistance 420  -cameraPitch 62  -speed 9
    let cameraDistance: Double
    let cameraPitch: Double
    let speed: Double              // metres per second of simulated travel
    private(set) var distance: CLLocationDistance

    private var startedAt = Date()
    private var lastPublish = Date.distantPast

    init(route: Route = .m10, defaults: UserDefaults = .standard) {
        self.route = route
        let progress = defaults.object(forKey: "progress") as? Double ?? 0.08
        distance = route.length * min(max(progress, 0), 1)
        paused = defaults.bool(forKey: "paused")
        cameraDistance = defaults.object(forKey: "cameraDistance") as? Double ?? 420
        cameraPitch = defaults.object(forKey: "cameraPitch") as? Double ?? 62
        speed = defaults.object(forKey: "speed") as? Double ?? 9
        publish(force: true)
    }

    func loadRoadGeometry() async {
        let fraction = route.length > 0 ? distance / route.length : 0
        let snapped = await RouteLoader.snapped(route)
        route = snapped
        distance = snapped.length * fraction
        publish(force: true)
    }

    func advance(by dt: TimeInterval) {
        guard !paused, route.length > 0 else { return }
        distance += speed * dt
        if distance >= route.length { restart() }
        publish(force: false)
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
        let mins = Int(((route.length - distance) / 3.5 / 60).rounded(.up))
        if mins != minutesLeft { minutesLeft = mins }
        elapsed = now.timeIntervalSince(startedAt)
    }
}
