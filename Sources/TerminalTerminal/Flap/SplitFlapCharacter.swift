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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardTheme) private var theme

    @State private var current: Character
    @State private var next: Character
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 90

    private static let halfTurn: Double = 0.055

    init(target: Character, color: Color, delay: Double = 0, scrambles: Bool = true, startsSettled: Bool = false) {
        self.target = target
        self.color = color
        self.delay = delay
        self.scrambles = scrambles
        let initial: Character = startsSettled ? target : " "
        _current = State(initialValue: initial)
        _next = State(initialValue: initial)
    }

    var body: some View {
        face.task(id: target) { await flip(to: target) }
    }

    @ViewBuilder
    private var face: some View {
        switch theme.cellStyle {
        case .flap:
            FlapFace(current: current, next: next, topAngle: topAngle, bottomAngle: bottomAngle, color: color)
        case .plain:
            PlainCell(glyph: current, color: color)
        case .dots(let shape):
            DotMatrixCell(glyph: current, color: color, shape: shape)
        }
    }

    private func flip(to target: Character) async {
        // A previous sequence may have been cancelled mid-turn. Snap to rest first.
        withoutAnimation {
            next = current
            topAngle = 0
            bottomAngle = 90
        }
        guard target != current else { return }

        if reduceMotion {
            withoutAnimation {
                current = target
                next = target
            }
            return
        }

        if delay > 0, !(await pause(delay)) { return }

        var sequence = scrambles ? (0..<Int.random(in: 2...4)).map { _ in FlapGlyphs.random(excluding: target) } : []
        sequence.append(target)

        guard theme.cellStyle == .flap else {
            for glyph in sequence {
                withoutAnimation { current = glyph }
                if glyph != target, !(await pause(Self.halfTurn * 1.4)) { return }
            }
            withoutAnimation { next = target }
            return
        }

        for glyph in sequence {
            withoutAnimation { next = glyph }
            withAnimation(.easeIn(duration: Self.halfTurn)) { topAngle = -90 }
            guard await pause(Self.halfTurn) else { return }
            withAnimation(.easeOut(duration: Self.halfTurn)) { bottomAngle = 0 }
            guard await pause(Self.halfTurn) else { return }
            withoutAnimation {
                current = glyph
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

    @Environment(\.boardTheme) private var theme

    var body: some View {
        let color = color ?? theme.ink
        let metrics = theme.metrics
        return VStack(spacing: metrics.hinge) {
            ZStack {
                FlapHalf(glyph: next, edge: .top, color: color)
                FlapHalf(glyph: current, edge: .top, color: color)
                    .overlay(Color.black.opacity(shade(topAngle)))
                    .rotation3DEffect(.degrees(topAngle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            }
            .zIndex(1)
            ZStack {
                FlapHalf(glyph: current, edge: .bottom, color: color)
                FlapHalf(glyph: next, edge: .bottom, color: color)
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

    @Environment(\.boardTheme) private var theme

    /// Draws the whole tile and glyph, then shows only this half. Only the tile's outer
    /// corners are rounded, so the halves meet in a straight hairline.
    var body: some View {
        let metrics = theme.metrics
        return ZStack {
            RoundedRectangle(cornerRadius: theme.tileCornerRadius, style: .continuous)
                .fill(edge == .top ? theme.tileTop : theme.tileBottom)
            Text(String(glyph))
                .font(theme.glyphFont())
                .foregroundStyle(color)
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .frame(width: metrics.cellWidth, height: metrics.halfHeight, alignment: edge == .top ? .top : .bottom)
        .clipped()
    }
}
