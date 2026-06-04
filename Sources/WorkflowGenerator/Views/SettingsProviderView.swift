import SwiftUI

@MainActor
struct ProviderSettingsView: View {
    @Bindable var store: AppStore
    @State private var selectedProviderId: UUID?
    @State private var searchText = ""

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredProviders) { provider in
                            Button {
                                selectedProviderId = provider.id
                            } label: {
                                ProviderSidebarRow(provider: provider, isSelected: provider.id == resolvedSelectedProviderId)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                Divider()
                HStack {
                    Menu {
                        ForEach(missingProviderPresets) { preset in
                            Button { store.addProvider(from: preset) } label: {
                                Label(preset.name, systemImage: preset.symbolName)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text(copy.restoreProviders)
                        }
                        .frame(width: 104)
                    }
                    .buttonStyle(.bordered)
                    .disabled(missingProviderPresets.isEmpty)
                    .quickHelp(copy.restoreProvidersHint)

                    Button(role: .destructive) {
                        if let provider = selectedProvider {
                            store.deleteProvider(provider)
                            selectedProviderId = store.configuration.providers.first?.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(copy.delete)
                        }
                        .frame(width: 88)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedProvider == nil || store.configuration.providers.count <= 1)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(width: 220)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.56))

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(copy.providers)
                        .font(.headline)
                    Spacer()
                    TextField(copy.search, text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                Divider()

                if let provider = selectedProvider {
                    ProviderEditor(store: store, provider: provider)
                        .id(provider.id)
                } else {
                    ContentUnavailableView(copy.noProviderSelected, systemImage: "network", description: Text(copy.noProviderDescription))
                }
            }
            .frame(minWidth: 500)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            selectedProviderId = resolvedSelectedProviderId
        }
    }

    private var filteredProviders: [ProviderConfig] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.configuration.providers }
        return store.configuration.providers.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.baseURL.localizedCaseInsensitiveContains(query)
        }
    }

    private var resolvedSelectedProviderId: UUID? {
        if let selectedProviderId, store.configuration.providers.contains(where: { $0.id == selectedProviderId }) {
            return selectedProviderId
        }
        return filteredProviders.first?.id ?? store.configuration.providers.first?.id
    }

    private var selectedProvider: ProviderConfig? {
        guard let id = resolvedSelectedProviderId else { return nil }
        return store.configuration.providers.first { $0.id == id }
    }

    private var missingProviderPresets: [ProviderConfig] {
        ProviderConfig.defaults.filter { preset in
            !store.configuration.providers.contains { provider in
                provider.name.caseInsensitiveCompare(preset.name) == .orderedSame
            }
        }
    }
}

private struct ProviderSidebarRow: View {
    let provider: ProviderConfig
    let isSelected: Bool

    private var isAgnesProvider: Bool {
        AgnesProviderVisuals.isAgnes(providerName: provider.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.symbolName)
                .frame(width: 18)
                .foregroundStyle(iconColor)
            Text(provider.name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .agnesAccentBackground(
            enabled: isAgnesProvider,
            isSelected: isSelected,
            baseColor: isSelected ? Color.secondary.opacity(0.18) : Color.clear,
            cornerRadius: 7
        )
        .agnesAccentBorder(
            enabled: isAgnesProvider,
            isSelected: isSelected,
            fallbackColor: .clear,
            cornerRadius: 7
        )
    }

    private var iconColor: Color {
        if isAgnesProvider { return Color(red: 0.95, green: 0.17, blue: 0.46) }
        return isSelected ? .pink : .secondary
    }
}

@MainActor
private struct ProviderEditor: View {
    @Bindable var store: AppStore
    @State var provider: ProviderConfig
    @State private var showsAPIKey = false
    @State private var showsModelManager = false
    @State private var customModelId = ""

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    private var isAgnesProvider: Bool {
        AgnesProviderVisuals.isAgnes(providerName: provider.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: provider.symbolName)
                        .foregroundStyle(isAgnesProvider ? Color(red: 0.95, green: 0.17, blue: 0.46) : .pink)
                    TextField("Provider", text: $provider.name)
                        .textFieldStyle(.plain)
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteProvider(provider)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.configuration.providers.count <= 1)
                }
                .padding(isAgnesProvider ? 10 : 0)
                .agnesAccentBackground(
                    enabled: isAgnesProvider,
                    baseColor: isAgnesProvider ? Color.secondary.opacity(0.05) : Color.clear,
                    cornerRadius: 10
                )
                .agnesAccentBorder(
                    enabled: isAgnesProvider,
                    fallbackColor: .clear,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API Base URL")
                            .font(.callout.weight(.medium))
                        HelpBadge(text: "Do NOT include /chat/completions in the URL.")
                    }
                    TextField("https://api.example.com/v1", text: $provider.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API 文档")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button {
                            openDocumentation(provider.documentationURL)
                        } label: {
                            Label("打开文档", systemImage: "book")
                        }
                        .controlSize(.small)
                        .disabled(provider.documentationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    TextField("https://provider.example.com/docs", text: $provider.documentationURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.callout.weight(.medium))
                    HStack {
                        if showsAPIKey {
                            TextField("sk-...", text: $provider.apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $provider.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showsAPIKey.toggle()
                        } label: {
                            Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                                .frame(width: 28, height: 24)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.model)
                        .font(.callout.weight(.medium))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            TextField("model-id", text: $customModelId)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 140)
                                .onSubmit {
                                    addCustomModel()
                                }
                            Button {
                                addCustomModel()
                            } label: {
                                Label(copy.newModel, systemImage: "plus")
                            }
                            Button {
                                store.testProviderConnection(provider)
                            } label: {
                                Label(copy.testConnection, systemImage: "checkmark.circle")
                            }
                        }
                        HStack(spacing: 6) {
                            Button {
                                store.fetchProviderModels(provider)
                            } label: {
                                Label(copy.fetchModels, systemImage: "arrow.clockwise")
                            }
                            Button {
                                showsModelManager = true
                            } label: {
                                Label(copy.manageModels, systemImage: "rectangle.expand.vertical")
                            }
                        }
                    }
                    .controlSize(.mini)

                    if selectedModelIds.isEmpty {
                        Text(copy.noModels)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .foregroundStyle(.secondary)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(selectedModelIds, id: \.self) { modelId in
                                Button {
                                    store.toggleProviderModel(modelId, from: provider)
                                } label: {
                                    HStack {
                                        Text(modelId)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .agnesAccentBackground(
                                        enabled: isAgnesProvider,
                                        baseColor: Color.secondary.opacity(0.08),
                                        cornerRadius: 8
                                    )
                                    .agnesAccentBorder(
                                        enabled: isAgnesProvider,
                                        fallbackColor: .clear,
                                        cornerRadius: 8
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text(provider.lastStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.connectionNotes)
                        .font(.callout.weight(.medium))
                    TextEditor(text: $provider.notes)
                        .font(.caption)
                        .frame(minHeight: 82)
                        .scrollContentBackground(.hidden)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .onChange(of: provider) { _, newValue in
            store.updateProvider(newValue)
        }
        .onChange(of: store.configuration.providers) { _, providers in
            guard let current = providers.first(where: { $0.id == provider.id }),
                  current != provider else { return }
            provider = current
        }
        .sheet(isPresented: $showsModelManager) {
            ProviderModelManagerView(store: store, provider: provider)
        }
    }

    private var modelIds: [String] {
        Array(Set(provider.defaultModelIds + provider.fetchedModelIds)).sorted()
    }

    private var selectedModelIds: [String] {
        store.configuration.models
            .filter { $0.providerId == provider.id }
            .map(\.modelId)
            .sorted()
    }

    private func addCustomModel() {
        let typed = customModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = modelIds.first { modelId in
            !store.configuration.models.contains { $0.providerId == provider.id && $0.modelId == modelId }
        } ?? provider.defaultModelIds.first ?? "model-id"
        let modelId = typed.isEmpty ? fallback : typed
        guard !modelId.isEmpty else { return }
        store.addDefaultModel(modelId, from: provider)
        if !provider.defaultModelIds.contains(modelId) && !provider.fetchedModelIds.contains(modelId) {
            provider.defaultModelIds.append(modelId)
        }
        customModelId = ""
    }
}

@MainActor
private struct ProviderModelManagerView: View {
    @Bindable var store: AppStore
    let provider: ProviderConfig
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    private var isAgnesProvider: Bool {
        AgnesProviderVisuals.isAgnes(providerName: provider.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.manageModels)
                        .font(.title3.bold())
                    Text(provider.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.fetchProviderModels(provider)
                } label: {
                    Label(copy.fetchModels, systemImage: "arrow.clockwise")
                }
                TextField(copy.search, text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button(copy.close) {
                    dismiss()
                }
            }
            .padding(16)

            Divider()

            HStack {
                Text("\(copy.availableModels): \(filteredModelIds.count)")
                Spacer()
                Text("\(copy.selected): \(selectedCount)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(filteredModelIds, id: \.self) { modelId in
                        ModelToggleButton(
                            modelId: modelId,
                            isSelected: isSelected(modelId),
                            isAgnesProvider: isAgnesProvider,
                            action: {
                                store.toggleProviderModel(modelId, from: provider)
                            }
                        )
                    }
                }
                .padding(16)
            }

            Text(copy.providerModelHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var allModelIds: [String] {
        Array(Set(currentProvider.defaultModelIds + currentProvider.fetchedModelIds)).sorted()
    }

    private var currentProvider: ProviderConfig {
        store.configuration.providers.first { $0.id == provider.id } ?? provider
    }

    private var filteredModelIds: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allModelIds }
        return allModelIds.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var selectedCount: Int {
        allModelIds.filter(isSelected).count
    }

    private func isSelected(_ modelId: String) -> Bool {
        store.configuration.models.contains { $0.providerId == provider.id && $0.modelId == modelId }
    }
}

@MainActor
private struct ModelToggleButton: View {
    let modelId: String
    let isSelected: Bool
    let isAgnesProvider: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(modelId)
                    .lineLimit(1)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .agnesAccentBackground(
                enabled: isAgnesProvider,
                isSelected: isSelected,
                baseColor: isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
                cornerRadius: 8
            )
            .agnesAccentBorder(
                enabled: isAgnesProvider,
                isSelected: isSelected,
                fallbackColor: .clear,
                cornerRadius: 8
            )
        }
        .buttonStyle(.plain)
    }
}
