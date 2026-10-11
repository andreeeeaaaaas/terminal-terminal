import SwiftUI

/// Settings in the style of System Settings: grouped rounded sections, labels left, controls right.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    var onResetPosition: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSection("Appearance") {
                SettingsRow("Style") {
                    Picker("Style", selection: $settings.style) {
                        ForEach(BoardTheme.all, id: \.name) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingsRow("Display") {
                    Picker("Display", selection: displayBinding) {
                        ForEach(BoardTheme.Display.allCases, id: \.self) { display in
                            Text(display.title).tag(display)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingsRow("Accent") {
                    AccentSwatches(settings: settings)
                }
                RowDivider()
                SettingsRow("Show seconds") {
                    Toggle("Show seconds", isOn: $settings.showSeconds)
                        .toggleStyle(GreenSwitch())
                        .labelsHidden()
                }
            }

            SettingsSection("Board") {
                SettingsRow("Refresh every") {
                    Picker("Refresh every", selection: $settings.pollInterval) {
                        ForEach(Settings.pollIntervals, id: \.self) { seconds in
                            Text("\(Int(seconds))s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingsRow("Show all ports", detail: "Include apps, system services and ports below 1024.") {
                    Toggle("Show all ports", isOn: $settings.showAllPorts)
                        .toggleStyle(GreenSwitch())
                        .labelsHidden()
                }
                RowDivider()
                SettingsRow("Appear on new server", detail: "Display the board anytime a new server is started.") {
                    Toggle("Appear on new server", isOn: $settings.showOnArrival)
                        .toggleStyle(GreenSwitch())
                        .labelsHidden()
                }
            }

            HStack {
                FooterButton("Reset Board Position", action: onResetPosition)
                Spacer()
                FooterButton("Quit Terminal Terminal", action: onQuit)
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    /// Shows the preset's own display until overridden; picking the preset's own clears the override.
    private var displayBinding: Binding<BoardTheme.Display> {
        Binding(
            get: { settings.display ?? settings.preset.display },
            set: { settings.display = $0 == settings.preset.display ? nil : $0 }
        )
    }
}

/// A titled group of rows on a rounded inset background.
private struct SettingsSection<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: Rows

    init(_ title: String, @ViewBuilder rows: () -> Rows) {
        self.title = title
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            VStack(spacing: 0) { rows }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

/// An inset hairline between rows.
private struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 10)
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let control: Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 34)
    }
}

/// The preset's own accent, then the fixed palette. Styled after System Settings' accent
/// colours: the selected swatch carries a white centre dot.
private struct AccentSwatches: View {
    @ObservedObject var settings: Settings

    var body: some View {
        HStack(spacing: 7) {
            Swatch(color: settings.preset.accent, label: "\(settings.preset.name) default", isSelected: settings.accent == nil) {
                settings.accent = nil
            }
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 12)
            ForEach(BoardTheme.Accent.allCases, id: \.self) { accent in
                Swatch(color: accent.color, label: accent.title, isSelected: settings.accent == accent) {
                    settings.accent = accent
                }
            }
        }
    }
}

private struct Swatch: View {
    let color: Color
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .shadow(color: .black.opacity(0.25), radius: 0.5)
                        .opacity(isSelected ? 1 : 0)
                )
                .frame(width: 15, height: 15)
                .scaleEffect(isHovering ? 1.15 : 1)
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(PressableStyle())
        .background(HoverTracker(isHovering: $isHovering))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A quiet text button with a hover highlight, for the footer.
private struct FooterButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .foregroundStyle(Color.primary.opacity(isHovering ? 1 : 0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .background(HoverTracker(isHovering: $isHovering))
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Dims slightly while pressed.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A mini switch drawn in SwiftUI. The app is never active, so AppKit's switch always
/// draws its inactive grey and ignores `.tint`; this one stays green when on.
private struct GreenSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color(nsColor: .systemGreen) : Color.primary.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 0.75, y: 0.5)
                        .padding(1.5)
                }
                .frame(width: 26, height: 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
