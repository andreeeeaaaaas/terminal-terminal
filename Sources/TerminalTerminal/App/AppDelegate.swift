import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let model: BoardModel
    private let demo: Demo?
    private var boardController: BoardPanelController!
    private var statusItem: NSStatusItem!
    /// Built on first open: it's hidden at launch, when the board is busy flipping in.
    private lazy var settingsBubble = makeSettingsBubble()
    private var settingsObservers: [AnyCancellable] = []
    /// Click and key monitors that close settings, only while it's open.
    private var settingsMonitors: [Any] = []
    /// When settings last closed. A click on the gear that closes it shouldn't reopen it.
    private var settingsClosedAt = Date.distantPast

    /// What the settings bubble points at.
    private enum SettingsAnchor {
        case statusItem
        /// A view behind the board's gear button.
        case board(NSView)
    }

    /// With a demo, takes commands on stdin against a fake process table, and quits when it closes.
    init(demo: Demo? = nil) {
        self.demo = demo
        settings = demo.map { Settings(defaults: $0.defaults) } ?? Settings()
        model = BoardModel(settings: settings, source: demo?.processes ?? ProcessScanner())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        boardController = BoardPanelController(defaults: demo?.defaults ?? .standard) { [unowned self] _ in
            ThemedBoard(
                model: model,
                settings: settings,
                opensLinks: demo == nil,
                waitsForFirstScan: demo == nil,
                onOpenSettings: { [unowned self] gear in showSettings(from: .board(gear)) },
                onHide: { [unowned self] in boardController.hide() }
            )
        }

        setUpStatusItem()

        model.onArrival = { [unowned self] isFirst in
            if isFirst || settings.showOnArrival { boardController.show() }
        }
        if let demo {
            boardController.show()
            Task { [model] in
                await demo.run(model: model, settings: settings)
                NSApp.terminate(nil)
            }
        } else {
            // Show once the first scan lands, so the board appears whole, flipping in header
            // and rows together, instead of blank and then growing a moment later.
            model.onFirstScan = { [unowned self] in boardController.show() }
            model.start()
        }

        settingsObservers.append(settings.$showAllPorts.dropFirst().sink { [unowned self] _ in
            model.refresh(quiet: true)
        })
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "airplane.departure", accessibilityDescription: "Terminal Terminal")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Terminal Terminal: click to show or hide, ⌘-click for settings"
    }

    private func makeSettingsBubble() -> SettingsBubble {
        let bubble = SettingsBubble { [unowned self] in
            SettingsView(
                settings: settings,
                onResetPosition: { [unowned self] in
                    boardController.resetPosition()
                    boardController.show()
                },
                onQuit: { NSApp.terminate(nil) }
            )
        }
        bubble.onClose = { [unowned self] in
            settingsClosedAt = Date()
            stopWatchingForDismissal()
        }
        return bubble
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.command) == true {
            showSettings(from: .statusItem)
        } else {
            boardController.toggle()
        }
    }

    private func showSettings(from anchor: SettingsAnchor) {
        if settingsBubble.isShown {
            settingsBubble.close()
            return
        }
        // The click that closed it (via the outside-click monitor) is also this toggle's click.
        guard Date().timeIntervalSince(settingsClosedAt) > 0.3 else { return }

        let view: NSView
        switch anchor {
        case .statusItem:
            guard let button = statusItem.button else { return }
            view = button
        case .board(let gear):
            view = gear
        }
        guard let window = view.window else { return }
        settingsBubble.show(pointingAt: window.convertToScreen(view.convert(view.bounds, to: nil)))
        watchForDismissal()
    }

    /// Closes settings on any click outside it (in another app or on the board) and on Escape.
    private func watchForDismissal() {
        stopWatchingForDismissal()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsBubble.close() }
        }) {
            settingsMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if event.type == .keyDown {
                    guard event.keyCode == 53 else { return false } // Escape
                    self.settingsBubble.close()
                    return true
                }
                // The status item handles its own clicks: it toggles settings.
                if event.window !== self.settingsBubble.panel, event.window !== self.statusItem.button?.window {
                    self.settingsBubble.close()
                }
                return false
            }
            return swallow ? nil : event
        }) {
            settingsMonitors.append(local)
        }
    }

    private func stopWatchingForDismissal() {
        settingsMonitors.forEach(NSEvent.removeMonitor)
        settingsMonitors.removeAll()
    }
}

/// The board in the style chosen in settings.
private struct ThemedBoard: View {
    @ObservedObject var model: BoardModel
    @ObservedObject var settings: Settings
    /// False in demos, whose ports are made up.
    var opensLinks: Bool
    /// Renders nothing until the first scan, so the board's cells don't start flipping unseen.
    var waitsForFirstScan: Bool
    var onOpenSettings: (NSView) -> Void
    var onHide: () -> Void

    var body: some View {
        if model.hasScanned || !waitsForFirstScan {
            BoardView(model: model, onOpenSettings: onOpenSettings, onHide: onHide)
                .environment(\.boardTheme, settings.theme)
                .environment(\.openURL, OpenURLAction { [opensLinks] _ in opensLinks ? .systemAction : .handled })
        }
    }
}
