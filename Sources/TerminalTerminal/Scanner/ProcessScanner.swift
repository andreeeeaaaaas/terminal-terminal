import Foundation

/// One process the board should show.
struct ScannedProcess: Equatable {
    let pid: Int32
    /// Lowest listening port, or nil for a portless background task.
    let port: Int?
    /// The address to open instead of `localhost`, set only when another row listens on the
    /// same port at a different address (IPv4 and IPv6 sockets can share a port).
    var host: String? = nil
    let label: String
    /// Matched a `web` label rule: clicking GATE opens the port in a browser.
    let isWebServer: Bool
    let destination: String
    let command: String
    let uptime: TimeInterval
    let cpu: Double
}

/// Where board rows come from, and where signals go: the live process table, or a scripted
/// one for demos.
protocol ProcessSource: AnyObject, Sendable {
    func scan(showAll: Bool) -> [ScannedProcess]
    /// The full command line of `pid`, or nil if it's gone.
    func command(of pid: Int32) -> String?
    /// False if the signal was refused.
    func send(_ signal: Int32, to pid: Int32) -> Bool
    func isAlive(_ pid: Int32) -> Bool
}

/// Reads listening sockets and the process table, and decides which processes are worth
/// a row. Not thread-safe: call `scan` from one task at a time.
final class ProcessScanner: @unchecked Sendable {
    /// Portless processes must have run this long to count as background tasks.
    static let backgroundTaskMinimumUptime: TimeInterval = 5 * 60
    static let minimumPort = 1024

    private var cwdCache: [Int32: String] = [:]
    private let uid = getuid()

    func scan(showAll: Bool) -> [ScannedProcess] {
        let listening = Self.listeningPorts()
        let table = Self.processTable()
        let commands = table.mapValues { ParsedCommand($0.command) }

        func isNoise(_ pid: Int32) -> Bool {
            guard let command = commands[pid] else { return true }
            if LabelHeuristics.isHidden(command) { return true }
            let labelled = LabelHeuristics.rule(for: command) != nil
            if (command.isBundled || command.isSystem) && !labelled { return true }
            return isSpawnedByApp(pid, table: table, commands: commands)
        }

        // Port owners
        var portOwners: [Int32: Int] = [:]
        for (pid, ports) in listening {
            guard let row = table[pid], row.uid == uid else { continue }
            let eligible = showAll ? Set(ports.keys) : Set(ports.keys.filter { $0 >= Self.minimumPort })
            guard let port = eligible.min() else { continue }
            if !showAll && isNoise(pid) { continue }
            portOwners[pid] = port
        }

        // Portless background tasks: recognised tools left running
        var background = Set<Int32>()
        for (pid, row) in table where row.uid == uid && portOwners[pid] == nil {
            guard row.uptime >= Self.backgroundTaskMinimumUptime,
                  let command = commands[pid],
                  LabelHeuristics.rule(for: command) != nil,
                  !isNoise(pid)
            else { continue }
            background.insert(pid)
        }

        // Collapse process trees: `npm run dev` → `sh -c` → `node vite` shows once, as the
        // worker. A background task is dropped if it sits above or below another row.
        let shown = Set(portOwners.keys).union(background)
        var ancestorsOfShown = Set<Int32>()
        for pid in shown {
            ancestorsOfShown.formUnion(ancestors(of: pid, table: table))
        }
        background = background.filter { pid in
            !ancestorsOfShown.contains(pid)
                && ancestors(of: pid, table: table).allSatisfy { portOwners[$0] == nil }
        }

        let pids = Array(portOwners.keys) + Array(background)
        resolveWorkingDirectories(for: pids)

        // `localhost` resolves to one of the addresses, so a shared port needs the exact one.
        var portCounts: [Int: Int] = [:]
        for port in portOwners.values { portCounts[port, default: 0] += 1 }
        func host(of pid: Int32) -> String? {
            guard let port = portOwners[pid], portCounts[port, default: 0] > 1,
                  let addresses = listening[pid]?[port], addresses.count == 1 else { return nil }
            return addresses.first
        }

        return pids.compactMap { pid in
            guard let row = table[pid], let command = commands[pid] else { return nil }
            let rule = LabelHeuristics.rule(for: command)
            return ScannedProcess(
                pid: pid,
                port: portOwners[pid],
                host: host(of: pid),
                label: rule?.label ?? command.executable,
                isWebServer: rule?.isWeb ?? false,
                destination: LabelHeuristics.destination(for: command, cwd: cwdCache[pid]),
                command: row.command,
                uptime: row.uptime,
                cpu: row.cpu
            )
        }
    }

    // MARK: - Process tree

    /// True when the first non-shell owner up the tree is a GUI app (Raycast, an editor).
    /// Walking stops at an interactive shell, so anything started from a terminal counts as yours.
    private func isSpawnedByApp(_ pid: Int32, table: [Int32: PSRow], commands: [Int32: ParsedCommand]) -> Bool {
        for ancestor in ancestors(of: pid, table: table) {
            guard let command = commands[ancestor] else { return false }
            if command.isInteractiveShell || command.isTerminalApp { return false }
            if command.isBundled { return true }
        }
        return false
    }

    private func ancestors(of pid: Int32, table: [Int32: PSRow]) -> [Int32] {
        var result: [Int32] = []
        var current = table[pid]?.ppid ?? 1
        while current > 1, result.count < 64, let row = table[current] {
            result.append(current)
            current = row.ppid
        }
        return result
    }

    // MARK: - lsof

    /// `lsof -iTCP -sTCP:LISTEN -P -n`, in field mode for reliable parsing. Maps each PID's
    /// ports to the loopback-reachable addresses they're bound to, as URL hosts.
    private static func listeningPorts() -> [Int32: [Int: Set<String>]] {
        guard let output = Subprocess.run("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "ptn"]) else { return [:] }
        var result: [Int32: [Int: Set<String>]] = [:]
        var pid: Int32?
        var isIPv6 = false
        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = line.dropFirst()
            switch field {
            case "p":
                pid = Int32(value)
            case "t":
                isIPv6 = value == "IPv6"
            case "n":
                guard let pid, let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let address = String(value[..<colon])
                let host = address != "*" ? address : isIPv6 ? "[::1]" : "127.0.0.1"
                result[pid, default: [:]][port, default: []].insert(host)
            default:
                continue
            }
        }
        return result
    }

    private func resolveWorkingDirectories(for pids: [Int32]) {
        let alive = Set(pids)
        cwdCache = cwdCache.filter { alive.contains($0.key) }
        let missing = pids.filter { cwdCache[$0] == nil }
        guard !missing.isEmpty else { return }

        let list = missing.map(String.init).joined(separator: ",")
        guard let output = Subprocess.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-F", "n"]) else { return }
        var pid: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let pid { cwdCache[pid] = String(line.dropFirst()) }
        }
        // Remember misses too, so a process we can't inspect isn't queried every poll.
        for pid in missing where cwdCache[pid] == nil { cwdCache[pid] = "/" }
    }

    // MARK: - ps

    struct PSRow {
        let ppid: Int32
        let uid: uid_t
        let uptime: TimeInterval
        let cpu: Double
        let command: String
    }

    private static func processTable() -> [Int32: PSRow] {
        guard let output = Subprocess.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,uid=,etime=,%cpu=,tty=,command="]) else { return [:] }
        var table: [Int32: PSRow] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard fields.count == 7,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]),
                  let uid = uid_t(fields[2]),
                  let uptime = parseElapsed(fields[3]),
                  let cpu = Double(fields[4])
            else { continue }
            // `split` keeps the column padding in front of the last field.
            let command = fields[6].trimmingCharacters(in: .whitespaces)
            table[pid] = PSRow(ppid: ppid, uid: uid, uptime: uptime, cpu: cpu, command: command)
        }
        return table
    }

    /// Parses `ps` elapsed time: `[[dd-]hh:]mm:ss`.
    static func parseElapsed<S: StringProtocol>(_ text: S) -> TimeInterval? {
        var days = 0.0
        var clock = Substring(text)
        if let dash = clock.firstIndex(of: "-") {
            guard let parsed = Double(clock[..<dash]) else { return nil }
            days = parsed
            clock = clock[clock.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        guard (2...3).contains(parts.count) else { return nil }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return days * 86_400 + seconds
    }
}

extension ProcessScanner: ProcessSource {
    func command(of pid: Int32) -> String? {
        Subprocess.run("/bin/ps", ["-ww", "-o", "command=", "-p", String(pid)])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func send(_ signal: Int32, to pid: Int32) -> Bool {
        kill(pid, signal) == 0
    }

    func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Runs a tool directly (no shell) and returns its standard output.
enum Subprocess {
    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
