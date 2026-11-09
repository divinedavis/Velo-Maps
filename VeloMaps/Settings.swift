import SwiftUI
import UIKit
import AVFoundation

/// Navigation settings (Settings card). Stored in UserDefaults via @AppStorage in the views;
/// the trip logic reads the same keys. Defaults match what the settings card shows.
enum SettingKey {
    static let voice = "voiceGuidance"
    static let stopAlert = "stopAlert"
    static let appearance = "appearance"
    static let buildings = "buildings3D"
    static let potholes = "showPotholes"
    static let mapMode = "mapMode"
    static let traffic = "mapTraffic"
}

extension UserDefaults {
    var voiceGuidance: Bool { object(forKey: SettingKey.voice) as? Bool ?? true }
    var stopAlertSetting: String { string(forKey: SettingKey.stopAlert) ?? "1 stop before" }
    var appearanceSetting: String { string(forKey: SettingKey.appearance) ?? "Auto" }
    var buildings3D: Bool { object(forKey: SettingKey.buildings) as? Bool ?? true }
    var showPotholes: Bool { object(forKey: SettingKey.potholes) as? Bool ?? true }
}

/// Map appearance: Auto follows the phone; Day/Night force it. `-night YES` (previews) wins.
func resolvedScheme(appearance: String, forcedNight: Bool) -> ColorScheme? {
    if forcedNight { return .dark }
    switch appearance {
    case "Day": return .light
    case "Night": return .dark
    default: return nil
    }
}

extension ColorScheme? {
    var uiStyle: UIUserInterfaceStyle {
        switch self { case .some(.dark): .dark; case .some(.light): .light; default: .unspecified }
    }
}

/// Something the trip wants the rider to know right now (stop alert, report confirmations).
struct Announcement: Equatable {
    let id = UUID()
    let text: String
}

/// Ends the walking leg (walking screen's End buttons).
private struct EndWalkKey: EnvironmentKey { static let defaultValue: @MainActor () -> Void = {} }
extension EnvironmentValues {
    var endWalk: @MainActor () -> Void {
        get { self[EndWalkKey.self] }
        set { self[EndWalkKey.self] = newValue }
    }
}
