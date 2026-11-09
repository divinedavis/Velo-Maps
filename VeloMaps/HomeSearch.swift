import SwiftUI
import MapKit

/// What the search sheet shows before you type (owner, 11/9, from Apple Maps): category
/// buttons, Recents (with the full This Week / This Month list), Suggested Places nearby and a
/// "Restaurants Nearby" carousel with Look Around imagery. Ratings, opening hours, "Trending"
/// and Guides are Apple-only content with no public API, so they are left out.

/// A driver's quick searches.
enum PlaceCategory: String, CaseIterable, Identifiable {
    case gas, ev, parking, coffee, fastFood, restaurants, groceries, hotels
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gas: "Gas"; case .ev: "EV Charging"; case .parking: "Parking"; case .coffee: "Coffee"
        case .fastFood: "Fast Food"; case .restaurants: "Restaurants"; case .groceries: "Groceries"; case .hotels: "Hotels"
        }
    }
    var icon: String {
        switch self {
        case .gas: "fuelpump.fill"; case .ev: "bolt.car.fill"; case .parking: "parkingsign"; case .coffee: "cup.and.saucer.fill"
        case .fastFood: "takeoutbag.and.cup.and.straw.fill"; case .restaurants: "fork.knife"; case .groceries: "cart.fill"
        case .hotels: "bed.double.fill"
        }
    }
    var color: Color {
        switch self {
        case .gas: Color(red: 0.85, green: 0.38, blue: 0.0); case .ev: Color(red: 0.10, green: 0.55, blue: 0.25)
        case .parking: Color(red: 0.13, green: 0.40, blue: 0.85); case .coffee: Color(red: 0.50, green: 0.32, blue: 0.18)
        case .fastFood: Color(red: 0.80, green: 0.20, blue: 0.10); case .restaurants: Color(red: 0.85, green: 0.35, blue: 0.10)
        case .groceries: Color(red: 0.15, green: 0.50, blue: 0.30); case .hotels: Color(red: 0.45, green: 0.30, blue: 0.75)
        }
    }
    var query: String {
        switch self {
        case .gas: "gas station"; case .ev: "EV charging"; case .parking: "parking"; case .coffee: "coffee"
        case .fastFood: "fast food"; case .restaurants: "restaurants"; case .groceries: "grocery store"; case .hotels: "hotel"
        }
    }
    var poi: [MKPointOfInterestCategory] {
        switch self {
        case .gas: [.gasStation]; case .ev: [.evCharger]; case .parking: [.parking]; case .coffee: [.cafe, .bakery]
        case .fastFood, .restaurants: [.restaurant]; case .groceries: [.foodMarket]; case .hotels: [.hotel]
        }
    }
}

/// A nearby place from Apple's search, with its distance from the rider.
struct NearbyPlace: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let category: MKPointOfInterestCategory?
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance

    static func == (a: NearbyPlace, b: NearbyPlace) -> Bool { a.id == b.id }

    var kindText: String { NearbySearch.title(for: category) }
    var detail: String { "\(kindText) · \(walkDistance(distance))" }
    var icon: String { NearbySearch.icon(for: category) }
    var saved: SavedPlace { SavedPlace(kind: .recent, name: name, subtitle: kindText, coordinate: coordinate) }
}

/// Apple MapKit searches near the rider (free; bounded: one per category tap, two per opening
/// of the search screen, and Look Around images for at most 6 cards, kept in memory only —
/// Apple's terms don't allow storing Look Around imagery).
enum NearbySearch {
    static func category(_ c: PlaceCategory, near here: CLLocation) async -> [NearbyPlace] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = c.query
        req.resultTypes = .pointOfInterest
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: c.poi)
        req.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 6_000, longitudinalMeters: 6_000)
        guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return [] }
        return places(items, from: here, limit: 15)
    }

    static func around(_ here: CLLocation, radius: CLLocationDistance, including: [MKPointOfInterestCategory], limit: Int) async -> [NearbyPlace] {
        let req = MKLocalPointsOfInterestRequest(center: here.coordinate, radius: radius)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: including)
        guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return [] }
        return places(items, from: here, limit: limit)
    }

    static func places(_ items: [MKMapItem], from here: CLLocation, limit: Int) -> [NearbyPlace] {
        items.compactMap { i -> NearbyPlace? in
            guard let name = i.name else { return nil }
            return NearbyPlace(name: name, category: i.pointOfInterestCategory, coordinate: i.location.coordinate,
                               distance: i.location.distance(from: here))
        }
        .sorted { $0.distance < $1.distance }
        .prefix(limit).map { $0 }
    }

    static func lookAround(at c: CLLocationCoordinate2D) async -> UIImage? {
        guard let scene = try? await MKLookAroundSceneRequest(coordinate: c).scene else { return nil }
        let opts = MKLookAroundSnapshotter.Options()
        opts.size = CGSize(width: 320, height: 220)
        return try? await MKLookAroundSnapshotter(scene: scene, options: opts).snapshot.image
    }

    static func title(for c: MKPointOfInterestCategory?) -> String {
        switch c {
        case .restaurant?: "Restaurant"; case .cafe?: "Cafe"; case .bakery?: "Bakery"; case .gasStation?: "Gas Station"
        case .evCharger?: "EV Charger"; case .parking?: "Parking"; case .foodMarket?: "Grocery"; case .hotel?: "Hotel"
        case .park?: "Park"; case .museum?: "Museum"; case .theater?: "Theater"; case .store?: "Store"
        case .pharmacy?: "Pharmacy"; case .nightlife?: "Nightlife"; case .publicTransport?: "Transit"
        default: "Place"
        }
    }

    static func icon(for c: MKPointOfInterestCategory?) -> String {
        switch c {
        case .restaurant?: "fork.knife"; case .cafe?, .bakery?: "cup.and.saucer.fill"; case .gasStation?: "fuelpump.fill"
        case .evCharger?: "bolt.car.fill"; case .parking?: "parkingsign"; case .foodMarket?: "cart.fill"; case .hotel?: "bed.double.fill"
        case .park?: "tree.fill"; case .museum?: "building.columns.fill"; case .theater?: "theatermasks.fill"; case .store?: "bag.fill"
        default: "mappin"
        }
    }
}

/// The search screen before you type.
struct SearchHomeView: View {
    @ObservedObject var places: PlacesStore
    let here: CLLocation?
    let onCategory: (PlaceCategory) -> Void
    let onPlace: (SavedPlace) -> Void
    let onAllRecents: () -> Void
    @State private var suggested: [NearbyPlace] = []
    @State private var food: [NearbyPlace] = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var loadedAt: CLLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            categories
            if !places.recents.isEmpty { recents }
            if !suggested.isEmpty { suggestedSection }
            if !food.isEmpty { foodCarousel }
        }
        .task(id: here.map { "\(($0.coordinate.latitude * 200).rounded()),\(($0.coordinate.longitude * 200).rounded())" }) { await load() }
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlaceCategory.allCases) { c in
                    Button { onCategory(c) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.icon).scaledFont(13, .bold).foregroundStyle(.white)
                                .frame(width: 26, height: 26).background(c.color, in: Circle())
                            Text(c.title).scaledFont(15, .semibold)
                        }
                        .padding(.leading, 6).padding(.trailing, 14)
                        .frame(minHeight: 44)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("category-\(c.rawValue)")
                }
            }
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onAllRecents) {
                HStack(spacing: 4) {
                    Text("Recents").scaledFont(20, .bold)
                    Image(systemName: "chevron.right").scaledFont(15, .bold).foregroundStyle(Color.primary.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All recents")
            .accessibilityIdentifier("recents-all")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(48)), GridItem(.fixed(48))], spacing: 14) {
                    ForEach(places.recents.prefix(8)) { r in
                        Button { onPlace(r) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").scaledFont(15, .semibold).foregroundStyle(Color.primary.opacity(0.7))
                                Text(r.name).scaledFont(15, .semibold).lineLimit(1)
                                if !r.subtitle.isEmpty {
                                    Text(r.subtitle).scaledFont(13).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                                }
                            }
                            .frame(width: 250, alignment: .leading)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recent-search")
                    }
                }
            }
        }
    }

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested Places").scaledFont(20, .bold).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(suggested) { p in
                    Button { onPlace(p.saved) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.icon).scaledFont(18, .semibold).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(Color.tripRed(.light), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).scaledFont(16, .semibold).lineLimit(1)
                                Text(p.detail).scaledFont(13).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("suggested-place")
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    private var foodCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Restaurants Nearby").scaledFont(20, .bold).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(food.enumerated()), id: \.element.id) { i, p in
                        Button { onPlace(p.saved) } label: { card(p, rank: i + 1) }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(p.name), \(p.detail)")
                            .accessibilityIdentifier("nearby-card")
                    }
                }
            }
        }
    }

    private func card(_ p: NearbyPlace, rank: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = images[p.id] {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.93, green: 0.26, blue: 0.29), Color(red: 0.60, green: 0.04, blue: 0.09)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: p.icon).font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.55)))
                }
            }
            .frame(width: 210, height: 230)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).scaledFont(16, .bold).lineLimit(2)
                Text(p.detail).scaledFont(13, .medium).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(12)
            Text("\(rank)").scaledFont(30, .heavy, .rounded).foregroundStyle(.white)
                .shadow(radius: 4)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 210, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load() async {
        guard let here else { return }
        if let loadedAt, loadedAt.distance(from: here) < 300, !suggested.isEmpty { return }
        loadedAt = here
        async let s = NearbySearch.around(here, radius: 700, including: [.park, .museum, .theater, .cafe, .bakery, .foodMarket, .store, .gasStation, .parking], limit: 4)
        async let f = NearbySearch.around(here, radius: 1_500, including: [.restaurant], limit: 6)
        suggested = await s
        food = await f
        for p in food where images[p.id] == nil {
            if let img = await NearbySearch.lookAround(at: p.coordinate) { images[p.id] = img }
        }
    }
}

/// Every recent search, grouped by when, with Clear per group and a menu per row.
struct RecentsListView: View {
    @ObservedObject var places: PlacesStore
    let onPlace: (SavedPlace) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recents").scaledFont(28, .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").scaledFont(15, .bold).frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("close-recents")
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(PlacesStore.groups(places.recents), id: \.title) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(g.title).scaledFont(15, .semibold).foregroundStyle(Color.primary.opacity(0.7))
                                Spacer()
                                Button("Clear") { places.clearRecents(g.places.map(\.id)) }
                                    .scaledFont(15, .semibold)
                                    .foregroundStyle(Color.tripRed(.light))
                                    .accessibilityLabel("Clear \(g.title)")
                                    .accessibilityIdentifier("clear-recents")
                            }
                            ForEach(g.places) { r in
                                HStack(spacing: 12) {
                                    Button { dismiss(); onPlace(r) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock.arrow.circlepath").scaledFont(16, .semibold).foregroundStyle(.white)
                                                .frame(width: 34, height: 34).background(Color.tripRed(.light), in: Circle())
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
                                    .accessibilityIdentifier("recents-list-row")
                                    Menu {
                                        Button("Add to Places", systemImage: "mappin") { places.set(.pinned, to: r) }
                                        Button("Remove", systemImage: "trash", role: .destructive) { places.remove(r) }
                                    } label: {
                                        Image(systemName: "ellipsis").scaledFont(17, .bold).frame(width: 44, height: 44).contentShape(Rectangle())
                                    }
                                    .foregroundStyle(Color.primary.opacity(0.7))
                                    .accessibilityLabel("More for \(r.name)")
                                }
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    if places.recents.isEmpty {
                        Text("No recent searches").scaledFont(16, .semibold).foregroundStyle(Color.primary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
    }
}
