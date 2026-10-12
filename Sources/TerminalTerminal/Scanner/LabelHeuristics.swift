import Foundation

/// Turns a process command line into its board label (the "airline").
///
/// To recognise a new tool, add a `LabelRule` to `rules`. Order matters: the first match
/// wins, so put frameworks before the interpreters that run them (ASTRO before NODE).
/// A matching rule also makes a portless process eligible as a background task, and lets
/// a process inside an `.app` bundle or system directory through the noise filter.
/// Mark `web: true` only for servers whose port serves a page, so clicking GATE opens it.
/// Interpreters stay unmarked: `node` may be a web server or a debugger socket.
enum LabelHeuristics {
    static let rules: [LabelRule] = [
        // Frameworks and dev servers
        LabelRule("NEXT", web: true, .token("next-server"), .phrase("next dev"), .phrase("next start"), .phrase("next/dist")),
        LabelRule("ASTRO", web: true, .token("astro")),
        LabelRule("NUXT", web: true, .token("nuxt"), .token("nuxi")),
        LabelRule("REMIX", web: true, .token("remix")),
        LabelRule("SVELTE", web: true, .phrase("svelte-kit")),
        LabelRule("STORYBOOK", web: true, .token("storybook")),
        LabelRule("VITEST", web: true, .token("vitest")),
        LabelRule("JEST", .token("jest")),
        LabelRule("VITE", web: true, .token("vite")),
        LabelRule("WEBPACK", web: true, .token("webpack"), .token("webpack-dev-server")),
        LabelRule("PARCEL", web: true, .token("parcel")),
        LabelRule("ESBUILD", web: true, .token("esbuild")),
        LabelRule("TSC", .token("tsc")),
        LabelRule("NODEMON", .token("nodemon")),
        LabelRule("ELEVENTY", web: true, .token("eleventy")),
        LabelRule("GATSBY", web: true, .token("gatsby")),
        LabelRule("EXPO", .token("expo")),
        LabelRule("METRO", .phrase("react-native start")),
        LabelRule("WRANGLER", web: true, .token("wrangler")),
        LabelRule("RAILS", web: true, .phrase("rails server"), .phrase("rails s"), .token("puma")),
        LabelRule("SIDEKIQ", .token("sidekiq")),
        LabelRule("JEKYLL", web: true, .token("jekyll")),
        LabelRule("DJANGO", web: true, .phrase("runserver")),
        LabelRule("FLASK", web: true, .token("flask")),
        LabelRule("UVICORN", web: true, .token("uvicorn")),
        LabelRule("GUNICORN", web: true, .token("gunicorn")),
        LabelRule("JUPYTER", web: true, .tokenPrefix("jupyter")),
        LabelRule("PY HTTP", web: true, .phrase("http.server")),
        LabelRule("HUGO", web: true, .token("hugo")),
        LabelRule("ZOLA", web: true, .token("zola")),
        LabelRule("GO", .phrase("go run"), .phrase("/go-build")),
        LabelRule("CARGO", .token("cargo")),
        LabelRule("TRUNK", web: true, .token("trunk")),
        LabelRule("LARAVEL", web: true, .phrase("artisan serve")),
        LabelRule("GRADLE", .phrase("gradledaemon")),

        // Services and tunnels
        LabelRule("DOCKER", .token("docker"), .token("com.docker.backend")),
        LabelRule("POSTGRES", .token("postgres"), .token("postmaster")),
        LabelRule("REDIS", .token("redis-server")),
        LabelRule("MONGO", .token("mongod")),
        LabelRule("MYSQL", .token("mysqld"), .token("mariadbd")),
        LabelRule("OLLAMA", .token("ollama")),
        LabelRule("NGROK", web: true, .token("ngrok")),
        LabelRule("TUNNEL", .token("cloudflared")),
        LabelRule("CADDY", web: true, .token("caddy")),
        LabelRule("NGINX", web: true, .token("nginx")),
        LabelRule("SSH", .custom { $0.executable == "ssh" && $0.raw.range(of: #" -\w*[LRD]"#, options: .regularExpression) != nil }),

        // Interpreters: generic fallbacks, keep last
        LabelRule("DENO", .token("deno")),
        LabelRule("BUN", .token("bun")),
        LabelRule("PHP", .tokenPrefix("php")),
        LabelRule("NODE", .token("node")),
        LabelRule("PYTHON", .tokenPrefix("python")),
        LabelRule("RUBY", .tokenPrefix("ruby")),
        LabelRule("JAVA", .token("java")),
    ]

    /// Executables never shown, even when they listen on a high port.
    static let hiddenExecutables: Set<String> = [
        "controlcenter", "rapportd", "sharingd", "identityservicesd", "remoted",
        "figma_agent", "adobe desktop service", "spotify",
    ]

    /// Any command containing one of these as part of a token is hidden.
    /// MCP servers are spawned and owned by AI tools, not by you.
    static let hiddenTokenFragments: [String] = ["mcp"]

    static func rule(for command: ParsedCommand) -> LabelRule? {
        rules.first { $0.matches(command) }
    }

    static func isHidden(_ command: ParsedCommand) -> Bool {
        if hiddenExecutables.contains(command.executable) { return true }
        return command.tokens.contains { token in
            hiddenTokenFragments.contains { token.contains($0) }
        }
    }

    /// The "destination": which project this process belongs to.
    static func destination(for command: ParsedCommand, cwd: String?) -> String {
        if let range = command.raw.range(of: "/node_modules/") {
            let project = (String(command.raw[..<range.lowerBound]) as NSString).lastPathComponent
            if !project.isEmpty { return project }
        }
        if let cwd, cwd != "/", cwd != NSHomeDirectory() {
            return (cwd as NSString).lastPathComponent
        }
        // Inline code (`python -c '…'`, `node -e '…'`) has no meaningful name.
        if command.tokens.contains(where: { ["-c", "-e", "--eval"].contains($0) }) { return "" }
        let argument = command.tokens.dropFirst().first { !$0.hasPrefix("-") && $0 != command.executable }
        return argument ?? ""
    }
}

struct LabelRule {
    enum Matcher {
        /// A command-line word, compared by basename without script extension.
        case token(String)
        case tokenPrefix(String)
        /// A substring of the lowercased full command line.
        case phrase(String)
        case custom((ParsedCommand) -> Bool)
    }

    let label: String
    /// The port serves a web page, so the board offers to open it.
    let isWeb: Bool
    let matchers: [Matcher]

    init(_ label: String, web: Bool = false, _ matchers: Matcher...) {
        self.label = label
        isWeb = web
        self.matchers = matchers
    }

    func matches(_ command: ParsedCommand) -> Bool {
        // App bundles carry arbitrary arguments, so only their executable name counts.
        if command.isBundled {
            return matchers.contains { matcher in
                switch matcher {
                case .token(let name): return command.executable == name
                case .tokenPrefix(let prefix): return command.executable.hasPrefix(prefix)
                case .phrase, .custom: return false
                }
            }
        }
        return matchers.contains { matcher in
            switch matcher {
            case .token(let name): return command.tokens.contains(name)
            case .tokenPrefix(let prefix): return command.tokens.contains { $0.hasPrefix(prefix) }
            case .phrase(let phrase): return command.lowercased.contains(phrase)
            case .custom(let test): return test(command)
            }
        }
    }
}

/// A `ps` command line split into comparable words.
struct ParsedCommand {
    let raw: String
    let lowercased: String
    /// Lowercased words, reduced to basenames with script extensions stripped:
    /// `node /x/node_modules/vite/bin/vite.js` becomes `["node", "vite"]`.
    let tokens: [String]
    /// The first token, without the leading dash of a login shell.
    let executable: String
    let isBundled: Bool
    let isSystem: Bool

    private static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "py", "rb"]
    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/Library/Apple/"]
    private static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "nu", "xonsh", "login", "tmux", "screen"]
    private static let terminalApps: Set<String> = ["terminal", "iterm2", "ghostty", "wezterm-gui", "alacritty", "kitty", "warp", "stable", "hyper", "tabby"]

    init(_ raw: String) {
        self.raw = raw
        lowercased = raw.lowercased()
        tokens = lowercased.split(separator: " ").map { word in
            let base = (String(word) as NSString).lastPathComponent
            let ext = (base as NSString).pathExtension
            return Self.scriptExtensions.contains(ext) ? (base as NSString).deletingPathExtension : base
        }
        var first = tokens.first ?? ""
        if first.hasPrefix("-") { first.removeFirst() }
        executable = first
        isBundled = raw.contains(".app/") || raw.hasPrefix("Contents/")
        isSystem = Self.systemPrefixes.contains { raw.hasPrefix($0) }
    }

    /// A shell a person is typing into, as opposed to `sh -c` run by a script.
    var isInteractiveShell: Bool {
        Self.shells.contains(executable) && !tokens.contains("-c")
    }

    var isTerminalApp: Bool {
        isBundled && Self.terminalApps.contains(executable)
    }
}
