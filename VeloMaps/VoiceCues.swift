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

    static func url(_ clip: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: clip, withExtension: "mp3")
    }
}

/// Spoken guidance: plays the ElevenLabs clips back to back; Apple's voice if one is missing.
/// Voice-prompt audio mode so it ducks music like other navigation apps.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private var queue: AVQueuePlayer?
    private var configured = false

    func say(_ line: VoiceLine) {
        if !configured {
            try? AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            configured = true
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        let urls = line.clips.compactMap { VoiceCues.url($0) }
        if urls.count == line.clips.count, !urls.isEmpty {
            queue?.pause()
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
