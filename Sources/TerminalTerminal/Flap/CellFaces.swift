import SwiftUI

/// A bare glyph in a fixed cell, for the plain styles.
struct PlainCell: View {
    let glyph: Character
    let color: Color

    @Environment(\.boardTheme) private var theme

    var body: some View {
        Text(String(glyph))
            .font(theme.glyphFont())
            .foregroundStyle(color)
            // Proportional glyphs (M, W) can be wider than the cell: overflow, never truncate.
            .fixedSize()
            .frame(width: theme.metrics.cellWidth, height: theme.metrics.cellHeight)
    }
}

/// A 5×7 LED matrix cell. Unlit dots stay faintly visible, like a real board.
struct DotMatrixCell: View {
    let glyph: Character
    let color: Color
    let shape: BoardTheme.DotShape

    @Environment(\.boardTheme) private var theme

    var body: some View {
        let rows = DotFont.rows(for: glyph)
        let unlit = theme.unlitDot
        let shape = shape
        Canvas { context, size in
            let pitch = min(size.width / CGFloat(DotFont.columns), size.height / CGFloat(DotFont.rows))
            let dot = pitch * 0.78
            let origin = CGPoint(
                x: (size.width - pitch * CGFloat(DotFont.columns)) / 2,
                y: (size.height - pitch * CGFloat(DotFont.rows)) / 2
            )
            func path(_ row: Int, _ column: Int) -> Path {
                let rect = CGRect(
                    x: origin.x + CGFloat(column) * pitch + (pitch - dot) / 2,
                    y: origin.y + CGFloat(row) * pitch + (pitch - dot) / 2,
                    width: dot,
                    height: dot
                )
                return shape == .round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: dot * 0.12)
            }

            var lit = Path()
            var dark = Path()
            for row in 0..<DotFont.rows {
                for column in 0..<DotFont.columns {
                    if rows[row] & (1 << (DotFont.columns - 1 - column)) != 0 {
                        lit.addPath(path(row, column))
                    } else {
                        dark.addPath(path(row, column))
                    }
                }
            }
            context.fill(dark, with: .color(unlit))
            // A soft glow under the lit dots.
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: pitch * 0.45))
                glow.fill(lit, with: .color(color.opacity(0.55)))
            }
            context.fill(lit, with: .color(color))
        }
        .frame(width: theme.metrics.cellWidth, height: theme.metrics.cellHeight)
    }
}

/// A 5×7 bitmap font covering `FlapGlyphs.set`. Each row is 5 bits, most significant on the left.
enum DotFont {
    static let columns = 5
    static let rows = 7

    static func rows(for glyph: Character) -> [UInt8] {
        bitmaps[glyph] ?? blank
    }

    private static let blank: [UInt8] = Array(repeating: 0, count: 7)

    private static let bitmaps: [Character: [UInt8]] = {
        let source: [Character: [String]] = [
            "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
            "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
            "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
            "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
            "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
            "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
            "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
            "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
            "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
            "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
            "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
            "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
            "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
            "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
            "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
            "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
            "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
            "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
            "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
            "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
            "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
            "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
            "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
            "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
            "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
            "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
            "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
            "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
            "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
            "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
            "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
            "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
            "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
            "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
            "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
            "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
            ":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
            ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
            "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
            "/": [".....", "....#", "...#.", "..#..", ".#...", "#....", "....."],
        ]
        return source.mapValues { lines in
            lines.map { line in
                line.reduce(UInt8(0)) { bits, pixel in (bits << 1) | (pixel == "#" ? 1 : 0) }
            }
        }
    }()
}
