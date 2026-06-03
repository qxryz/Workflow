import SwiftUI

enum ModelRegistrationWizardStep: Int, CaseIterable, Identifiable {
    case connection = 1
    case interfaceType
    case requestContent
    case responseHandling
    case testAndRegister

    var id: Int { rawValue }
}

struct ModelRegistrationWizardDraft: Identifiable {
    var step: ModelRegistrationWizardStep = .connection
    var registration: RegisteredModelInterface
    var selectedTemplateId: String?

    var id: UUID { registration.id }
}

@MainActor
struct ModelRegistrationWizardView: View {
    @Bindable var store: AppStore
    @State var draft: ModelRegistrationWizardDraft
    let onClose: () -> Void

    @State private var configurationCheck = ""
    @State private var hasCheckedConfiguration = false

    private var isChinese: Bool { store.configuration.language == .zhCN }
    private var model: ModelConfig? { store.configuration.models.first { $0.id == draft.registration.modelId } }
    private var provider: ProviderConfig? {
        model?.providerId.flatMap { id in store.configuration.providers.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "注册模型接口" : "Register Model Interface")
                        .font(.title3.weight(.semibold))
                    Text(model?.modelId ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RegistrationStatusBadge(status: draft.registration.status, isChinese: isChinese)
            }
            .padding(14)
            Divider()
            HStack(spacing: 0) {
                stepRail
                    .frame(width: 190)
                Divider()
                ScrollView {
                    stepContent
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            }
            Divider()
            footer
        }
        .frame(width: 940, height: 680)
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(ModelRegistrationWizardStep.allCases) { step in
                Button {
                    draft.step = step
                } label: {
                    HStack(spacing: 8) {
                        Text("\(step.rawValue)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(step == draft.step ? Color.accentColor : .secondary.opacity(0.18), in: Circle())
                            .foregroundStyle(step == draft.step ? .white : .secondary)
                        Text(stepTitle(step))
                            .font(.caption.weight(step == draft.step ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(7)
                    .background(step == draft.step ? Color.accentColor.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(isChinese ? "接口细节只在这里维护。节点会自动使用注册后的输入槽与常用参数。" : "Maintain route details here. Nodes use registered slots and common controls automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch draft.step {
        case .connection:
            connectionStep
        case .interfaceType:
            interfaceTypeStep
        case .requestContent:
            requestContentStep
        case .responseHandling:
            responseHandlingStep
        case .testAndRegister:
            testAndRegisterStep
        }
    }

    private var connectionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                isChinese ? "确认连接地址" : "Confirm Connection",
                isChinese ? "先决定这个模型是否沿用供应商地址。其他接口细节会在后面的步骤出现。" : "First decide whether this model inherits the provider URL. Route details come later."
            )
            RegistrationPanel(
                title: isChinese ? "连接" : "Connection",
                icon: "link",
                help: isChinese ? "大多数聊天模型沿用供应商 Base URL。图片、视频、音频等特殊接口有时需要独立地址，模板会在下一步给出建议。" : "Most chat models inherit the provider Base URL. Media endpoints may use a dedicated URL; templates suggest one in the next step."
            ) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        RegistrationFieldLabel(isChinese ? "供应商" : "Provider")
                        Text(provider?.name ?? (isChinese ? "未关联" : "Unlinked"))
                    }
                    GridRow {
                        RegistrationFieldLabel(isChinese ? "模型 ID" : "Model ID")
                        Text(model?.modelId ?? "")
                            .font(.caption.monospaced())
                    }
                    GridRow {
                        RegistrationFieldLabel("Base URL")
                        Toggle(isChinese ? "沿用供应商地址" : "Inherit provider URL", isOn: $draft.registration.inheritsProviderBaseURL)
                    }
                    if !draft.registration.inheritsProviderBaseURL {
                        GridRow {
                            RegistrationFieldLabel(isChinese ? "重写地址" : "Override URL")
                            TextField("https://api.example.com/v1", text: $draft.registration.baseURLOverride)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }
    }

    private var interfaceTypeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                isChinese ? "选择接口类型" : "Choose Interface Type",
                isChinese ? "普通理解与对话通常使用 Messages。图片、视频、音频、3D 生成等使用特殊接口。" : "Understanding and chat usually use Messages. Image, video, audio, and 3D generation use special interfaces."
            )
            Picker("", selection: $draft.registration.interfaceFamily) {
                Text(isChinese ? "对话 / Messages" : "Conversation / Messages").tag(InterfaceFamily.conversation)
                Text(isChinese ? "特殊接口" : "Special Interface").tag(InterfaceFamily.special)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 9)], spacing: 9) {
                ForEach(availableTemplates) { template in
                    templateCard(template)
                }
            }
            if availableTemplates.isEmpty {
                Text(isChinese ? "当前供应商没有对应模板。你仍然可以继续，从空白接口开始填写。" : "No matching template is available. Continue to configure a blank interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var requestContentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                isChinese ? "填写请求内容" : "Configure Request Content",
                draft.registration.interfaceFamily == .conversation
                    ? (isChinese ? "声明 Messages 可以接收哪些材料。图片理解、视频理解等都属于这里。" : "Declare which materials Messages accept. Image and video understanding belong here.")
                    : (isChinese ? "把附件卡片放到供应商要求的参数位置。节点附件会按类型自动填入。" : "Map attachment cards to provider parameter paths. Node attachments fill matching cards automatically.")
            )
            if draft.registration.interfaceFamily == .conversation {
                conversationRequestEditor
            } else {
                specialRequestEditor
            }
        }
    }

    private var conversationRequestEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            materialPalette
            RegistrationPanel(
                title: isChinese ? "消息输入卡片" : "Message Input Cards",
                icon: "bubble.left.and.text.bubble.right",
                help: isChinese ? "每张卡片都会写入 Messages 内容数组。文本照常得到文本回复；附带图片、视频、音频或文件时，支持对应模态的模型会在同一个对话接口里理解附件。" : "Each card writes into the Messages content array. Text still returns text; attached images, video, audio, or files are understood by capable models through the same conversation endpoint."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "角色：system / user / assistant / tool" : "Roles: system / user / assistant / tool")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    inputCardRows
                }
            }
            RegistrationPanel(
                title: isChinese ? "接口能力" : "Capabilities",
                icon: "switch.2",
                help: isChinese ? "这些开关描述消息接口能否使用流式输出、思考内容、工具调用与结构化输出。模型不支持时请关闭。" : "Describe whether this Messages endpoint supports streaming, reasoning, tools, and structured output."
            ) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 7)], spacing: 7) {
                    featureToggle(title: isChinese ? "流式输出" : "Streaming", path: "stream", defaultValue: "true")
                    featureToggle(title: isChinese ? "思考内容" : "Reasoning", path: "thinking.enabled", defaultValue: "true")
                    featureToggle(title: isChinese ? "工具调用" : "Tools", path: "tools", defaultValue: "[]")
                    featureToggle(title: isChinese ? "结构化输出" : "Structured output", path: "response_format", defaultValue: #"{"type":"json_object"}"#)
                }
            }
            parameterEditor
        }
    }

    private var specialRequestEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            materialPalette
            RegistrationPanel(
                title: isChinese ? "输入卡片" : "Input Cards",
                icon: "square.and.arrow.down",
                help: isChinese ? "每张卡片代表一个可自动填入的附件槽。参数位置使用点号表达嵌套 JSON，例如 input.image_url。" : "Each card is an auto-filled attachment slot. Use dot paths for nested JSON, such as input.image_url."
            ) {
                inputCardRows
            }
            parameterEditor
        }
    }

    private var inputCardRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($draft.registration.inputCards) { $card in
                RegistrationInputSlotRow(
                    slot: $card,
                    interfaceTemplateId: draft.registration.templateId,
                    onMoveUp: { moveInputCard(card.id, offset: -1) },
                    onMoveDown: { moveInputCard(card.id, offset: 1) },
                    onDelete: { draft.registration.inputCards.removeAll { $0.id == card.id } }
                )
            }
            if draft.registration.interfaceFamily == .special {
                Button {
                    addInputCard(.file)
                } label: {
                    Label(isChinese ? "增加空白卡片" : "Add blank card", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
    }

    private var materialPalette: some View {
        RegistrationPanel(
            title: isChinese ? "附件卡片" : "Attachment Cards",
            icon: "square.grid.3x3",
            help: isChinese ? "拖动卡片到输入槽，或点击添加。图片、首帧、尾帧、参考图、音频、视频、遮罩和文件都可以独立映射。" : "Drag or add cards for images, frames, references, audio, video, masks, and files."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 7)], spacing: 7) {
                ForEach(paletteModalities) { modality in
                    Button {
                        addInputCard(modality)
                    } label: {
                        Label(modality.title, systemImage: modality.symbolName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .draggable(modality.rawValue)
                }
            }
            .controlSize(.small)
        }
    }

    private var paletteModalities: [Modality] {
        draft.registration.interfaceFamily == .conversation
            ? [.text, .image, .video, .audio, .file]
            : [.text, .image, .video, .audio, .file, .reference, .mask, .bbox]
    }

    private var parameterEditor: some View {
        RegistrationPanel(
            title: isChinese ? "可调参数" : "Parameters",
            icon: "slider.horizontal.3",
            help: isChinese ? "这里登记接口可接受的参数。只有选为节点常用项的参数，才会在节点面板里出现。" : "Register accepted parameters here. Only common node controls appear in node inspectors."
        ) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach($draft.registration.parameters) { $parameter in
                    HStack {
                        TextField("parameters.duration", text: $parameter.parameterPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                        TextField(isChinese ? "名称" : "Title", text: $parameter.title)
                            .textFieldStyle(.roundedBorder)
                        TextField(isChinese ? "默认值" : "Default", text: $parameter.defaultValue)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            draft.registration.parameters.removeAll { $0.id == parameter.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button {
                    draft.registration.parameters.append(
                        RegistrationParameterDefinition(parameterPath: "parameters.value", title: isChinese ? "新参数" : "New parameter", valueType: "string")
                    )
                } label: {
                    Label(isChinese ? "增加参数" : "Add parameter", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
    }

    private var responseHandlingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                isChinese ? "处理响应" : "Handle Response",
                isChinese ? "常规输出保持简洁；异步任务、轮询路径、Headers 与原始 JSON 收进高级设置。" : "Keep common outputs simple. Polling, headers, and raw JSON stay in advanced settings."
            )
            RegistrationPanel(
                title: isChinese ? "输出结果" : "Outputs",
                icon: "square.and.arrow.up",
                help: isChinese ? "填写响应中结果所在位置。星号表示遍历数组，例如 output.results.*.url。" : "Point to response fields. An asterisk walks arrays, such as output.results.*.url."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($draft.registration.outputSlots) { $slot in
                        RegistrationOutputSlotRow(slot: $slot) {
                            draft.registration.outputSlots.removeAll { $0.id == slot.id }
                        }
                    }
                    Button {
                        draft.registration.outputSlots.append(
                            ModelRegistrationOutputSlot(label: isChinese ? "新输出" : "New output", kind: .asset, modality: .file, jsonPath: "output.url")
                        )
                    } label: {
                        Label(isChinese ? "增加输出" : "Add output", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
            }
            RegistrationPanel(
                title: isChinese ? "响应方式" : "Response Mode",
                icon: "arrow.triangle.2.circlepath",
                help: isChinese ? "同步接口直接返回结果。SSE 会持续返回文本片段。异步任务先返回任务 ID，再按轮询规则查询。" : "Sync returns immediately. SSE streams chunks. Async tasks return an ID and require polling."
            ) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        RegistrationFieldLabel(isChinese ? "编码" : "Encoding")
                        Picker("", selection: $draft.registration.requestEncoding) {
                            ForEach(RequestEncoding.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        RegistrationFieldLabel(isChinese ? "方式" : "Mode")
                        Picker("", selection: $draft.registration.mode) {
                            ForEach(InvocationMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
            }
            DisclosureGroup(isChinese ? "高级响应设置" : "Advanced response settings") {
                VStack(alignment: .leading, spacing: 10) {
                    if draft.registration.mode == .async {
                        if draft.registration.polling == nil {
                            Button(isChinese ? "启用轮询" : "Enable polling") {
                                draft.registration.polling = ModelRegistrationPolling()
                            }
                        } else {
                            RegistrationPollingFields(
                                polling: Binding(
                                    get: { draft.registration.polling! },
                                    set: { draft.registration.polling = $0 }
                                )
                            )
                        }
                    }
                    Text(isChinese ? "接口路径" : "Endpoint path")
                        .font(.caption.weight(.semibold))
                    TextField("/chat/completions", text: $draft.registration.path)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                    Text(isChinese ? "模型参数位置" : "Model parameter path")
                        .font(.caption.weight(.semibold))
                    TextField("model", text: $draft.registration.modelParameterPath)
                        .textFieldStyle(.roundedBorder)
                    Text(isChinese ? "默认请求 JSON" : "Default request JSON")
                        .font(.caption.weight(.semibold))
                    TextEditor(text: $draft.registration.defaultRequestJSON)
                        .font(.caption.monospaced())
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.2)))
                    RegistrationHeaderFields(headers: $draft.registration.headers)
                }
                .padding(.top, 9)
            }
            .padding(11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var testAndRegisterStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                isChinese ? "预览并注册" : "Preview and Register",
                isChinese ? "先检查地址与模板，再决定保存为未验证，或在你确认官网调用已经跑通后标记为已验证。" : "Check the route first. Save as unverified, or mark verified after you have confirmed the official call works."
            )
            RegistrationPanel(
                title: isChinese ? "请求预览" : "Request Preview",
                icon: "doc.text.magnifyingglass",
                help: isChinese ? "这里只展示路由骨架。真实调用时，节点附件会按卡片映射填入请求。" : "This shows the route skeleton. Node attachments fill mapped cards during real invocation."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    previewRow("URL", resolvedURLPreview)
                    previewRow("Method", draft.registration.method.rawValue)
                    previewRow(isChinese ? "方式" : "Mode", draft.registration.mode.title)
                    previewRow(isChinese ? "输入卡片" : "Input cards", draft.registration.inputCards.map(\.label).joined(separator: ", "))
                    previewRow(isChinese ? "输出" : "Outputs", draft.registration.outputSlots.map(\.label).joined(separator: ", "))
                    if !draft.registration.headers.isEmpty {
                        previewRow("Headers", draft.registration.headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n"))
                    }
                }
            }
            HStack {
                Button {
                    checkConfiguration()
                } label: {
                    Label(isChinese ? "检查配置" : "Check Configuration", systemImage: "checkmark.circle")
                }
                if !configurationCheck.isEmpty {
                    Text(configurationCheck)
                        .font(.caption)
                        .foregroundStyle(hasCheckedConfiguration ? .green : .orange)
                }
            }
            Text(isChinese ? "未验证接口也可以使用，但节点会显示提醒。已验证状态应只用于你确认过官网请求可以成功返回的接口。" : "Unverified interfaces remain usable with a warning. Mark verified only after confirming the official request succeeds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button(isChinese ? "取消" : "Cancel", action: onClose)
            Spacer()
            if draft.step != .connection {
                Button {
                    moveStep(-1)
                } label: {
                    Label(isChinese ? "上一步" : "Back", systemImage: "chevron.left")
                }
            }
            if draft.step == .testAndRegister {
                Button {
                    store.saveRegistration(draft, as: .unverified)
                    onClose()
                } label: {
                    Label(isChinese ? "保存为未验证" : "Save Unverified", systemImage: "square.and.arrow.down")
                }
                Button {
                    store.saveRegistration(draft, as: .verified)
                    onClose()
                } label: {
                    Label(isChinese ? "确认已验证并注册" : "Register Verified", systemImage: "checkmark.seal.fill")
                }
                .disabled(!hasCheckedConfiguration)
            } else {
                Button {
                    moveStep(1)
                } label: {
                    Label(isChinese ? "下一步" : "Next", systemImage: "chevron.right")
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var availableTemplates: [ProviderInterfaceTemplate] {
        let key = providerTemplateKey(provider?.name ?? model?.provider ?? "")
        return ProviderInterfaceTemplateRegistry.all.filter {
            $0.providerKey == key && $0.family == draft.registration.interfaceFamily
        }
    }

    private var resolvedURLPreview: String {
        let base = draft.registration.inheritsProviderBaseURL ? provider?.baseURL ?? "" : draft.registration.baseURLOverride
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) +
            (draft.registration.path.hasPrefix("/") ? draft.registration.path : "/\(draft.registration.path)")
    }

    private func stepHeading(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func templateCard(_ template: ProviderInterfaceTemplate) -> some View {
        Button {
            store.applyTemplate(template, to: &draft)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(template.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if draft.selectedTemplateId == template.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(template.path.isEmpty ? "/" : template.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text(template.mode.title)
                    Spacer()
                    Text(template.docs.status == .verified ? (isChinese ? "官方已核验" : "Docs verified") : (isChinese ? "需按模型核验" : "Needs review"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(draft.selectedTemplateId == template.id ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(draft.selectedTemplateId == template.id ? Color.accentColor.opacity(0.55) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func conversationWrapper(for modality: Modality) -> String {
        switch modality {
        case .text:
            #"{"type":"text","text":"$value"}"#
        case .image, .reference, .mask:
            #"{"type":"image_url","image_url":{"url":"$value"}}"#
        case .video, .audioVideo:
            #"{"type":"video_url","video_url":{"url":"$value"}}"#
        case .audio, .music:
            #"{"type":"audio_url","audio_url":{"url":"$value"}}"#
        case .file:
            #"{"type":"file_url","file_url":{"url":"$value"}}"#
        default:
            #"{"type":"text","text":"$value"}"#
        }
    }

    private func featureToggle(title: String, path: String, defaultValue: String) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { draft.registration.parameters.contains { $0.parameterPath == path } },
                set: { enabled in
                    if enabled {
                        guard !draft.registration.parameters.contains(where: { $0.parameterPath == path }) else { return }
                        draft.registration.parameters.append(
                            RegistrationParameterDefinition(parameterPath: path, title: title, valueType: "boolean", defaultValue: defaultValue)
                        )
                    } else {
                        draft.registration.parameters.removeAll { $0.parameterPath == path }
                    }
                }
            )
        )
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 88, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func addInputCard(_ modality: Modality) {
        if draft.registration.interfaceFamily == .conversation {
            guard !draft.registration.inputCards.contains(where: { $0.modality == modality }) else { return }
            if draft.registration.defaultRequestJSON.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
                draft.registration.defaultRequestJSON = #"{"messages":[{"role":"user"}]}"#
            }
            draft.registration.inputCards.append(
                ModelRegistrationInputSlot(
                    label: modality.title,
                    parameterPath: "messages.0.content",
                    source: modality == .text ? .prompt : .attachment,
                    modality: modality,
                    required: modality == .text,
                    collectsAsArray: true,
                    valueTemplateJSON: conversationWrapper(for: modality)
                )
            )
            return
        }
        draft.registration.inputCards.append(
            ModelRegistrationInputSlot(
                label: modality.title,
                parameterPath: modality == .text ? "input.prompt" : "input.\(modality.rawValue)_url",
                source: modality == .text ? .prompt : .attachment,
                modality: modality,
                required: modality == .text
            )
        )
    }

    private func moveInputCard(_ id: UUID, offset: Int) {
        guard let index = draft.registration.inputCards.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard draft.registration.inputCards.indices.contains(target) else { return }
        draft.registration.inputCards.swapAt(index, target)
    }

    private func moveStep(_ delta: Int) {
        guard let step = ModelRegistrationWizardStep(rawValue: draft.step.rawValue + delta) else { return }
        draft.step = step
    }

    private func stepTitle(_ step: ModelRegistrationWizardStep) -> String {
        switch step {
        case .connection: isChinese ? "连接地址" : "Connection"
        case .interfaceType: isChinese ? "接口类型" : "Interface"
        case .requestContent: isChinese ? "请求内容" : "Request"
        case .responseHandling: isChinese ? "响应处理" : "Response"
        case .testAndRegister: isChinese ? "预览注册" : "Register"
        }
    }

    private func checkConfiguration() {
        guard let model, let provider else {
            configurationCheck = isChinese ? "请先关联供应商。" : "Link a provider first."
            hasCheckedConfiguration = false
            return
        }
        let context = ResolvedModelRegistration(model: model, provider: provider, registration: draft.registration)
        do {
            _ = try ModelRegistrationRouter().requestURL(context: context)
            configurationCheck = isChinese ? "地址与接口路径可以解析。" : "URL and path are valid."
            hasCheckedConfiguration = true
        } catch {
            configurationCheck = error.localizedDescription
            hasCheckedConfiguration = false
        }
    }

    private func providerTemplateKey(_ name: String) -> String {
        let value = name.lowercased()
        if value.contains("openai") { return "openai" }
        if value.contains("volc") || value.contains("ark") || value.contains("火山") { return "volc" }
        if value.contains("aliyun") || value.contains("dashscope") || value.contains("百炼") || value.contains("阿里") { return "aliyun" }
        if value.contains("deepseek") { return "deepseek" }
        if value.contains("minimax") { return "minimax" }
        return "custom"
    }
}
