import SwiftUI

/// A turn (or arrival) on the ride route, at a distance along the line.
struct Maneuver: Identifiable {
    let id: Int
    let at: Double          // metres along the route
    let icon: String        // SF Symbol
    let verb: String        // "Turn left onto"
    let street: String      // "W 96 St"
    var instruction: String { "\(verb) \(street)" }
}

/// Lane arrows for the lane-guidance design. `active` lanes are the ones to be in.
struct Lane: Identifiable {
    let id: Int
    let icon: String
    let active: Bool
}

extension Trip {
    var nextManeuver: Maneuver? { route.maneuvers.first { $0.at > distanceAlong + 1 } }
    var followingManeuver: Maneuver? {
        guard let n = nextManeuver else { return nil }
        return route.maneuvers.first { $0.id == n.id + 1 }
    }
    var metresToManeuver: Double { max(0, (nextManeuver?.at ?? route.length) - distanceAlong) }
    /// Distance along the line, refreshed with the card's ~4 Hz updates.
    var distanceAlong: Double { progress * route.length }
}

// MARK: 1 — Classic glass banner at the top.

struct TurnBannerClassic: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let m = trip.nextManeuver {
            HStack(spacing: 16) {
                Image(systemName: m.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.tripRed(scheme))
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text(walkDistance(trip.metresToManeuver))
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(m.street).font(.system(size: 22, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-banner")
        }
    }
}

// MARK: 2 — Banner with lane guidance.

struct TurnBannerLanes: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let m = trip.nextManeuver {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: m.icon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.tripRed(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(walkDistance(trip.metresToManeuver))
                            .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(m.instruction).font(.system(size: 16, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    ForEach(trip.route.lanesAtNextTurn) { lane in
                        Image(systemName: lane.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(lane.active ? Color.white : Color.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(lane.active ? Color.tripRed(scheme) : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-banner")
        }
    }
}

// MARK: 3 — Island pill: a compact dark capsule tucked under the Dynamic Island.

struct TurnBannerIsland: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let m = trip.nextManeuver {
            HStack(spacing: 12) {
                Image(systemName: m.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.tripRed(scheme), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(walkDistance(trip.metresToManeuver))
                        .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(m.street).font(.system(size: 13, weight: .medium)).opacity(0.75)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("\(trip.minutesLeft) min")
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.trailing, 8)
            }
            .padding(6)
            .frame(width: 290)
            .glassEffect(.regular.tint(.black.opacity(0.75)), in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-banner")
        }
    }
}

// MARK: 4 — In-card: the turn is a row inside the Hero card; nothing covers the map top.

struct TurnRowInCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let m = trip.nextManeuver {
            HStack(spacing: 12) {
                Image(systemName: m.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.tripRed(scheme), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.instruction).font(.system(size: 16, weight: .bold))
                    Text("then \(trip.followingManeuver?.instruction ?? "arrive")")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(walkDistance(trip.metresToManeuver))
                    .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .padding(10)
            .background(Color.tripRed(scheme).opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-banner")
        }
    }
}

// MARK: 5 — Red primary banner + attached "then" chip, with a countdown bar to the turn.

struct TurnBannerThen: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let m = trip.nextManeuver {
            GlassEffectContainer(spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Image(systemName: m.icon)
                                .font(.system(size: 38, weight: .heavy))
                                .frame(width: 52)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(walkDistance(trip.metresToManeuver))
                                    .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                                Text(m.street).font(.system(size: 20, weight: .semibold))
                            }
                            Spacer(minLength: 0)
                        }
                        // Empties over the last 300 m before the turn.
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.3))
                                Capsule().fill(.white)
                                    .frame(width: g.size.width * min(1, trip.metresToManeuver / 300))
                            }
                        }
                        .frame(height: 5)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .glassEffect(.regular.tint(Color.tripRed(scheme)), in: .rect(cornerRadius: 28))

                    if let then = trip.followingManeuver {
                        HStack(spacing: 8) {
                            Text("Then").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                            Image(systemName: then.icon).font(.system(size: 14, weight: .bold))
                            Text(then.instruction).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        }
                        .padding(.horizontal, 14).frame(height: 38)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turn-banner")
        }
    }
}
