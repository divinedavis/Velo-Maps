import SwiftUI

/// The road the vehicle is on, shown just above the trip card on the route line (owner, 11/7).
/// Five Liquid Glass designs behind -roadStyle 1…5.
struct CurrentRoadLabel: View {
    @ObservedObject var trip: Trip
    let style: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let road = trip.currentRoad {
            Group {
                switch style {
                case 2: streetSign(road)
                case 3: callout(road)
                case 4: routeBadge(road)
                case 5: headingPill(road)
                default: pill(road)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Now on \(road.name)")
            .accessibilityIdentifier("current-road")
            .animation(.snappy, value: road.name)
        }
    }

    /// 1 — Plain glass pill with the road name.
    private func pill(_ road: RoadSpec) -> some View {
        Text(road.name)
            .scaledFont(15, .semibold)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .readableGlass(in: .capsule)
    }

    /// 2 — Real-world sign: highways get their route shield, streets a green NYC street blade.
    @ViewBuilder private func streetSign(_ road: RoadSpec) -> some View {
        HStack(spacing: 8) {
            if let ref = road.ref { RouteShield(ref: ref, onLight: false, compact: true) }
            Text(road.name)
                .scaledFont(16, .semibold)
                .fontWidth(.condensed)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .glassEffect(.regular.tint(HighwaySignView.green.opacity(0.92)), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 2.5).stroke(.white.opacity(0.85), lineWidth: 1.2))
    }

    /// 3 — Callout pinned to the route line: red-rimmed glass with a pointer down onto the line.
    private func callout(_ road: RoadSpec) -> some View {
        VStack(spacing: 0) {
            Text(road.name)
                .scaledFont(15, .semibold)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .readableGlass(in: .capsule)
                .overlay(Capsule().stroke(Color.tripRed(scheme), lineWidth: 2))
            Triangle()
                .fill(Color.tripRed(scheme))
                .frame(width: 14, height: 8)
        }
    }

    /// 4 — Route-coloured badge: the label is part of the red line itself.
    private func routeBadge(_ road: RoadSpec) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "road.lanes").scaledFont(13, .bold)
            Text(road.name).scaledFont(15, .bold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .glassEffect(.regular.tint(Color.tripRed(scheme)), in: .capsule)
    }

    /// 5 — Heading + road: a compass chip (from the route's real bearing) joined to the name.
    private func headingPill(_ road: RoadSpec) -> some View {
        HStack(spacing: 0) {
            Text(trip.compassHeading)
                .scaledFont(13, .heavy)
                .foregroundStyle(.white)
                .frame(minWidth: 36, minHeight: 36)
                .background(Color.tripRed(scheme), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("NOW ON").scaledFont(10, .heavy).tracking(1).foregroundStyle(Color.primary.opacity(0.75))
                Text(road.name).scaledFont(15, .semibold)
            }
            .padding(.leading, 10).padding(.trailing, 16)
        }
        .padding(3)
        .readableGlass(in: .capsule)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
