import SwiftUI

/// US-style guide sign (MUTCD green, white legend) showing a ramp's sign text verbatim:
/// exit-number tab (only when OSM has one), route shields with their direction word, then
/// the destination lines exactly as tagged.
struct HighwaySignView: View {
    let sign: HighwaySign
    var style: Int = 0
    static let green = Color(red: 0.0, green: 0.42, blue: 0.27)

    var body: some View {
        Group {
            switch style {
            case 1: GlassGuideSign(sign: sign)
            case 2: ShieldHeroSign(sign: sign)
            case 3: ChipSign(sign: sign)
            case 4: JunctionSign(sign: sign)
            case 5: OverheadSign(sign: sign)
            default: classic
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Highway sign: \(sign.spoken)")
        .accessibilityIdentifier("highway-sign")
    }

    /// 0 — flat MUTCD-green guide sign.
    private var classic: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let n = sign.exitNumber {
                Text("EXIT \(n)")
                    .scaledFont(13, .bold)
                    .fontWidth(.condensed)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Self.green, in: UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                        .inset(by: 2.5).stroke(.white, lineWidth: 1.5))
                    .padding(.trailing, 14)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if !sign.shields.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(sign.shields, id: \.self) { RouteShield(ref: $0) }
                        }
                    }
                    ForEach(sign.destinations, id: \.self) { line in
                        Text(line)
                            .scaledFont(20, .semibold)
                            .fontWidth(.condensed)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: sign.kind == .exit ? "arrow.down.right" : "arrow.up.right")
                    .scaledFont(26, .heavy)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).inset(by: 3.5).stroke(.white, lineWidth: 2))
        }
    }
}

// MARK: - Liquid Glass sign designs (owner asked for 5 glass alternatives, 11/7)

private let signGreen = HighwaySignView.green

/// Destination lines in sign type (white, condensed), shared by the green designs.
private struct SignLines: View {
    let sign: HighwaySign
    var size: CGFloat = 20
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sign.destinations, id: \.self) {
                Text($0).scaledFont(size, .semibold).fontWidth(.condensed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private func exitWord(_ sign: HighwaySign) -> String {
    if let n = sign.exitNumber { return "EXIT \(n)" }
    return sign.kind == .exit ? "EXIT" : "ENTRANCE"
}

private func rampArrow(_ sign: HighwaySign) -> String { sign.kind == .exit ? "arrow.down.right" : "arrow.up.right" }

/// 1 — Glass guide sign: the classic layout on green-tinted Liquid Glass with a white keyline.
struct GlassGuideSign: View {
    let sign: HighwaySign
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if !sign.shields.isEmpty {
                    HStack(spacing: 10) { ForEach(sign.shields, id: \.self) { RouteShield(ref: $0) } }
                }
                SignLines(sign: sign)
            }
            Spacer(minLength: 0)
            Image(systemName: rampArrow(sign)).scaledFont(26, .heavy)
        }
        .foregroundStyle(.white)
        .padding(14)
        .glassEffect(.regular.tint(signGreen.opacity(0.9)), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).inset(by: 3).stroke(.white.opacity(0.75), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if let n = sign.exitNumber {
                Text("EXIT \(n)").scaledFont(12, .bold).fontWidth(.condensed).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .glassEffect(.regular.tint(signGreen), in: .capsule)
                    .offset(x: -12, y: -12)
            }
        }
    }
}

/// 2 — Shield hero: a big route shield (or ramp arrow) on clear glass, the words beside it,
/// a green keyline down the edge.
struct ShieldHeroSign: View {
    let sign: HighwaySign
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let ref = sign.shields.first {
                    RouteShield(ref: ref, onLight: true).scaleEffect(1.35).frame(width: 64, height: 58)
                } else {
                    Image(systemName: rampArrow(sign)).scaledFont(26, .heavy).foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .glassEffect(.regular.tint(signGreen), in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(exitWord(sign)).scaledFont(11, .heavy).tracking(1.2).foregroundStyle(signGreen)
                ForEach(sign.destinations, id: \.self) {
                    Text($0).scaledFont(19, .bold).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.leading, 6)
        .readableGlass(in: .rect(cornerRadius: 18))
        .overlay(alignment: .leading) {
            Capsule().fill(signGreen).frame(width: 5).padding(.vertical, 12).padding(.leading, 6)
        }
    }
}

/// 3 — Chips: each shield and destination is its own glass capsule, ending in an arrow chip.
struct ChipSign: View {
    let sign: HighwaySign
    var body: some View {
        FlowLayout(spacing: 8) {
            Text(exitWord(sign)).scaledFont(12, .heavy).tracking(1).foregroundStyle(.white)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .glassEffect(.regular.tint(signGreen), in: .capsule)
            ForEach(sign.shields, id: \.self) { ref in
                RouteShield(ref: ref, onLight: true, compact: true)
                    .padding(.horizontal, 8).frame(minHeight: 34)
                    .readableGlass(in: .capsule)
            }
            ForEach(sign.destinations, id: \.self) { d in
                HStack(spacing: 6) {
                    Circle().fill(signGreen).frame(width: 8, height: 8)
                    Text(d).scaledFont(16, .semibold).foregroundStyle(.primary)
                }
                .padding(.horizontal, 12).frame(minHeight: 34)
                .readableGlass(in: .capsule)
            }
            Image(systemName: rampArrow(sign)).scaledFont(15, .heavy).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.tint(Color.tripRed(.light)), in: .circle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // line up with the banner text
    }
}

/// 4 — Junction view: a live mini diagram of the ramp leaving (or joining) the road on glass,
/// next to the sign words on green glass.
struct JunctionSign: View {
    let sign: HighwaySign
    var body: some View {
        HStack(spacing: 10) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                var road = Path()
                road.move(to: CGPoint(x: w * 0.38, y: h)); road.addLine(to: CGPoint(x: w * 0.38, y: 0))
                ctx.stroke(road, with: .color(.gray.opacity(0.55)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                var ramp = Path()
                if sign.kind == .exit {
                    ramp.move(to: CGPoint(x: w * 0.38, y: h * 0.95))
                    ramp.addLine(to: CGPoint(x: w * 0.38, y: h * 0.62))
                    ramp.addQuadCurve(to: CGPoint(x: w * 0.85, y: h * 0.1), control: CGPoint(x: w * 0.42, y: h * 0.25))
                } else {
                    ramp.move(to: CGPoint(x: w * 0.85, y: h * 0.95))
                    ramp.addQuadCurve(to: CGPoint(x: w * 0.38, y: h * 0.35), control: CGPoint(x: w * 0.45, y: h * 0.75))
                    ramp.addLine(to: CGPoint(x: w * 0.38, y: h * 0.05))
                }
                ctx.stroke(ramp, with: .color(Color.tripRed(.light)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 66, height: 66)
            .padding(6)
            .readableGlass(in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(exitWord(sign)).scaledFont(11, .heavy).tracking(1)
                    ForEach(sign.shields, id: \.self) { RouteShield(ref: $0, compact: true) }
                }
                SignLines(sign: sign, size: 18)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .glassEffect(.regular.tint(signGreen.opacity(0.9)), in: .rect(cornerRadius: 16))
        }
    }
}

/// 5 — Overhead gantry: the green glass sign tilted back in perspective, hung from a glass
/// gantry bar, like the real sign seen through the windscreen.
struct OverheadSign: View {
    let sign: HighwaySign
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.clear).frame(height: 8)
                .readableGlass(in: .capsule)
                .padding(.horizontal, 6)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if !sign.shields.isEmpty {
                        HStack(spacing: 10) { ForEach(sign.shields, id: \.self) { RouteShield(ref: $0) } }
                    }
                    SignLines(sign: sign, size: 21)
                }
                Spacer(minLength: 0)
                Image(systemName: rampArrow(sign)).scaledFont(28, .heavy)
            }
            .foregroundStyle(.white)
            .padding(14)
            .glassEffect(.regular.tint(signGreen.opacity(0.92)), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).inset(by: 3).stroke(.white.opacity(0.85), lineWidth: 2))
            .rotation3DEffect(.degrees(10), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
            .padding(.horizontal, 10)   // the tilt widens the bottom edge; keep it inside the banner
            .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
        }
    }
}

/// Wraps its children onto new lines (for the chip design).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

/// A route shield parsed from a `destination:ref` value such as "NY 9A North",
/// "I 87 South" or "US 9". The direction word sits above the shield, as on real signs.
struct RouteShield: View {
    let ref: String
    /// Direction word drawn dark when the shield sits on light glass instead of green.
    var onLight = false
    /// Direction word beside the shield instead of above it.
    var compact = false

    private var parts: (network: String, number: String, direction: String?) {
        var words = ref.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        let dirs = ["North", "South", "East", "West", "N", "S", "E", "W"]
        var direction: String?
        if let last = words.last, dirs.contains(last), words.count > 1 { direction = words.removeLast() }
        let network = words.count > 1 ? words[0] : ""
        let number = words.count > 1 ? words.dropFirst().joined(separator: " ") : (words.first ?? ref)
        return (network, number, direction)
    }

    var body: some View {
        let p = parts
        let word = p.direction.map {
            Text(fullDirection($0).uppercased()).scaledFont(11, .bold).fontWidth(.condensed)
                .foregroundStyle(onLight ? Color.primary : Color.white)
        }
        if compact {
            HStack(spacing: 5) { shield(network: p.network, number: p.number); word }
        } else {
            VStack(spacing: 3) { word; shield(network: p.network, number: p.number) }
        }
    }

    private func fullDirection(_ d: String) -> String {
        ["N": "North", "S": "South", "E": "East", "W": "West"][d] ?? d
    }

    @ViewBuilder private func shield(network: String, number: String) -> some View {
        let label = Text(number).scaledFont(17, .heavy).fontWidth(.condensed).lineLimit(1).minimumScaleFactor(0.6)
        switch network.uppercased() {
        case "I":   // Interstate: red cap over blue
            label.foregroundStyle(.white)
                .frame(minWidth: 34, minHeight: 32)
                .padding(.horizontal, 4)
                .background(
                    VStack(spacing: 0) { Color(red: 0.75, green: 0.1, blue: 0.15).frame(height: 8); Color(red: 0.0, green: 0.25, blue: 0.6) }
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white, lineWidth: 1.5))
        default:    // US and state routes: black legend on a white shield
            label.foregroundStyle(.black)
                .frame(minWidth: 34, minHeight: 30)
                .padding(.horizontal, 5)
                .background(.white, in: RoundedRectangle(cornerRadius: network.uppercased() == "US" ? 10 : 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: network.uppercased() == "US" ? 10 : 5, style: .continuous)
                    .inset(by: 2).stroke(.black, lineWidth: 1.2))
        }
    }
}
