import SwiftUI

@MainActor
struct AppearanceSettingsView: View {
    @Bindable var store: AppStore
    @State private var settings: CanvasBoardSettings

    private let accentPresets = ["#0A84FF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#64D2FF"]
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    init(store: AppStore) {
        self.store = store
        _settings = State(initialValue: store.configuration.boardSettings)
    }

    var body: some View {
        Form {
            Section(copy.appearanceMode) {
                Picker(copy.appearance, selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(title(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.appearanceMode) { _, newMode in
                    settings.canvasBackgroundHex = newMode.defaultCanvasBackgroundHex
                }
            }

            Section(copy.themeColors) {
                LabeledContent(copy.accentColor) {
                    HStack {
                        TextField("#0A84FF", text: $settings.themeAccentHex)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 140)
                        ColorPresetRow(colors: accentPresets, selection: $settings.themeAccentHex)
                    }
                }

                Text(copy.canvasBackgroundFollowsMode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(copy.canvasPattern) {
                Picker(copy.canvasPattern, selection: $settings.canvasPattern) {
                    ForEach(CanvasPatternStyle.allCases) { pattern in
                        Text(title(for: pattern)).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)

                Text(copy.canvasPatternHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            settings.canvasBackgroundHex = settings.appearanceMode.defaultCanvasBackgroundHex
        }
        .onChange(of: settings) { _, newValue in
            var normalized = newValue
            normalized.themeAccentHex = normalizedHex(normalized.themeAccentHex)
            normalized.canvasBackgroundHex = normalized.appearanceMode.defaultCanvasBackgroundHex
            store.updateBoardSettings(normalized)
        }
        .onChange(of: store.configuration.boardSettings) { _, newValue in
            guard newValue != settings else { return }
            settings = newValue
        }
    }

    private func normalizedHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "#000000" }
        return trimmed.hasPrefix("#") ? trimmed.uppercased() : "#\(trimmed.uppercased())"
    }

    private func title(for mode: AppAppearanceMode) -> String {
        switch mode {
        case .light: copy.lightMode
        case .dark: copy.darkMode
        }
    }

    private func title(for pattern: CanvasPatternStyle) -> String {
        switch pattern {
        case .grid: copy.gridPattern
        case .dots: copy.dotsPattern
        case .blueprint: copy.blueprintPattern
        case .none: copy.noPattern
        }
    }
}

@MainActor
private struct ColorPresetRow: View {
    let colors: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 7) {
            ForEach(colors, id: \.self) { hex in
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(selection.caseInsensitiveCompare(hex) == .orderedSame ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
