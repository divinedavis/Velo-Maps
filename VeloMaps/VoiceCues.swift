import Foundation
import AVFoundation

/// A spoken line: the ElevenLabs clips to stitch (rendered by scripts/make_voice_cues.py) and
/// the text Apple's voice says if any clip is missing.
struct VoiceLine: Equatable {
    let clips: [String]
    let fallback: String
}

enum VoiceCues {
    /// Must match slug() in scripts/make_voice_cues.py.
    static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        var out = ""
        var dash = false
        for ch in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) && ch.isASCII {
                out.unicodeScalars.append(ch); dash = false
            } else if !dash && !out.isEmpty {
                out += "-"; dash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return "cue-" + out
    }

    /// Distances rounded like a navigation voice: 100–1000 ft in hundreds, then tenths of a
    /// mile up to 2 (banners now come up to 2 miles out at highway speed; clips match).
    static func distanceText(_ metres: Double) -> String {
        let feet = metres * 3.28084
        if feet < 1050 {
            let f = min(1000, max(100, Int((feet / 100).rounded()) * 100))
            return "In \(f) feet"
        }
        let tenths = min(20, max(2, Int((metres / 1609.34 * 10).rounded())))
        if tenths == 10 { return "In 1 mile" }
        if tenths == 20 { return "In 2 miles" }
        return String(format: "In %.1f miles", Double(tenths) / 10)
    }

    static func turn(remaining metres: Double, instruction: String) -> VoiceLine {
        let d = distanceText(metres)
        return VoiceLine(clips: [slug(d), slug(instruction)],
                         fallback: "\(d), \(instruction.prefix(1).lowercased() + instruction.dropFirst())")
    }

    static func line(_ text: String) -> VoiceLine { VoiceLine(clips: [slug(text)], fallback: text) }

    /// Display text → what the voice says (abbreviations expanded); mirrors spoken() in
    /// scripts/make_voice_cues.py.
    static func spokenText(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: #"\bW (\d+) St\b"#, with: "West $1 Street", options: .regularExpression)
        // ordinals for "West 96 Street"
        if let r = t.range(of: #"West (\d+) Street"#, options: .regularExpression) {
            let n = Int(t[r].split(separator: " ")[1]) ?? 0
            let suf = (11...13).contains(n % 100) ? "th" : ([1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th")
            t.replaceSubrange(r, with: "West \(n)\(suf) Street")
        }
        t = t.replacingOccurrences(of: "Columbus Av / ", with: "Columbus Avenue and ")
            .replacingOccurrences(of: "CPW", with: "Central Park West")
        t = t.replacingOccurrences(of: #"\bNY (\w+)"#, with: "New York $1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\bI (\d+)"#, with: "Interstate $1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\bUS (\d+)"#, with: "U.S. $1", options: .regularExpression)
        // The voice service accepts letters, digits and basic punctuation only.
        t = String(t.unicodeScalars.filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;'!?/&()-").contains($0) })
        if !t.hasSuffix(".") { t += "." }
        return String(t.prefix(200))
    }

    static func url(_ clip: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: clip, withExtension: "mp3")
    }
}

/// Whole sentences in Rene's voice from the Velo Maps voice service (droplet), cached on the
/// phone (Caches/voice) so repeat drives need no network. nil = unavailable → fall back.
enum VoiceService {
    static let base = URL(string: "https://velomaps.104.236.120.144.sslip.io/tts")!

    static func cacheURL(_ text: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var h: UInt64 = 1469598103934665603                 // FNV-1a, stable across launches
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return dir.appendingPathComponent(String(h, radix: 16) + ".mp3")
    }

    /// Off under unit tests, the scripted demo and fixed-location UI tests: tests must never
    /// spend ElevenLabs credits (owner rule; caught 11/8 when unit tests reached the service).
    static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        let d = UserDefaults.standard
        return !AppSecrets.voiceToken.isEmpty && env["XCTestConfigurationFilePath"] == nil
            && d.string(forKey: "demo") == nil && d.string(forKey: "mockLocation") == nil
    }

    static func audio(for text: String, timeout: TimeInterval = 2.5) async -> Data? {
        let file = cacheURL(text)
        if let d = try? Data(contentsOf: file) { return d }
        guard enabled,
              var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = [URLQueryItem(name: "text", value: text)]
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue(AppSecrets.voiceToken, forHTTPHeaderField: "X-Velo-App")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 else { return nil }
        try? data.write(to: file, options: .atomic)
        return data
    }
}

/// Spoken guidance, most consistent first: one whole sentence in Rene's voice (voice service);
/// else the bundled Rene clips stitched (demo phrases, offline); else Apple's voice.
/// Voice-prompt audio mode so it ducks music like other navigation apps.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private var queue: AVQueuePlayer?
    private var player: AVAudioPlayer?
    private var configured = false
    private var latest = 0

    func say(_ line: VoiceLine) {
        if !configured {
            try? AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            configured = true
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        latest += 1
        let ticket = latest
        let text = VoiceCues.spokenText(line.fallback)
        Task {
            let data = await VoiceService.audio(for: text)
            guard ticket == latest else { return }          // a newer prompt replaced this one
            if let data, let p = try? AVAudioPlayer(data: data) {
                stopAll()
                player = p
                p.play()
            } else {
                fallback(line)
            }
        }
    }

    private func stopAll() {
        player?.stop(); queue?.pause()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func fallback(_ line: VoiceLine) {
        stopAll()
        let urls = line.clips.compactMap { VoiceCues.url($0) }
        if urls.count == line.clips.count, !urls.isEmpty {
            let q = AVQueuePlayer(items: urls.map { AVPlayerItem(url: $0) })
            queue = q
            q.play()
        } else {
            let u = AVSpeechUtterance(string: line.fallback)
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            synth.speak(u)
        }
    }
}
