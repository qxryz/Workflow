import SwiftUI

@MainActor
struct ModelSettingsView: View {
    @Bindable var store: AppStore
    @State private var selectedModelId: UUID?

    private var isChinese: Bool { store.configuration.language == .zhCN }
    private var selectedModel: ModelConfig? {
        let id = selectedModelId ?? store.settingsSelection.modelId ?? store.configuration.defaultModelId ?? store.configuration.models.first?.id
        return store.configuration.models.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            modelRegistry
                .frame(width: 300)
            Divider()
            if let selectedModel {
                ModelRegistrationWorkspace(store: store, model: selectedModel)
                    .id(selectedModel.id)
            } else {
                ContentUnavailableView(
                    isChinese ? "还没有模型" : "No models",
                    systemImage: "cpu",
                    description: Text(isChinese ? "先在供应商页面导入模型，或手动创建一个模型。" : "Import a provider model or create one manually.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .onAppear { selectInitialModel() }
        .onChange(of: store.settingsSelection.modelId) { _, value in
            if let value { selectedModelId = value }
        }
    }

    private var modelRegistry: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "模型注册表" : "Model Registry")
                        .font(.headline)
                    Text(isChinese ? "\(store.configuration.models.count) 个模型" : "\(store.configuration.models.count) models")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.addModel()
                    selectedModelId = store.configuration.models.last?.id
                } label: {
                    Image(systemName: "plus")
                }
                .help(isChinese ? "手动创建模型" : "Create model manually")
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(store.configuration.models) { model in
                        RegisteredModelRow(
                            model: model,
                            provider: provider(for: model),
                            registrations: store.registrations(for: model),
                            isSelected: selectedModel?.id == model.id,
                            isDefault: store.configuration.defaultModelId == model.id
                        ) {
                            selectedModelId = model.id
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.visible)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func provider(for model: ModelConfig) -> ProviderConfig? {
        model.providerId.flatMap { id in store.configuration.providers.first { $0.id == id } }
    }

    private func selectInitialModel() {
        selectedModelId = store.settingsSelection.modelId ?? store.configuration.defaultModelId ?? store.configuration.models.first?.id
    }
}

@MainActor
private struct RegisteredModelRow: View {
    let model: ModelConfig
    let provider: ProviderConfig?
    let registrations: [RegisteredModelInterface]
    let isSelected: Bool
    let isDefault: Bool
    let action: () -> Void

    private var hasRegisteredInterface: Bool {
        registrations.contains { $0.status.isNodeSelectable }
    }

    private var isAgnesModel: Bool {
        AgnesProviderVisuals.isAgnes(provider) || AgnesProviderVisuals.isAgnes(providerName: model.provider)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(model.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Text("\(registrations.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(model.modelId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(provider?.name ?? model.provider)
                        .lineLimit(1)
                    Spacer()
                    Label(
                        hasRegisteredInterface ? "Registered" : "Draft",
                        systemImage: hasRegisteredInterface ? "checkmark.circle.fill" : "pencil.circle"
                    )
                    .foregroundStyle(hasRegisteredInterface ? .green : .secondary)
                }
                .font(.caption2)
            }
            .padding(9)
            .agnesAccentBackground(
                enabled: isAgnesModel,
                isSelected: isSelected,
                baseColor: isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06),
                cornerRadius: 8
            )
            .agnesAccentBorder(
                enabled: isAgnesModel,
                isSelected: isSelected,
                fallbackColor: isSelected ? Color.accentColor.opacity(0.55) : .clear,
                cornerRadius: 8
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct ModelRegistrationWorkspace: View {
    @Bindable var store: AppStore
    @State var model: ModelConfig
    @State private var wizardDraft: ModelRegistrationWizardDraft?

    private var isChinese: Bool { store.configuration.language == .zhCN }
    private var registrations: [RegisteredModelInterface] { store.registrations(for: model) }
    private var provider: ProviderConfig? {
        model.providerId.flatMap { id in store.configuration.providers.first { $0.id == id } }
    }
    private var isAgnesModel: Bool {
        AgnesProviderVisuals.isAgnes(provider) || AgnesProviderVisuals.isAgnes(providerName: model.provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            modelHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isChinese ? "已注册接口" : "Registered Interfaces")
                                .font(.headline)
                            Text(isChinese ? "节点只会使用这里完成注册的接口。复杂地址、参数槽与轮询规则留在设置里。" : "Nodes use interfaces registered here. Routes, input slots, and polling stay in settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            wizardDraft = store.beginRegistration(for: model)
                        } label: {
                            Label(isChinese ? "新增接口" : "Add Interface", systemImage: "plus")
                        }
                    }
                    if registrations.isEmpty {
                        ContentUnavailableView(
                            isChinese ? "尚未注册" : "Not registered",
                            systemImage: "rectangle.stack.badge.plus",
                            description: Text(isChinese ? "从供应商地址开始，按步骤把这个模型跑通。" : "Start from the provider URL and register this model step by step.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 10)], spacing: 10) {
                            ForEach(registrations) { registration in
                                RegisteredInterfaceCard(
                                    registration: registration,
                                    isChinese: isChinese,
                                    onEdit: { wizardDraft = store.beginEditingRegistration(registration) },
                                    onReset: { store.resetRegistrationToTemplate(registration.id) },
                                    onDelete: { store.deleteModelRegistration(registration) }
                                )
                            }
                        }
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.visible)
        }
        .onChange(of: model) { _, value in store.updateModel(value) }
        .sheet(item: $wizardDraft) { draft in
            ModelRegistrationWizardView(store: store, draft: draft) {
                wizardDraft = nil
            }
        }
    }

    private var modelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.title3)
                .foregroundStyle(isAgnesModel ? Color(red: 0.95, green: 0.17, blue: 0.46) : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                TextField(isChinese ? "模型名称" : "Model name", text: $model.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                TextField("model-id", text: $model.modelId)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(isChinese ? "供应商" : "Provider", selection: $model.providerId) {
                Text(isChinese ? "未关联" : "Unlinked").tag(Optional<UUID>.none)
                ForEach(store.configuration.providers) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }
            .frame(width: 180)
            Button {
                store.configuration.defaultModelId = model.id
                store.save()
            } label: {
                Label(isChinese ? "默认" : "Default", systemImage: store.configuration.defaultModelId == model.id ? "star.fill" : "star")
            }
            .disabled(store.configuration.defaultModelId == model.id)
            Button(role: .destructive) { store.deleteModel(model) } label: {
                Image(systemName: "trash")
            }
            .disabled(store.configuration.models.count <= 1)
        }
        .padding(12)
        .agnesAccentBackground(
            enabled: isAgnesModel,
            baseColor: isAgnesModel ? Color.secondary.opacity(0.03) : Color.clear,
            cornerRadius: 0
        )
    }
}

@MainActor
private struct RegisteredInterfaceCard: View {
    let registration: RegisteredModelInterface
    let isChinese: Bool
    let onEdit: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    private var isAgnesRegistration: Bool {
        AgnesProviderVisuals.isAgnesRegistration(registration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: registration.interfaceFamily == .conversation ? "bubble.left.and.bubble.right" : "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(isAgnesRegistration ? Color(red: 0.95, green: 0.17, blue: 0.46) : Color.accentColor)
                Text(registration.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                RegistrationStatusBadge(status: registration.status, isChinese: isChinese)
            }
            Text(registration.task.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(registration.inputCards) { card in
                    Image(systemName: card.modality.symbolName)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                ForEach(registration.outputSlots) { slot in
                    Image(systemName: slot.modality.symbolName)
                }
            }
            .font(.caption)
            Text(registration.path.isEmpty ? "/" : registration.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            parameterPreview(
                title: isChinese ? "输入" : "Inputs",
                values: registration.inputCards.map(\.parameterPath)
            )
            parameterPreview(
                title: isChinese ? "参数" : "Params",
                values: registration.nodeControls.map(\.parameterPath)
            )
            if let polling = registration.polling {
                Label(pollingSummary(polling), systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(isChinese ? "编辑" : "Edit", action: onEdit)
                Spacer()
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help(isChinese ? "恢复系统模板" : "Reset from system template")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
            .controlSize(.small)
        }
        .padding(11)
        .agnesAccentBackground(
            enabled: isAgnesRegistration,
            baseColor: isAgnesRegistration ? Color.secondary.opacity(0.04) : Color.clear,
            cornerRadius: 9
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .agnesAccentBorder(
            enabled: isAgnesRegistration,
            fallbackColor: .secondary.opacity(0.14),
            cornerRadius: 9
        )
    }

    @ViewBuilder
    private func parameterPreview(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(values, id: \.self) { value in
                            Text(value)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func pollingSummary(_ polling: ModelRegistrationPolling) -> String {
        let totalSeconds = polling.intervalSeconds * polling.maxAttempts
        let total = totalSeconds < 60 ? "\(totalSeconds)s" : "\(totalSeconds / 60)m"
        let prefix = isChinese ? "轮询" : "Polling"
        return "\(prefix): \(polling.method.rawValue) \(polling.pollingPath) · \(polling.intervalSeconds)s x \(polling.maxAttempts) (~\(total))"
    }
}

@MainActor
struct RegistrationStatusBadge: View {
    let status: RegistrationStatus
    let isChinese: Bool

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch status {
        case .draft: isChinese ? "草稿" : "Draft"
        case .unverified: isChinese ? "未验证" : "Unverified"
        case .verified: isChinese ? "已验证" : "Verified"
        case .disabled: isChinese ? "已停用" : "Disabled"
        }
    }

    private var color: Color {
        switch status {
        case .draft, .disabled: .secondary
        case .unverified: .orange
        case .verified: .green
        }
    }
}
