import AppKit
import SwiftUI

struct BoardRow: View {
    let entry: BoardEntry
    /// Shows GATE as OPEN without hovering, for static boards.
    var previewsOpen = false
    var onTerminate: () -> Void
    var onForceQuit: () -> Void
    var onCancelForceQuit: () -> Void

    @State private var isHovering = false
    @State private var isHoveringGate = false
    /// Set on the first hover over GATE, after it has flipped in with the row.
    @State private var gateFlipsQuietly = false
    @Environment(\.flapStartsSettled) private var isStaticRender
    @Environment(\.boardTheme) private var theme
    @Environment(\.openURL) private var openURL

    private static let openText = "OPEN\(FlapGlyphs.openArrow)"

    private var showsOpen: Bool {
        entry.url != nil && (isHoveringGate || previewsOpen)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            RowLayout(
                gate: entry.isClearing ? "" : showsOpen ? Self.openText : entry.process.port.map(String.init) ?? "--",
                flight: entry.isClearing ? "" : flight,
                pid: entry.isClearing ? "" : String(entry.pid),
                status: entry.status,
                time: entry.isClearing ? "" : Self.uptime(context.date.timeIntervalSince(entry.startedAt), seconds: theme.showsSeconds),
                statusColor: statusColor,
                dimmed: !entry.isLive,
                gateInverted: showsOpen,
                gateFlipsQuietly: gateFlipsQuietly
            )
        }
        .padding(.vertical, theme.rowPadding)
        .boardRule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .overlay(alignment: .trailing) { control }
        .overlay(alignment: .leading) { openControl }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(isHovering && entry.isLive ? 0.035 : 0))
                .padding(.horizontal, -6)
        )
        .background {
            if !isStaticRender { HoverTracker(isHovering: $isHovering) }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var flight: String {
        entry.process.destination.isEmpty
            ? entry.process.label
            : "\(entry.process.label) \(entry.process.destination)"
    }

    private var statusColor: Color {
        let colors = theme.statusColors
        switch entry.phase {
        case .boarding: return colors?.boarding ?? theme.accent
        case .closing, .delayed, .denied: return colors?.warning ?? theme.accent
        case .active:
            let running = colors?.running ?? theme.ink
            return entry.isIdle ? running.opacity(0.5) : running
        case .departed, .clearing: return colors?.departed ?? theme.ink.opacity(0.6)
        }
    }

    @ViewBuilder
    private var control: some View {
        if entry.phase == .delayed {
            ForceQuitPrompt(onForceQuit: onForceQuit, onCancel: onCancelForceQuit)
        } else if entry.canTerminate && isHovering {
            Button(action: onTerminate) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.board)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(theme.accent))
                    .frame(width: BoardColumn.controlWidth, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop process (SIGTERM)")
            .accessibilityLabel("Stop \(entry.process.label)")
            .transition(.opacity)
        }
    }

    /// Covers GATE: hovering flips it to OPEN, clicking opens the page.
    @ViewBuilder
    private var openControl: some View {
        if let url = entry.url {
            Color.clear
                .frame(width: theme.metrics.width(ofCells: theme.cells(.gate)))
                .contentShape(Rectangle())
                // A tap, not a button, so a drag that starts here still moves the board.
                .onTapGesture { openURL(url) }
                .background {
                    if !isStaticRender { HoverTracker(isHovering: $isHoveringGate) }
                }
                .onChange(of: isHoveringGate) { hovering in
                    if hovering { gateFlipsQuietly = true }
                }
                .onDisappear { isHoveringGate = false }
                .accessibilityElement()
                .accessibilityLabel("Open \(entry.process.label) in browser")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { openURL(url) }
        }
    }

    private var accessibilityText: String {
        let gate = entry.process.port.map { "port \($0)" } ?? "no port"
        return "\(entry.process.label) \(entry.process.destination), \(gate), process \(entry.pid), \(entry.status.lowercased()), up \(Self.uptime(entry.process.uptime))"
    }

    /// Uptime as `hh:mm:ss`, or `hh:mm` without seconds, capped at 99 hours.
    static func uptime(_ seconds: TimeInterval, seconds showsSeconds: Bool = true) -> String {
        let total = min(max(Int(seconds), 0), 99 * 3600 + 59 * 60 + 59)
        return showsSeconds
            ? String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 3600, total / 60 % 60)
    }
}

/// Shown when a process survives SIGTERM. Nothing escalates without this confirmation.
private struct ForceQuitPrompt: View {
    var onForceQuit: () -> Void
    var onCancel: () -> Void

    @Environment(\.boardTheme) private var theme

    /// TIME, the control column, and STATUS's last cell, which is always blank here:
    /// kill statuses are at most 7 letters in an 8-cell column. DELAYED stays readable.
    private var coveredWidth: CGFloat {
        theme.metrics.width(ofCells: theme.cells(.time)) + BoardColumn.gap + BoardColumn.controlWidth
            + BoardColumn.gap + theme.metrics.cellWidth
    }

    var body: some View {
        // Narrow boards (small sizes, no seconds) get the short label.
        ViewThatFits(in: .horizontal) {
            buttons(label: "Force quit")
            buttons(label: "Force")
        }
        .font(.system(size: 10.5, weight: .semibold))
        .frame(width: coveredWidth, alignment: .trailing)
        .padding(.vertical, 1)
        .background(theme.board)
        .transition(.opacity)
    }
}

extension ForceQuitPrompt {
    private func buttons(label: String) -> some View {
        HStack(spacing: 4) {
            Button(label, action: onForceQuit)
                .buttonStyle(PromptButtonStyle(prominent: true))
                .help("Force quit (SIGKILL)")
                .accessibilityLabel("Force quit")
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 10, height: 13)
            }
            .buttonStyle(PromptButtonStyle(prominent: false, compact: true))
            .help("Cancel")
            .accessibilityLabel("Cancel")
        }
        .fixedSize()
    }
}

private struct PromptButtonStyle: ButtonStyle {
    let prominent: Bool
    var compact = false

    @Environment(\.boardTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? theme.board : theme.ink)
            .padding(.horizontal, compact ? 3 : 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(prominent ? theme.accent : Color.white.opacity(0.1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
