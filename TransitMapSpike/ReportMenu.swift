import SwiftUI

/// Things riders can report from the "+" button. Pothole has its own button.
enum ReportKind: String, CaseIterable, Identifiable {
    case police = "Police"
    case accident = "Accident"
    case traffic = "Heavy traffic"
    case closure = "Road closed"
    case hazard = "Hazard"
    case crowded = "Crowded bus"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .police: "light.beacon.max.fill"
        case .accident: "car.side.rear.and.collision.and.car.side.front"
        case .traffic: "car.2.fill"
        case .closure: "xmark.octagon.fill"
        case .hazard: "exclamationmark.triangle.fill"
        case .crowded: "person.3.fill"
        }
    }

    var color: Color {
        switch self {
        case .police: Color(red: 0.13, green: 0.42, blue: 0.95)
        case .accident: Color(red: 0.90, green: 0.20, blue: 0.20)
        case .traffic: Color(red: 0.97, green: 0.55, blue: 0.10)
        case .closure: Color(red: 0.55, green: 0.12, blue: 0.16)
        case .hazard: Color(red: 0.96, green: 0.76, blue: 0.08)
        case .crowded: Color(red: 0.52, green: 0.32, blue: 0.86)
        }
    }
}

/// Glass "+" button that morphs into a menu of report types.
///
/// Uses the technique from the 11/7 reference recording: `matchedTransitionSource` on the
/// label (before the glass button style is applied) plus a zoom navigation transition on the
/// popover content. On iOS 27 that gives the native menu-style morph out of the glass button;
/// on iOS 26 it shows as a regular popover.
struct ReportMenuButton: View {
    @Binding var isOpen: Bool
    let onReport: (ReportKind) -> Void
    @Namespace private var ns

    var body: some View {
        Button { isOpen = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 34, height: 34)
                .matchedTransitionSource(id: "report-menu", in: ns)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Report police, accidents and more")
        .accessibilityIdentifier("report-menu")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ReportKind.allCases) { kind in
                    Button {
                        isOpen = false
                        onReport(kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(kind.color, in: Circle())
                            Text(kind.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("report-\(kind.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
            .navigationTransition(.zoom(sourceID: "report-menu", in: ns))
        }
    }
}
