import CoreLocation

/// While driving: is one of a fresh set of live-traffic routes clearly faster than staying on
/// this one? (owner, 11/9: keep checking for a faster route.)
///
/// The rule scales with the trip (owner's report, 11/10). The first rule — every 4 min, save
/// 2 min and 10%, stop 2 km out — suits a 40-minute highway drive, but on a 15-minute city
/// trip 2 minutes is 13% of the drive and only two checks ever ran, so short trips never
/// switched. Now: how often to ask and where to stop come from the distance left; the saving
/// that justifies a switch comes from the time left.
enum FasterRoute {
    struct Policy: Equatable {
        /// How often to ask (each ask is one routing request against the daily cap).
        let checkEvery: TimeInterval
        /// Not worth it this close to the end.
        let minRemaining: CLLocationDistance
        /// Most switches in one trip while this policy applies (a route must not flip-flop).
        let maxSwitches: Int

        static func forRemaining(_ metres: CLLocationDistance) -> Policy {
            switch metres {
            case ..<3_000: return Policy(checkEvery: 60, minRemaining: 300, maxSwitches: 2)     // under ~1.9 mi
            case ..<8_000: return Policy(checkEvery: 120, minRemaining: 500, maxSwitches: 2)    // under ~5 mi
            default: return Policy(checkEvery: 180, minRemaining: 1_000, maxSwitches: 1)
            }
        }
    }

    /// The saving that justifies a switch, from the time left on the current route: 45 s on a
    /// short hop, 72 s with 15 minutes left, and the original 2 min / 10% beyond 25 minutes.
    static func threshold(forTimeLeft stay: TimeInterval) -> TimeInterval {
        switch stay {
        case ..<720: return max(45, 0.08 * stay)
        case ..<1_500: return max(60, 0.08 * stay)
        default: return max(120, 0.10 * stay)
        }
    }

    /// A check may run with a turn banner up only if the turn is still this far off (a new
    /// route must never arrive in the middle of a turn).
    static let clearOfManeuver: CLLocationDistance = 150
    /// A faster-route answer older than this is for where the car used to be: 4 s, not the 8 s
    /// a first route may take.
    static let timeout: TimeInterval = 4

    /// `candidate` drives the rest of `current` from `distance` on (≥ 85% of it within 30 m).
    static func follows(_ candidate: Route, _ current: Route, from distance: CLLocationDistance) -> Bool {
        guard candidate.length > 0 else { return false }
        let step = max(50, candidate.length / 40)
        var on = 0, n = 0, s = 0.0
        while s <= candidate.length {
            n += 1
            if current.snap(candidate.position(at: s).0, near: distance, behind: 100, ahead: .infinity).offBy <= 30 { on += 1 }
            s += step
        }
        return Double(on) / Double(n) >= 0.85
    }

    /// The route to switch to and the seconds it saves, or nil to stay on `current`.
    /// The time to stay comes from the fresh candidate that follows the current route (today's
    /// traffic), else from the current route's own estimate for what's left.
    static func pick(current: Route, at distance: CLLocationDistance, candidates: [Route],
                     policy: Policy? = nil) -> (route: Route, saves: TimeInterval)? {
        let left = max(0, current.length - distance)
        guard left >= (policy ?? .forRemaining(left)).minRemaining else { return nil }
        let split = candidates.map { ($0, follows($0, current, from: distance)) }
        let stay = split.first { $0.1 }?.0.duration
            ?? current.duration.map { $0 * left / max(current.length, 1) }
            ?? left / current.etaSpeed
        guard let best = split.filter({ !$0.1 }).compactMap({ r, _ in r.duration.map { (r, $0) } }).min(by: { $0.1 < $1.1 })
        else { return nil }
        let saves = stay - best.1
        guard saves >= threshold(forTimeLeft: stay) else { return nil }
        return (best.0, saves)
    }
}
