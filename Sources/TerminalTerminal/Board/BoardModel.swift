import Foundation
import SwiftUI

struct BoardEntry: Identifiable, Equatable {
    enum Phase: Equatable {
        case boarding(until: Date)
        case active
        /// SIGTERM sent; waiting to see if the process exits.
        case closing(since: Date)
        /// Survived SIGTERM. Waiting for the user to confirm SIGKILL.
        case delayed
        /// The signal was refused (not our process).
        case denied(until: Date)
        case departed(since: Date)
        /// Every field flips to blank before the row collapses.
        case clearing(since: Date)
    }

    let id = UUID()
    var process: ScannedProcess
    var phase: Phase
    var lastActive: Date
    var isIdle = false
    /// When the process started, fixed at first sight so the ticking uptime doesn't jitter
    /// with each scan's rounding.
    var startedAt: Date

    var pid: Int32 { process.pid }

    var isLive: Bool {
        switch phase {
        case .departed, .clearing: return false
        default: return true
        }
    }

    var isClearing: Bool {
        if case .clearing = phase { return true }
        return false
    }

    /// A web server's page, while the row is live.
    var url: URL? {
        guard isLive, process.isWebServer, let port = process.port else { return nil }
        return URL(string: "http://\(process.host ?? "localhost"):\(port)")
    }

    var canTerminate: Bool {
        switch phase {
        case .boarding, .active, .denied: return true
        default: return false
        }
    }

    var status: String {
        switch phase {
        case .boarding: return "BOARDING"
        case .active: return isIdle ? "IDLE" : "RUNNING"
        case .closing: return "CLOSING"
        case .delayed: return "DELAYED"
        case .denied: return "DENIED"
        case .departed: return "DEPARTED"
        case .clearing: return ""
        }
    }
}

/// Polls the scanner, diffs results into board rows, and runs each row through its
/// arrival and departure phases.
@MainActor
final class BoardModel: ObservableObject {
    @Published private(set) var entries: [BoardEntry] = []
    /// PIDs whose GATE shows OPEN in a static board, as if hovered.
    private(set) var previewsOpen: Set<Int32> = []

    /// Called when new rows arrive after launch, with whether the board had no live rows before.
    /// Not called for rows that appear because a setting changed.
    var onArrival: ((_ isFirst: Bool) -> Void)?

    static let boardingDuration: TimeInterval = 5
    static let departedHold: TimeInterval = 4
    static let clearingDuration: TimeInterval = 1.4
    static let terminateGrace: TimeInterval = 3
    static let idleAfter: TimeInterval = 60
    /// `ps` %CPU at or above this counts as activity.
    static let activeCPU = 0.5

    private let settings: Settings
    private let source: ProcessSource
    private var loop: Task<Void, Never>?
    private var isScanning = false
    private var lastScan = Date.distantPast
    private var hasScanned = false
    /// After a filter change, rows that drop out collapse without a departure.
    private var quietNextScan = false

    init(settings: Settings, source: ProcessSource = ProcessScanner()) {
        self.settings = settings
        self.source = source
    }

    /// A static board for snapshots.
    init(settings: Settings, preview processes: [ScannedProcess], idle: Set<Int32> = [], delayed: Set<Int32> = [], boarding: Set<Int32> = [], departed: Set<Int32> = [], open: Set<Int32> = []) {
        self.settings = settings
        source = ProcessScanner()
        previewsOpen = open
        entries = processes.map {
            BoardEntry(
                process: $0,
                phase: delayed.contains($0.pid) ? .delayed
                    : boarding.contains($0.pid) ? .boarding(until: .distantFuture)
                    : departed.contains($0.pid) ? .departed(since: .distantFuture) : .active,
                lastActive: Date(),
                isIdle: idle.contains($0.pid),
                startedAt: Date() - $0.uptime
            )
        }
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    /// Rescan now, e.g. after a settings change.
    func refresh(quiet: Bool = false) {
        quietNextScan = quiet
        lastScan = .distantPast
    }

    private func tick() {
        advancePhases()
        if !isScanning, Date().timeIntervalSince(lastScan) >= settings.pollInterval {
            Task { await scan() }
        }
    }

    private func scan() async {
        isScanning = true
        let showAll = settings.showAllPorts
        let source = source
        let results = await Task.detached(priority: .utility) {
            source.scan(showAll: showAll)
        }.value
        lastScan = Date()
        isScanning = false
        apply(results)
    }

    // MARK: - Diffing

    private func apply(_ results: [ScannedProcess]) {
        let now = Date()
        let wasEmpty = !entries.contains(where: \.isLive)
        let isQuiet = quietNextScan
        var unmatched = Dictionary(results.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var updated = entries

        for index in updated.indices where updated[index].isLive {
            let entry = updated[index]
            if let process = unmatched[entry.pid], process.command == entry.process.command {
                unmatched[entry.pid] = nil
                updated[index].process = process
                if process.cpu >= Self.activeCPU { updated[index].lastActive = now }
                updated[index].isIdle = now.timeIntervalSince(updated[index].lastActive) >= Self.idleAfter
            } else {
                updated[index].phase = .departed(since: now)
            }
        }

        if quietNextScan {
            updated.removeAll { entry in
                guard case .departed(let since) = entry.phase else { return false }
                return since == now
            }
            quietNextScan = false
        }

        let arrivals = unmatched.values.sorted { ($0.port ?? .max, $0.pid) < ($1.port ?? .max, $1.pid) }
        for process in arrivals {
            // Rows present at launch are already running; only later ones are boarding.
            let phase: BoardEntry.Phase = hasScanned ? .boarding(until: now + Self.boardingDuration) : .active
            updated.append(BoardEntry(process: process, phase: phase, lastActive: now, startedAt: now - process.uptime))
        }

        publish(updated)
        if hasScanned, !isQuiet, !arrivals.isEmpty { onArrival?(wasEmpty) }
        hasScanned = true
    }

    private func advancePhases() {
        let now = Date()
        var updated = entries
        for index in updated.indices {
            switch updated[index].phase {
            case .boarding(let until) where now >= until:
                updated[index].phase = .active
            case .denied(let until) where now >= until:
                updated[index].phase = .active
            case .closing(let since) where now.timeIntervalSince(since) >= Self.terminateGrace:
                if source.isAlive(updated[index].pid) { updated[index].phase = .delayed }
            case .departed(let since) where now.timeIntervalSince(since) >= Self.departedHold:
                updated[index].phase = .clearing(since: now)
            default:
                break
            }
        }
        updated.removeAll { entry in
            guard case .clearing(let since) = entry.phase else { return false }
            return now.timeIntervalSince(since) >= Self.clearingDuration
        }
        publish(updated)
    }

    private func publish(_ updated: [BoardEntry]) {
        guard updated != entries else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            entries = updated
        }
    }

    // MARK: - Signals

    func terminate(_ id: BoardEntry.ID) {
        guard let entry = entries.first(where: { $0.id == id }), entry.canTerminate else { return }
        send(SIGTERM, to: entry)
    }

    func forceQuit(_ id: BoardEntry.ID) {
        guard let entry = entries.first(where: { $0.id == id }), entry.phase == .delayed else { return }
        send(SIGKILL, to: entry)
    }

    func cancelForceQuit(_ id: BoardEntry.ID) {
        update(id) { $0.phase = .active }
    }

    private func send(_ signal: Int32, to entry: BoardEntry) {
        // The PID may have been reused since the last scan. Only signal the process we showed.
        guard source.command(of: entry.pid) == entry.process.command else {
            update(entry.id) { $0.phase = .departed(since: Date()) }
            return
        }
        let succeeded = source.send(signal, to: entry.pid)
        update(entry.id) {
            $0.phase = succeeded ? .closing(since: Date()) : .denied(until: Date() + 3)
        }
    }

    private func update(_ id: BoardEntry.ID, _ change: (inout BoardEntry) -> Void) {
        var updated = entries
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        change(&updated[index])
        publish(updated)
    }
}
