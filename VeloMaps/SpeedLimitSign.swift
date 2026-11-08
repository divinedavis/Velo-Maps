import SwiftUI

/// Posted speed limit, top-left under the turn banner (owner, 11/8). Five designs behind
/// -speedStyle 1…5. Hidden when the limit isn't known. Designs that show your speed turn red
/// more than 5 mph over.
struct SpeedLimitView: View {
    @ObservedObject var trip: Trip
    let style: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let limit = trip.speedLimitMPH {
            let speed = trip.speedMPH
            let over = speed > limit + 5
            Group {
                switch style {
                case 2: withSpeed(limit, speed, over)
                case 3: roundSign(limit)
                case 4: speedometer(limit, speed, over)
                case 5: chip(limit)
                default: usSign(limit, scale: 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed limit \(limit) miles per hour" + ([2, 4].contains(style) ? ", you're going \(speed)" : ""))
            .accessibilityIdentifier("speed-limit")
            .animation(.snappy, value: limit)
        }
    }

    /// 1 — The US regulatory sign (MUTCD R2-1): white, black border, SPEED LIMIT over the number.
    private func usSign(_ limit: Int, scale: CGFloat) -> some View {
        VStack(spacing: -2 * scale) {
            Text("SPEED").scaledFont(10 * scale, .heavy).fontWidth(.condensed)
            Text("LIMIT").scaledFont(10 * scale, .heavy).fontWidth(.condensed)
            Text("\(limit)").scaledFont(30 * scale, .heavy).fontWidth(.condensed).monospacedDigit()
        }
        .foregroundStyle(.black)
        .frame(width: 52 * scale, height: 66 * scale)
        .background(.white, in: RoundedRectangle(cornerRadius: 9 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).inset(by: 3 * scale).stroke(.black, lineWidth: 1.6 * scale))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }

    /// 2 — Glass pill: the US sign with your current speed beside it.
    private func withSpeed(_ limit: Int, _ speed: Int, _ over: Bool) -> some View {
        HStack(spacing: 10) {
            usSign(limit, scale: 0.78)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(speed)").scaledFont(28, .bold, .rounded).monospacedDigit()
                    .foregroundStyle(over ? Color.tripRed(scheme) : .primary)
                Text("mph").scaledFont(12, .semibold).foregroundStyle(Color.primary.opacity(0.75))
            }
            .padding(.trailing, 8)
        }
        .padding(5)
        .readableGlass(in: .rect(cornerRadius: 18))
    }

    /// 3 — Round sign: number in a red-ringed glass disc.
    private func roundSign(_ limit: Int) -> some View {
        VStack(spacing: -3) {
            Text("\(limit)").scaledFont(24, .heavy, .rounded).monospacedDigit()
            Text("MPH").scaledFont(9, .heavy).foregroundStyle(Color.primary.opacity(0.75))
        }
        .frame(width: 58, height: 58)
        .readableGlass(in: .circle)
        .overlay(Circle().inset(by: 2).stroke(Color.tripRed(scheme), lineWidth: 5))
    }

    /// 4 — Speedometer: your speed large in a glass dial, the limit sign tucked at its corner.
    private func speedometer(_ limit: Int, _ speed: Int, _ over: Bool) -> some View {
        VStack(spacing: -3) {
            Text("\(speed)").scaledFont(26, .bold, .rounded).monospacedDigit()
            Text("mph").scaledFont(10, .semibold).foregroundStyle(Color.primary.opacity(0.75))
        }
        .foregroundStyle(over ? Color.white : Color.primary)
        .frame(width: 66, height: 66)
        .background { if over { Circle().fill(Color.tripRed(scheme)) } }
        .readableGlass(in: .circle)
        .overlay(alignment: .bottomTrailing) { usSign(limit, scale: 0.55).offset(x: 16, y: 10) }
        .padding(.trailing, 16).padding(.bottom, 10)
    }

    /// 5 — Chip: a compact glass capsule.
    private func chip(_ limit: Int) -> some View {
        HStack(spacing: 6) {
            Text("LIMIT").scaledFont(10, .heavy).tracking(0.8).foregroundStyle(Color.primary.opacity(0.75))
            Text("\(limit)").scaledFont(20, .bold, .rounded).monospacedDigit()
            Text("mph").scaledFont(11, .semibold).foregroundStyle(Color.primary.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .readableGlass(in: .capsule)
    }
}
