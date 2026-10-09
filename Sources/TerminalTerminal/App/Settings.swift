import Foundation

@MainActor
final class Settings: ObservableObject {
    static let pollIntervals: [Double] = [1, 2, 5, 10]

    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Keys.pollInterval) }
    }

    @Published var showAllPorts: Bool {
        didSet { defaults.set(showAllPorts, forKey: Keys.showAllPorts) }
    }

    /// A `BoardTheme` preset name. Choosing one clears the display and accent overrides.
    @Published var style: String {
        didSet {
            defaults.set(style, forKey: Keys.style)
            display = nil
            accent = nil
        }
    }

    /// Overrides the preset's display; nil uses the preset's own.
    @Published var display: BoardTheme.Display? {
        didSet { defaults.set(display?.rawValue, forKey: Keys.display) }
    }

    /// Overrides the preset's accent colour; nil uses the preset's own.
    @Published var accent: BoardTheme.Accent? {
        didSet { defaults.set(accent?.rawValue, forKey: Keys.accent) }
    }

    @Published var showSeconds: Bool {
        didSet { defaults.set(showSeconds, forKey: Keys.showSeconds) }
    }

    var preset: BoardTheme { BoardTheme.named(style) }

    var theme: BoardTheme {
        preset.customised(display: display, accent: accent, showsSeconds: showSeconds)
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let pollInterval = "pollInterval"
        static let showAllPorts = "showAllPorts"
        static let style = "style"
        static let display = "display"
        static let accent = "accent"
        static let showSeconds = "showSeconds"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Keys.pollInterval)
        pollInterval = Self.pollIntervals.contains(stored) ? stored : 2
        showAllPorts = defaults.bool(forKey: Keys.showAllPorts)
        style = defaults.string(forKey: Keys.style) ?? BoardTheme.current.name
        display = defaults.string(forKey: Keys.display).flatMap(BoardTheme.Display.init(rawValue:))
        accent = defaults.string(forKey: Keys.accent).flatMap(BoardTheme.Accent.init(rawValue:))
        showSeconds = defaults.object(forKey: Keys.showSeconds) as? Bool ?? true
    }
}
