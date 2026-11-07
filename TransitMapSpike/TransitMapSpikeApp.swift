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
            card
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { cardTop = $0 }
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
