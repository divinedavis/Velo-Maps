import CoreLocation

/// While driving, every few minutes: is one of a fresh set of live-traffic routes clearly
/// faster than staying on this one? (owner, 11/9: keep checking for a faster route.)
enum FasterRoute {
    /// How often to ask (each ask is one routing request against the daily cap).
    static let checkEvery: TimeInterval = 240
    /// Only switch for a real gain: at least 2 minutes and 10% of the time left.
    static let minSaving: TimeInterval = 120
    static let minFraction = 0.10
    /// Not worth it this close to the end.
    static let minRemaining: CLLocationDistance = 2_000

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
    static func pick(current: Route, at distance: CLLocationDistance, candidates: [Route]) -> (route: Route, saves: TimeInterval)? {
        let left = max(0, current.length - distance)
        guard left >= minRemaining else { return nil }
        let split = candidates.map { ($0, follows($0, current, from: distance)) }
        let stay = split.first { $0.1 }?.0.duration
            ?? current.duration.map { $0 * left / max(current.length, 1) }
            ?? left / current.etaSpeed
        guard let best = split.filter({ !$0.1 }).compactMap({ r, _ in r.duration.map { (r, $0) } }).min(by: { $0.1 < $1.1 })
        else { return nil }
        let saves = stay - best.1
        guard saves >= minSaving, saves >= stay * minFraction else { return nil }
        return (best.0, saves)
    }
}
