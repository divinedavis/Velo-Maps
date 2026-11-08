import Foundation
import MetricKit
import os

/// Real-device performance and crash data (Apple quality gate 4). MetricKit hands over a
/// daily MXMetricPayload (launch time, hangs, memory, battery) and MXDiagnosticPayload
/// (crashes, hangs, disk-write exceptions). They are logged here; the same numbers reach
/// Xcode Organizer and the ASC API, which scripts/organizer_report.py prints before a ship.
final class Metrics: NSObject, MXMetricManagerSubscriber {
    static let shared = Metrics()
    private let log = Logger(subsystem: "com.divinedavis.velomaps", category: "metrics")

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads {
            log.info("MXMetricPayload \(p.timeStampBegin, privacy: .public)–\(p.timeStampEnd, privacy: .public), \(p.jsonRepresentation().count) bytes")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let crashes = p.crashDiagnostics?.count ?? 0
            let hangs = p.hangDiagnostics?.count ?? 0
            log.error("MXDiagnosticPayload crashes=\(crashes) hangs=\(hangs)")
        }
    }
}
