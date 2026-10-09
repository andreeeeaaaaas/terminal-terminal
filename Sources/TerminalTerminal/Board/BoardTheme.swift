import AppKit
import SwiftUI

/// Everything that varies between board looks: palette, typography, cell size and chrome.
/// Views read it from the environment; `BoardTheme.current` is the one the app ships with.
struct BoardTheme {
    enum Typeface {
        case mono, condensed, grotesk
    }

    /// How a single character cell is drawn.
    enum CellStyle: Equatable {
        /// Mechanical split-flap tile with a hinge.
        case flap
        /// Bare glyph, no tile. Changes scramble in place.
        case plain
        /// 5×7 LED matrix, with unlit dots visible.
        case dots(DotShape)
    }

    enum DotShape: Equatable {
        case round, square
    }

    /// Status colours that differ from `accent`/`ink`, e.g. green BOARDING on an LED board.
    struct StatusColors {
        var running: Color
        var boarding: Color
        var warning: Color
        var departed: Color
    }

    var name: String
    var board: Color
    var boardEdge: Color
    var tileTop: Color
    var tileBottom: Color
    /// Settled characters.
    var ink: Color
    /// Title and attention statuses (BOARDING, DELAYED).
    var accent: Color
    /// Column headers.
    var label: Color
    var cellStyle: CellStyle = .flap
    /// Unlit LED dots. Only used by `.dots`.
    var unlitDot: Color = .clear
    /// A rule under the header and each row, or nil for none.
    var rule: Color?
    /// Per-column ink, for boards whose columns are colour-coded.
    var columnInk: [BoardColumn: Color] = [:]
    var statusColors: StatusColors?
    var typeface: Typeface = .mono
    var glyphWeight: Font.Weight = .medium
    var metrics = FlapMetrics()
    var cornerRadius: CGFloat = 12
    var tileCornerRadius: CGFloat = 1.5
    /// Vertical padding around each row.
    var rowPadding: CGFloat = 3
    /// False folds the title bar away and puts the buttons on the column header.
    var showsTitle = true
    /// Column headers take the accent colour, so they follow an accent override.
    var labelFollowsAccent = false
    /// TIME as `hh:mm:ss` rather than `hh:mm`. Set from settings, not by presets.
    var showsSeconds = true

    static let current = charcoal

    func cells(_ column: BoardColumn) -> Int {
        column == .time && !showsSeconds ? 5 : column.cells
    }

    func glyphFont() -> Font {
        font(size: metrics.fontSize, weight: glyphWeight)
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch typeface {
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .condensed: return .system(size: size, weight: weight).width(.condensed)
        case .grotesk: return .system(size: size, weight: weight)
        }
    }
}

extension BoardTheme {
    static let charcoal = BoardTheme(
        name: "Charcoal",
        board: Color(red: 0.067, green: 0.067, blue: 0.071),
        boardEdge: .white.opacity(0.06),
        tileTop: Color(red: 0.185, green: 0.181, blue: 0.175),
        tileBottom: Color(red: 0.165, green: 0.161, blue: 0.155),
        ink: Color(red: 0.937, green: 0.910, blue: 0.835),
        accent: Color(red: 0.961, green: 0.729, blue: 0.290),
        label: Color(red: 0.851, green: 0.643, blue: 0.255).opacity(0.85),
        labelFollowsAccent: true
    )

    /// After the Frankfurt Airport board: brown-black tiles, white condensed letters, wide spacing.
    static let frankfurt = BoardTheme(
        name: "Frankfurt",
        board: Color(red: 0.090, green: 0.082, blue: 0.075),
        boardEdge: .white.opacity(0.05),
        tileTop: Color(red: 0.200, green: 0.188, blue: 0.172),
        tileBottom: Color(red: 0.172, green: 0.160, blue: 0.146),
        ink: Color(red: 0.965, green: 0.953, blue: 0.925),
        accent: Color(red: 0.965, green: 0.808, blue: 0.392),
        label: Color(red: 0.965, green: 0.953, blue: 0.925).opacity(0.5),
        typeface: .condensed,
        glyphWeight: .semibold,
        metrics: FlapMetrics(fontSize: 14, cellWidth: 11, cellHeight: 19.5, cellSpacing: 2),
        tileCornerRadius: 1
    )

    /// Smallest footprint: no title bar, smaller cells, tighter rows.
    static let compact = BoardTheme(
        name: "Compact",
        board: charcoal.board,
        boardEdge: charcoal.boardEdge,
        tileTop: charcoal.tileTop,
        tileBottom: charcoal.tileBottom,
        ink: charcoal.ink,
        accent: charcoal.accent,
        label: charcoal.label,
        metrics: FlapMetrics(fontSize: 10.5, cellWidth: 8.5, cellHeight: 15.5, cellSpacing: 1),
        cornerRadius: 10,
        rowPadding: 2,
        showsTitle: false,
        labelFollowsAccent: true
    )

    /// Ruled ledger, after the typographic timetable: thin rules, bold labels, plain mono.
    static let ledger = BoardTheme(
        name: "Ledger",
        board: .black,
        boardEdge: .white.opacity(0.1),
        tileTop: .clear,
        tileBottom: .clear,
        ink: .white,
        accent: .white,
        label: .white,
        cellStyle: .plain,
        rule: .white.opacity(0.32),
        glyphWeight: .regular,
        metrics: FlapMetrics(fontSize: 13, cellWidth: 8, cellHeight: 17, cellSpacing: 0),
        cornerRadius: 4,
        rowPadding: 6
    )

    /// Amber LED dot-matrix, after the Departures board.
    static let ledAmber = BoardTheme(
        name: "LED Amber",
        board: Color(red: 0.067, green: 0.055, blue: 0.047),
        boardEdge: .white.opacity(0.06),
        tileTop: .clear,
        tileBottom: .clear,
        ink: Color(red: 1.0, green: 0.741, blue: 0.180),
        accent: Color(red: 1.0, green: 0.741, blue: 0.180),
        label: Color(white: 0.92),
        cellStyle: .dots(.round),
        unlitDot: Color(red: 1.0, green: 0.741, blue: 0.180).opacity(0.09),
        typeface: .grotesk,
        metrics: FlapMetrics(fontSize: 12, cellWidth: 10, cellHeight: 14, cellSpacing: 2.5),
        cornerRadius: 10,
        rowPadding: 3.5
    )

    /// Colour-coded LED board: white times and PIDs, amber flights, green/red statuses.
    static let ledMulticolour = BoardTheme(
        name: "LED Multicolour",
        board: Color(white: 0.06),
        boardEdge: .white.opacity(0.06),
        tileTop: .clear,
        tileBottom: .clear,
        ink: Color(white: 0.95),
        accent: Color(red: 0.996, green: 0.733, blue: 0.231),
        label: Color(white: 0.75),
        cellStyle: .dots(.round),
        unlitDot: Color(white: 1).opacity(0.075),
        columnInk: [.flight: Color(red: 0.996, green: 0.733, blue: 0.231)],
        statusColors: StatusColors(
            running: Color(red: 0.996, green: 0.733, blue: 0.231),
            boarding: Color(red: 0.588, green: 0.906, blue: 0.231),
            warning: Color(red: 0.996, green: 0.733, blue: 0.231),
            departed: Color(red: 0.937, green: 0.196, blue: 0.180)
        ),
        typeface: .grotesk,
        metrics: FlapMetrics(fontSize: 12, cellWidth: 10, cellHeight: 14, cellSpacing: 2.5),
        cornerRadius: 10,
        rowPadding: 3.5
    )

    /// Square white pixels: a sharper, more digital matrix.
    static let pixel = BoardTheme(
        name: "Pixel",
        board: Color(white: 0.04),
        boardEdge: .white.opacity(0.08),
        tileTop: .clear,
        tileBottom: .clear,
        ink: Color(white: 0.96),
        accent: Color(red: 0.302, green: 0.851, blue: 1.0),
        label: Color(white: 0.96).opacity(0.5),
        cellStyle: .dots(.square),
        unlitDot: Color(white: 1).opacity(0.06),
        metrics: FlapMetrics(fontSize: 12, cellWidth: 10, cellHeight: 14, cellSpacing: 2),
        cornerRadius: 4,
        rowPadding: 3
    )

    static let all: [BoardTheme] = [
        charcoal, frankfurt, compact, ledger, ledAmber, ledMulticolour, pixel,
    ]

    static func named(_ name: String) -> BoardTheme {
        all.first { $0.name == name } ?? current
    }
}

private struct BoardThemeKey: EnvironmentKey {
    static let defaultValue = BoardTheme.current
}

extension EnvironmentValues {
    var boardTheme: BoardTheme {
        get { self[BoardThemeKey.self] }
        set { self[BoardThemeKey.self] = newValue }
    }
}

// MARK: - Settings overrides

extension BoardTheme {
    /// How characters are drawn, as offered in settings.
    enum Display: String, CaseIterable {
        case flap, led, pixel, plain

        var title: String {
            switch self {
            case .flap: return "Flap"
            case .led: return "LED"
            case .pixel: return "Pixel"
            case .plain: return "Plain"
            }
        }

        var cellStyle: CellStyle {
            switch self {
            case .flap: return .flap
            case .led: return .dots(.round)
            case .pixel: return .dots(.square)
            case .plain: return .plain
            }
        }

        /// Cell sizes each display is designed at, before a preset's scale is applied.
        var metrics: FlapMetrics {
            switch self {
            case .flap: return FlapMetrics()
            case .led: return FlapMetrics(fontSize: 12, cellWidth: 10, cellHeight: 14, cellSpacing: 2.5)
            case .pixel: return FlapMetrics(fontSize: 12, cellWidth: 10, cellHeight: 14, cellSpacing: 2)
            case .plain: return FlapMetrics(fontSize: 13, cellWidth: 8, cellHeight: 17, cellSpacing: 0)
            }
        }

        var isMatrix: Bool { self == .led || self == .pixel }
    }

    enum Accent: String, CaseIterable {
        case amber, yellow, green, cyan, red, white

        var title: String { rawValue.capitalized }

        var color: Color {
            switch self {
            case .amber: return Color(red: 0.961, green: 0.729, blue: 0.290)
            case .yellow: return Color(red: 1.0, green: 0.851, blue: 0.0)
            case .green: return Color(red: 0.494, green: 0.949, blue: 0.604)
            case .cyan: return Color(red: 0.302, green: 0.851, blue: 1.0)
            case .red: return Color(red: 1.0, green: 0.353, blue: 0.310)
            case .white: return Color(white: 0.95)
            }
        }
    }

    var display: Display {
        switch cellStyle {
        case .flap: return .flap
        case .dots(.round): return .led
        case .dots(.square): return .pixel
        case .plain: return .plain
        }
    }

    /// This preset with the user's settings applied. A nil override keeps the preset's own.
    func customised(display: Display?, accent: Accent?, showsSeconds: Bool) -> BoardTheme {
        var theme = self
        theme.showsSeconds = showsSeconds
        if let accent {
            theme.accent = accent.color
            if labelFollowsAccent { theme.label = accent.color.opacity(0.85) }
        }
        if let display, display != self.display {
            theme.switchDisplay(to: display)
        }
        return theme
    }

    /// Redraws a preset in another display, keeping its palette and relative size.
    private mutating func switchDisplay(to display: Display) {
        let from = self.display
        let scale = metrics.fontSize / from.metrics.fontSize
        let base = display.metrics
        metrics = FlapMetrics(
            fontSize: base.fontSize * scale,
            cellWidth: base.cellWidth * scale,
            // Whole half-points keep flap halves on pixel boundaries at 2x.
            cellHeight: (base.cellHeight * scale * 2).rounded() / 2,
            cellSpacing: base.cellSpacing * scale
        )
        cellStyle = display.cellStyle

        if from.isMatrix && !display.isMatrix {
            // LED presets use a sans for labels; text cells read better in mono.
            typeface = .mono
            glyphWeight = .medium
        }
        if display == .flap && from != .flap {
            // Tiles must be opaque: the falling flap hides the next glyph behind it.
            tileTop = Self.blend(board, white: 0.12)
            tileBottom = Self.blend(board, white: 0.095)
        }
        if display.isMatrix && !from.isMatrix {
            unlitDot = ink.opacity(0.08)
        }
    }

    private static func blend(_ color: Color, white fraction: CGFloat) -> Color {
        let base = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return Color(nsColor: base.blended(withFraction: fraction, of: .white) ?? base)
    }
}
