import AppKit

/// Demo mode for recordings: the real app, fed a scripted process table and driven by
/// commands on stdin, one per line. Quits when stdin closes.
///
///     TerminalTerminal --demo
///     demo-video run demos/kill-flow.demo.yaml
///
/// Commands (names match a sample's destination or label, e.g. `backoffice` or `vite`):
///
///     start                 begin scanning; rows already added show as running
///     add <name> [stubborn] a process starts (boards if scanning); stubborn ignores SIGTERM
///     exit <name>           the process exits, so its row departs
///     style <name>          a preset by name, e.g. `style LED Amber`
///     display <flap|led|pixel|plain>, accent <name|default>, seconds <on|off>
///     quit
@MainActor
final class Demo {
    let processes = ScriptedProcesses()
    /// Settings and board position live here, not in the user's defaults.
    let defaults: UserDefaults

    private static let suite = "com.andreasthoma.TerminalTerminal.demo"

    init() {
        UserDefaults().removePersistentDomain(forName: Self.suite)
        defaults = UserDefaults(suiteName: Self.suite)!
    }

    func run(model: BoardModel, settings: Settings) async {
        let lines = AsyncStream<String> { continuation in
            Thread.detachNewThread {
                while let line = readLine() { continuation.yield(line) }
                continuation.finish()
            }
        }
        for await line in lines {
            let words = line.split(separator: " ").map(String.init)
            guard let command = words.first?.lowercased() else { continue }
            if command == "quit" { break }
            if let error = perform(command, Array(words.dropFirst()), model: model, settings: settings) {
                FileHandle.standardError.write(Data("demo: \(error)\n".utf8))
            }
        }
        defaults.removePersistentDomain(forName: Self.suite)
    }

    /// Returns an error message, or nil when the command worked.
    private func perform(_ command: String, _ arguments: [String], model: BoardModel, settings: Settings) -> String? {
        let rest = arguments.joined(separator: " ")
        switch command {
        case "start":
            // The shortest interval, so state changes reach the board within a second.
            settings.pollInterval = Settings.pollIntervals[0]
            model.start()
        case "add":
            guard let sample = Self.sample(arguments.first) else { return "no sample named \(rest)" }
            processes.add(sample, ignoresSIGTERM: arguments.dropFirst().contains("stubborn"))
            model.refresh()
        case "exit":
            guard let sample = Self.sample(arguments.first) else { return "no sample named \(rest)" }
            processes.remove(sample.pid)
            model.refresh()
        case "style":
            guard let theme = BoardTheme.all.first(where: { $0.name.caseInsensitiveCompare(rest) == .orderedSame }) else {
                return "no style named \(rest). Styles: \(BoardTheme.all.map(\.name).joined(separator: ", "))"
            }
            settings.style = theme.name
        case "display":
            guard let display = BoardTheme.Display(rawValue: rest.lowercased()) else { return "display wants flap, led, pixel or plain" }
            settings.display = display
        case "accent":
            if rest.lowercased() == "default" {
                settings.accent = nil
            } else {
                guard let accent = BoardTheme.Accent(rawValue: rest.lowercased()) else { return "no accent named \(rest)" }
                settings.accent = accent
            }
        case "seconds":
            settings.showSeconds = rest.lowercased() != "off"
        default:
            return "unknown command \(command)"
        }
        return nil
    }

    private static func sample(_ name: String?) -> ScannedProcess? {
        guard let name else { return nil }
        return Snapshot.samples.first { $0.destination.caseInsensitiveCompare(name) == .orderedSame }
            ?? Snapshot.samples.first { $0.label.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// A process table the demo edits. SIGTERM removes a process unless it's stubborn;
/// SIGKILL always does.
final class ScriptedProcesses: ProcessSource, @unchecked Sendable {
    private let lock = NSLock()
    private var running: [ScannedProcess] = []
    private var stubborn: Set<Int32> = []

    func add(_ process: ScannedProcess, ignoresSIGTERM: Bool = false) {
        lock.withLock {
            running.removeAll { $0.pid == process.pid }
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
