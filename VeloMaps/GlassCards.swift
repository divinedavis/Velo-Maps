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
            .scaledFont(size, .heavy, .rounded)
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
                    Text("→ \(trip.route.destination)").scaledFont(16, .bold)
                    HStack(spacing: 16) {
                        stat("clock", "\(trip.minutesLeft)", "min")
                        stat("person.2.fill", "10", "passengers")
                    }
                }
                Spacer()
                Button {} label: { Image(systemName: "chevron.down").scaledFont(14, .bold) }
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
                .scaledFont(15, .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .glassEffect(.regular.tint(Color.tripRed(scheme)).interactive(), in: .capsule)
            }
            .modifier(HoldToEnd(trip: trip))
        }
        .padding(16)
        .readableGlass(in: .rect(cornerRadius: 34))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-card")
    }

    private func stat(_ icon: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon).scaledFont(12, .semibold).foregroundStyle(.secondary)
            Text(value).scaledFont(22, .bold, .rounded).monospacedDigit()
            Text(unit).scaledFont(12, .medium).foregroundStyle(.secondary)
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
                        .scaledFont(14, i == next ? .bold : .medium)
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
        Group {   // no GlassEffectContainer: it draws merged glass over readableGlass text
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    LineBadge(line: trip.route.line, size: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next · \(trip.nextStopName)")
                            .scaledFont(15, .bold)
                            .lineLimit(1)
                        Text("\(trip.minutesLeft) min to \(shortDest) · 10 aboard")
                            .scaledFont(12, .medium)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 66)
                .readableGlass(in: .capsule)

                Image(systemName: "stop.fill")
                    .scaledFont(20, .bold)
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
        Group {   // no GlassEffectContainer: it draws merged glass over readableGlass text
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 8) {
                        LineBadge(line: trip.route.line)
                        Text("→ \(trip.route.destination)").scaledFont(15, .bold)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .readableGlass(in: .capsule)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .scaledFont(14, .bold)
                        .frame(width: 44, height: 44)
                        .readableGlass(in: .circle, interactive: true)
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
                    .scaledFont(15, .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
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
            Text(title).scaledFont(11, .semibold).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value)
                .scaledFont(big ? 24 : 16, .bold, .rounded)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 12)
        .readableGlass(in: .rect(cornerRadius: 20))
    }
}

// MARK: 4 — Hero: giant ETA, next stop, red glass end button. Swipe up for navigation settings.

struct GlassHeroCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.colorScheme) private var scheme
    @GestureState private var drag: CGFloat = 0
    private var expanded: Bool { trip.cardExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 38, height: 5)
                .frame(width: 120, height: 44)          // 44 pt touch target (audit)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .padding(.top, -24).padding(.bottom, -14)
                .accessibilityLabel(expanded ? "Hide navigation settings" : "Show navigation settings")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("card-grabber")
                .onTapGesture { toggle() }
            if trip.turnStyle == 4 { TurnRowInCard(trip: trip) }
            // .lastTextBaseline puts "9 min" on the same line as the "10 aboard" row.
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(trip.minutesLeft)")
                        .scaledFont(64, .bold, .rounded)
                        .monospacedDigit()
                    Text("min").scaledFont(22, .medium).foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    LineBadge(line: trip.route.line)
                    Text("to \(trip.route.destination)").scaledFont(14, .semibold)
                        .accessibilityIdentifier("trip-destination")
                    if trip.route.kind == .bus {
                        Label("10 aboard", systemImage: "person.2.fill")
                            .scaledFont(12, .semibold).foregroundStyle(.primary)
                    }
                }
            }
            Text(trip.route.kind == .drive ? "Via \(trip.route.via ?? trip.route.destination)" : "Next: \(trip.nextStopName)")
                .scaledFont(14, .bold)
                .accessibilityIdentifier("next-stop")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Text("Hold to end ride")
                    Spacer()
                    Text(clock(trip.elapsed)).monospacedDigit()
                }
                .scaledFont(15, .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .glassEffect(.regular.tint(Color.tripRed(scheme)).interactive(), in: .capsule)
            }
            .modifier(HoldToEnd(trip: trip))
            .clipShape(Capsule())
            if expanded {
                NavSettings(trip: trip)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(18)
        .readableGlass(in: .rect(cornerRadius: 36))
        // Follows the finger a little while dragging, then snaps open or closed.
        .offset(y: max(-40, min(40, drag * 0.35)))
        // Simultaneous so the buttons and hold gesture inside the card don't swallow the swipe;
        // predicted end counts a quick flick as a full swipe.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .updating($drag) { v, state, _ in state = v.translation.height }
                .onEnded { v in
                    let up = min(v.translation.height, v.predictedEndTranslation.height)
                    let down = max(v.translation.height, v.predictedEndTranslation.height)
                    if up < -40, !expanded { toggle() } else if down > 40, expanded { toggle() }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-card")
    }

    private func toggle() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { trip.cardExpanded.toggle() }
    }
}

/// Revealed by swiping the card up. Stored locally for the preview; not yet wired to the map.
private struct NavSettings: View {
    @ObservedObject var trip: Trip
    @AppStorage(SettingKey.voice) private var voice = true
    @AppStorage(SettingKey.stopAlert) private var stopAlert = "1 stop before"
    @AppStorage(SettingKey.appearance) private var appearance = "Auto"
    @AppStorage(SettingKey.buildings) private var buildings = true
    @AppStorage(SettingKey.potholes) private var potholes = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Navigation settings")
                .scaledFont(13, .semibold)
                .foregroundStyle(Color.primary.opacity(0.7))
                .textCase(.uppercase)
                .padding(.top, 4)
                .accessibilityIdentifier("nav-settings")
            VStack(spacing: 0) {
                row("map.fill", "Demo ride") {
                    Picker("Demo ride", selection: Binding(
                        get: { trip.route.kind == .drive ? "Drive" : "Bus" },
                        set: { trip.useRoute($0 == "Drive" ? .hhDrive : .m10) })) {
                        ForEach(["Bus", "Drive"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .accessibilityIdentifier("demo-ride")
                }
                Divider().padding(.leading, 44)
                row("speaker.wave.2.fill", "Voice guidance") { Toggle("Voice guidance", isOn: $voice).labelsHidden().accessibilityIdentifier("setting-voice") }
                Divider().padding(.leading, 44)
                row("bell.badge.fill", "Stop alert") {
                    Menu {
                        ForEach(["Off", "At my stop", "1 stop before", "2 stops before"], id: \.self) { o in
                            Button(o) { stopAlert = o }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(stopAlert)
                            Image(systemName: "chevron.up.chevron.down").scaledFont(11, .semibold)
                        }
                        .scaledFont(15, .medium)
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
                Divider().padding(.leading, 44)
                row("circle.lefthalf.filled", "Map appearance") {
                    Picker("Map appearance", selection: $appearance) {
                        ForEach(["Auto", "Day", "Night"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }
                Divider().padding(.leading, 44)
                row("building.2.fill", "3D buildings") { Toggle("3D buildings", isOn: $buildings).labelsHidden().accessibilityIdentifier("setting-buildings") }
                Divider().padding(.leading, 44)
                row("exclamationmark.triangle.fill", "Show reported potholes") { Toggle("Show reported potholes", isOn: $potholes).labelsHidden().accessibilityIdentifier("setting-potholes") }
            }
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            // The iPhone share sheet with the route, minutes left and arrival time.
            ShareLink(item: trip.shareText) {
                Label("Share trip progress", systemImage: "square.and.arrow.up")
                    .scaledFont(15, .semibold)
                    .foregroundStyle(Color.tripRed(.light))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("share-trip")
        }
        .tint(Color.tripRed(.light))
    }

    private func row<Accessory: View>(_ icon: String, _ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .scaledFont(15, .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)   // decorative; the row's text says it
            Text(title).scaledFont(15, .medium)
            Spacer(minLength: 8)
            accessory()
        }
        .frame(minHeight: 46)
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
                    .scaledFont(13, .medium).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").scaledFont(11, .bold).foregroundStyle(.secondary)
                Text(trip.route.destination.replacingOccurrences(of: "CPW / ", with: ""))
                    .scaledFont(13, .bold)
                Spacer()
                Text("\(trip.minutesLeft) min")
                    .scaledFont(20, .bold, .rounded).monospacedDigit()
            }
            GeometryReader { g in
                let x = max(14, min(g.size.width - 14, g.size.width * trip.progress))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 6)
                    Capsule().fill(red).frame(width: x, height: 6)
                    Image(systemName: "bus.fill")
                        .scaledFont(13, .bold)
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
            .scaledFont(13)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 12) {
                    Image(systemName: "stop.fill")
                        .scaledFont(14, .bold)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(red, in: Circle())
                    Text("Hold to end").scaledFont(15, .semibold)
                    Spacer()
                    Text(clock(trip.elapsed)).scaledFont(15, .semibold).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 14)
                }
                .padding(4)
                .readableGlass(in: .capsule, interactive: true)
            }
            .modifier(HoldToEnd(trip: trip))
            .clipShape(Capsule())
        }
        .padding(16)
        .readableGlass(in: .rect(cornerRadius: 32))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-card")
    }
}
