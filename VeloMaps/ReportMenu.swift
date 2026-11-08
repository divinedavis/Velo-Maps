import SwiftUI

/// Things riders can report from the "+" button. Pothole is first (owner, 11/7: "put the
/// pothole button inside the plus sign") and still reports in one tap, no form. Heavy
/// traffic, hazard and crowded bus were removed (owner, 11/7).
enum ReportKind: String, CaseIterable, Identifiable {
    case pothole = "Pothole"
    case police = "Police"
    case accident = "Accident"
    case closure = "Road closed"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pothole: "exclamationmark.triangle.fill"
        case .police: "light.beacon.max.fill"
        case .accident: "car.side.rear.and.collision.and.car.side.front"
        case .closure: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .pothole: Color(white: 0.96)
        case .police: Color(red: 0.13, green: 0.42, blue: 0.95)
        case .accident: Color(red: 0.90, green: 0.20, blue: 0.20)
        case .closure: Color(red: 0.55, green: 0.12, blue: 0.16)
        }
    }
}

/// Glass "+" button that opens a menu of report types straight up from the button.
///
/// A custom overlay rather than a system popover: iOS places popovers itself and covered the
/// trip card with one (11/7). This always opens above the button row, right-aligned.
struct ReportMenuButton: View {
    @Binding var isOpen: Bool
    let onReport: (ReportKind) -> Void

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { isOpen.toggle() }
        } label: {
            Image(systemName: "plus")
                .scaledFont(20, .semibold)
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(isOpen ? 45 : 0))   // + becomes ×
        }
        .buttonStyle(.plain)
        .frame(width: 46, height: 46)
        .readableGlass(in: .circle, interactive: true)
        .contentShape(Circle())
        .accessibilityLabel(isOpen ? "Close report menu" : "Report police, accidents and more")
        .accessibilityIdentifier("report-menu")
        .overlay(alignment: .bottomTrailing) {
            if isOpen {
                menu
                    .offset(y: -56)   // straight up from the button, leaving + / × visible
                    .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
    }

    /// Compact glass pills stacked up the right edge — label, then the coloured icon — right-
    /// aligned with the + so the open menu never covers the road the rider is on (owner, 11/7),
    /// and short enough to fit under the turn banner.
    private var menu: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(ReportKind.allCases) { kind in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isOpen = false }
                    onReport(kind)
                } label: {
                    HStack(spacing: 8) {
                        Text(kind.rawValue)
                            .scaledFont(14, .semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize()
                        Group {
                            if kind == .pothole {
                                // The same warning sign riders see on the map.
                                Image(uiImage: PotholeAnnotation.sign).resizable().scaledToFit().padding(6)
                            } else {
                                Image(systemName: kind.icon).scaledFont(14, .semibold).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(kind.color, in: Circle())
                    }
                    .padding(.leading, 12).padding(.trailing, 5)
                    .frame(minHeight: 44)
                    .readableGlass(in: .capsule, interactive: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Report \(kind.rawValue.lowercased())")
                .accessibilityIdentifier("report-\(kind.rawValue)")
            }
        }
        .fixedSize()
    }
}
