import SwiftUI

@main
struct TransitMapSpikeApp: App {
    @StateObject private var trip = Trip()
    @StateObject private var walk = Walk()

    var body: some Scene {
        WindowGroup {
            RideScreen(trip: trip, walk: walk)
        }
    }
}

struct RideScreen: View {
    @ObservedObject var trip: Trip
    @ObservedObject var walk: Walk
    @State private var cardTop: CGFloat = 0
    @State private var showReportMenu = false
    @State private var toast: String?

    var body: some View {
        Group {
            if trip.walking { walkScreen } else { rideScreen }
        }
        .preferredColorScheme(trip.night ? .dark : .light)
    }

    private var walkScreen: some View {
        ZStack {
            WalkMapView(walk: walk, night: trip.night).ignoresSafeArea()
            walkLayout
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
        .task { await walk.load(from: trip.route.stops.last!.coordinate) }
    }

    @ViewBuilder private var walkLayout: some View {
        switch trip.walkStyle {
        case 2: WalkHandoffLayout(walk: walk, line: trip.route.line, stop: trip.route.destination)
        case 3: WalkStepsLayout(walk: walk)
        case 4: WalkGlanceLayout(walk: walk)
        case 5: WalkActivityLayout(walk: walk)
        default: WalkTurnLayout(walk: walk)
        }
    }

    private var rideScreen: some View {
        ZStack(alignment: .bottom) {
            TransitMapView(trip: trip, cardTop: cardTop)
                .ignoresSafeArea()
            if showReportMenu {
                // Tap anywhere else to close the report menu.
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showReportMenu = false } }
            }
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    if let (_, metres) = trip.potholeAhead() {
                        PotholeAheadPill(metres: metres)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    // Pothole is its own one-tap button; everything else lives behind "+".
                    PotholeButton { reportPothole() }
                    ReportMenuButton(isOpen: $showReportMenu) { kind in
                        showToast("\(kind.rawValue) reported. Thanks!")
                    }
                }
                card
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { cardTop = $0 }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                turnBanner
                if let toast {
                    ReportToast(text: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
        }
        .onAppear {
            if trip.startPotholeTap { reportPothole(keepToast: true) }
            if trip.startReportMenu {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { showReportMenu = true }
                }
            }
        }
    }

    /// Turn-by-turn banner in the chosen design (4 lives inside the card instead).
    @ViewBuilder private var turnBanner: some View {
        switch trip.turnStyle {
        case 1: TurnBannerClassic(trip: trip)
        case 2: TurnBannerLanes(trip: trip)
        case 3: TurnBannerIsland(trip: trip)
        case 5: TurnBannerThen(trip: trip)
        default: EmptyView()
        }
    }

    private func reportPothole(keepToast: Bool = false) {
        trip.reportPothole()
        showToast("Pothole reported for all riders", keep: keepToast)
    }

    private func showToast(_ text: String, keep: Bool = false) {
        withAnimation(.spring) { toast = text }
        guard !keep else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut) { if toast == text { toast = nil } }
        }
    }

    @ViewBuilder private var card: some View {
        switch trip.cardStyle {
        case 1: GlassSheetCard(trip: trip)
        case 2: GlassPillCard(trip: trip)
        case 3: GlassClusterCard(trip: trip)
        case 4: GlassHeroCard(trip: trip)
        case 5: GlassActivityCard(trip: trip)
        default: TripCard(trip: trip)
        }
    }
}
