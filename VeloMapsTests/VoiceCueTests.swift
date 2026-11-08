import Testing
import Foundation
@testable import VeloMaps

/// Every phrase the demo can say has an ElevenLabs clip in the app, so riders never hear a
/// silent switch to Apple's voice (drift between the Swift phrases and the render script
/// is a test failure).
@Suite("ElevenLabs voice cues")
@MainActor
struct VoiceCueTests {
    private func missing(_ line: VoiceLine) -> [String] { line.clips.filter { VoiceCues.url($0) == nil } }

    @Test func slugMatchesTheRenderScript() {
        #expect(VoiceCues.slug("Turn left onto W 96 St") == "cue-turn-left-onto-w-96-st")
        #expect(VoiceCues.slug("Your stop is next: Columbus Av / W 96 St") == "cue-your-stop-is-next-columbus-av-w-96-st")
        #expect(VoiceCues.slug("In 0.4 miles") == "cue-in-0-4-miles")
    }

    @Test(arguments: [(20.0, "In 100 feet"), (91.0, "In 300 feet"), (305.0, "In 1000 feet"), (330.0, "In 0.2 miles"),
                      (1609.0, "In 1 mile"), (2000.0, "In 1.2 miles"), (3219.0, "In 2 miles"), (5000.0, "In 2 miles")])
    func distancesRoundLikeANavigationVoice(_ m: Double, _ text: String) {
        #expect(VoiceCues.distanceText(m) == text)
    }

    @Test func everyTurnOnBothDemoRoutesHasClips() {
        for route in [Route.m10, Route.hhDrive] {
            for m in route.maneuvers {
                for d in stride(from: 20.0, through: 3300, by: 15) {
                    let line = VoiceCues.turn(remaining: d, instruction: m.instruction)
                    #expect(missing(line).isEmpty, "\(route.line): \(line.fallback) missing \(missing(line))")
                }
            }
        }
    }

    @Test func alertsHaveClips() {
        let lines = ["Pothole ahead",
                     "Your stop is next: Columbus Av / W 96 St",
                     "2 stops to go. Your stop is Columbus Av / W 96 St",
                     "Arriving at your stop, Columbus Av / W 96 St",
                     "Arriving at your stop, West 96th Street"]
        for l in lines { #expect(missing(VoiceCues.line(l)).isEmpty, "\(l)") }
    }

    @Test func spokenStopAlertMatchesAClip() {
        let d = UserDefaults(suiteName: "velo-tests-\(UUID())")!
        d.set("30", forKey: "turnPassed")
        let trip = Trip(defaults: d)
        let text = try! #require(trip.announcement?.text)
        #expect(missing(VoiceCues.line(text)).isEmpty, "no clip for \(text)")
    }
}

@Suite("Whole-sentence voice")
struct WholeSentenceVoiceTests {
    @Test(arguments: [
        ("In 300 feet, turn left onto W 96 St", "In 300 feet, turn left onto West 96th Street."),
        ("In 0.4 miles, take the ramp to NY 9A North", "In 0.4 miles, take the ramp to New York 9A North."),
        ("Your stop is next: Columbus Av / W 96 St", "Your stop is next: Columbus Avenue and West 96th Street."),
        ("In 1 mile, keep right onto I 87 North", "In 1 mile, keep right onto Interstate 87 North."),
        ("Pothole ahead", "Pothole ahead."),
    ])
    func spokenTextReadsLikeASentence(_ display: String, _ spoken: String) {
        #expect(VoiceCues.spokenText(display) == spoken)
    }

    @Test func spokenTextIsSafeForTheVoiceService() {
        let t = VoiceCues.spokenText("Turn left onto Café Street ⚠️ " + String(repeating: "x", count: 300))
        #expect(t.count <= 200)
        #expect(t.unicodeScalars.allSatisfy { $0.isASCII })
    }

    @Test func voiceServiceIsOffUnderTests() {
        #expect(!VoiceService.enabled, "tests must never call the paid voice service")
    }

    @Test func cacheFileIsStablePerSentence() {
        #expect(VoiceService.cacheURL("Pothole ahead.") == VoiceService.cacheURL("Pothole ahead."))
        #expect(VoiceService.cacheURL("Pothole ahead.") != VoiceService.cacheURL("Pothole ahead!"))
    }
}
