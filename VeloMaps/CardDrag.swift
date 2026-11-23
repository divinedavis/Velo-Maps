import CoreGraphics

/// The ride card's drag maths, kept free of SwiftUI so it can be tested.
///
/// The card used to move only a token 35% of the finger (capped at 40 pt)
/// and then jump open or shut on release, so it felt stuck under the thumb
/// (owner, 2026-11-22: "it should follow my thumb completely"). Now the
/// settings panel is revealed point for point with the finger, rubber-bands
/// past either end like a system sheet, and settles open or closed by where
/// the finger is heading when it lifts.
enum CardDrag {
    /// How much of the settings panel shows, in points, for a drag of
    /// `translation` (negative = up) starting open or closed.
    static func reveal(expanded: Bool, translation: CGFloat, panel: CGFloat) -> CGFloat {
        guard panel > 0 else { return 0 }
        let raw = (expanded ? panel : 0) - translation
        if raw < 0 { return -rubberBand(-raw) }
        if raw > panel { return panel + rubberBand(raw - panel) }
        return raw
    }

    /// Open or closed after release. Uses the predicted end, so a short quick
    /// flick still counts, and a slow drag settles on whichever side of
    /// halfway it was let go.
    static func settlesExpanded(expanded: Bool, translation: CGFloat, predicted: CGFloat, panel: CGFloat) -> Bool {
        guard panel > 0 else { return !expanded && predicted < -40 }
        let projected = (expanded ? panel : 0) - predicted
        return projected > panel / 2
    }

    /// Diminishing travel past the end, like UIScrollView's bounce.
    static func rubberBand(_ overshoot: CGFloat, limit: CGFloat = 60) -> CGFloat {
        guard overshoot > 0 else { return 0 }
        return limit * (1 - 1 / (overshoot / limit * 0.55 + 1))
    }
}
