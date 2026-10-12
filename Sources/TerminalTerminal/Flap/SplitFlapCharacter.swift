import SwiftUI

/// One character cell. When `target` changes, the cell runs through a few random glyphs
/// before settling, the way a physical drum spins past letters on its way to the right one.
///
/// In the flap style each step is two half-turns: the top flap (old glyph) falls forward to
/// reveal the new glyph's top half, then the bottom flap (new glyph) lands over the old
/// bottom half. Plain and dot-matrix styles swap glyphs in place at the same rhythm.
struct SplitFlapCharacter: View {
    let target: Character
    var color: Color
    /// Seconds to wait before starting, so a field ripples left to right.
    var delay: Double = 0
    /// False goes straight to the target, for ticking digits.
    var scrambles = true
    /// Flap: accent tile with a board-coloured glyph, like the board's buttons, turning with
    /// the flap. Other styles have no tile, so the glyph takes the accent instead.
    var inverted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardTheme) private var theme

    @State private var current: Character
    @State private var next: Character
    @State private var currentInverted = false
    @State private var nextInverted = false
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 90

    private static let halfTurn: Double = 0.055

    init(target: Character, color: Color, delay: Double = 0, scrambles: Bool = true, inverted: Bool = false, startsSettled: Bool = false) {
        self.target = target
        self.color = color
        self.delay = delay
        self.scrambles = scrambles
        self.inverted = inverted
        let initial: Character = startsSettled ? target : " "
        _current = State(initialValue: initial)
        _next = State(initialValue: initial)
        _currentInverted = State(initialValue: startsSettled && inverted)
        _nextInverted = State(initialValue: startsSettled && inverted)
    }

    private struct Target: Equatable {
        let glyph: Character
        let inverted: Bool
    }

    var body: some View {
        face.task(id: Target(glyph: target, inverted: inverted)) { await flip(to: target, inverted: inverted) }
    }

    @ViewBuilder
    private var face: some View {
        switch theme.cellStyle {
        case .flap:
            FlapFace(
                current: current, next: next, topAngle: topAngle, bottomAngle: bottomAngle, color: color,
                currentInverted: currentInverted, nextInverted: nextInverted
            )
        case .plain:
            PlainCell(glyph: current, color: currentInverted ? theme.accent : color)
        case .dots(let shape):
            DotMatrixCell(glyph: current, color: currentInverted ? theme.accent : color, shape: shape)
        }
    }

    private func flip(to target: Character, inverted: Bool) async {
        // A previous sequence may have been cancelled mid-turn. Snap to rest first.
        withoutAnimation {
            next = current
            nextInverted = currentInverted
            topAngle = 0
            bottomAngle = 90
        }
        guard target != current || inverted != currentInverted else { return }

        if reduceMotion {
            withoutAnimation {
                current = target
                next = target
                currentInverted = inverted
                nextInverted = inverted
            }
            return
        }

        if delay > 0, !(await pause(delay)) { return }

        var sequence = scrambles ? (0..<Int.random(in: 2...4)).map { _ in FlapGlyphs.random(excluding: target) } : []
        sequence.append(target)

        guard theme.cellStyle == .flap else {
            for glyph in sequence {
                withoutAnimation {
                    current = glyph
                    currentInverted = inverted
                }
                if glyph != target, !(await pause(Self.halfTurn * 1.4)) { return }
            }
            withoutAnimation {
                next = target
                nextInverted = inverted
            }
            return
        }

        for glyph in sequence {
            withoutAnimation {
                next = glyph
                nextInverted = inverted
            }
            withAnimation(.easeIn(duration: Self.halfTurn)) { topAngle = -90 }
            guard await pause(Self.halfTurn) else { return }
            withAnimation(.easeOut(duration: Self.halfTurn)) { bottomAngle = 0 }
            guard await pause(Self.halfTurn) else { return }
            withoutAnimation {
                current = glyph
                currentInverted = inverted
                topAngle = 0
                bottomAngle = 90
            }
        }
    }

    /// Sleeps for `seconds`. Returns false if the task was cancelled because the target changed.
    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

/// A stateless rendering of one cell at a given point in a flip. Angles run from
/// 0 to -90 for the falling top flap and from 90 to 0 for the landing bottom flap.
struct FlapFace: View {
    let current: Character
    let next: Character
    let topAngle: Double
    let bottomAngle: Double
    /// Defaults to the theme's ink.
    var color: Color?
    var currentInverted = false
    var nextInverted = false

    @Environment(\.boardTheme) private var theme

    var body: some View {
        let color = color ?? theme.ink
        let metrics = theme.metrics
        return VStack(spacing: metrics.hinge) {
            ZStack {
                FlapHalf(glyph: next, edge: .top, color: color, inverted: nextInverted)
                FlapHalf(glyph: current, edge: .top, color: color, inverted: currentInverted)
                    .overlay(Color.black.opacity(shade(topAngle)))
                    .rotation3DEffect(.degrees(topAngle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            }
            .zIndex(1)
            ZStack {
                FlapHalf(glyph: current, edge: .bottom, color: color, inverted: currentInverted)
                FlapHalf(glyph: next, edge: .bottom, color: color, inverted: nextInverted)
                    .overlay(Color.black.opacity(shade(bottomAngle)))
                    .rotation3DEffect(.degrees(bottomAngle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
    }

    /// Flaps darken as they turn away from the light.
    private func shade(_ angle: Double) -> Double {
        min(abs(angle) / 90, 1) * 0.6
    }
}

/// The top or bottom half of a tile, showing that half of its glyph.
private struct FlapHalf: View {
    let glyph: Character
    let edge: VerticalEdge
    let color: Color
    var inverted = false

    @Environment(\.boardTheme) private var theme

    /// Draws the whole tile and glyph, then shows only this half. Only the tile's outer
    /// corners are rounded, so the halves meet in a straight hairline.
    var body: some View {
        let metrics = theme.metrics
        return ZStack {
            RoundedRectangle(cornerRadius: theme.tileCornerRadius, style: .continuous)
                .fill(tile)
            GlyphLabel(glyph: glyph)
                .foregroundStyle(inverted ? theme.board : color)
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .frame(width: metrics.cellWidth, height: metrics.halfHeight, alignment: edge == .top ? .top : .bottom)
        .clipped()
    }

    private var tile: Color {
        switch (inverted, edge) {
        case (false, .top): return theme.tileTop
        case (false, .bottom): return theme.tileBottom
        case (true, .top): return theme.accent
        // The lower half sits slightly in shadow, as on the dark tiles.
        case (true, .bottom): return theme.accent.opacity(0.9)
        }
    }
}
