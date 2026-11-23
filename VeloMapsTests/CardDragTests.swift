import Testing
import CoreGraphics
@testable import VeloMaps

/// The ride card follows the thumb completely (owner, 11/22: "it gets stuck as
/// I pull it up or down").
@Suite("Ride card drag")
struct CardDragTests {
    let panel: CGFloat = 300

    @Test func revealTracksTheFingerPointForPoint() {
        #expect(CardDrag.reveal(expanded: false, translation: -1, panel: panel) == 1)
        #expect(CardDrag.reveal(expanded: false, translation: -120, panel: panel) == 120)
        #expect(CardDrag.reveal(expanded: false, translation: -299, panel: panel) == 299)
        #expect(CardDrag.reveal(expanded: true, translation: 0, panel: panel) == 300)
        #expect(CardDrag.reveal(expanded: true, translation: 80, panel: panel) == 220)
        #expect(CardDrag.reveal(expanded: true, translation: 300, panel: panel) == 0)
    }

    @Test func pastEitherEndItRubberBandsInsteadOfStopping() {
        let over = CardDrag.reveal(expanded: true, translation: -100, panel: panel)
        #expect(over > 300 && over < 360)
        let under = CardDrag.reveal(expanded: false, translation: 100, panel: panel)
        #expect(under < 0 && under > -60)
        // Further still gives a little more, never a hard stop.
        #expect(CardDrag.reveal(expanded: true, translation: -200, panel: panel) > over)
    }

    @Test func aSlowDragSettlesOnWhicheverSideOfHalfwayItWasLetGo() {
        #expect(CardDrag.settlesExpanded(expanded: false, translation: -160, predicted: -160, panel: panel))
        #expect(!CardDrag.settlesExpanded(expanded: false, translation: -100, predicted: -100, panel: panel))
        #expect(!CardDrag.settlesExpanded(expanded: true, translation: 170, predicted: 170, panel: panel))
        #expect(CardDrag.settlesExpanded(expanded: true, translation: 90, predicted: 90, panel: panel))
    }

    @Test func aQuickFlickCountsByWhereItWasHeading() {
        // A short flick up whose momentum carries past halfway opens.
        #expect(CardDrag.settlesExpanded(expanded: false, translation: -40, predicted: -260, panel: panel))
        // A short flick down from open closes.
        #expect(!CardDrag.settlesExpanded(expanded: true, translation: 30, predicted: 240, panel: panel))
    }

    @Test func beforeThePanelIsMeasuredNothingIsRevealed() {
        #expect(CardDrag.reveal(expanded: false, translation: -100, panel: 0) == 0)
        #expect(CardDrag.settlesExpanded(expanded: false, translation: -60, predicted: -60, panel: 0))
    }
}
