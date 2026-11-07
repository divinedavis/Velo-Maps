import SwiftUI

// Five Liquid Glass takes on the walking leg after the ride ends.

private struct ETALine: View {
    @ObservedObject var walk: Walk
    var body: some View {
        Text("\(walk.minutesLeft) min · \(walkDistance(walk.metresLeft)) · Arrive \(walk.arrivalText)")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct EndButton: View {
    var body: some View {
        Button("End") {}
            .font(.system(size: 15, weight: .semibold))
            .buttonStyle(.glass)
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
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .glassEffect(.regular.tint(Color.tripRed(scheme)), in: .rect(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(walkDistance(walk.metresToTurn))
                            .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(step.instruction).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
            }
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(walk.destinationName).font(.system(size: 17, weight: .bold))
                    ETALine(walk: walk)
                }
                Spacer()
                EndButton()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
        }
    }
}

// MARK: 2 — Handoff: the moment the ride ends. Confirms the drop-off, offers the walk.

struct WalkHandoffLayout: View {
    @ObservedObject var walk: Walk
    let line: String
    let stop: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You're off the \(line)").font(.system(size: 17, weight: .bold))
                        Text("Dropped at \(stop)").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walk to \(walk.destinationName)").font(.system(size: 16, weight: .semibold))
                        ETALine(walk: walk)
                    }
                }
                HStack(spacing: 10) {
                    Button {} label: {
                        Text("Not now").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glass)
                    Button {} label: {
                        Label("Start walking", systemImage: "figure.walk")
                            .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.tripRed(scheme))
                }
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
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
                        .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("walk").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    EndButton()
                }
                Text("to \(walk.destinationName) · \(walkDistance(walk.metresLeft)) · Arrive \(walk.arrivalText)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(walk.steps.prefix(5)) { step in
                        StepRow(step: step, isCurrent: step.id == walk.current?.id,
                                isDone: step.id < (walk.current?.id ?? 0), red: Color.tripRed(scheme))
                    }
                }
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isCurrent ? .white : .primary)
                .frame(width: 34, height: 34)
                .background(isCurrent ? red : Color.secondary.opacity(0.15), in: Circle())
            Text(step.instruction)
                .font(.system(size: 14, weight: isCurrent ? .bold : .medium))
                .lineLimit(1)
            Spacer()
            Text(walkDistance(step.length))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
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
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        Image(systemName: walk.current?.icon ?? "arrow.up")
                            .font(.system(size: 54, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 104)
                            .glassEffect(.regular.tint(Color.tripRed(scheme)), in: .circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(walkDistance(walk.metresToTurn))
                                .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(walk.current?.instruction ?? "")
                                .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                            if let then = walk.following {
                                Text("Then: \(then.instruction)")
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 34))

                    HStack {
                        Image(systemName: "theatermasks.fill").foregroundStyle(Color.tripRed(scheme))
                        Text(walk.destinationName).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("\(walk.minutesLeft) min · \(walk.arrivalText)")
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    }
                    .padding(.horizontal, 18).frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.tripRed(scheme), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(walkDistance(walk.metresToTurn)).font(.system(size: 16, weight: .bold)).monospacedDigit()
                    Text(shortInstruction).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "figure.walk").foregroundStyle(.secondary)
                Text("\(walk.minutesLeft) min").font(.system(size: 16, weight: .bold)).monospacedDigit()
            }
            .padding(.horizontal, 10).frame(height: 56)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 24)
            .padding(.top, 2)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(walk.destinationName).font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text("Arrive \(walk.arrivalText)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
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
                    Text("\(walkDistance(walk.metresLeft)) left").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    EndButton()
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
        }
    }

    private var shortInstruction: String {
        (walk.current?.instruction ?? "").replacingOccurrences(of: "Turn ", with: "").capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
