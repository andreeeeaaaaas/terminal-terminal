import AppKit
import SwiftUI

/// Renders boards to PNG without launching the app, with sample rows and every cell
/// already settled. Used to check layout headlessly.
///
///     TerminalTerminal --snapshot out.png   # current theme: full, empty and mid-flip
///     TerminalTerminal --themes out.png     # every theme side by side
///     TerminalTerminal --stack out.png      # every theme in one column, unlabelled and transparent
///     TerminalTerminal --screens out/       # each style, the empty board and settings, one PNG each
@MainActor
enum Snapshot {
    static func render(to path: String) -> Bool {
        let view = VStack(alignment: .leading, spacing: 24) {
            BoardView(model: previewModel(samples, delayed: [41007], open: [7862]))
            BoardView(model: previewModel([]))
            HStack(spacing: 8) {
                FlapFace(current: "A", next: "B", topAngle: 0, bottomAngle: 90)
                FlapFace(current: "A", next: "B", topAngle: -45, bottomAngle: 90)
                FlapFace(current: "A", next: "B", topAngle: -90, bottomAngle: 45)
                FlapFace(current: "A", next: "B", topAngle: -90, bottomAngle: 0)
            }
            .padding(8)
            .background(BoardTheme.current.board)
            .scaleEffect(3, anchor: .topLeading)
            .frame(height: 120, alignment: .topLeading)
        }
        return write(view, to: path)
    }

    static func renderThemes(to path: String, background: Color = backdrop) -> Bool {
        let themes = Array(BoardTheme.all.enumerated())
        let view = Grid(alignment: .topLeading, horizontalSpacing: 40, verticalSpacing: 36) {
            ForEach(Array(stride(from: 0, to: themes.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(themes[start..<min(start + 2, themes.count)], id: \.offset) { index, theme in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(index + 1)  \(theme.name)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.75))
                            BoardView(model: previewModel(samples, boarding: [40211], departed: [41007]))
                                .environment(\.boardTheme, theme)
                                .fixedSize()
                                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        }
                    }
                }
            }
        }
        return write(view, to: path, background: background)
    }

    /// Every theme in one centred column, unlabelled, on a transparent background.
    static func renderStack(to path: String) -> Bool {
        let view = VStack(spacing: 36) {
            ForEach(Array(BoardTheme.all.enumerated()), id: \.offset) { _, theme in
                BoardView(model: previewModel(samples, boarding: [40211], departed: [41007]))
                    .environment(\.boardTheme, theme)
                    .fixedSize()
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            }
        }
        return write(view, to: path, background: .clear)
    }

    static func renderScreens(to directory: String) -> Bool {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("screens: \(error)\n".utf8))
            return false
        }
        func path(_ name: String) -> String { folder.appendingPathComponent(name).path }

        var ok = true
        for (index, theme) in BoardTheme.all.enumerated() {
            let slug = theme.name.lowercased().replacingOccurrences(of: " ", with: "-")
            // Colour-coded boards show a boarding and a departed row, so every status colour appears.
            let model = theme.statusColors == nil
                ? previewModel(samples)
                : previewModel(samples, boarding: [40211], departed: [41007])
            let board = BoardView(model: model).environment(\.boardTheme, theme)
            ok = writeScreen(board, to: path(String(format: "board-%02d-%@.png", index + 1, slug))) && ok
        }
        ok = writeScreen(BoardView(model: previewModel([])), to: path("board-empty.png")) && ok
        ok = writeScreen(BoardView(model: previewModel(samples, delayed: [41007], boarding: [40211], departed: [40388], open: [7862])), to: path("board-states.png")) && ok
        ok = renderThemes(to: path("themes.png"), background: .clear) && ok
        ok = writeSettings(appearance: .aqua, to: path("settings-light.png")) && ok
        ok = writeSettings(appearance: .darkAqua, to: path("settings-dark.png")) && ok
        return ok
    }

    /// A board on a transparent background, keeping its drop shadow.
    private static func writeScreen(_ board: some View, to path: String) -> Bool {
        write(board.fixedSize().shadow(color: .black.opacity(0.35), radius: 14, y: 6), to: path, background: .clear)
    }

    /// Settings uses AppKit-backed pickers and toggles, which `ImageRenderer` can't draw,
    /// so it goes through an offscreen hosting view. The glass surface is replaced by a plain card.
    private static func writeSettings(appearance: NSAppearance.Name, to path: String) -> Bool {
        let content = SettingsView(
            settings: Settings(defaults: UserDefaults(suiteName: "snapshot")!),
            onResetPosition: {},
            onQuit: {}
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        )
        .padding(32)

        let hosting = NSHostingView(rootView: content)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            return false
        }
    }

    nonisolated private static let backdrop = Color(white: 0.86)

    private static func write(_ content: some View, to path: String, background: Color = backdrop) -> Bool {
        let view = content
            .environment(\.flapStartsSettled, true)
            .padding(32)
            .background(background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            return false
        }
    }

    private static func previewModel(
        _ processes: [ScannedProcess],
        delayed: Set<Int32> = [],
        boarding: Set<Int32> = [],
        departed: Set<Int32> = [],
        open: Set<Int32> = []
    ) -> BoardModel {
        BoardModel(
            settings: Settings(defaults: UserDefaults(suiteName: "snapshot")!),
            preview: processes,
            idle: [11769],
            delayed: delayed,
            boarding: boarding,
            departed: departed,
            open: open
        )
    }

    static let samples: [ScannedProcess] = [
        ScannedProcess(pid: 7862, port: 4321, label: "ASTRO", isWebServer: true, destination: "oceanheroes", command: "astro dev", uptime: 325_000, cpu: 0),
        ScannedProcess(pid: 11769, port: 4323, label: "ASTRO", isWebServer: true, destination: "sandrathoma-site", command: "astro dev", uptime: 30_000, cpu: 0),
        ScannedProcess(pid: 40211, port: 5173, label: "VITE", isWebServer: true, destination: "terminal-ui", command: "vite", uptime: 1_260, cpu: 2.1),
        ScannedProcess(pid: 40388, port: nil, label: "TSC", isWebServer: false, destination: "api", command: "tsc --watch", uptime: 4_020, cpu: 0.6),
        ScannedProcess(pid: 41007, port: 8000, label: "DJANGO", isWebServer: true, destination: "backoffice", command: "python manage.py runserver", uptime: 540, cpu: 1.0),
    ]
}
