import Foundation
import CoreLocation

/// A Police / Accident / Road closed report dropped on the map.
struct RoadReport: Identifiable {
    let id = UUID()
    let kind: ReportKind
    let coordinate: CLLocationCoordinate2D
}

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
    /// The maneuver whose turn banner is showing, if any (see updateBanner()).
    @Published private(set) var bannerManeuver: Maneuver?
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
    /// -signStyle 0…5: highway sign design inside the turn banner (0 = flat green sign, 4 = Junction, default).
    let signStyle: Int
    /// -roadStyle 0…5: current-road label above the card (0 = hidden).
    let roadStyle: Int
    /// -laneStyle 0…3: draw the route in the lane to be in (0 = road centre line).
    let laneStyle: Int
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

    /// Navigation settings (same keys the settings card writes).
    let settings: UserDefaults
    /// Speech output; tests swap it to record what would be said.
    var speak: (VoiceLine) -> Void = { Speaker.shared.say($0) }
    /// Latest thing to tell the rider on screen (stop alert); the screen shows it as a toast.
    @Published private(set) var announcement: Announcement?
    @Published private(set) var reports: [RoadReport] = []
    private var spokenPotholes: Set<UUID> = []
    private var stopAlertFired = false

    /// Live navigation from real GPS (the default app); false = the scripted demo used by tests
    /// and previews (`-demo bus|drive`).
    let live: Bool
    /// Live: GPS speed (m/s) and the snapped distance the display catches up to.
    private(set) var liveSpeed: Double = 0
    private var targetDistance: CLLocationDistance = 0
    private var offRouteFixes = 0
    private var lastGoodFix: Date?
    /// Live: the rider has left the route (3 fixes in a row well off the line) → reroute.
    @Published private(set) var offRoute = false
    /// Live: the trip is over (arrived and ended, or "Hold to end").
    @Published private(set) var ended = false
    private var arrived = false

    init(route: Route? = nil, defaults: UserDefaults = .standard, live: Bool = false) {
        self.settings = defaults
        self.live = live
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
        // Junction (4) chosen by the owner 11/7.
        signStyle = defaults.number("signStyle").map(Int.init) ?? 4
        roadStyle = defaults.number("roadStyle").map(Int.init) ?? 1
        // All lanes (3) chosen by the owner 11/8.
        laneStyle = defaults.number("laneStyle").map(Int.init) ?? 3
        startReportMenu = defaults.bool(forKey: "reportMenu")
        // Glance (4) chosen by the owner 11/7 for the walking leg.
        walkStyle = defaults.number("walkStyle").map(Int.init) ?? 4
        if let ahead = defaults.number("turnAhead"), let turn = route.maneuvers.first {
            distance = max(0, turn.at - ahead)
        }
        // -turnPassed 30: start this far past the first turn (banner should be gone).
        if let past = defaults.number("turnPassed"), let turn = route.maneuvers.first {
            distance = min(route.length, turn.at + past)
        }
        // -signAhead 150 -signIndex 0|1: start this far before a ramp with a highway sign.
        let signs = route.maneuvers.filter { $0.sign != nil }
        if let ahead = defaults.number("signAhead"), !signs.isEmpty {
            let i = min(Int(defaults.number("signIndex") ?? 0), signs.count - 1)
            distance = max(0, signs[i].at - ahead)
        }
        // Reports other riders already made on this route (demo data; the real app would load
        // these from a shared server). Live trips start clean, at the start of the route.
        if live {
            distance = 0
            paused = false
        } else {
            potholes = [700, 1450].map { Pothole(coordinate: route.position(at: $0).0, at: $0, mine: false) }
        }
        // -demoReports YES (previews): a police and a road-closed marker just ahead.
        if defaults.bool(forKey: "demoReports") {
            reports = [(ReportKind.police, 60.0), (.closure, 140.0)].map {
                RoadReport(kind: $0.0, coordinate: route.position(at: distance + $0.1).0)
            }
        }
        publish(force: true)
    }

    /// Road the vehicle is on now, and its heading (for the current-road label).
    var currentRoad: RoadSpec? { route.road(at: progress * route.length) }
    var compassHeading: String {
        let h = route.smoothedHeading(at: progress * route.length, window: 40)
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((h + 22.5) / 45) % 8]
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
        if live {
            // Between GPS fixes, carry on at the GPS speed; ease toward each new fix so the
            // vehicle glides instead of jumping once a second.
            // Only coast while the last fix was on the route: off it, the vehicle must not keep
            // gliding down the planned road (seen 11/8 in a simulated drive).
            if !arrived, offRouteFixes == 0 { targetDistance = min(route.length, targetDistance + liveSpeed * dt) }
            distance += (targetDistance - distance) * (1 - exp(-dt / 0.5))
            if !arrived, route.length - targetDistance < 20 { arrive() }
        } else {
            distance += speed * dt
            if distance >= route.length { restart() }
        }
        // Refresh the published state every 0.25 s of *trip* time (not wall-clock), so a big
        // step (tests, a hitch) still updates banners, alerts and voice.
        sincePublish += dt
        if sincePublish >= 0.25 {
            sincePublish = 0
            publish(force: true)
        }
    }
    private var sincePublish: TimeInterval = 0

    func endRide() {
        if live { ended = true; return }
        walking = true
    }

    /// Live: a new GPS fix. Snaps it to the route, takes its speed, and flags leaving the route.
    func update(fix: CLLocation) {
        guard live, !arrived else { return }
        if fix.speed >= 0 { liveSpeed = fix.speed }
        let tolerance = max(35, fix.horizontalAccuracy * 1.5)
        // Only accept a point on the route we could actually have driven to since the last good
        // fix: a nearby stretch of the same route (Riverside Drive beside the parkway) must not
        // pull the vehicle down the road, in the search window or beyond it.
        let since = lastGoodFix.map { fix.timestamp.timeIntervalSince($0) } ?? .infinity
        let reach = 200 + max(liveSpeed, 15) * since * 1.5
        func plausible(_ c: (distance: CLLocationDistance, offBy: Double)) -> Bool {
            c.offBy <= tolerance && c.distance >= targetDistance - 50 && c.distance - targetDistance <= reach
        }
        var snap = route.snap(fix.coordinate, near: targetDistance)
        if !plausible(snap) {
            // A gap in fixes (tunnel, first fix after Start) can put us past the search window.
            snap = route.snap(fix.coordinate, near: targetDistance, behind: .infinity, ahead: .infinity)
        }
        if !plausible(snap) {
            offRouteFixes += 1
            if offRouteFixes >= 3, !offRoute { offRoute = true }
        } else {
            offRouteFixes = 0
            targetDistance = snap.distance
            lastGoodFix = fix.timestamp
        }
    }

    /// Live: swap in a fresh route from where the rider is now (after leaving the route).
    func reroute(_ newRoute: Route) {
        route = newRoute
        distance = 0
        targetDistance = 0
        offRouteFixes = 0
        lastGoodFix = nil
        offRoute = false
        bannerManeuver = nil
        potholes = []          // positions were along the old line
        publish(force: true)
    }

    private func arrive() {
        arrived = true
        targetDistance = route.length
        let text = "You have arrived at \(route.destination)"
        announcement = Announcement(text: text)
        if settings.voiceGuidance { speak(VoiceCues.line(text)) }
    }

    /// The turn banner appears when the next maneuver is within its time window at the current
    /// speed, stays up until that maneuver is passed (no flicker if the vehicle slows), and goes
    /// away once the turn is made (owner, 11/7).
    private func updateBanner() {
        guard let next = nextManeuver else {
            if bannerManeuver != nil { bannerManeuver = nil }
            return
        }
        if bannerManeuver?.id == next.id { return }            // already up: keep until passed
        let remaining = next.at - distance
        let show = remaining <= Self.bannerWindow(for: next, speed: currentSpeed)
        let wanted = show ? next : nil
        if wanted?.id != bannerManeuver?.id {
            bannerManeuver = wanted
            // Voice guidance: say the turn once, as its banner appears.
            if let m = wanted, settings.voiceGuidance {
                say(VoiceCues.turn(remaining: remaining, instruction: m.instruction))
            }
        }
    }

    private func say(_ line: VoiceLine) {
        guard !walking, !paused else { return }   // no speech in paused previews/tests
        speak(line)
    }

    /// Spoken "Pothole ahead" once per pothole, when its alert comes up (if potholes are shown).
    private func announcePotholes() {
        guard settings.showPotholes, let (p, _) = potholeAhead(), !spokenPotholes.contains(p.id) else { return }
        spokenPotholes.insert(p.id)
        if settings.voiceGuidance { say(VoiceCues.line("Pothole ahead")) }
    }

    /// Stop alert (settings): "At my stop" fires within 120 m of the last stop; "N stops
    /// before" fires when N stops are left including yours. Once per trip, spoken + on screen.
    private func checkStopAlert() {
        guard !live, !stopAlertFired, !walking, route.stops.count > 1 else { return }
        let setting = settings.stopAlertSetting
        guard setting != "Off" else { return }
        let dest = route.stops.count - 1
        let left = dest - min(nextStop, dest) + 1          // stops still to come, incl. yours
        let toEnd = route.length - distance
        let text: String?
        switch setting {
        case "At my stop": text = toEnd <= 120 ? "Arriving at your stop, \(route.destination)" : nil
        case "2 stops before": text = left <= 2 && toEnd > 0 ? "2 stops to go. Your stop is \(route.destination)" : nil
        default: text = left <= 1 && toEnd > 0 ? "Your stop is next: \(route.destination)" : nil
        }
        guard let text, route.kind == .bus || setting == "At my stop" else { return }
        stopAlertFired = true
        announcement = Announcement(text: text)
        if settings.voiceGuidance { say(VoiceCues.line(text)) }
    }

    /// Police / Accident / Road closed: drop a marker at the vehicle's spot.
    func report(_ kind: ReportKind) {
        let (coord, _) = route.position(at: distance)
        reports.append(RoadReport(kind: kind, coordinate: coord))
    }

    /// End the walking leg (walking screen's End): back to the start of the ride.
    func endWalk() {
        walking = false
        restart()
    }

    /// Text for "Share trip progress".
    var shareText: String {
        let arrive = Date().addingTimeInterval(Double(minutesLeft) * 60).formatted(date: .omitted, time: .shortened)
        let what = route.kind == .bus ? "on the \(route.line)" : "driving"
        return "I'm \(what) to \(route.destination), about \(minutesLeft) min away (arriving around \(arrive)). Shared from Velo Maps."
    }

    /// Switch demo route (settings): start over at the beginning with fresh demo reports.
    func useRoute(_ newRoute: Route) {
        route = newRoute
        bannerManeuver = nil   // maneuver ids restart per route
        stopAlertFired = false
        spokenPotholes = []
        reports = []
        distance = 0
        startedAt = Date()
        potholes = [700, 1450].map { Pothole(coordinate: newRoute.position(at: $0).0, at: $0, mine: false) }
        publish(force: true)
    }

    func restart() {
        distance = 0
        bannerManeuver = nil
        stopAlertFired = false
        spokenPotholes = []
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
        let remaining = max(0, route.length - distance)
        let seconds = route.duration.map { $0 * remaining / max(route.length, 1) } ?? remaining / route.etaSpeed
        let mins = Int((seconds / 60).rounded(.up))
        if mins != minutesLeft { minutesLeft = mins }
        elapsed = now.timeIntervalSince(startedAt)
        progress = route.length > 0 ? distance / route.length : 0
        updateBanner()
        announcePotholes()
        checkStopAlert()
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
