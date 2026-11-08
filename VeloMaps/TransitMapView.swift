import SwiftUI
import MapKit

/// MKMapView in Apple's realistic-elevation (3D city) mode, with a chase camera locked behind
/// the bus. UIKit rather than SwiftUI's Map because the camera is set every frame.
struct TransitMapView: UIViewRepresentable {
    @ObservedObject var trip: Trip
    /// Screen y of the card's top edge; the camera keeps the bus a fixed gap above it.
    var cardTop: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(trip: trip) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config
        map.overrideUserInterfaceStyle = trip.night ? .dark : .light
        map.showsCompass = false
        map.showsScale = false
        map.isUserInteractionEnabled = false   // camera is driven by the trip
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "transit-map"
        context.coordinator.attach(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.cardTop = cardTop
        context.coordinator.syncRoute()
        context.coordinator.syncPotholes()
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        let trip: Trip
        weak var map: MKMapView?
        var cardTop: CGFloat = 0
        /// Metres ahead of the bus the camera aims. Starts from the launch setting, then is
        /// nudged every frame until the bus sits `trip.busGap` points above the card.
        private lazy var leadMetres: Double = trip.cameraDistance * trip.cameraLead
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
            map.view(for: bus)?.image = BusAnnotation.image(for: trip.route.kind)   // bus or car
            cameraHeading = nil   // new route: start facing its first heading
        }

        private var shownPotholes: Set<UUID> = []

        /// Adds a warning sign for every reported pothole not yet on the map.
        func syncPotholes() {
            guard let map else { return }
            let new = trip.potholes.filter { !shownPotholes.contains($0.id) }
            guard !new.isEmpty else { return }
            map.addAnnotations(new.map { PotholeAnnotation(pothole: $0) })
            new.forEach { shownPotholes.insert($0.id) }
        }

        /// Frames in a row where the bus already sat where it should; once settled while
        /// paused, the camera stops being re-set so the map (and the glass over it) can idle.
        private var settledFrames = 0
        private var lastCardTop: CGFloat = -1

        @objc private func tick(_ link: CADisplayLink) {
            let dt = lastTick == 0 ? 0 : min(link.timestamp - lastTick, 0.1)
            lastTick = link.timestamp
            if cardTop != lastCardTop { settledFrames = 0; lastCardTop = cardTop }
            if trip.paused && settledFrames > 30 { return }   // nothing moving: let the map idle
            trip.advance(by: dt)
            placeCamera(dt: dt)
        }

        /// Camera heading, eased toward the vehicle's heading over time (not snapped to it).
        private var cameraHeading: CLLocationDirection?
        private weak var vehicleView: MKAnnotationView?

        /// Chase camera like Apple Maps: the vehicle drives the rounded line and its icon turns
        /// with it; the camera eases its heading toward the vehicle's (≈0.45 s time constant),
        /// and is centred on the vehicle, offset along the *camera* heading — following the
        /// line instead cut corners and swung the view (owner, 11/8: "the navigation skips").
        private func placeCamera(dt: TimeInterval = 0) {
            guard let map else { return }
            let d = trip.distance
            let (coord, _) = trip.route.position(at: d)
            bus.coordinate = coord
            let travel = trip.route.vehicleHeading(at: d)
            var heading = cameraHeading ?? travel
            let delta = Self.shortestTurn(from: heading, to: travel)
            heading = Self.normalised(heading + delta * (1 - exp(-dt / 0.45)))
            cameraHeading = heading
            let center = coord.offset(by: leadMetres, bearing: heading)
            map.setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: trip.cameraDistance,
                                      pitch: trip.cameraPitch, heading: heading), animated: false)
            // Screen-up is the camera heading; turn the icon by the difference.
            let iconTurn = Self.shortestTurn(from: heading, to: travel) * .pi / 180
            vehicleView?.transform = CGAffineTransform(rotationAngle: iconTurn)
            keepBusAboveCard(coord, in: map)
            if abs(delta) > 0.3 { settledFrames = 0 }
        }

        nonisolated static func shortestTurn(from a: CLLocationDirection, to b: CLLocationDirection) -> Double {
            var d = (b - a).truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            return d
        }

        nonisolated static func normalised(_ h: Double) -> Double {
            let r = h.truncatingRemainder(dividingBy: 360)
            return r < 0 ? r + 360 : r
        }

        /// Measures where the bus landed on screen and moves the aim point so its centre sits
        /// `busGap` points above the card. Bus too high → aim further ahead (bus moves down).
        private func keepBusAboveCard(_ coord: CLLocationCoordinate2D, in map: MKMapView) {
            guard cardTop > 0 else { return }
            let y = map.convert(coord, toPointTo: map).y
            guard y.isFinite else { return }
            let error = Double((cardTop - trip.busGap) - y)
            leadMetres = min(max(leadMetres + error * 0.12, -250), 250)
            settledFrames = abs(error) < 0.5 ? settledFrames + 1 : 0
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
            if annotation is PotholeAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pothole")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "pothole")
                v.annotation = annotation
                v.image = PotholeAnnotation.sign
                v.centerOffset = CGPoint(x: 0, y: -PotholeAnnotation.sign.size.height / 2)  // sign stands on the spot
                v.zPriority = .defaultSelected
                v.collisionMode = .none
                v.accessibilityLabel = "Pothole"
                return v
            }
            guard annotation is BusAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "bus")
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "bus")
            v.annotation = annotation
            v.image = BusAnnotation.image(for: trip.route.kind)
            v.zPriority = .max
            vehicleView = v
            v.collisionMode = .none
            return v
        }
    }
}

final class RouteGlow: MKPolyline {}

final class BusAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()

    static func image(for kind: RouteKind) -> UIImage { kind == .drive ? car : image }

    /// White car seen from above: dark windscreen and rear window, front = screen-up.
    static let car: UIImage = {
        let size = CGSize(width: 26, height: 44)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 2, height: 3), blur: 4, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 20, height: 40), cornerRadius: 8).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(white: 0.7, alpha: 1).setStroke()
            let body = UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 20, height: 40), cornerRadius: 8)
            body.lineWidth = 1; body.stroke()
            UIColor(white: 0.2, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 6, y: 9, width: 14, height: 7), cornerRadius: 3).fill()   // windscreen
            UIBezierPath(roundedRect: CGRect(x: 7, y: 31, width: 12, height: 5), cornerRadius: 2).fill()  // rear window
            UIColor(red: 0.84, green: 0.07, blue: 0.13, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 7, y: 18, width: 12, height: 11), cornerRadius: 2).fill() // red roof
        }
    }()

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

/// A reported pothole on the map, drawn as a yellow warning sign on a short post.
final class PotholeAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(pothole: Pothole) { coordinate = pothole.coordinate }

    static let sign: UIImage = {
        let size = CGSize(width: 34, height: 42)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            // post
            UIColor(white: 0.35, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 15.5, y: 26, width: 3, height: 14), cornerRadius: 1.5).fill()
            // triangle with rounded corners, dark border
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: 17, y: 2))
            tri.addLine(to: CGPoint(x: 32, y: 28))
            tri.addLine(to: CGPoint(x: 2, y: 28))
            tri.close()
            tri.lineJoinStyle = .round
            tri.lineWidth = 3.5
            UIColor(red: 0.99, green: 0.80, blue: 0.10, alpha: 1).setFill()
            tri.fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(white: 0.1, alpha: 1).setStroke()
            tri.stroke()
            // pothole glyph: dark ellipse with a crack
            UIColor(white: 0.12, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 10.5, y: 17, width: 13, height: 6)).fill()
            let crack = UIBezierPath()
            crack.move(to: CGPoint(x: 17, y: 10)); crack.addLine(to: CGPoint(x: 15.5, y: 13))
            crack.addLine(to: CGPoint(x: 18, y: 15)); crack.addLine(to: CGPoint(x: 16.5, y: 17.5))
            crack.lineWidth = 1.6
            UIColor(white: 0.12, alpha: 1).setStroke()
            crack.stroke()
        }
    }()
}
