import SwiftUI

private let busRed = Color(red: 0.84, green: 0.07, blue: 0.13)

/// Frosted bottom card: line badge, destination, ETA + load, the next few stops, and a
/// hold-to-end button with the ride timer.
struct TripCard: View {
    @ObservedObject var trip: Trip
    @State private var holdProgress: CGFloat = 0
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded { stopList }
            holdButton
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityIdentifier("trip-card")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.route.line)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(busRed, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("→ \(trip.route.destination)")
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityIdentifier("trip-destination")
                HStack(spacing: 14) {
                    stat(icon: "clock", value: "\(trip.minutesLeft)", unit: "min")
                    stat(icon: "person.2.fill", value: "10", unit: "passengers")
                }
            }
            Spacer()
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse stops" : "Show stops")
        }
    }

    private func stat(icon: String, value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    /// Previous stop (faded), next stop (bold, filled dot), then the two after it.
    private var stopList: some View {
        let next = trip.nextStop
        let shown: [Int] = trip.route.stops.indices.filter { $0 >= next - 1 && $0 <= next + 2 }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown, id: \.self) { i in
                StopRow(name: trip.route.stops[i].name,
                        state: i < next ? .passed : (i == next ? .next : .upcoming),
                        drawsLine: i != shown.last)
            }
        }
        .padding(.leading, 2)
        .accessibilityIdentifier("stop-list")
    }

    private var holdButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                Image(systemName: "stopwatch").font(.system(size: 14, weight: .semibold))
                Text(clock(trip.elapsed)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Spacer()
                Text("Hold to end").font(.system(size: 13, weight: .semibold)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(alignment: .leading) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        busRed
                        Color.black.opacity(0.18).frame(width: g.size.width * holdProgress)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.9) {
            trip.restart()
            withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: 0.9) : .easeOut(duration: 0.2)) {
                holdProgress = pressing ? 1 : 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hold-to-end")
        .accessibilityAddTraits(.isButton)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct StopRow: View {
    enum State { case passed, next, upcoming }
    let name: String
    let state: State
    let drawsLine: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if drawsLine {
                    Rectangle()
                        .fill(busRed.opacity(state == .passed ? 0.25 : 1))
                        .frame(width: 2)
                        .offset(y: 10)
                }
                dot
            }
            .frame(width: 14, height: 20)
            Text(name)
                .font(.system(size: 13, weight: state == .next ? .bold : .medium))
                .foregroundStyle(state == .passed ? Color.secondary : Color.primary)
                .opacity(state == .passed ? 0.6 : 1)
        }
    }

    private var dot: some View {
        let size: CGFloat = state == .next ? 12 : 9
        return Circle()
            .fill(state == .next ? busRed : Color.white)
            .overlay(Circle().strokeBorder(busRed.opacity(state == .passed ? 0.3 : 1), lineWidth: 2))
            .frame(width: size, height: size)
    }
}
