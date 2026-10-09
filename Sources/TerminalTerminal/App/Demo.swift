import AppKit

/// Scripted scenarios for demo recordings: the real app, fed a fake process table, so the
/// board animates exactly as it does in use. Exits when the script ends.
///
///     TerminalTerminal --demo <scenario>
///     demo-record --out demos/boarding.mov -- .build/debug/TerminalTerminal --demo boarding
///
/// Under demo-record, waits for `DEMO_READY_FILE` before the first action.
@MainActor
final class Demo {
    enum Scenario: String, CaseIterable {
        /// Running rows flip in, then two new arrivals board and settle to RUNNING.
        case boarding
    }

    let scenario: Scenario
    let processes = ScriptedProcesses()
    /// Settings and board position live here, not in the user's defaults.
    let defaults: UserDefaults

    private static let suite = "com.andreasthoma.TerminalTerminal.demo"

    init(_ scenario: Scenario) {
        self.scenario = scenario
        UserDefaults().removePersistentDomain(forName: Self.suite)
        defaults = UserDefaults(suiteName: Self.suite)!
    }

    func run(model: BoardModel) async {
        let samples = Dictionary(uniqueKeysWithValues: Snapshot.samples.map { ($0.destination, $0) })
        switch scenario {
        case .boarding:
            processes.add(samples["oceanheroes"]!)
            processes.add(samples["api"]!)
            await waitForRecorder()
            model.start()
            await pause(2.5)
            processes.add(samples["terminal-ui"]!)
            model.refresh()
            await pause(1.5)
            processes.add(samples["backoffice"]!)
            model.refresh()
            await pause(BoardModel.boardingDuration + 2)
        }
        defaults.removePersistentDomain(forName: Self.suite)
    }

    /// Waits until the recorder is capturing, then a beat so the video opens on a still board.
    private func waitForRecorder() async {
        if let path = ProcessInfo.processInfo.environment["DEMO_READY_FILE"] {
            let deadline = Date() + 10
            while !FileManager.default.fileExists(atPath: path), Date() < deadline {
                await pause(0.05)
            }
        }
        await pause(0.8)
    }

    private func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// A process table the demo script edits. SIGTERM removes a process unless it's stubborn;
/// SIGKILL always does.
final class ScriptedProcesses: ProcessSource, @unchecked Sendable {
    private let lock = NSLock()
    private var running: [ScannedProcess] = []
    private var stubborn: Set<Int32> = []

    func add(_ process: ScannedProcess, ignoresSIGTERM: Bool = false) {
        lock.withLock {
            running.append(process)
            if ignoresSIGTERM { stubborn.insert(process.pid) }
        }
    }

    func remove(_ pid: Int32) {
        lock.withLock { running.removeAll { $0.pid == pid } }
    }

    func scan(showAll: Bool) -> [ScannedProcess] {
        lock.withLock { running }
    }

    func command(of pid: Int32) -> String? {
        lock.withLock { running.first { $0.pid == pid }?.command }
    }

    func send(_ signal: Int32, to pid: Int32) -> Bool {
        let survives = lock.withLock { signal == SIGTERM && stubborn.contains(pid) }
        if !survives { remove(pid) }
        return true
    }

    func isAlive(_ pid: Int32) -> Bool {
        lock.withLock { running.contains { $0.pid == pid } }
    }
}
