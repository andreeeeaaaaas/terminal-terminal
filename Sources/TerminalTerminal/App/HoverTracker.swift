import AppKit
import SwiftUI

/// Hover tracking with an `.activeAlways` tracking area, so hover works while the app is
/// inactive, which this app's non-activating panels always leave it. Use as a `.background`.
/// With a `cursor`, shows it while hovering.
struct HoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool
    var cursor: NSCursor?

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = { isHovering = $0 }
        view.cursor = cursor
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) {
        view.leave()
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        var cursor: NSCursor?

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
            if window == nil { leave() }
        }

        /// Ends a hover without reporting it, for a view that's going away.
        func leave() {
            if isInside, cursor != nil { NSCursor.arrow.set() }
            isInside = false
            stopExitCheck()
        }

        override func mouseEntered(with event: NSEvent) { setInside(true) }
        override func mouseExited(with event: NSEvent) { setInside(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func setInside(_ inside: Bool) {
            guard inside != isInside else { return }
            isInside = inside
            onChange?(inside)
            stopExitCheck()
            if cursor != nil {
                BackgroundCursor.enable()
                (inside ? cursor : .arrow)?.set()
            }
            guard inside else { return }
            exitCheck = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { return timer.invalidate() }
                    self.checkForExit()
                }
            }
        }

        private func checkForExit() {
            guard isInside else { return }
            guard containsMouse else { return setInside(false) }
            // The app underneath can reset the pointer as it moves, so keep it set.
            cursor?.set()
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

/// macOS ignores pointer changes from an app that isn't active, and this one never is. A
/// private CoreGraphics connection property lifts that. It's undocumented, so it's looked up
/// at runtime: if a future macOS drops it, the pointer just stays an arrow.
private enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static let enabled: Void = {
        guard let connection = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection"),
              let setProperty = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetConnectionProperty") else { return }
        let id = unsafeBitCast(connection, to: DefaultConnection.self)()
        _ = unsafeBitCast(setProperty, to: SetConnectionProperty.self)(id, id, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }()

    static func enable() { enabled }
}

