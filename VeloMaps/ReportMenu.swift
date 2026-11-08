import SwiftUI

/// Things riders can report from the "+" button. Pothole is first (owner, 11/7: "put the
/// pothole button inside the plus sign") and still reports in one tap, no form.
enum ReportKind: String, CaseIterable, Identifiable {
    case pothole = "Pothole"
    case police = "Police"
    case accident = "Accident"
    case traffic = "Heavy traffic"
    case closure = "Road closed"
    case hazard = "Hazard"
    case crowded = "Crowded bus"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pothole: "exclamationmark.triangle.fill"
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
        case .pothole: Color(white: 0.96)
        case .police: Color(red: 0.13, green: 0.42, blue: 0.95)
        case .accident: Color(red: 0.90, green: 0.20, blue: 0.20)
        case .traffic: Color(red: 0.97, green: 0.55, blue: 0.10)
        case .closure: Color(red: 0.55, green: 0.12, blue: 0.16)
        case .hazard: Color(red: 0.96, green: 0.76, blue: 0.08)
        case .crowded: Color(red: 0.52, green: 0.32, blue: 0.86)
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
                    .offset(y: -56)   // sit above the button row, leaving + / × visible
                    .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
    }

    /// Two columns so all seven fit between the turn banner and the + button (a single
    /// column pushed Pothole, the first item, under the banner — 11/7).
    private var menu: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .leading),
                            GridItem(.flexible(), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 4) {
            ForEach(ReportKind.allCases) { kind in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isOpen = false }
                    onReport(kind)
                } label: {
                    HStack(spacing: 9) {
                        Group {
                            if kind == .pothole {
                                // The same warning sign riders see on the map.
                                Image(uiImage: PotholeAnnotation.sign).resizable().scaledToFit().padding(5)
                            } else {
                                Image(systemName: kind.icon).scaledFont(13, .semibold).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .background(kind.color, in: Circle())
                        Text(kind.rawValue)
                            .scaledFont(15, .medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report-\(kind.rawValue)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .readableGlass(in: .rect(cornerRadius: 26))
    }
}
