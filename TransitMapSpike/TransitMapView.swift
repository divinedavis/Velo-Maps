import SwiftUI
import MapKit

/// MKMapView in Apple's realistic-elevation (3D city) mode, with a chase camera locked behind
/// the bus. UIKit rather than SwiftUI's Map because the camera is set every frame.
struct TransitMapView: UIViewRepresentable {
    @ObservedObject var trip: Trip
    /// Height of the card covering the bottom of the map, so the bus sits in the visible part.
    var bottomInset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(trip: trip) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config
        map.showsCompass = false
        map.showsScale = false
        map.isUserInteractionEnabled = false   // camera is driven by the trip
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "transit-map"
        context.coordinator.attach(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.bottomInset = bottomInset
        context.coordinator.syncRoute()
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        let trip: Trip
        weak var map: MKMapView?
        var bottomInset: CGFloat = 0
        private var link: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        private let bus = BusAnnotation()
        private var drawnRouteLength: Double = -1

        init(trip: Trip) { self.trip = trip }

        func attach(_ map: MKMapView) {
            self.map = map
            map.addAnnotation(bus)
            syncRoute()
            placeCamera()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// Redraw the route overlays when the geometry changes (straight → road-snapped).
        func syncRoute() {
            guard let map, trip.route.length != drawnRouteLength else { return }
            drawnRouteLength = trip.route.length
            map.removeOverlays(map.overlays)
            let pts = trip.route.points
            let glow = RouteGlow(coordinates: pts, count: pts.count)
            let core = MKPolyline(coordinates: pts, count: pts.count)
            map.addOverlay(glow, level: .aboveRoads)
            map.addOverlay(core, level: .aboveRoads)
        }

        @objc private func tick(_ link: CADisplayLink) {
            let dt = lastTick == 0 ? 0 : min(link.timestamp - lastTick, 0.1)
            lastTick = link.timestamp
            trip.advance(by: dt)
            placeCamera()
        }

        private func placeCamera() {
            guard let map else { return }
            let (coord, _) = trip.route.position(at: trip.distance)
            bus.coordinate = coord
            let heading = trip.route.smoothedHeading(at: trip.distance)
            // Aim the camera a little ahead of the bus so the bus lands just above the card,
            // as in the reference video.
            let lead = trip.cameraDistance * trip.cameraLead
            let (ahead, _) = trip.route.position(at: trip.distance + lead)
            let camera = MKMapCamera(lookingAtCenter: ahead,
                                     fromDistance: trip.cameraDistance,
                                     pitch: trip.cameraPitch,
                                     heading: heading)
            map.setCamera(camera, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.lineCap = .round
            r.lineJoin = .round
            if overlay is RouteGlow {
                r.strokeColor = UIColor(red: 0.93, green: 0.23, blue: 0.27, alpha: 0.28)
                r.lineWidth = 26
            } else {
                r.strokeColor = UIColor(red: 0.89, green: 0.11, blue: 0.17, alpha: 0.92)
                r.lineWidth = 14
            }
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is BusAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "bus")
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "bus")
            v.annotation = annotation
            v.image = BusAnnotation.image
            v.zPriority = .max
            v.collisionMode = .none
            return v
        }
    }
}

final class RouteGlow: MKPolyline {}

final class BusAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()

    /// White bus seen from above and behind, like the vehicle in the reference: roof with an
    /// AC unit, dark windscreen at the front (screen-up = direction of travel, since the camera
    /// heading follows the bus), and the rear face with a green livery stripe at the bottom.
    static let image: UIImage = {
        let size = CGSize(width: 30, height: 60)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            // soft ground shadow
            cg.setShadow(offset: CGSize(width: 2, height: 3), blur: 4, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 24, height: 54), cornerRadius: 6).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            // body outline
            UIColor(white: 0.7, alpha: 1).setStroke()
            let outline = UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 24, height: 54), cornerRadius: 6)
            outline.lineWidth = 1
            outline.stroke()
            // front windscreen
            UIColor(white: 0.22, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 6, y: 4, width: 18, height: 6), cornerRadius: 2.5).fill()
            // roof AC unit
            UIColor(white: 0.84, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 8, y: 16, width: 14, height: 14), cornerRadius: 2).fill()
            // rear face: dark window band + green livery stripe
            UIColor(white: 0.2, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 5, y: 40, width: 20, height: 7), cornerRadius: 2).fill()
            UIColor(red: 0.18, green: 0.62, blue: 0.27, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 5, y: 48.5, width: 20, height: 3.5), cornerRadius: 1.5).fill()
        }
    }()
}
