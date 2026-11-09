import Foundation
import CoreLocation
import UIKit

/// The phone's real position for live navigation. Best-for-navigation accuracy only while a
/// trip is running; keeps updating with the screen locked (background location + audio).
/// `-mockLocation lat,lon` (UI tests, previews) publishes a fixed fix and never prompts.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var fix: CLLocation?
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    private let manager = CLLocationManager()
    private let mock: CLLocation?

    override init() {
        if let s = UserDefaults.standard.string(forKey: "mockLocation") {
            let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            mock = p.count == 2 ? CLLocation(latitude: p[0], longitude: p[1]) : nil
        } else {
            mock = nil
        }
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func start() {
        if let mock { fix = mock; authorized = true; return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: authorized = true; manager.startUpdatingLocation()
        }
    }

    /// Navigating: best accuracy, keep going in the background, keep the screen on.
    func setNavigating(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
        guard mock == nil else { return }
        manager.desiredAccuracy = on ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyNearestTenMeters
        manager.allowsBackgroundLocationUpdates = on
        manager.showsBackgroundLocationIndicator = on
        manager.pausesLocationUpdatesAutomatically = !on
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor in
            guard mock == nil else { return }       // -mockLocation: never show "Turn on Location"
            authorized = status == .authorizedWhenInUse || status == .authorizedAlways
            denied = status == .denied || status == .restricted
            if authorized { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in fix = last }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
