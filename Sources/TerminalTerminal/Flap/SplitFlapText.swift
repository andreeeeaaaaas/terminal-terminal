import SwiftUI

/// A fixed-width field of split-flap cells. Changing `text` flips only the cells whose
/// glyph changes, rippling left to right.
struct SplitFlapText: View {
    let text: String
    let width: Int
    var alignment: HorizontalAlignment = .leading
    /// Defaults to the theme's ink.
    var color: Color?
    /// False goes straight to each new character, for clocks and counters.
    var scrambles = true

    @Environment(\.boardTheme) private var theme
    @Environment(\.flapStartsSettled) private var startsSettled

    private static let ripple: Double = 0.03

    var body: some View {
        let cells = FlapGlyphs.cells(text, width: width, alignment: alignment)
        HStack(spacing: theme.metrics.cellSpacing) {
            ForEach(0..<width, id: \.self) { index in
                SplitFlapCharacter(
                    target: cells[index],
                    color: color ?? theme.ink,
                    delay: scrambles ? Double(index) * Self.ripple : 0,
                    scrambles: scrambles,
                    startsSettled: startsSettled
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
