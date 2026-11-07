import SwiftUI

@main
struct TransitMapSpikeApp: App {
    @StateObject private var trip = Trip()

    var body: some Scene {
        WindowGroup {
            RideScreen(trip: trip)
                .task { await trip.loadRoadGeometry() }
        }
    }
}

struct RideScreen: View {
    @ObservedObject var trip: Trip
    @State private var cardHeight: CGFloat = 220

    var body: some View {
        ZStack(alignment: .bottom) {
            TransitMapView(trip: trip, bottomInset: cardHeight)
                .ignoresSafeArea()
            TripCard(trip: trip)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
        }
    }
}
