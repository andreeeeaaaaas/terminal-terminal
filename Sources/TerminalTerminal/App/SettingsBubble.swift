import AppKit
import SwiftUI

/// A popover-style panel for settings, positioned by hand. `NSPopover` misplaces itself when
/// anchored to a view in a floating panel near the bottom of the screen, so this replaces it:
/// below the anchor when there's room, above it otherwise, with the arrow on the anchor.
@MainActor
final class SettingsBubble {
    let panel: NSPanel
    var onClose: () -> Void = {}

    private let layout = BubbleLayout()
    private let hosting: NSHostingView<AnyView>

    private static let gap: CGFloat = 2
    private static let screenMargin: CGFloat = 8

    init<Content: View>(@ViewBuilder content: () -> Content) {
        panel = BubblePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        hosting = NSHostingView(rootView: AnyView(Bubble(layout: layout, content: content())))
        panel.contentView = hosting
    }

    var isShown: Bool { panel.isVisible }

    /// Shows the bubble pointing at `anchor`, a rect in screen coordinates.
    func show(pointingAt anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor.insetBy(dx: -1000, dy: -1000)

        // Measure with the arrow on top, then flip if it doesn't fit below.
        layout.arrowOnTop = true
        let size = hosting.fittingSize
        let roomBelow = anchor.minY - Self.gap - visible.minY
        let roomAbove = visible.maxY - anchor.maxY - Self.gap
        layout.arrowOnTop = roomBelow >= size.height || roomBelow >= roomAbove

        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + Self.screenMargin), visible.maxX - Self.screenMargin - size.width)
        let y = layout.arrowOnTop ? anchor.minY - Self.gap - size.height : anchor.maxY + Self.gap
        layout.arrowX = anchor.midX - x

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        onClose()
    }
}

/// Can become key so Escape and ⌘Q reach the settings, without activating the app.
private final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BubbleLayout: ObservableObject {
    @Published var arrowOnTop = true
    /// The arrow tip's x position from the bubble's left edge.
    @Published var arrowX: CGFloat = 150
}

private struct Bubble<Content: View>: View {
    @ObservedObject var layout: BubbleLayout
    let content: Content

    static var arrowHeight: CGFloat { 9 }

    var body: some View {
        let shape = BubbleShape(arrowOnTop: layout.arrowOnTop, arrowX: layout.arrowX, arrowHeight: Self.arrowHeight)
        content
            .padding(.top, layout.arrowOnTop ? Self.arrowHeight : 0)
            .padding(.bottom, layout.arrowOnTop ? 0 : Self.arrowHeight)
            .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            .fixedSize()
    }
}

/// A rounded rectangle with a triangular arrow on its top or bottom edge.
private struct BubbleShape: Shape {
    let arrowOnTop: Bool
    let arrowX: CGFloat
    let arrowHeight: CGFloat
    var radius: CGFloat = 10
    var arrowHalfWidth: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let body = arrowOnTop
            ? CGRect(x: rect.minX, y: rect.minY + arrowHeight, width: rect.width, height: rect.height - arrowHeight)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - arrowHeight)
        let tipX = min(max(arrowX, body.minX + radius + arrowHalfWidth), body.maxX - radius - arrowHalfWidth)
        let baseY = arrowOnTop ? body.minY : body.maxY
        let tipY = arrowOnTop ? rect.minY : rect.maxY

        // Trace the outline clockwise so the arrow joins the body without an inner seam.
        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if arrowOnTop {
            path.addLine(to: CGPoint(x: tipX - arrowHalfWidth, y: baseY))
            path.addLine(to: CGPoint(x: tipX, y: tipY))
            path.addLine(to: CGPoint(x: tipX + arrowHalfWidth, y: baseY))
        }
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: radius)
        if !arrowOnTop {
            path.addLine(to: CGPoint(x: tipX + arrowHalfWidth, y: baseY))
            path.addLine(to: CGPoint(x: tipX, y: tipY))
            path.addLine(to: CGPoint(x: tipX - arrowHalfWidth, y: baseY))
        }
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}
