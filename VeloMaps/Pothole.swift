import SwiftUI

private let amber = Color(red: 0.98, green: 0.68, blue: 0.08)

/// Shown above the card when a reported pothole is coming up on the route.
struct PotholeAheadPill: View {
    let metres: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, amber)
            VStack(alignment: .leading, spacing: 0) {
                Text("Pothole ahead").scaledFont(14, .bold).foregroundStyle(.black)
                Text(walkDistance(metres)).scaledFont(12, .semibold).monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.78))
            }
        }
        .padding(.leading, 10).padding(.trailing, 14)
        .frame(minHeight: 46)
        .padding(.vertical, 4)
        .background(amber, in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pothole-ahead")
    }
}

/// Confirmation pill shown at the top after any report.
struct ReportToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text)
        }
        .scaledFont(15, .semibold)
        .padding(.horizontal, 18)
        .frame(minHeight: 46)
        .fixedSize(horizontal: false, vertical: true)
        .readableGlass(in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report-toast")
    }
}
