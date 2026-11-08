import SwiftUI
import MapKit

/// App state: the live trip (or the scripted demo for tests/previews) and the phone's location.
@MainActor
final class AppModel: ObservableObject {
    let location = LocationService()
    let walk = Walk()
    @Published var trip: Trip?
    /// `-demo bus|drive`: the scripted demo ride (UI tests, previews). Riders never see it.
    let isDemo: Bool
    private var lastReroute = Date.distantPast

    init() {
        isDemo = UserDefaults.standard.string(forKey: "demo") != nil
        if isDemo { trip = Trip(defaults: .standard) }
        // -autoStart "lat,lon,Name" (dev/QA only): route there from the first fix and start,
        // so a simulated GPS drive (simctl location) can be recorded without typing.
        if let s = UserDefaults.standard.string(forKey: "autoStart") {
            let p = s.split(separator: ",", maxSplits: 2).map(String.init)
            if p.count == 3, let lat = Double(p[0]), let lon = Double(p[1]) {
                autoStart = (CLLocationCoordinate2D(latitude: lat, longitude: lon), p[2])
            }
        }
    }
    private var autoStart: (CLLocationCoordinate2D, String)?

    private func startIfAsked(from fix: CLLocation) {
        guard let (to, name) = autoStart else { return }
        autoStart = nil
        Task {
            if let r = try? await Router.drive(from: fix.coordinate, to: to, name: name) { start(r) }
        }
    }

    func start(_ route: Route) {
        location.setNavigating(true)
        trip = Trip(route: route, live: true)
        if let fix = location.fix { trip?.update(fix: fix) }
    }

    func end() {
        location.setNavigating(false)
        trip = nil
    }

    /// Feed each GPS fix to the trip; reroute (at most every 15 s) after leaving the route.
    func handle(_ fix: CLLocation) {
        startIfAsked(from: fix)
        guard let trip, trip.live else { return }
        trip.update(fix: fix)
        guard trip.offRoute, Date().timeIntervalSince(lastReroute) > 15 else { return }
        lastReroute = Date()
        let dest = trip.route.stops[trip.route.stops.count - 1].coordinate
        let name = trip.route.destination
        Task {
            if let r = try? await Router.drive(from: fix.coordinate, to: dest, name: name), self.trip === trip {
                trip.reroute(r)
            }
        }
    }
}

/// "Where to?": the map at your real location, a search field, a route preview, and Start.
struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var location: LocationService
    @StateObject private var search = PlaceSearch()
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var preview: Route?
    @State private var routing = false
    @State private var error: String?
    @FocusState private var searching: Bool

    init(model: AppModel) {
        self.model = model
        self.location = model.location
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                if let fix = location.fix {
                    Annotation("You", coordinate: fix.coordinate) {
                        Circle().fill(.blue).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 3)
                    }
                }
                if let preview {
                    MapPolyline(coordinates: preview.points).stroke(Color.tripRed(.light), lineWidth: 7)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            VStack(spacing: 10) {
                if let error { Text(error).scaledFont(14, .semibold).padding(12).readableGlass(in: .capsule) }
                if let preview { previewCard(preview) } else { searchPanel }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .onAppear { location.start() }
        .onChange(of: location.fix) { _, fix in
            guard preview == nil, let fix else { return }
            camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 1500, heading: 0, pitch: 45))
            search.region = MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        .onChange(of: query) { _, q in search.query = q }
    }

    private var searchPanel: some View {
        VStack(spacing: 8) {
            if searching && !search.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(search.results.prefix(5), id: \.self) { r in
                        Button { Task { await choose(r) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).scaledFont(16, .semibold).foregroundStyle(.primary)
                                if !r.subtitle.isEmpty {
                                    Text(r.subtitle).scaledFont(13).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-result")
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
                .readableGlass(in: .rect(cornerRadius: 24))
            }
            if location.denied {
                Text("Turn on Location for Velo Maps in Settings to navigate.")
                    .scaledFont(14, .semibold).multilineTextAlignment(.center).padding(14)
                    .readableGlass(in: .rect(cornerRadius: 20))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").scaledFont(17, .semibold).foregroundStyle(Color.tripRed(.light))
                TextField("Where to?", text: $query)
                    .scaledFont(18, .semibold)
                    .focused($searching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("where-to")
                if routing { ProgressView() }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .readableGlass(in: .capsule)
        }
    }

    private func previewCard(_ r: Route) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(((r.duration ?? r.length / r.etaSpeed) / 60).rounded(.up)))")
                    .scaledFont(52, .bold, .rounded).monospacedDigit()
                Text("min").scaledFont(20, .semibold)
                Spacer()
                Text(walkDistance(r.length)).scaledFont(17, .semibold).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.destination).scaledFont(17, .bold).lineLimit(2)
                if let via = r.via { Text("via \(via)").scaledFont(14, .medium).foregroundStyle(Color.primary.opacity(0.75)) }
            }
            HStack(spacing: 10) {
                Button { withAnimation { preview = nil } } label: {
                    Text("Cancel").scaledFont(16, .semibold).frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .readableGlass(in: .capsule, interactive: true)
                Button { model.start(r) } label: {
                    Text("Start").scaledFont(17, .bold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.tripRed(.light), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("start-navigation")
            }
        }
        .padding(18)
        .readableGlass(in: .rect(cornerRadius: 34))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-preview")
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        searching = false
        error = nil
        guard let from = location.fix?.coordinate else { error = "Waiting for your location…"; return }
        routing = true
        defer { routing = false }
        do {
            let item = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
            guard let item else { error = "Couldn't find that place"; return }
            let to = item.location.coordinate
            let route = try await Router.drive(from: from, to: to, name: item.name ?? completion.title)
            withAnimation {
                preview = route
                camera = .rect(MKPolyline(coordinates: route.points, count: route.points.count).boundingMapRect
                    .insetBy(dx: -800, dy: -800))
            }
        } catch {
            self.error = "Couldn't get a route: \(error.localizedDescription)"
        }
    }
}

/// Type-ahead place search near the rider.
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    var query = "" { didSet { completer.queryFragment = query; if query.isEmpty { results = [] } } }
    var region: MKCoordinateRegion? { didSet { if let region { completer.region = region } } }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = c.results
        Task { @MainActor in results = r }
    }

    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
