import SwiftUI

// Five Liquid Glass (iOS 26) takes on the bottom trip card. Each works in light and dark;
// in dark the red is dimmed a step so it doesn't glare in a dark vehicle.

extension Color {
    static func tripRed(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.72, green: 0.08, blue: 0.13) : busRed
    }
}

private func clock(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Shared hold-to-end gesture: press and hold 0.9 s to end the ride; a darker fill sweeps
/// across while held.
private struct HoldToEnd: ViewModifier {
    let trip: Trip
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Color.black.opacity(0.18).frame(width: g.size.width * progress)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.9) {
                trip.endRide()
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 0.9) : .easeOut(duration: 0.2)) {
                    progress = pressing ? 1 : 0
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("hold-to-end")
            .accessibilityAddTraits(.isButton)
    }
}

private struct LineBadge: View {
    let line: String
    var size: CGFloat = 15
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(line)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, size * 0.5).padding(.vertical, size * 0.15)
            .background(Color.tripRed(scheme), in: RoundedRectangle(cornerRadius: size * 0.4, style: .continuous))
    }
}

private extension Trip {
    var nextStopName: String { route.stops[min(nextStop, route.stops.count - 1)].name }
}

// MARK: 1 — Glass sheet: the original layout on one big glass panel, red glass button.

struct GlassSheetCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    LineBadge(line: trip.route.line)
                    Text("→ \(trip.route.destination)").font(.system(size: 16, weight: .bold))
                    HStack(spacing: 16) {
                        stat("clock", "\(trip.minutesLeft)", "min")
                        stat("person.2.fill", "10", "passengers")
                    }
                }
                Spacer()
                Button {} label: { Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            stops
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Image(systemName: "stopwatch")
                    Text(clock(trip.elapsed)).monospacedDigit()
                    Spacer()
                    Text("Hold to end").opacity(0.9)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .glassEffect(.regular.tint(Color.tripRed(scheme)).interactive(), in: .capsule)
            }
            .modifier(HoldToEnd(trip: trip))
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .accessibilityIdentifier("trip-card")
    }

    private func stat(_ icon: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private var stops: some View {
        let next = trip.nextStop
        let shown = trip.route.stops.indices.filter { $0 >= next - 1 && $0 <= next + 2 }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle()
                        .fill(i == next ? Color.tripRed(scheme) : .clear)
                        .overlay(Circle().strokeBorder(Color.tripRed(scheme).opacity(i < next ? 0.35 : 1), lineWidth: 2))
                        .frame(width: 10, height: 10)
                    Text(trip.route.stops[i].name)
                        .font(.system(size: 14, weight: i == next ? .bold : .medium))
                        .foregroundStyle(i < next ? .tertiary : .primary)
                }
            }
        }
    }
}

// MARK: 2 — Pill: one slim glass capsule + a separate red glass end button that merges with it.

struct GlassPillCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    LineBadge(line: trip.route.line, size: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next · \(trip.nextStopName)")
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text("\(trip.minutesLeft) min to \(shortDest) · 10 aboard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 66)
                .glassEffect(.regular, in: .capsule)

                Image(systemName: "stop.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .glassEffect(.regular.tint(Color.tripRed(scheme)).interactive(), in: .circle)
                    .modifier(HoldToEnd(trip: trip))
                    .clipShape(Circle())
                    .accessibilityLabel("Hold to end")
            }
        }
        .padding(.bottom, 6)
        .accessibilityIdentifier("trip-card")
    }

    private var shortDest: String { trip.route.destination.replacingOccurrences(of: "CPW / ", with: "") }
}

// MARK: 3 — Cluster: separate glass pieces (header chip, three tiles, end bar) in one container.

struct GlassClusterCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 8) {
                        LineBadge(line: trip.route.line)
                        Text("→ \(trip.route.destination)").font(.system(size: 15, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                HStack(spacing: 8) {
                    tile(title: "Next stop", value: trip.nextStopName.replacingOccurrences(of: "CPW / ", with: ""), big: false)
                    tile(title: "Arrive in", value: "\(trip.minutesLeft) min", big: true)
                    tile(title: "On board", value: "10", big: true)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack {
                        Image(systemName: "stopwatch")
                        Text(clock(trip.elapsed)).monospacedDigit()
                        Spacer()
                        Text("Hold to end")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .glassEffect(.regular.tint(Color.tripRed(scheme)).interactive(), in: .rect(cornerRadius: 22))
                }
                .modifier(HoldToEnd(trip: trip))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .accessibilityIdentifier("trip-card")
    }

    private func tile(title: String, value: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value)
                .font(.system(size: big ? 24 : 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: 4 — Hero: giant ETA, horizontal stop timeline, red glass end button.

struct GlassHeroCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(trip.minutesLeft)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("min").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    LineBadge(line: trip.route.line)
                    Text("to \(trip.route.destination)").font(.system(size: 14, weight: .semibold))
                    Label("10 aboard", systemImage: "person.2.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            timeline
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Text("Hold to end ride")
                    Spacer()
                    Text(clock(trip.elapsed)).monospacedDigit().opacity(0.85)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .glassEffect(.regular.tint(Color.tripRed(scheme)).interactive(), in: .capsule)
            }
            .modifier(HoldToEnd(trip: trip))
            .clipShape(Capsule())
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 36))
        .accessibilityIdentifier("trip-card")
    }

    /// All stops left to right; passed ones faded, next one large with its name under it.
    private var timeline: some View {
        let count = trip.route.stops.count
        let next = trip.nextStop
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    TimelineStop(index: i, next: next, isLast: i == count - 1, red: Color.tripRed(scheme))
                }
            }
            Text("Next: \(trip.nextStopName)")
                .font(.system(size: 14, weight: .bold))
        }
    }
}

private struct TimelineStop: View {
    let index: Int
    let next: Int
    let isLast: Bool
    let red: Color

    var body: some View {
        let isNext = index == next
        let reached = index <= next
        let size: CGFloat = isNext ? 14 : 8
        HStack(spacing: 0) {
            Circle()
                .fill(reached ? red : Color.secondary.opacity(0.35))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(isNext ? 0.9 : 0), lineWidth: 2))
            if !isLast {
                Capsule()
                    .fill(index < next ? red : Color.secondary.opacity(0.3))
                    .frame(height: 3)
            }
        }
    }
}

// MARK: 5 — Live Activity: from → to with a moving bus on a progress track, slide-style end.

struct GlassActivityCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let red = Color.tripRed(scheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LineBadge(line: trip.route.line)
                Text(trip.route.stops.first!.name.replacingOccurrences(of: "CPW / ", with: ""))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Text(trip.route.destination.replacingOccurrences(of: "CPW / ", with: ""))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(trip.minutesLeft) min")
                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { g in
                let x = max(14, min(g.size.width - 14, g.size.width * trip.progress))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 6)
                    Capsule().fill(red).frame(width: x, height: 6)
                    Image(systemName: "bus.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(red, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(x: x, y: g.size.height / 2)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
            HStack {
                Text("Next stop").foregroundStyle(.secondary)
                Text(trip.nextStopName).fontWeight(.bold)
                Spacer()
                Label("10", systemImage: "person.2.fill").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 12) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(red, in: Circle())
                    Text("Hold to end").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(clock(trip.elapsed)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 14)
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .modifier(HoldToEnd(trip: trip))
            .clipShape(Capsule())
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .accessibilityIdentifier("trip-card")
    }
}
