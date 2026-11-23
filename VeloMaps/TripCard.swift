import SwiftUI

let busRed = Color(red: 0.84, green: 0.07, blue: 0.13)

/// Frosted bottom card: line badge, destination, ETA + load, the next few stops, and a
/// tap-to-end button with the ride timer.
struct TripCard: View {
    @ObservedObject var trip: Trip
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded { stopList }
            endButton
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-card")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.route.line)
                    .scaledFont(15, .heavy, .rounded)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(busRed, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("→ \(trip.route.destination)")
                    .scaledFont(15, .bold)
                    .accessibilityIdentifier("trip-destination")
                HStack(spacing: 14) {
                    stat(icon: "clock", value: "\(trip.minutesLeft)", unit: "min")
                    stat(icon: "person.2.fill", value: "10", unit: "passengers")
                }
            }
            Spacer()
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .scaledFont(13, .bold)
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
            Image(systemName: icon).scaledFont(12, .semibold).foregroundStyle(.secondary)
            Text(value).scaledFont(20, .bold, .rounded).monospacedDigit()
            Text(unit).scaledFont(11, .medium).foregroundStyle(.secondary)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stop-list")
    }

    /// One tap ends the ride (owner, 11/22: was a 0.9 s hold).
    private var endButton: some View {
        Button { trip.endRide() } label: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Image(systemName: "stopwatch").scaledFont(14, .semibold)
                    Text(clock(trip.elapsed)).scaledFont(15, .semibold).monospacedDigit()
                    Spacer()
                    Text("End ride").scaledFont(13, .semibold).opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(alignment: .leading) {
                    busRed
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("End ride")
        .accessibilityIdentifier("end-ride")
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
                .scaledFont(13, state == .next ? .bold : .medium)
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
