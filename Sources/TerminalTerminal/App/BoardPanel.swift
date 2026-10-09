import AppKit
import SwiftUI

/// A borderless, non-activating, always-on-top panel. Clicking it never takes focus
/// from the app you're working in.
final class BoardPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Places, sizes and shows the board panel, and remembers where the user dragged it.
@MainActor
final class BoardPanelController {
    let panel = BoardPanel()

    private let defaults: UserDefaults
    private var isMovingProgrammatically = false
    private var hasPlaced = false
    private var pendingShrink: DispatchWorkItem?
    private var moveObserver: NSObjectProtocol?
    /// Mouse location and panel origin when the current drag began, in screen coordinates.
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    private static let positionKey = "boardTopLeft"
    private static let topInset: CGFloat = 10

    init<Content: View>(defaults: UserDefaults = .standard, @ViewBuilder content: (BoardPanelController) -> Content) {
        self.defaults = defaults
        let root = content(self)
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.preference(key: BoardSizeKey.self, value: proxy.size)
            })
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { [weak self] _ in MainActor.assumeIsolated { self?.dragChanged() } }
                    .onEnded { [weak self] _ in MainActor.assumeIsolated { self?.dragEnded() } }
            )
            .onPreferenceChange(BoardSizeKey.self) { [weak self] size in
                MainActor.assumeIsolated { self?.resize(to: size) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        let hosting = FirstMouseHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        panel.contentView = hosting

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelDidMove() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        if !hasPlaced { place() }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func resetPosition() {
        defaults.removeObject(forKey: Self.positionKey)
        place()
    }

    /// Keeps the top-left corner fixed so the board grows and shrinks downward. Shrinks wait
    /// for row-collapse animations to finish so the content isn't clipped mid-animation.
    func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        pendingShrink?.cancel()
        let frame = panel.frame
        let apply = { [weak self] in
            guard let self else { return }
            let top = self.panel.frame.maxY
            self.setFrame(NSRect(x: self.panel.frame.minX, y: top - size.height, width: size.width, height: size.height))
            if !self.hasPlaced { self.place() }
        }
        if size.height < frame.height, hasPlaced {
            let work = DispatchWorkItem(block: apply)
            pendingShrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        } else {
            apply()
        }
    }

    /// Moves the panel with the mouse. Uses screen coordinates from `NSEvent` rather than the
    /// gesture's, which are relative to a view that is itself moving.
    private func dragChanged() {
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (mouse, panel.frame.origin)
        dragStart = start
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    private func dragEnded() {
        dragStart = nil
    }

    private func place() {
        let size = panel.frame.size
        let topLeft = savedTopLeft() ?? defaultTopLeft(for: size)
        setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height))
        hasPlaced = true
    }

    private func setFrame(_ frame: NSRect) {
        isMovingProgrammatically = true
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        isMovingProgrammatically = false
    }

    private func panelDidMove() {
        guard !isMovingProgrammatically, hasPlaced else { return }
        let frame = panel.frame
        defaults.set(["x": frame.minX, "y": frame.maxY], forKey: Self.positionKey)
    }

    private func savedTopLeft() -> NSPoint? {
        guard let stored = defaults.dictionary(forKey: Self.positionKey) as? [String: CGFloat],
              let x = stored["x"], let y = stored["y"] else { return nil }
        let point = NSPoint(x: x, y: y)
        // Ignore positions on a display that's no longer connected.
        let onScreen = NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: x + 40, y: y - 10)) }
        return onScreen ? point : nil
    }

    private func defaultTopLeft(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - Self.topInset)
    }
}

private struct BoardSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    /// Views that don't report a size contribute the zero default; don't let them win.
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Lets buttons on the board respond to the first click, without the panel becoming key first.
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
