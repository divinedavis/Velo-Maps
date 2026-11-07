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
        .accessibilityElement(children: .contain)
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
        .accessibilityElement(children: .contain)
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
        .accessibilityElement(children: .contain)
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
            // .lastTextBaseline puts "9 min" on the same line as the "10 aboard" row.
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(trip.minutesLeft)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("min").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    LineBadge(line: trip.route.line)
                    Text("to \(trip.route.destination)").font(.system(size: 14, weight: .semibold))
                        .accessibilityIdentifier("trip-destination")
                    Label("10 aboard", systemImage: "person.2.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HeroTrack(stopCount: trip.route.stops.count,
                          position: trip.stopSpacePosition,
                          red: Color.tripRed(scheme))
                Text("Next: \(trip.nextStopName)")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityIdentifier("next-stop")
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-card")
    }
}

private extension Trip {
    /// Where the bus is on the evenly spaced stop track: 2.4 = 40% of the way from stop 2 to 3.
    var stopSpacePosition: Double {
        let d = progress * route.length
        let sd = route.stopDistances
        guard sd.count > 1 else { return 0 }
        guard let i = sd.indices.dropLast().last(where: { sd[$0] <= d }) else { return 0 }
        let span = sd[i + 1] - sd[i]
        return Double(i) + (span > 0 ? min(max((d - sd[i]) / span, 0), 1) : 0)
    }
}

/// Stop dots on a line, red up to the bus, with a tiny copy of the map's bus riding on it.
private struct HeroTrack: View {
    let stopCount: Int
    let position: Double
    let red: Color

    private static let bus: UIImage = {
        // Map marker is drawn front-up; rotate so the front faces right (direction of travel).
        let src = BusAnnotation.image
        let size = CGSize(width: src.size.height, height: src.size.width)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            src.draw(at: CGPoint(x: -src.size.width / 2, y: -src.size.height / 2))
        }
    }()

    var body: some View {
        GeometryReader { g in
            let inset: CGFloat = 5
            let usable = g.size.width - inset * 2
            let step = stopCount > 1 ? usable / CGFloat(stopCount - 1) : 0
            let busX = inset + step * CGFloat(position)
            let midY = g.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.secondary.opacity(0.3))
                    .frame(width: usable, height: 3)
                    .position(x: inset + usable / 2, y: midY)
                Capsule().fill(red)
                    .frame(width: max(0, busX - inset), height: 3)
                    .position(x: inset + max(0, busX - inset) / 2, y: midY)
                ForEach(0..<stopCount, id: \.self) { i in
                    Circle()
                        .fill(Double(i) <= position ? red : Color.secondary.opacity(0.45))
                        .frame(width: 8, height: 8)
                        .position(x: inset + step * CGFloat(i), y: midY)
                }
                Image(uiImage: Self.bus)
                    .resizable()
                    .frame(width: 36, height: 18)
                    .position(x: busX, y: midY)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 22)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-card")
    }
}
