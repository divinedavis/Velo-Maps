import SwiftUI

/// US-style guide sign (MUTCD green, white legend) showing a ramp's sign text verbatim:
/// exit-number tab (only when OSM has one), route shields with their direction word, then
/// the destination lines exactly as tagged.
struct HighwaySignView: View {
    let sign: HighwaySign
    static let green = Color(red: 0.0, green: 0.42, blue: 0.27)

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Highway sign: \(sign.spoken)")
        .accessibilityIdentifier("highway-sign")
    }
}

/// A route shield parsed from a `destination:ref` value such as "NY 9A North",
/// "I 87 South" or "US 9". The direction word sits above the shield, as on real signs.
struct RouteShield: View {
    let ref: String

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
        VStack(spacing: 3) {
            if let d = p.direction {
                Text(fullDirection(d).uppercased())
                    .scaledFont(11, .bold)
                    .fontWidth(.condensed)
                    .foregroundStyle(.white)
            }
            shield(network: p.network, number: p.number)
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
