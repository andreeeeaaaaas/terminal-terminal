import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var onResetPosition: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Style")
                    .font(.subheadline.weight(.medium))
                Picker("Style", selection: $settings.style) {
                    ForEach(BoardTheme.all, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Display")
                    .font(.subheadline.weight(.medium))
                Picker("Display", selection: displayBinding) {
                    ForEach(BoardTheme.Display.allCases, id: \.self) { display in
                        Text(display.title).tag(display)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accent")
                    .font(.subheadline.weight(.medium))
                AccentSwatches(settings: settings)
            }

            Toggle("Show seconds", isOn: $settings.showSeconds)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Refresh every")
                    .font(.subheadline.weight(.medium))
                Picker("Refresh every", selection: $settings.pollInterval) {
                    ForEach(Settings.pollIntervals, id: \.self) { seconds in
                        Text("\(Int(seconds))s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Show all ports", isOn: $settings.showAllPorts)
                Text("Includes apps, system services and ports below 1024.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }

            Divider()

            HStack {
                Button("Reset board position", action: onResetPosition)
                Spacer()
                Button("Quit", action: onQuit)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    /// Shows the preset's own display until overridden; picking the preset's own clears the override.
    private var displayBinding: Binding<BoardTheme.Display> {
        Binding(
            get: { settings.display ?? settings.preset.display },
            set: { settings.display = $0 == settings.preset.display ? nil : $0 }
        )
    }
}

/// The preset's own accent first, then the fixed palette.
private struct AccentSwatches: View {
    @ObservedObject var settings: Settings

    var body: some View {
        HStack(spacing: 8) {
            swatch(color: settings.preset.accent, label: "\(settings.preset.name) default", isSelected: settings.accent == nil) {
                settings.accent = nil
            }
            Divider().frame(height: 16)
            ForEach(BoardTheme.Accent.allCases, id: \.self) { accent in
                swatch(color: accent.color, label: accent.title, isSelected: settings.accent == accent) {
                    settings.accent = accent
                }
            }
        }
    }

    private func swatch(color: Color, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
