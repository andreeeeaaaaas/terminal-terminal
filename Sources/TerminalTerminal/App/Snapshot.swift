import AppKit
import SwiftUI

/// Renders boards to PNG without launching the app, with sample rows and every cell
/// already settled. Used to check layout headlessly.
///
///     TerminalTerminal --snapshot out.png   # current theme: full, empty and mid-flip
///     TerminalTerminal --themes out.png     # every theme side by side
@MainActor
enum Snapshot {
    static func render(to path: String) -> Bool {
        let view = VStack(alignment: .leading, spacing: 24) {
            BoardView(model: previewModel(samples, delayed: [41007]))
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

    static func renderThemes(to path: String) -> Bool {
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
        return write(view, to: path)
    }

    private static func write(_ content: some View, to path: String) -> Bool {
        let view = content
            .environment(\.flapStartsSettled, true)
            .padding(32)
            .background(Color(white: 0.86))
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
        departed: Set<Int32> = []
    ) -> BoardModel {
        BoardModel(
            settings: Settings(defaults: UserDefaults(suiteName: "snapshot")!),
            preview: processes,
            idle: [11769],
            delayed: delayed,
            boarding: boarding,
            departed: departed
        )
    }

    private static let samples: [ScannedProcess] = [
        ScannedProcess(pid: 7862, port: 4321, label: "ASTRO", destination: "oceanheroes", command: "astro dev", uptime: 325_000, cpu: 0),
        ScannedProcess(pid: 11769, port: 4323, label: "ASTRO", destination: "sandrathoma-site", command: "astro dev", uptime: 30_000, cpu: 0),
        ScannedProcess(pid: 40211, port: 5173, label: "VITE", destination: "terminal-ui", command: "vite", uptime: 1_260, cpu: 2.1),
        ScannedProcess(pid: 40388, port: nil, label: "TSC", destination: "api", command: "tsc --watch", uptime: 4_020, cpu: 0.6),
        ScannedProcess(pid: 41007, port: 8000, label: "DJANGO", destination: "backoffice", command: "python manage.py runserver", uptime: 540, cpu: 1.0),
    ]
}
