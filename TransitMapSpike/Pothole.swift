import SwiftUI

private let amber = Color(red: 0.98, green: 0.68, blue: 0.08)

/// Glass button that sits on the right, just above the trip card. One tap reports a pothole
/// at the bus's current spot; no form.
struct PotholeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(amber)
                Text("Pothole")
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(height: 34)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Report a pothole")
        .accessibilityIdentifier("report-pothole")
    }
}

/// Shown above the card when a reported pothole is coming up on the route.
struct PotholeAheadPill: View {
    let metres: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, amber)
            VStack(alignment: .leading, spacing: 0) {
                Text("Pothole ahead").font(.system(size: 14, weight: .bold))
                Text(walkDistance(metres)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 10).padding(.trailing, 14)
        .frame(height: 46)
        .glassEffect(.regular.tint(amber.opacity(0.35)), in: .capsule)
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
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 18)
        .frame(height: 46)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report-toast")
    }
}
