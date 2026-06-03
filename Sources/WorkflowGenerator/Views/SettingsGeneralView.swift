import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    @Bindable var store: AppStore
    @State private var selectedLanguage: AppLanguage

    init(store: AppStore) {
        self.store = store
        _selectedLanguage = State(initialValue: store.configuration.language)
    }

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    var body: some View {
        Form {
            Section(copy.languageLabel) {
                Picker(copy.appLanguage, selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text("\(language.shortTitle) · \(language.title)")
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    store.updateLanguage(selectedLanguage)
                } label: {
                    Label(copy.saveAndRefresh, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                Text(copy.languageHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(copy.helpAndDocs) {
                Button {
                    openDocumentation("https://workflow.zhouzhou.dev/")
                } label: {
                    Label(copy.openDocsHome, systemImage: "book")
                }
                Text(copy.docsHomeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            BoardSettingsSection(store: store)
        }
        .formStyle(.grouped)
    }
}


@MainActor
private struct BoardSettingsSection: View {
    @Bindable var store: AppStore
    @State private var settings: CanvasBoardSettings

    init(store: AppStore) {
        self.store = store
        _settings = State(initialValue: store.configuration.boardSettings)
    }

    var body: some View {
        Section("Board") {
            Toggle("Show grid", isOn: $store.configuration.showsCanvasGrid)
            Toggle("Snap to grid", isOn: $settings.snapToGrid)
            LabeledContent("Grid density") {
                HStack {
                    Slider(value: gridDensity, in: 1...12, step: 1)
                    Text("\(Int(gridDensity.wrappedValue))")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
            LabeledContent("Grid opacity") {
                Slider(value: $settings.gridOpacity, in: 0.02...0.35)
            }
            Toggle("Smooth pen curves", isOn: $settings.smoothPen)
            LabeledContent("Pen width") {
                Slider(value: $settings.penWidth, in: 1...12, step: 1)
            }
            Text("Color is controlled from the canvas toolbar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: settings) { _, newValue in
            store.updateBoardSettings(newValue)
        }
        .onChange(of: store.configuration.showsCanvasGrid) { _, _ in
            store.save()
        }
    }

    private var gridDensity: Binding<Double> {
        Binding(
            get: { max(1, min(12, (104 - settings.gridSize) / 8)) },
            set: { settings.gridSize = 104 - max(1, min(12, $0)) * 8 }
        )
    }
}
