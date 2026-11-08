import SwiftUI

/// System font at a design size that still follows the rider's text-size setting
/// (Dynamic Type). The design sizes are the defaults; larger settings scale them up.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        // Big numerals scale against the large-title curve so they don't balloon.
        _size = ScaledMetric(wrappedValue: size, relativeTo: size >= 28 ? .largeTitle : .body)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

/// How solid the frost under text on glass is. 0.9 read as flat black/white panels (owner,
/// 11/7: "we need to use apple glass"); 0.55 keeps the see-through look, and the accessibility
/// audit's pixel re-check confirms text contrast on the real rendering.
let glassFrost = 0.55

extension View {
    /// Liquid Glass with a solid frost under the content — light by day, dark at night — so
    /// text on it keeps contrast over a busy map (plain or tinted glass let the green park
    /// bleed through; accessibility audit, 11/7).
    func readableGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        // The glass is a layer *behind* the content rather than wrapped around it: content
        // inside a glass effect gets adaptive colouring from the map moving behind it, which
        // the accessibility audit measured as contrast failures on text that reads fine.
        background(Color(uiColor: .systemBackground).opacity(glassFrost), in: shape)
            .background(shape.fill(Color.white.opacity(0.001))
                .glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape))
    }
}

/// Text grows with the rider's setting up to the largest standard size, not the
/// accessibility sizes: a glanceable navigation overlay can't fit those on a phone.
/// Owner decision 11/7 ("Cap + ship today"); the audit skips its Dynamic Type check for it.
let maxTextSize = DynamicTypeSize.xxxLarge
