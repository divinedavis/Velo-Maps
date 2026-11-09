import Testing
import Foundation
import CoreLocation
@testable import VeloMaps

/// Home's Apple Maps-style sheet: Home/Work, saved places and recents (owner, 11/9).
@Suite("Places")
@MainActor
struct PlacesTests {
    private func store() -> (PlacesStore, UserDefaults) {
        let d = UserDefaults(suiteName: "velo-places-\(UUID())")!
        return (PlacesStore(defaults: d), d)
    }
    private func place(_ name: String, _ lat: Double = 40.78, _ lon: Double = -73.97) -> SavedPlace {
        SavedPlace(kind: .recent, name: name, subtitle: "NY", coordinate: .init(latitude: lat, longitude: lon))
    }

    @Test func homeWorkAndSavedPlacesPersist() {
        let (s, d) = store()
        s.set(.home, to: place("2537 Broadway"))
        s.set(.work, to: place("Columbus Circle", 40.768, -73.982))
        s.set(.pinned, to: place("Lincoln Center", 40.772, -73.983))
        s.set(.pinned, to: place("Lincoln Center", 40.772, -73.983))        // same spot: once
        #expect(s.row.map(\.kind) == [.home, .work, .pinned])
        let again = PlacesStore(defaults: d)
        #expect(again.home?.name == "2537 Broadway" && again.home?.kind == .home)
        #expect(again.pinned.map(\.name) == ["Lincoln Center"])
        again.remove(again.home!)
        #expect(PlacesStore(defaults: d).home == nil)
    }

    @Test func recentsAreNewestFirstWithoutDuplicatesAndCapped() {
        let (s, _) = store()
        s.addRecent(place("Zabar's"))
        s.addRecent(place("Symphony Space", 40.7937, -73.972))
        s.addRecent(place("Zabar's"))
        #expect(s.recents.map(\.name) == ["Zabar's", "Symphony Space"])
        for i in 0..<20 { s.addRecent(place("Spot \(i)", 40.7 + Double(i) * 0.01)) }
        #expect(s.recents.count == PlacesStore.maxRecents)
        #expect(s.recents.first?.name == "Spot 19")
        s.remove(s.recents[0])
        #expect(s.recents.first?.name == "Spot 18")
    }

    @Test func driveTimeText() {
        #expect(PlaceETA.text(9) == "9 min")
        #expect(PlaceETA.text(65) == "1 hr 5 min")
    }

    @Test func demoPlacesFillTheSheet() {
        let d = UserDefaults(suiteName: "velo-places-\(UUID())")!
        d.set(true, forKey: "demoPlaces")
        let s = PlacesStore(defaults: d)
        #expect(s.home != nil && s.work != nil && !s.recents.isEmpty)
    }
}

@Suite("Recents list")
@MainActor
struct RecentsGroupTests {
    @Test func groupsByWeekMonthAndEarlierAndClearsAGroup() {
        let now = Date()
        func r(_ name: String, daysAgo: Double) -> SavedPlace {
            SavedPlace(kind: .recent, name: name, coordinate: .init(latitude: 40.78, longitude: -73.97), date: now.addingTimeInterval(-daysAgo * 86_400))
        }
        let list = [r("A", daysAgo: 1), r("B", daysAgo: 10), r("C", daysAgo: 40), r("D", daysAgo: 3)]
        let g = PlacesStore.groups(list, now: now)
        #expect(g.map(\.title) == ["This Week", "This Month", "Earlier"])
        #expect(g[0].places.map(\.name) == ["A", "D"])
        #expect(PlacesStore.groups([r("A", daysAgo: 1)], now: now).map(\.title) == ["This Week"], "empty groups are dropped")

        let s = PlacesStore(defaults: UserDefaults(suiteName: "velo-places-\(UUID())")!)
        s.addRecent(SavedPlace(kind: .recent, name: "Zabar's", coordinate: .init(latitude: 40.7848, longitude: -73.98)))
        #expect(s.recents.first?.date != nil, "recents are dated")
        s.clearRecents(s.recents.map(\.id))
        #expect(s.recents.isEmpty)
    }
}
