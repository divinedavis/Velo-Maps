import SwiftUI
import MapKit

/// The walking leg on the same 3D map: dotted path, walker marker, destination pin, and a
/// chase camera that follows the walker.
struct WalkMapView: UIViewRepresentable {
    @ObservedObject var walk: Walk
    let night: Bool

    func makeCoordinator() -> Coordinator { Coordinator(walk: walk) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.overrideUserInterfaceStyle = night ? .dark : .light
        map.showsCompass = false
        map.showsScale = false
        map.isUserInteractionEnabled = false
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "walk-map"
        context.coordinator.attach(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.syncPath() }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        let walk: Walk
        weak var map: MKMapView?
        private var link: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        private let walker = WalkerAnnotation()
        private let pin = MKPointAnnotation()
        private var drawn = false

        init(walk: Walk) { self.walk = walk }

        func attach(_ map: MKMapView) {
            self.map = map
            pin.coordinate = walk.destination
            pin.title = walk.destinationName
            map.addAnnotations([walker, pin])
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func syncPath() {
            guard let map, !drawn, let path = walk.path else { return }
            drawn = true
            map.addOverlay(MKPolyline(coordinates: path.points, count: path.points.count), level: .aboveRoads)
            placeCamera()
        }

        @objc private func tick(_ link: CADisplayLink) {
            let dt = lastTick == 0 ? 0 : min(link.timestamp - lastTick, 0.1)
            lastTick = link.timestamp
            walk.advance(by: dt)
            placeCamera()
        }

        private func placeCamera() {
            guard let map, let path = walk.path else { return }
            let (coord, _) = path.position(at: walk.distance)
            walker.coordinate = coord
            let heading = path.smoothedHeading(at: walk.distance, window: 60)
            let (aim, _) = path.position(at: walk.distance + 40)
            map.setCamera(MKMapCamera(lookingAtCenter: aim, fromDistance: 380, pitch: 52, heading: heading), animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = UIColor(red: 0.84, green: 0.07, blue: 0.13, alpha: 1)
            r.lineWidth = 8
            r.lineCap = .round
            r.lineDashPattern = [0.01, 15]   // round caps on near-zero dashes = dotted line
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is WalkerAnnotation {
                let v = MKAnnotationView(annotation: annotation, reuseIdentifier: "walker")
                v.image = WalkerAnnotation.image
                v.zPriority = .max
                return v
            }
            let m = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dest")
            m.markerTintColor = UIColor(red: 0.84, green: 0.07, blue: 0.13, alpha: 1)
            m.glyphImage = UIImage(systemName: "theatermasks.fill")
            m.titleVisibility = .visible
            m.displayPriority = .required
            return m
        }
    }
}

final class WalkerAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()

    /// White disc with a red ring and a walking figure.
    static let image: UIImage = {
        let size = CGSize(width: 34, height: 34)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30)).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            let red = UIColor(red: 0.84, green: 0.07, blue: 0.13, alpha: 1)
            red.setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 3.5, y: 3.5, width: 27, height: 27))
            ring.lineWidth = 3
            ring.stroke()
            let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            if let fig = UIImage(systemName: "figure.walk", withConfiguration: cfg)?.withTintColor(red, renderingMode: .alwaysOriginal) {
                fig.draw(at: CGPoint(x: 17 - fig.size.width / 2, y: 17 - fig.size.height / 2))
            }
        }
    }()
}
