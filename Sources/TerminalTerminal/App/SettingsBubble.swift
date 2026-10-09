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

    /// False as soon as closing starts, even while the closing animation runs.
    private(set) var isShown = false

    /// Shows the bubble pointing at `anchor`, a rect in screen coordinates.
    func show(pointingAt anchor: NSRect) {
        isShown = true
        withoutAnimation { layout.isPresented = false }
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
        // Grow out of the arrow, like a system popover. Reduce Motion fades only.
        DispatchQueue.main.async { [layout] in
            withAnimation(Self.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.24, dampingFraction: 0.82)) {
                layout.isPresented = true
            }
        }
    }

    func close() {
        guard isShown else { return }
        isShown = false
        withAnimation(.easeIn(duration: 0.12)) { layout.isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        }
        onClose()
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
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
    /// Drives the open and close animation.
    @Published var isPresented = false
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
            .background { BubbleSurface(shape: shape) }
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.preference(key: BubbleWidthKey.self, value: proxy.size.width)
            })
            .onPreferenceChange(BubbleWidthKey.self) { width = $0 }
            .scaleEffect(layout.isPresented ? 1 : 0.94, anchor: arrowAnchor)
            .opacity(layout.isPresented ? 1 : 0)
    }

    @State private var width: CGFloat = 1

    /// Where the arrow tip is, so the bubble grows out of it.
    private var arrowAnchor: UnitPoint {
        UnitPoint(x: min(max(layout.arrowX / max(width, 1), 0), 1), y: layout.arrowOnTop ? 0 : 1)
    }
}

private struct BubbleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Liquid Glass on macOS 26 and later; the classic popover vibrancy before that.
private struct BubbleSurface: View {
    let shape: BubbleShape

    var body: some View {
        if #available(macOS 26, *) {
            // Tinted toward the window colour (light or dark), so controls keep their contrast
            // over bright wallpapers, as system popovers do.
            Color.clear.glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.55)), in: shape)
        } else {
            VibrantBackground(shape: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

/// `NSVisualEffectView` blurring the desktop behind the window, masked to the bubble shape.
/// A mask image is needed: behind-window blur ignores SwiftUI clipping.
private struct VibrantBackground: NSViewRepresentable {
    let shape: BubbleShape

    func makeNSView(context: Context) -> MaskedEffectView {
        let view = MaskedEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.shape = shape
        return view
    }

    func updateNSView(_ view: MaskedEffectView, context: Context) {
        view.shape = shape
    }

    final class MaskedEffectView: NSVisualEffectView {
        var shape: BubbleShape? {
            didSet { needsLayout = true }
        }

        override func layout() {
            super.layout()
            guard let shape, bounds.width > 0, bounds.height > 0 else { return }
            let rect = CGRect(origin: .zero, size: bounds.size)
            maskImage = NSImage(size: bounds.size, flipped: true) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(shape.path(in: rect).cgPath)
                context.setFillColor(.black)
                context.fillPath()
                return true
            }
        }
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
