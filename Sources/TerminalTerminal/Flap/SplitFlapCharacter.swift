import SwiftUI

/// One character cell. When `target` changes, the cell runs through a few random glyphs
/// before settling, the way a physical drum spins past letters on its way to the right one.
///
/// In the flap style each step is two half-turns: the top flap (old glyph) falls forward to
/// reveal the new glyph's top half, then the bottom flap (new glyph) lands over the old
/// bottom half. Plain and dot-matrix styles swap glyphs in place at the same rhythm.
///
/// A flip is stored once, when it starts, and each frame is worked out from the time since,
/// on the display's clock. Cells used to run their own loops of state changes, which pinned
/// the main thread for seconds when a whole board flipped in.
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

    @State private var flip: Flip
    /// Pauses the timeline between flips.
    @State private var isSettled = true

    fileprivate static let halfTurn: Double = 0.055

    init(target: Character, color: Color, delay: Double = 0, scrambles: Bool = true, inverted: Bool = false, startsSettled: Bool = false) {
        self.target = target
        self.color = color
        self.delay = delay
        self.scrambles = scrambles
        self.inverted = inverted
        _flip = State(initialValue: Flip(resting: startsSettled ? Face(glyph: target, inverted: inverted) : Face(glyph: " ", inverted: false)))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: isSettled)) { context in
            // A paused timeline keeps its last frame's date, which can fall before the flip
            // ended, so a settled cell shows the end state rather than working it out.
            face(at: isSettled ? .infinity : context.date.timeIntervalSince(flip.start))
        }
        .task(id: Face(glyph: target, inverted: inverted)) { await start() }
    }

    @ViewBuilder
    private func face(at elapsed: TimeInterval) -> some View {
        switch theme.cellStyle {
        case .flap:
            let frame = flip.flapFrame(at: elapsed)
            FlapFace(
                current: frame.current.glyph, next: frame.next.glyph,
                topAngle: frame.topAngle, bottomAngle: frame.bottomAngle, color: color,
                currentInverted: frame.current.inverted, nextInverted: frame.next.inverted
            )
        case .plain:
            let shown = flip.swappedFace(at: elapsed)
            PlainCell(glyph: shown.glyph, color: shown.inverted ? theme.accent : color)
        case .dots(let shape):
            let shown = flip.swappedFace(at: elapsed)
            DotMatrixCell(glyph: shown.glyph, color: shown.inverted ? theme.accent : color, shape: shape)
        }
    }

    private func start() async {
        let target = Face(glyph: target, inverted: inverted)
        let style = theme.cellStyle
        let now = Date()
        // A flip still running is cut short at the glyph it last landed on.
        let shown = flip.landedFace(at: now.timeIntervalSince(flip.start), style: style)
        guard shown != target, !reduceMotion else {
            if shown != target || !isSettled {
                withoutAnimation {
                    flip = Flip(resting: target)
                    isSettled = true
                }
            }
            return
        }

        var steps = scrambles
            ? (0..<Int.random(in: 2...4)).map { _ in Face(glyph: FlapGlyphs.random(excluding: target.glyph), inverted: target.inverted) }
            : []
        steps.append(target)
        let next = Flip(from: shown, steps: steps, start: now, delay: delay)
        withoutAnimation {
            flip = next
            isSettled = false
        }
        guard await pause(next.duration(style)) else { return }
        withoutAnimation { isSettled = true }
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

private struct Face: Equatable {
    var glyph: Character
    var inverted: Bool
}

/// A run from one face through `steps`, the last of which is the target.
private struct Flip {
    var from: Face
    var steps: [Face]
    var start: Date
    var delay: Double

    /// Flap: each step is two half-turns.
    static let stepTime = 2 * SplitFlapCharacter.halfTurn
    /// Plain and dots: each glyph before the target shows for this long.
    static let swapTime = 1.4 * SplitFlapCharacter.halfTurn

    struct FlapFrame {
        var current: Face
        var next: Face
        var topAngle: Double = 0
        var bottomAngle: Double = 90

        static func resting(_ face: Face) -> FlapFrame { FlapFrame(current: face, next: face) }
    }

    init(from: Face, steps: [Face], start: Date, delay: Double) {
        self.from = from
        self.steps = steps
        self.start = start
        self.delay = delay
    }

    init(resting face: Face) {
        self.init(from: face, steps: [], start: .distantPast, delay: 0)
    }

    var target: Face { steps.last ?? from }

    func duration(_ style: BoardTheme.CellStyle) -> Double {
        style == .flap
            ? delay + Double(steps.count) * Self.stepTime
            : delay + Double(max(steps.count - 1, 0)) * Self.swapTime
    }

    /// Eases in as the top flap falls, then out as the bottom one lands.
    func flapFrame(at elapsed: TimeInterval) -> FlapFrame {
        let time = elapsed - delay
        guard time >= 0, !steps.isEmpty else { return .resting(from) }
        guard time < Double(steps.count) * Self.stepTime else { return .resting(target) }
        let index = Int(time / Self.stepTime)
        let current = index == 0 ? from : steps[index - 1]
        let half = SplitFlapCharacter.halfTurn
        let phase = time - Double(index) * Self.stepTime
        if phase < half {
            let progress = phase / half
            return FlapFrame(current: current, next: steps[index], topAngle: -90 * progress * progress)
        }
        let remaining = 1 - (phase - half) / half
        return FlapFrame(current: current, next: steps[index], topAngle: -90, bottomAngle: 90 * remaining * remaining)
    }

    func swappedFace(at elapsed: TimeInterval) -> Face {
        let time = elapsed - delay
        guard time >= 0, !steps.isEmpty else { return from }
        guard time < Double(steps.count - 1) * Self.swapTime else { return target }
        return steps[Int(time / Self.swapTime)]
    }

    /// The last glyph fully showing, where an interrupted flip restarts from.
    func landedFace(at elapsed: TimeInterval, style: BoardTheme.CellStyle) -> Face {
        style == .flap ? flapFrame(at: elapsed).current : swappedFace(at: elapsed)
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
