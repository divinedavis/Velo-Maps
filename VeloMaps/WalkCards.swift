import SwiftUI

// Five Liquid Glass takes on the walking leg after the ride ends.

private struct ETALine: View {
    @ObservedObject var walk: Walk
    var body: some View {
        Text("\(walk.minutesLeft) min · \(walkDistance(walk.metresLeft)) · Arrive \(walk.arrivalText)")
            .scaledFont(13, .medium)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

/// Ends the walk and returns to the ride.
private struct EndButton: View {
    @Environment(\.endWalk) private var endWalk
    var body: some View {
        Button("End") { endWalk() }
            .scaledFont(15, .semibold)
            .buttonStyle(.glass)
            .accessibilityIdentifier("end-walk")
    }
}

// MARK: 1 — Turn banner on top, compact destination bar at the bottom (classic nav layout).

struct WalkTurnLayout: View {
    @ObservedObject var walk: Walk
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            if let step = walk.current {
                HStack(spacing: 14) {
                    Image(systemName: step.icon)
                        .scaledFont(30, .bold)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .glassEffect(.regular.tint(Color.tripRed(scheme)), in: .rect(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(walkDistance(walk.metresToTurn))
                            .scaledFont(30, .bold, .rounded).monospacedDigit()
                        Text(step.instruction).scaledFont(15, .semibold).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .readableGlass(in: .rect(cornerRadius: 28))
            }
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(walk.destinationName).scaledFont(17, .bold)
                    ETALine(walk: walk)
                }
                Spacer()
                EndButton()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .readableGlass(in: .rect(cornerRadius: 30))
        }
    }
}

// MARK: 2 — Handoff: the moment the ride ends. Confirms the drop-off, offers the walk.

struct WalkHandoffLayout: View {
    @ObservedObject var walk: Walk
    let line: String
    let stop: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.endWalk) private var endWalk

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(26).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You're off the \(line)").scaledFont(17, .bold)
                        Text("Dropped at \(stop)").scaledFont(13).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk")
                        .scaledFont(20, .bold)
                        .frame(width: 44, height: 44)
                        .readableGlass(in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walk to \(walk.destinationName)").scaledFont(16, .semibold)
                        ETALine(walk: walk)
                    }
                }
                HStack(spacing: 10) {
                    Button { endWalk() } label: {
                        Text("Not now").scaledFont(16, .semibold).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glass)
                    Button {} label: {
                        Label("Start walking", systemImage: "figure.walk")
                            .scaledFont(16, .semibold).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.tripRed(scheme))
                }
            }
            .padding(18)
            .readableGlass(in: .rect(cornerRadius: 34))
        }
    }
}

// MARK: 3 — Step list: every instruction in a sheet, current one highlighted.

struct WalkStepsLayout: View {
    @ObservedObject var walk: Walk
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(walk.minutesLeft) min")
                        .scaledFont(28, .bold, .rounded).monospacedDigit()
                    Text("walk").scaledFont(17, .semibold).foregroundStyle(.secondary)
                    Spacer()
                    EndButton()
                }
                Text("to \(walk.destinationName) · \(walkDistance(walk.metresLeft)) · Arrive \(walk.arrivalText)")
                    .scaledFont(13, .medium).foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(walk.steps.prefix(5)) { step in
                        StepRow(step: step, isCurrent: step.id == walk.current?.id,
                                isDone: step.id < (walk.current?.id ?? 0), red: Color.tripRed(scheme))
                    }
                }
            }
            .padding(18)
            .readableGlass(in: .rect(cornerRadius: 34))
        }
    }
}

private struct StepRow: View {
    let step: WalkStep
    let isCurrent: Bool
    let isDone: Bool
    let red: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.icon)
                .scaledFont(15, .bold)
                .foregroundStyle(isCurrent ? .white : .primary)
                .frame(width: 34, height: 34)
                .background(isCurrent ? red : Color.secondary.opacity(0.15), in: Circle())
            Text(step.instruction)
                .scaledFont(14, isCurrent ? .bold : .medium)
                .lineLimit(1)
            Spacer()
            Text(walkDistance(step.length))
                .scaledFont(13, .medium).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .opacity(isDone ? 0.4 : 1)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(red.opacity(0.12))
            }
        }
    }
}

// MARK: 4 — Glance: one huge arrow + distance, for looking down while walking.

struct WalkGlanceLayout: View {
    @ObservedObject var walk: Walk
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Spacer()
            Group {   // no GlassEffectContainer: it draws merged glass over readableGlass text
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        Image(systemName: walk.current?.icon ?? "arrow.up")
                            .accessibilityHidden(true)   // the instruction text says the turn
                            .scaledFont(54, .heavy)
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 104)
                            .glassEffect(.regular.tint(Color.tripRed(scheme)), in: .circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(walkDistance(walk.metresToTurn))
                                .scaledFont(44, .bold, .rounded).monospacedDigit()
                            Text(walk.current?.instruction ?? "")
                                .scaledFont(15, .semibold)
                                .fixedSize(horizontal: false, vertical: true)
                            if let then = walk.following {
                                Text("Then: \(then.instruction)")
                                    .scaledFont(12, .semibold).foregroundStyle(.primary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .readableGlass(in: .rect(cornerRadius: 34))

                    HStack {
                        Image(systemName: "theatermasks.fill").foregroundStyle(Color.tripRed(scheme))
                            .accessibilityHidden(true)
                        Text(walk.destinationName).scaledFont(14, .semibold)
                        Spacer()
                        Text("\(walk.minutesLeft) min · \(walk.arrivalText)")
                            .scaledFont(14, .semibold).monospacedDigit()
                        EndButton()
                    }
                    .padding(.leading, 18).padding(.trailing, 6).frame(minHeight: 48)
                    .readableGlass(in: .capsule, interactive: true)
                }
            }
        }
    }
}

// MARK: 5 — Live Activity: a compact island-style pill on top, slim progress bar at the bottom.

struct WalkActivityLayout: View {
    @ObservedObject var walk: Walk
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: walk.current?.icon ?? "arrow.up")
                    .scaledFont(16, .bold)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.tripRed(scheme), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(walkDistance(walk.metresToTurn)).scaledFont(16, .bold).monospacedDigit()
                    Text(shortInstruction).scaledFont(12, .medium).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "figure.walk").foregroundStyle(.secondary)
                Text("\(walk.minutesLeft) min").scaledFont(16, .bold).monospacedDigit()
            }
            .padding(.horizontal, 10).frame(minHeight: 56)
            .readableGlass(in: .capsule)
            .padding(.horizontal, 24)
            .padding(.top, 2)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(walk.destinationName).scaledFont(16, .bold)
                    Spacer()
                    Text("Arrive \(walk.arrivalText)").scaledFont(14, .semibold).monospacedDigit()
                }
                GeometryReader { g in
                    let total = walk.path?.length ?? 1
                    let frac = total > 0 ? 1 - walk.metresLeft / total : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25))
                        Capsule().fill(Color.tripRed(scheme)).frame(width: max(8, g.size.width * frac))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("\(walkDistance(walk.metresLeft)) left").scaledFont(13).foregroundStyle(.secondary)
                    Spacer()
                    EndButton()
                }
            }
            .padding(16)
            .readableGlass(in: .rect(cornerRadius: 30))
        }
    }

    private var shortInstruction: String {
        (walk.current?.instruction ?? "").replacingOccurrences(of: "Turn ", with: "").capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
