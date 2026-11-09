import SwiftUI
import MapKit

/// App state: the live trip (or the scripted demo for tests/previews) and the phone's location.
@MainActor
final class AppModel: ObservableObject {
    let location = LocationService()
    let walk = Walk()
    let places = PlacesStore()
    @Published var trip: Trip?
    /// `-demo bus|drive`: the scripted demo ride (UI tests, previews). Riders never see it.
    let isDemo: Bool
    private var lastReroute = Date.distantPast
    private var lastFasterCheck = Date()
    private var checkingFaster = false

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
        let trip = Trip(route: route, live: true)
        self.trip = trip
        lastFasterCheck = Date()
        if let fix = location.fix { trip.update(fix: fix) }
        loadLimits(for: trip)
    }

    /// Every 4 minutes on the route: ask for live-traffic routes from here and switch if one is
    /// clearly faster. Only with live traffic (the no-traffic fallbacks never change their
    /// answer mid-drive), never with a turn banner up, never in the last 2 km.
    private func checkForFasterRoute(_ trip: Trip, from fix: CLLocation) {
        guard Router.trafficEnabled, !trip.offRoute, !checkingFaster, trip.bannerManeuver == nil,
              Date().timeIntervalSince(lastFasterCheck) >= FasterRoute.checkEvery,
              trip.route.length - trip.distance > FasterRoute.minRemaining else { return }
        lastFasterCheck = Date()
        checkingFaster = true
        let dest = trip.route.stops[trip.route.stops.count - 1].coordinate
        let name = trip.route.destination
        Task {
            defer { checkingFaster = false }
            guard let candidates = try? await Router.traffic(from: fix.coordinate, to: dest, name: name),
                  self.trip === trip, !trip.offRoute, trip.bannerManeuver == nil,
                  let (route, saves) = FasterRoute.pick(current: trip.route, at: trip.distance, candidates: candidates)
            else { return }
            trip.switchToFaster(route, saves: saves)
            loadLimits(for: trip)
        }
    }

    /// One Overpass request per route for posted speed limits (sign hidden until then).
    private func loadLimits(for trip: Trip) {
        let route = trip.route
        Task {
            let changes = await SpeedLimits.lookup(route)
            trip.setSpeedLimits(changes, forRouteLength: route.length)
        }
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
        checkForFasterRoute(trip, from: fix)
        guard trip.offRoute, Date().timeIntervalSince(lastReroute) > 15 else { return }
        lastReroute = Date()
        lastFasterCheck = Date()
        let dest = trip.route.stops[trip.route.stops.count - 1].coordinate
        let name = trip.route.destination
        Task {
            if let r = try? await Router.drive(from: fix.coordinate, to: dest, name: name), self.trip === trip {
                trip.reroute(r)
                loadLimits(for: trip)
            }
        }
    }
}

/// "Where to?" in an Apple Maps-style sheet (owner, 11/9): the map at your real location, and a
/// sheet that rests at three heights — search only, Places + Recents, full. Places are Home,
/// Work and saved spots with Apple's drive time; Recents are where you searched. Map buttons:
/// Map Modes (Explore / Driving / Satellite + Traffic), 3D/2D, and back to your location.
struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var location: LocationService
    @ObservedObject var places: PlacesStore
    @StateObject private var search = PlaceSearch()
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var preview: Route?
    @State private var lookAround: MKLookAroundScene?
    @State private var routing = false
    @State private var error: String?
    @State private var detent: PresentationDetent = HomeView.half
    @State private var showSheet = true
    @State private var showModes = false
    @State private var picking: SavedPlace.Kind?
    @State private var etas: [UUID: Int] = [:]
    @State private var pitched = true
    @State private var category: PlaceCategory?
    @State private var categoryResults: [NearbyPlace] = []
    @State private var showRecents = false
    @FocusState private var searching: Bool
    @AppStorage(SettingKey.mapMode) private var mapMode = MapMode.explore.rawValue
    @AppStorage(SettingKey.traffic) private var traffic = false

    static let peek = PresentationDetent.height(96)
    static let half = PresentationDetent.fraction(0.45)

    init(model: AppModel) {
        self.model = model
        self.location = model.location
        self.places = model.places
    }

    private var mode: MapMode { MapMode(rawValue: mapMode) ?? .explore }

    private var mapStyle: MapStyle {
        switch mode {
        case .explore: .standard(elevation: .realistic, pointsOfInterest: .all, showsTraffic: traffic)
        case .driving: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: true)
        case .satellite: .hybrid(elevation: .realistic, pointsOfInterest: .all, showsTraffic: traffic)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $camera) {
                if let fix = location.fix {
                    Annotation("You", coordinate: fix.coordinate) {
                        Circle().fill(.blue).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 3)
                    }
                }
                if let preview {
                    MapPolyline(coordinates: preview.points).stroke(Color.tripRed(.light), lineWidth: 7)
                    Marker(preview.destination, coordinate: preview.points[preview.points.count - 1]).tint(Color.tripRed(.light))
                } else if category != nil {
                    ForEach(categoryResults) { p in
                        Marker(p.name, systemImage: p.icon, coordinate: p.coordinate).tint(category?.color ?? .red)
                    }
                } else {
                    ForEach(places.row) { p in
                        Marker(p.kind == .home ? "Home" : p.kind == .work ? "Work" : p.name,
                               systemImage: icon(for: p), coordinate: p.coordinate).tint(tint(for: p))
                    }
                }
            }
            .mapStyle(mapStyle)
            .mapControls { MapCompass(); MapScaleView() }
            .ignoresSafeArea()

            mapButtons.padding(.trailing, 12).padding(.top, 6)
        }
        .sheet(isPresented: $showSheet) {
            sheet
                .presentationDetents([Self.peek, Self.half, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.half))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .sheet(isPresented: $showModes) {
                    MapModesSheet(mode: $mapMode, traffic: $traffic)
                        .presentationDetents([.height(330)])
                }
                .sheet(isPresented: $showRecents) {
                    RecentsListView(places: places) { r in Task { await route(to: r) } }
                        .presentationDetents([.large])
                }
        }
        .onAppear { location.start() }
        .onChange(of: location.fix, initial: true) { _, fix in
            guard let fix else { return }
            // Search near the rider (a same-named place 2,900 mi away was picked on 11/8).
            search.region = MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
            guard preview == nil, !moved else { return }
            moved = true
            recenter(fix.coordinate)
        }
        .onChange(of: query) { _, q in search.query = q }
        .onChange(of: searching) { _, on in if on { withAnimation { detent = .large } } }
        .task(id: etaKey) { await loadETAs() }
    }
    @State private var moved = false

    // MARK: Map buttons

    private var mapButtons: some View {
        VStack(spacing: 0) {
            mapButton("map", label: "Map modes", id: "map-modes") { showModes = true }
            Divider().frame(width: 30)
            Button {
                pitched.toggle()
                if let c = location.fix?.coordinate { recenter(c) }
            } label: {
                Text(pitched ? "2D" : "3D").scaledFont(15, .bold).frame(width: 46, height: 46).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pitched ? "Show flat map" : "Show 3D map")
            .accessibilityIdentifier("toggle-3d")
            Divider().frame(width: 30)
            mapButton("location.fill", label: "Show my location", id: "locate") {
                if let c = location.fix?.coordinate { recenter(c) }
            }
        }
        .foregroundStyle(Color.primary)
        .readableGlass(in: .rect(cornerRadius: 23))
    }

    private func mapButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).scaledFont(17, .semibold).frame(width: 46, height: 46).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func recenter(_ c: CLLocationCoordinate2D) {
        withAnimation { camera = .camera(MapCamera(centerCoordinate: c, distance: 1500, heading: 0, pitch: pitched ? 45 : 0)) }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error { Text(error).scaledFont(14, .semibold).foregroundStyle(Color.tripRed(.light)) }
                    if let preview {
                        previewCard(preview)
                    } else if let category {
                        categoryList(category)
                    } else if searching && query.isEmpty && picking == nil {
                        SearchHomeView(places: places, here: location.fix,
                                       onCategory: { c in Task { await show(c) } },
                                       onPlace: { p in searching = false; Task { await route(to: p) } },
                                       onAllRecents: { showRecents = true })
                    } else if searching || !query.isEmpty || picking != nil {
                        if let picking {
                            Text("Search for your \(picking == .home ? "home" : "work") address")
                                .scaledFont(15, .semibold).foregroundStyle(Color.primary.opacity(0.75))
                                .accessibilityIdentifier("picking-hint")
                        }
                        results
                    } else {
                        if location.denied {
                            Text("Turn on Location for Velo Maps in Settings to navigate.")
                                .scaledFont(14, .semibold)
                        }
                        placesSection
                        recentsSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 18)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").scaledFont(17, .semibold).foregroundStyle(Color.primary.opacity(0.7))
                TextField("Where to?", text: $query)
                    .scaledFont(17, .medium)
                    .focused($searching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("where-to")
                if routing { ProgressView() }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color.primary.opacity(0.08), in: Capsule())
            if searching || !query.isEmpty || picking != nil || category != nil {
                Button("Cancel") { cancelSearch() }
                    .scaledFont(16, .semibold)
                    .foregroundStyle(Color.tripRed(.light))
                    .accessibilityIdentifier("cancel-search")
            }
        }
        .padding(.horizontal, 18)
    }

    private var results: some View {
        VStack(spacing: 0) {
            ForEach(search.results.prefix(8), id: \.self) { r in
                Button { Task { await choose(r) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").scaledFont(28).foregroundStyle(Color.tripRed(.light))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).scaledFont(16, .semibold).foregroundStyle(.primary)
                            if !r.subtitle.isEmpty {
                                Text(r.subtitle).scaledFont(13).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-result")
                Divider().padding(.leading, 40)
            }
        }
    }

    // Places: Home, Work, saved spots, then "Add".
    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Places").scaledFont(20, .bold).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    placeTile(places.home, kind: .home)
                    placeTile(places.work, kind: .work)
                    ForEach(places.pinned) { placeTile($0, kind: .pinned) }
                }
            }
        }
    }

    private func placeTile(_ place: SavedPlace?, kind: SavedPlace.Kind) -> some View {
        let name = kind == .home ? "Home" : kind == .work ? "Work" : place?.name ?? ""
        let detail = place.map { p in etas[p.id].map(PlaceETA.text) ?? distanceText(to: p) } ?? "Add"
        return Button {
            if let place { Task { await route(to: place) } } else { startPicking(kind) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind == .home ? "house.fill" : kind == .work ? "briefcase.fill" : "mappin")
                    .scaledFont(24, .semibold).foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(place == nil ? Color.gray : tint(forKind: kind), in: Circle())
                Text(name).scaledFont(13, .semibold).lineLimit(1)
                Text(detail).scaledFont(12).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
            }
            .frame(width: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(place == nil ? "Add \(name)" : "\(name), \(place!.subtitle), \(detail)")
        .accessibilityIdentifier(kind == .pinned ? "place-pinned" : "place-\(kind.rawValue)")
        .contextMenu {
            if let place {
                if kind != .pinned { Button("Change", systemImage: "pencil") { startPicking(kind) } }
                Button("Remove", systemImage: "trash", role: .destructive) { places.remove(place) }
            }
        }
    }

    @ViewBuilder private var recentsSection: some View {
        if !places.recents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recents").scaledFont(20, .bold).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(places.recents) { r in
                        HStack(spacing: 12) {
                            Button { Task { await route(to: r) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath").scaledFont(18, .semibold)
                                        .foregroundStyle(.white).frame(width: 36, height: 36)
                                        .background(Color.tripRed(.light), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).scaledFont(16, .semibold).lineLimit(1)
                                        if !r.subtitle.isEmpty {
                                            Text(r.subtitle).scaledFont(13).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 56).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recent-row")
                            Menu {
                                Button("Add to Places", systemImage: "mappin") { places.set(.pinned, to: r) }
                                Button("Remove", systemImage: "trash", role: .destructive) { places.remove(r) }
                            } label: {
                                Image(systemName: "ellipsis").scaledFont(17, .bold).frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .accessibilityLabel("More for \(r.name)")
                            .accessibilityIdentifier("recent-more")
                        }
                        Divider().padding(.leading, 48)
                    }
                }
            }
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.destination).scaledFont(17, .bold).lineLimit(2)
                    if let via = r.via { Text("via \(via)").scaledFont(14, .medium).foregroundStyle(Color.primary.opacity(0.75)) }
                }
                Spacer()
                let saved = places.row.contains { $0.sameSpot(as: destinationPlace(r)) }
                Button {
                    if !saved { places.set(.pinned, to: destinationPlace(r)) }
                } label: {
                    Image(systemName: saved ? "mappin.circle.fill" : "mappin.and.ellipse").scaledFont(22, .semibold)
                        .foregroundStyle(Color.tripRed(.light)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(saved ? "Saved to Places" : "Add to Places")
                .accessibilityIdentifier("save-place")
            }
            if let lookAround {
                LookAroundPreview(initialScene: lookAround, allowsNavigation: true, badgePosition: .bottomTrailing)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Look Around at \(r.destination)")
                    .accessibilityIdentifier("look-around")
            }
            HStack(spacing: 10) {
                Button { closePreview() } label: {
                    Text("Cancel").scaledFont(16, .semibold).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cancel-preview")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-preview")
    }

    private func categoryList(_ c: PlaceCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: c.icon).scaledFont(15, .bold).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(c.color, in: Circle())
                Text(c.title).scaledFont(20, .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                if routing { ProgressView() }
            }
            if categoryResults.isEmpty && !routing {
                Text("Nothing found nearby").scaledFont(15, .semibold).foregroundStyle(Color.primary.opacity(0.7))
            }
            VStack(spacing: 0) {
                ForEach(categoryResults) { p in
                    Button { Task { places.addRecent(p.saved); await route(to: p.saved) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.icon).scaledFont(17, .semibold).foregroundStyle(.white)
                                .frame(width: 38, height: 38).background(c.color, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).scaledFont(16, .semibold).lineLimit(1)
                                Text(p.detail).scaledFont(13).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("category-result")
                    Divider().padding(.leading, 50)
                }
            }
        }
    }

    /// A category button: nearby results in the sheet and as pins on the map.
    private func show(_ c: PlaceCategory) async {
        guard let here = location.fix else { error = "Waiting for your location…"; return }
        category = c
        categoryResults = []
        searching = false
        withAnimation { detent = Self.half }
        routing = true
        defer { routing = false }
        let found = await NearbySearch.category(c, near: here)
        guard category == c else { return }
        categoryResults = found
        if !found.isEmpty {
            let pts = found.map(\.coordinate) + [here.coordinate]
            withAnimation {
                camera = .rect(MKPolyline(coordinates: pts, count: pts.count).boundingMapRect.insetBy(dx: -500, dy: -1800))
            }
        }
    }

    // MARK: Actions

    private func startPicking(_ kind: SavedPlace.Kind) {
        picking = kind
        query = ""
        searching = true
        withAnimation { detent = .large }
    }

    private func cancelSearch() {
        category = nil
        categoryResults = []
        query = ""
        picking = nil
        searching = false
        error = nil
        withAnimation { detent = Self.half }
    }

    private func closePreview() {
        withAnimation {
            preview = nil
            lookAround = nil
            detent = Self.half
        }
        if let c = location.fix?.coordinate { recenter(c) }
    }

    private func destinationPlace(_ r: Route) -> SavedPlace {
        SavedPlace(kind: .pinned, name: r.destination, subtitle: r.via.map { "via \($0)" } ?? "", coordinate: r.points[r.points.count - 1])
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        searching = false
        error = nil
        guard let from = location.fix?.coordinate else { error = "Waiting for your location…"; return }
        routing = true
        defer { routing = false }
        do {
            let request = MKLocalSearch.Request(completion: completion)
            request.region = MKCoordinateRegion(center: from, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
            let here = CLLocation(latitude: from.latitude, longitude: from.longitude)
            // Of the matches, take the closest one.
            let item = try await MKLocalSearch(request: request).start().mapItems
                .min { $0.location.distance(from: here) < $1.location.distance(from: here) }
            guard let item else { error = "Couldn't find that place"; return }
            let place = SavedPlace(kind: .recent, name: item.name ?? completion.title, subtitle: completion.subtitle,
                                   coordinate: item.location.coordinate)
            if let kind = picking {                // setting Home / Work, not routing
                places.set(kind, to: place)
                cancelSearch()
                return
            }
            places.addRecent(place)
            query = ""
            await route(to: place)
        } catch {
            self.error = "Couldn't find that place: \(error.localizedDescription)"
        }
    }

    private func route(to place: SavedPlace) async {
        error = nil
        guard let from = location.fix?.coordinate else { error = "Waiting for your location…"; return }
        routing = true
        defer { routing = false }
        do {
            let name = place.kind == .home ? "Home" : place.kind == .work ? "Work" : place.name
            let route = try await Router.drive(from: from, to: place.coordinate, name: name)
            // Warm the speed-limit cache while the rider looks at the preview.
            Task.detached(priority: .utility) { _ = await SpeedLimits.lookup(route) }
            lookAround = nil
            category = nil
            withAnimation {
                preview = route
                detent = Self.half
                camera = .rect(MKPolyline(coordinates: route.points, count: route.points.count).boundingMapRect
                    .insetBy(dx: -800, dy: -2400))
            }
            lookAround = try? await MKLookAroundSceneRequest(coordinate: place.coordinate).scene
        } catch {
            self.error = "Couldn't get a route: \(error.localizedDescription)"
        }
    }

    // MARK: Drive times

    /// Re-ask when the places change or the rider moves ~1 km.
    private var etaKey: String {
        let here = location.fix.map { "\(($0.coordinate.latitude * 100).rounded()),\(($0.coordinate.longitude * 100).rounded())" } ?? "-"
        return here + places.row.map(\.id.uuidString).joined()
    }

    private func loadETAs() async {
        guard let from = location.fix?.coordinate else { return }
        for p in places.row.prefix(8) where etas[p.id] == nil {
            if let m = await PlaceETA.minutes(from: from, to: p.coordinate) { etas[p.id] = m }
        }
    }

    private func distanceText(to p: SavedPlace) -> String {
        guard let fix = location.fix else { return p.subtitle }
        return walkDistance(fix.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)))
    }

    private func icon(for p: SavedPlace) -> String {
        p.kind == .home ? "house.fill" : p.kind == .work ? "briefcase.fill" : "mappin"
    }

    private func tint(for p: SavedPlace) -> Color { tint(forKind: p.kind) }

    private func tint(forKind k: SavedPlace.Kind) -> Color {
        switch k {
        case .home: Color(red: 0.13, green: 0.45, blue: 0.92)
        case .work: Color(red: 0.55, green: 0.36, blue: 0.20)
        default: Color.tripRed(.light)
        }
    }
}

/// Map Modes: Explore, Driving (traffic always on), Satellite, and a Traffic switch.
struct MapModesSheet: View {
    @Binding var mode: String
    @Binding var traffic: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Map Modes").scaledFont(22, .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").scaledFont(15, .bold).frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("close-map-modes")
            }
            HStack(spacing: 12) {
                ForEach(MapMode.allCases) { m in
                    let on = mode == m.rawValue
                    Button { mode = m.rawValue } label: {
                        VStack(spacing: 8) {
                            Image(systemName: m.icon).scaledFont(26, .semibold)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 74)
                                .background(on ? Color.tripRed(.light) : Color.primary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(m.title).scaledFont(14, .semibold)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("map-mode-\(m.rawValue)")
                }
            }
            Toggle("Traffic", isOn: Binding(get: { traffic || mode == MapMode.driving.rawValue }, set: { traffic = $0 }))
                .scaledFont(17, .semibold)
                .tint(Color.tripRed(.light))
                .disabled(mode == MapMode.driving.rawValue)
                .accessibilityIdentifier("traffic-toggle")
            Spacer(minLength: 0)
        }
        .padding(22)
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
        completer.regionPriority = .required
    }

    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = c.results
        Task { @MainActor in results = r }
    }

    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
