import Foundation
import CoreLocation
import MapKit

/// A place on Home's sheet: Home, Work, a saved place, or a recent search (owner, 11/9: search
/// on the bottom "like Apple Maps, with the same functionality").
struct SavedPlace: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case home, work, pinned, recent }
    var id = UUID()
    var kind: Kind
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    /// When it was last searched (recents; nil for older saved data).
    var date: Date?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(kind: Kind, name: String, subtitle: String = "", coordinate: CLLocationCoordinate2D, date: Date? = nil) {
        self.date = date
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    /// Same spot (within ~30 m) and name, whatever the kind.
    func sameSpot(as other: SavedPlace) -> Bool {
        name == other.name && CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude)) < 30
    }
}

/// Home, Work, saved places and recent searches, kept on the phone (UserDefaults, JSON).
/// Nothing leaves the device.
@MainActor
final class PlacesStore: ObservableObject {
    static let key = "places.v1"
    static let maxRecents = 12
    static let maxPinned = 20

    @Published private(set) var home: SavedPlace?
    @Published private(set) var work: SavedPlace?
    @Published private(set) var pinned: [SavedPlace] = []
    @Published private(set) var recents: [SavedPlace] = []
    private let defaults: UserDefaults

    private struct Stored: Codable {
        var home: SavedPlace?
        var work: SavedPlace?
        var pinned: [SavedPlace]
        var recents: [SavedPlace]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: "demoPlaces") { seedDemo(); return }
        guard let data = defaults.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        home = s.home
        work = s.work
        pinned = s.pinned
        recents = s.recents
    }

    /// Home's Places row: Home, Work, then saved places.
    var row: [SavedPlace] { [home, work].compactMap { $0 } + pinned }

    func set(_ kind: SavedPlace.Kind, to place: SavedPlace) {
        var p = place
        p.kind = kind
        switch kind {
        case .home: home = p
        case .work: work = p
        case .pinned:
            guard !pinned.contains(where: { $0.sameSpot(as: p) }) else { return }
            pinned = Array((pinned + [p]).suffix(Self.maxPinned))
        case .recent: addRecent(p); return
        }
        save()
    }

    func remove(_ place: SavedPlace) {
        switch place.kind {
        case .home: home = nil
        case .work: work = nil
        case .pinned: pinned.removeAll { $0.id == place.id }
        case .recent: recents.removeAll { $0.id == place.id }
        }
        save()
    }

    /// A place the rider searched for and routed to: newest first, no duplicates.
    func addRecent(_ place: SavedPlace) {
        var p = place
        p.kind = .recent
        p.date = Date()
        recents.removeAll { $0.sameSpot(as: p) }
        recents.insert(p, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        save()
    }

    func clearRecents(_ ids: [UUID]) {
        recents.removeAll { ids.contains($0.id) }
        save()
    }

    /// The full Recents list: This Week, This Month, Earlier (empty groups dropped).
    static func groups(_ recents: [SavedPlace], now: Date = Date()) -> [(title: String, places: [SavedPlace])] {
        let week = now.addingTimeInterval(-7 * 86_400), month = now.addingTimeInterval(-30 * 86_400)
        let groups: [(String, [SavedPlace])] = [
            ("This Week", recents.filter { ($0.date ?? .distantPast) >= week }),
            ("This Month", recents.filter { let d = $0.date ?? .distantPast; return d < week && d >= month }),
            ("Earlier", recents.filter { ($0.date ?? .distantPast) < month }),
        ]
        return groups.filter { !$0.1.isEmpty }.map { (title: $0.0, places: $0.1) }
    }

    func clear() {
        home = nil; work = nil; pinned = []; recents = []
        defaults.removeObject(forKey: Self.key)
    }

    private func save() {
        let s = Stored(home: home, work: work, pinned: pinned, recents: recents)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: Self.key) }
    }

    /// `-demoPlaces YES` (screenshots, UI tests): a filled-in sheet on the Upper West Side.
    private func seedDemo() {
        home = SavedPlace(kind: .home, name: "Home", subtitle: "W 89th St", coordinate: .init(latitude: 40.7895, longitude: -73.9745))
        work = SavedPlace(kind: .work, name: "Work", subtitle: "Columbus Circle", coordinate: .init(latitude: 40.7681, longitude: -73.9819))
        pinned = [SavedPlace(kind: .pinned, name: "Lincoln Center", subtitle: "Broadway", coordinate: .init(latitude: 40.7725, longitude: -73.9835))]
        recents = [
            SavedPlace(kind: .recent, name: "Symphony Space", subtitle: "2537 Broadway, New York", coordinate: .init(latitude: 40.7937, longitude: -73.9720), date: Date()),
            SavedPlace(kind: .recent, name: "Zabar's", subtitle: "2245 Broadway, New York", coordinate: .init(latitude: 40.7848, longitude: -73.9800), date: Date().addingTimeInterval(-2 * 86_400)),
            SavedPlace(kind: .recent, name: "Central Park Zoo", subtitle: "East 64th Street, New York", coordinate: .init(latitude: 40.7678, longitude: -73.9718), date: Date().addingTimeInterval(-12 * 86_400)),
        ]
    }
}

/// Drive time to a place from here, from Apple (free ETA endpoint, traffic-aware). One request
/// per place when the sheet's places or the rider's rough position change.
enum PlaceETA {
    static func minutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Int? {
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        req.transportType = .automobile
        guard let eta = try? await MKDirections(request: req).calculateETA() else { return nil }
        return max(1, Int((eta.expectedTravelTime / 60).rounded()))
    }

    static func text(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}

/// Home map look (Map Modes sheet). Driving always shows traffic.
enum MapMode: String, CaseIterable, Identifiable {
    case explore, driving, satellite
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self { case .explore: "map.fill"; case .driving: "car.fill"; case .satellite: "globe.americas.fill" }
    }
}
