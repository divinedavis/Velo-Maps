import SwiftUI

private let amber = Color(red: 0.98, green: 0.68, blue: 0.08)

/// Glass button that sits on the right, just above the trip card.
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

/// Short report form shown as a system sheet (Liquid Glass on iOS 26).
struct PotholeReportSheet: View {
    let location: String
    let onCancel: () -> Void
    let onReport: () -> Void
    @State private var size = "Medium"
    @State private var spot = "Traffic lane"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(amber)
                    .frame(width: 44, height: 44)
                    .background(amber.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report a pothole").font(.system(size: 20, weight: .bold))
                    Label(location, systemImage: "location.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("How big?").font(.system(size: 14, weight: .semibold))
                Picker("Size", selection: $size) {
                    ForEach(["Small", "Medium", "Large"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Where?").font(.system(size: 14, weight: .semibold))
                Picker("Where", selection: $spot) {
                    ForEach(["Traffic lane", "Bus lane", "Crosswalk"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
                Button(action: onReport) {
                    Text("Report").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.tripRed(scheme))
                .accessibilityIdentifier("send-pothole-report")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pothole-sheet")
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
