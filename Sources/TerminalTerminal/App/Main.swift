import AppKit

@main
enum TerminalTerminalMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count {
            exit(Snapshot.render(to: arguments[flag + 1]) ? 0 : 1)
        }
        if let flag = arguments.firstIndex(of: "--themes"), flag + 1 < arguments.count {
            exit(Snapshot.renderThemes(to: arguments[flag + 1]) ? 0 : 1)
        }
        if arguments.contains("--scan") {
            // Prints what the board would show, for tuning label heuristics.
            for process in ProcessScanner().scan(showAll: arguments.contains("--all")) {
                let gate = process.port.map(String.init) ?? "--"
                print(gate, process.label, process.destination, process.pid, Int(process.uptime / 60), "min", process.cpu, separator: "\t")
            }
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
