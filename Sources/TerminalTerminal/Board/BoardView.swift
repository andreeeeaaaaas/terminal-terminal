import AppKit
import SwiftUI

/// Column widths in flap cells.
enum BoardColumn: CaseIterable {
    case gate, flight, pid, status, time

    var title: String {
        switch self {
        case .gate: return "GATE"
        case .flight: return "FLIGHT"
        case .status: return "STATUS"
        case .pid: return "PID"
        case .time: return "TIME"
        }
    }

    var cells: Int {
        switch self {
        case .gate: return 5
        case .flight: return 16
        case .pid: return 5
        case .status: return 8
        case .time: return 8
        }
    }

    var alignment: HorizontalAlignment {
        switch self {
        case .pid: return .trailing
        default: return .leading
        }
    }

    static let gap: CGFloat = 10
    /// Space reserved at the end of each row for the kill control.
    static let controlWidth: CGFloat = 18
}

struct BoardView: View {
    @ObservedObject var model: BoardModel
    /// Receives a view behind the gear button, to anchor the settings popover on.
    var onOpenSettings: (NSView) -> Void = { _ in }
    var onHide: () -> Void = {}

    @Environment(\.boardTheme) private var theme

    /// A real board never shrinks to nothing: empty slots stay as blank tiles.
    static let minimumRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if theme.showsTitle {
                TitleBar(onOpenSettings: onOpenSettings, onHide: onHide)
                    .padding(.bottom, 12)
            }
            ColumnHeader(onOpenSettings: onOpenSettings, onHide: onHide)
                .padding(.bottom, theme.showsTitle ? 6 : 4)
                .boardRule()
            ForEach(model.entries) { entry in
                BoardRow(
                    entry: entry,
                    previewsOpen: model.previewsOpen.contains(entry.pid),
                    onTerminate: { model.terminate(entry.id) },
                    onForceQuit: { model.forceQuit(entry.id) },
                    onCancelForceQuit: { model.cancelForceQuit(entry.id) }
                )
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
            ForEach(0..<max(Self.minimumRows - model.entries.count, 0), id: \.self) { _ in
                BlankRow()
                    .transition(.identity)
            }
        }
        .padding(.horizontal, theme.showsTitle ? 16 : 12)
        .padding(.top, theme.showsTitle ? 14 : 9)
        .padding(.bottom, theme.showsTitle ? 12 : 9)
        .background(theme.board)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .strokeBorder(theme.boardEdge, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

private struct TitleBar: View {
    var onOpenSettings: (NSView) -> Void
    var onHide: () -> Void

    @Environment(\.boardTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text("TERMINAL, TERMINAL!")
                .font(theme.font(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(theme.accent)
            Spacer(minLength: 12)
            BoardButtons(onOpenSettings: onOpenSettings, onHide: onHide)
        }
    }
}

/// Settings and hide, at the board's right edge. The minimise button sits over the
/// kill-control gutter, in line with each row's ×.
private struct BoardButtons: View {
    var onOpenSettings: (NSView) -> Void
    var onHide: () -> Void

    @State private var anchor = AnchorBox()
    @Environment(\.flapStartsSettled) private var isStaticRender

    var body: some View {
        HStack(spacing: 2) {
            TitleButton(symbol: "gearshape.fill", label: "Settings") {
                if let view = anchor.view { onOpenSettings(view) }
            }
            .background {
                if !isStaticRender { PopoverAnchor(box: anchor) }
            }
            TitleButton(symbol: "minus", label: "Hide board", help: "Hide board. Click the menu bar plane to bring it back.", action: onHide)
        }
    }
}

/// Holds the AppKit view behind the gear, so AppKit can position the popover on it directly.
private final class AnchorBox {
    weak var view: NSView?
}

private struct PopoverAnchor: NSViewRepresentable {
    let box: AnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    /// Never takes clicks: the gear button above it handles them.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct TitleButton: View {
    let symbol: String
    let label: String
    var help: String?
    let action: () -> Void

    @Environment(\.boardTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.label)
                .frame(width: BoardColumn.controlWidth, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

/// Column titles. Without a title bar, the board's buttons sit at the end of this row.
private struct ColumnHeader: View {
    var onOpenSettings: (NSView) -> Void
    var onHide: () -> Void

    @Environment(\.boardTheme) private var theme

    var body: some View {
        HStack(spacing: BoardColumn.gap) {
            ForEach(BoardColumn.allCases, id: \.self) { column in
                Text(column.title)
                    .font(theme.font(size: 9.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(theme.label)
                    .frame(
                        width: theme.metrics.width(ofCells: theme.cells(column)),
                        alignment: column.alignment == .trailing ? .trailing : .leading
                    )
                    .accessibilityHidden(true)
            }
            if theme.showsTitle {
                Color.clear.frame(width: BoardColumn.controlWidth, height: 1)
            } else {
                BoardButtons(onOpenSettings: onOpenSettings, onHide: onHide)
            }
        }
    }
}

/// An empty slot: blank tiles under each column.
private struct BlankRow: View {
    @Environment(\.boardTheme) private var theme

    var body: some View {
        RowLayout(gate: "", flight: "", pid: "", status: "", time: "")
            .padding(.vertical, theme.rowPadding)
            .boardRule()
            .accessibilityHidden(true)
    }
}

/// The five fields of a row, laid out to match `ColumnHeader`.
struct RowLayout: View {
    let gate: String
    let flight: String
    let pid: String
    let status: String
    let time: String
    /// Defaults to the theme's ink.
    var statusColor: Color?
    /// Departing rows fade their text.
    var dimmed = false
    /// GATE on accent tiles, while it reads OPEN.
    var gateInverted = false
    /// GATE flips straight to new text, still rippling: hover feedback shouldn't lag.
    var gateFlipsQuietly = false

    @Environment(\.boardTheme) private var theme

    var body: some View {
        HStack(spacing: BoardColumn.gap) {
            field(gate, .gate, scrambles: !gateFlipsQuietly, inverted: gateInverted)
            field(flight, .flight)
            field(pid, .pid)
            SplitFlapText(text: status, width: theme.cells(.status), color: statusColor)
            field(time, .time, scrambles: false)
            Color.clear.frame(width: BoardColumn.controlWidth, height: 1)
        }
    }

    private func field(_ text: String, _ column: BoardColumn, scrambles: Bool = true, inverted: Bool = false) -> some View {
        let ink = theme.columnInk[column] ?? theme.ink
        return SplitFlapText(
            text: text,
            width: theme.cells(column),
            alignment: column.alignment,
            color: dimmed ? ink.opacity(0.6) : ink,
            scrambles: scrambles,
            ripples: column != .time,
            inverted: inverted
        )
    }
}

extension View {
    /// A hairline under the view when the theme draws ruled rows.
    func boardRule() -> some View {
        modifier(BoardRule())
    }
}

private struct BoardRule: ViewModifier {
    @Environment(\.boardTheme) private var theme

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let rule = theme.rule {
                Rectangle()
                    .fill(rule)
                    .frame(height: 0.5)
                    .padding(.horizontal, -4)
            }
        }
    }
}
