import AppKit
import SwiftUI

/// Hover tracking with an `.activeAlways` tracking area, so hover works while the app is
/// inactive, which this app's non-activating panels always leave it. Use as a `.background`.
struct HoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = { isHovering = $0 }
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = { isHovering = $0 }
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        private var isInside = false
        /// Runs while hovering. AppKit can drop `mouseExited` for an inactive app's window when
        /// the cursor leaves it in one fast move, or when the area is replaced or the window
        /// moves under a still cursor, so this checks the cursor itself.
        private var exitCheck: Timer?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
            // Removing an area never sends its exit.
            checkForExit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopExitCheck() }
        }

        override func mouseEntered(with event: NSEvent) { setInside(true) }
        override func mouseExited(with event: NSEvent) { setInside(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func setInside(_ inside: Bool) {
            guard inside != isInside else { return }
            isInside = inside
            onChange?(inside)
            stopExitCheck()
            guard inside else { return }
            exitCheck = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { return timer.invalidate() }
                    self.checkForExit()
                }
            }
        }

        private func checkForExit() {
            guard isInside, !containsMouse else { return }
            setInside(false)
        }

        private var containsMouse: Bool {
            guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return false }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return visibleRect.contains(point)
        }

        private func stopExitCheck() {
            exitCheck?.invalidate()
            exitCheck = nil
        }
    }
}
