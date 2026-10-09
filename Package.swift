// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TerminalTerminal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TerminalTerminal",
            path: "Sources/TerminalTerminal"
        )
    ]
)
