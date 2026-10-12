import SwiftUI

/// The characters a physical flap drum carries. Anything else is mapped before display.
enum FlapGlyphs {
    /// The external-link arrow, drawn as a symbol in text faces. Only the open control uses it.
    static let openArrow: Character = "↗"
    static let set: [Character] = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.-/↗")
    private static let lookup = Set(set)
    private static let scramble: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Uppercases, maps unsupported characters, and pads or truncates to exactly `width` cells.
    static func cells(_ text: String, width: Int, alignment: HorizontalAlignment = .leading) -> [Character] {
        var chars = text.uppercased().map { char -> Character in
            if lookup.contains(char) { return char }
            return char == "_" ? "-" : " "
        }
        if chars.count > width { chars = Array(chars.prefix(width)) }
        let padding = Array(repeating: Character(" "), count: width - chars.count)
        return alignment == .trailing ? padding + chars : chars + padding
    }

    static func random(excluding excluded: Character) -> Character {
        var glyph: Character
        repeat { glyph = scramble.randomElement()! } while glyph == excluded
        return glyph
    }
}

struct FlapMetrics {
    var fontSize: CGFloat = 12
    var cellWidth: CGFloat = 10
    /// With `hinge`, chosen so both halves land on whole pixels at 2x.
    var cellHeight: CGFloat = 17.5
    var cellSpacing: CGFloat = 1
    /// Gap between the two halves of a tile: a hairline, so glyphs stay legible across it.
    var hinge: CGFloat = 0.5

    var halfHeight: CGFloat { (cellHeight - hinge) / 2 }

    func width(ofCells count: Int) -> CGFloat {
        CGFloat(count) * cellWidth + CGFloat(max(count - 1, 0)) * cellSpacing
    }
}

private struct FlapStartsSettledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, cells first render already showing their value, and AppKit-backed
    /// views are left out. Used for static snapshots.
    var flapStartsSettled: Bool {
        get { self[FlapStartsSettledKey.self] }
        set { self[FlapStartsSettledKey.self] = newValue }
    }
}
