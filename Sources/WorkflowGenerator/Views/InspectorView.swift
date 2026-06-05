import SwiftUI

enum InspectorPanel {
    case nodeAssets
    case consistency
}

@MainActor
struct AdaptiveInspectorView: View {
    @Bindable var store: AppStore
    @Binding var activePanel: InspectorPanel?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                InspectorView(store: store, activePanel: $activePanel)
                    .frame(width: 376)
            }
    }
}

@MainActor
struct InspectorView: View {
    @Bindable var store: AppStore
    @Binding var activePanel: InspectorPanel?
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        Group {
            if let activePanel {
                InspectorFloatingCard(store: store, activePanel: $activePanel, panel: activePanel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: activePanel)
    }
}

@MainActor
private struct InspectorFloatingCard: View {
    @Bindable var store: AppStore
    @Binding var activePanel: InspectorPanel?
    let panel: InspectorPanel
    @Environment(\.colorScheme) private var colorScheme
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    InspectorSectionHeader(
                        title: title,
                        systemImage: symbolName,
                        trailing: trailingText
                    )

                    switch panel {
                    case .nodeAssets:
                        if let node = store.selectedNode {
                            NodeEditor(store: store, node: node)
                            AssetLibraryView(store: store)
                        } else {
                            ContentUnavailableView(copy.noNodeSelected, systemImage: "square.dashed")
                        }

                    case .consistency:
                        MediaConsistencyView(store: store)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: 22, x: 0, y: 10)
    }

    private var title: String {
        switch panel {
        case .nodeAssets: copy.nodeAndAssets
        case .consistency: copy.consistencyWindow
        }
    }

    private var symbolName: String {
        switch panel {
        case .nodeAssets: "rectangle.3.group"
        case .consistency: "scope"
        }
    }

    private var trailingText: String? {
        switch panel {
        case .nodeAssets: store.selectedNode?.title
        case .consistency: "\(store.configuration.workflow.consistency.categories.count)"
        }
    }
}



@MainActor
private struct InspectorSectionHeader: View {
    let title: String
    let systemImage: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer()
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
    }
}

@MainActor
private struct NodeEditor: View {
    @Bindable var store: AppStore
    @State var node: WorkflowNode
    @State private var configurationExpanded = false
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorCard {
                HStack(spacing: 10) {
                    Image(systemName: nodeIcon(node.kind))
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.node)
                            .font(.headline)
                        Text(node.kind.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteSelectedNode()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .quickHelp("删除当前选中的节点。")
                }

                TextField(copy.title, text: $node.title)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: node) { _, newValue in store.updateNode(newValue) }

                TextField(copy.description, text: $node.description, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: node) { _, newValue in store.updateNode(newValue) }
            }

            InspectorCard {
                DisclosureGroup(isExpanded: $configurationExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        NodeRoutingSection(store: store, node: $node)
                        Divider()
                        NodeLinkSection(node: $node, copy: copy)
                        Divider()
                        NodeStyleSection(node: $node, copy: copy)
                        Divider()
                        NodeAutomationSection(node: $node)
                    }
                    .padding(.top, 10)
                } label: {
                    Label(copy.nodeConfiguration, systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if node.kind != .consistency {
                InspectorCard {
                    ChatPanel(store: store, node: $node)
                }
            }
        }
        .onChange(of: node) { _, newValue in store.updateNode(newValue) }
        .onChange(of: store.configuration.workflow.nodes) { _, nodes in
            guard let selected = nodes.first(where: { $0.id == node.id }), selected != node else { return }
            node = selected
        }
        .onChange(of: store.configuration.workflow.selectedNodeId) { _, _ in
            if let selected = store.selectedNode {
                node = selected
            }
        }
    }

    private func nodeIcon(_ kind: NodeKind) -> String {
        switch kind {
        case .model: "cpu"
        case .agent: "terminal"
        case .consistency: "scope"
        }
    }
}

@MainActor
private struct NodeRoutingSection: View {
    @Bindable var store: AppStore
    @Binding var node: WorkflowNode
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }
    private var isChinese: Bool { store.configuration.language == .zhCN }
    private var selectableInterfaces: [RegisteredModelInterface] {
        store.selectableRegisteredInterfaces()
    }
    private var selectedInterface: RegisteredModelInterface? {
        node.registeredModelInterfaceId.flatMap { id in
            store.configuration.modelRegistrations.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption("路由")
            Picker(copy.kind, selection: $node.kind) {
                ForEach(NodeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if node.kind == .model {
                Picker(isChinese ? "已注册接口" : "Registered interface", selection: $node.registeredModelInterfaceId) {
                    Text(isChinese ? "选择接口" : "Choose interface")
                        .tag(Optional<UUID>.none)
                    ForEach(selectableInterfaces) { registration in
                        Text(interfaceLabel(registration))
                            .lineLimit(1)
                            .tag(Optional(registration.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: node.registeredModelInterfaceId) { _, interfaceId in
                    applyRegisteredInterface(interfaceId)
                }

                if let selectedInterface {
                    HStack(spacing: 7) {
                        RegistrationStatusBadge(status: selectedInterface.status, isChinese: isChinese)
                        Text(selectedInterface.task.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.openModelSettingsWindow(for: selectedInterface.modelId)
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                        .quickHelp(isChinese ? "在设置里编辑这个模型接口的地址、输入卡片和响应规则。" : "Edit this interface URL, input cards, and response rules in Settings.")
                    }
                    if selectedInterface.status == .unverified {
                        Label(
                            isChinese ? "这个接口尚未完成验证，节点仍可试用。" : "This interface has not been verified yet. The node can still try it.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    RegisteredInterfaceSummary(registration: selectedInterface, isChinese: isChinese)
                    RegisteredNodeControls(node: $node, registration: selectedInterface, isChinese: isChinese)
                } else {
                    Label(
                        isChinese ? "先在设置 > 模型中注册接口，再把它分配给节点。" : "Register an interface in Settings > Models, then assign it to this node.",
                        systemImage: "rectangle.stack.badge.plus"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else if node.kind == .agent {
                Picker(copy.agents, selection: $node.agentExecutable) {
                    ForEach(store.configuration.agents) { agent in
                        Text(agent.name).lineLimit(1).tag(Optional(agent.executable))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let executable = node.agentExecutable,
                   let agent = store.configuration.agents.first(where: { $0.executable == executable }) {
                    Button {
                        store.launchAgentTUI(agent)
                    } label: {
                        Label(copy.launchTUI, systemImage: "play.rectangle")
                    }
                    .disabled(!agent.isAvailable)
                }
            } else {
                ConsistencyNodeConfigSection(store: store, node: $node)
            }
        }
    }

    private func interfaceLabel(_ registration: RegisteredModelInterface) -> String {
        let modelName = store.configuration.models.first { $0.id == registration.modelId }?.name ?? copy.model
        return "\(modelName) · \(registration.title)"
    }

    private func applyRegisteredInterface(_ interfaceId: UUID?) {
        guard let interfaceId,
              let registration = store.configuration.modelRegistrations.first(where: { $0.id == interfaceId }) else {
            node.modelParameterOverrides = [:]
            return
        }
        node.modelId = registration.modelId
        node.inputModalities = Set(registration.inputCards.map(\.modality))
        node.outputModalities = registration.outputModalities
        node.modelParameterOverrides = [:]
    }
}

@MainActor
private struct RegisteredNodeControls: View {
    @Binding var node: WorkflowNode
    let registration: RegisteredModelInterface
    let isChinese: Bool

    var body: some View {
        if !registration.nodeControls.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text(isChinese ? "常用参数" : "Common parameters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(registration.nodeControls) { control in
                    controlRow(control)
                }
            }
        }
    }

    @ViewBuilder
    private func controlRow(_ control: NodeControlDefinition) -> some View {
        switch control.kind {
        case .text, .number:
            LabeledContent(control.title) {
                TextField(control.defaultValue, text: stringBinding(control))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 136)
            }
            .quickHelp(helpText(control))
        case .picker:
            Picker(control.title, selection: stringBinding(control)) {
                ForEach(control.choices, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.menu)
            .quickHelp(helpText(control))
        case .toggle:
            Toggle(control.title, isOn: boolBinding(control))
                .quickHelp(helpText(control))
        case .slider:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(control.title)
                    Spacer()
                    Text(stringBinding(control).wrappedValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: doubleBinding(control),
                    in: (control.minimum ?? 0)...(control.maximum ?? 1)
                )
            }
            .quickHelp(helpText(control))
        }
    }

    private func stringBinding(_ control: NodeControlDefinition) -> Binding<String> {
        Binding(
            get: { node.modelParameterOverrides[control.parameterPath] ?? control.defaultValue },
            set: { node.modelParameterOverrides[control.parameterPath] = $0 }
        )
    }

    private func boolBinding(_ control: NodeControlDefinition) -> Binding<Bool> {
        Binding(
            get: { stringBinding(control).wrappedValue.lowercased() == "true" },
            set: { node.modelParameterOverrides[control.parameterPath] = $0 ? "true" : "false" }
        )
    }

    private func doubleBinding(_ control: NodeControlDefinition) -> Binding<Double> {
        Binding(
            get: { Double(stringBinding(control).wrappedValue) ?? control.minimum ?? 0 },
            set: { node.modelParameterOverrides[control.parameterPath] = String(format: "%.2f", $0) }
        )
    }

    private func helpText(_ control: NodeControlDefinition) -> String {
        control.help.isEmpty
            ? (isChinese ? "该值只覆盖当前节点，不会修改模型注册表。" : "Overrides this node only. The registered interface stays unchanged.")
            : control.help
    }
}

@MainActor
private struct ConsistencyNodeConfigSection: View {
    @Bindable var store: AppStore
    @Binding var node: WorkflowNode
    private var isChinese: Bool { store.configuration.language == .zhCN }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "收纳传入资产，整理成后续节点可引用的参考资料。" : "Collects incoming assets and turns them into reusable references.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ModalityPicker(title: isChinese ? "接收资产类型" : "Accepted artifact types", selection: $node.consistencyConfig.acceptedArtifactTypes)
                .quickHelp(isChinese ? "只有勾选的类型会写入一致性资料库。未勾选的附件会被跳过并记录在运行日志里。" : "Only selected asset types are written to the consistency library. Others are skipped and logged.")

            Picker(isChinese ? "默认写入类别" : "Default category", selection: $node.consistencyConfig.defaultCategory) {
                Text(isChinese ? "自动判断" : "Auto").tag(Optional<ConsistencyCategoryKind>.none)
                ForEach(ConsistencyCategoryKind.allCases) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quickHelp(isChinese ? "选择类别后，传入资产会优先写入该类别；选择自动判断时，会按图片、视频、音频、文本等类型分配。" : "Choose a category to send incoming assets there first. Auto groups by file type.")

            Toggle(isChinese ? "自动去重" : "Auto deduplicate", isOn: $node.consistencyConfig.autoDeduplicate)
                .quickHelp(isChinese ? "同一路径的资产不会重复写入。若同时允许覆盖，则会更新已有记录。" : "Prevents the same path from being written twice. With overwrite enabled, existing records are updated.")
            Toggle(isChinese ? "提取一致性锚点" : "Extract anchors", isOn: $node.consistencyConfig.extractAnchors)
                .quickHelp(isChinese ? "为人物、风格、场景、声音等类别生成可检索的身份、风格、动作或声音锚点。" : "Creates searchable identity, style, motion, or voice anchors for each category.")
            Toggle(isChinese ? "允许覆盖已有资产" : "Allow overwrite", isOn: $node.consistencyConfig.allowOverwrite)
                .quickHelp(isChinese ? "遇到同一路径的资料时，允许用新的说明和标签更新原记录。" : "Allows notes and tags on an existing asset path to be updated.")
            Toggle(isChinese ? "锁定写入结果" : "Lock written assets", isOn: $node.consistencyConfig.lockWrittenAssets)
                .quickHelp(isChinese ? "写入后自动锁定，后续整理不会轻易覆盖这些资料。" : "New records are locked after writing so later passes do not overwrite them casually.")

            Picker(isChinese ? "写入策略" : "Write policy", selection: $node.consistencyConfig.writePolicy) {
                ForEach(ConsistencyWritePolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quickHelp(isChinese ? "append 保留全部；merge 合并说明；replace 用新记录替换；versioned 预留为版本化资料。" : "append keeps all records; merge updates notes; replace favors the latest record; versioned is reserved for asset versions.")
            Picker(isChinese ? "冲突策略" : "Conflict policy", selection: $node.consistencyConfig.conflictPolicy) {
                ForEach(ConsistencyConflictPolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quickHelp(isChinese ? "遇到锁定资料或重复资料时的处理方式。默认优先保留已锁定资料。" : "Controls how duplicates or locked records are handled. The default keeps locked records safe.")
        }
        .font(.caption)
    }
}

@MainActor
private struct RegisteredInterfaceSummary: View {
    let registration: RegisteredModelInterface
    let isChinese: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isChinese ? "接口输入 / 输出" : "Interface I/O")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Label(isChinese ? "输入" : "Input", systemImage: "arrow.down.to.line")
                modalityIcons(Set(registration.inputCards.map(\.modality)))
                Spacer(minLength: 4)
                Label(isChinese ? "输出" : "Output", systemImage: "arrow.up.from.line")
                modalityIcons(registration.outputModalities)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
        .quickHelp(isChinese ? "输入输出由设置里的模型注册表决定。节点只负责选择接口和填写少量常用参数。" : "Input and output come from the registered model interface. Nodes only choose an interface and edit common parameters.")
    }

    private func modalityIcons(_ modalities: Set<Modality>) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(modalities).sorted(by: { $0.rawValue < $1.rawValue })) { modality in
                Image(systemName: modality.symbolName)
                    .help(modality.title)
            }
        }
    }
}

@MainActor
private struct NodeLinkSection: View {
    @Binding var node: WorkflowNode
    let copy: AppCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(copy.nodeURL)
            TextField(copy.nodeURL, text: $node.referenceURL)
                .textFieldStyle(.roundedBorder)
                .quickHelp("节点卡片会显示链接按钮；可填 https://example.com，也可直接填域名。")
        }
    }
}

@MainActor
private struct NodeStyleSection: View {
    @Binding var node: WorkflowNode
    let copy: AppCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(copy.nodeStyle)
            Picker(copy.nodeStyle, selection: $node.visualStyle) {
                ForEach(NodeVisualStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            Text(node.visualStyle.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            NodeStylePreview(style: node.visualStyle, title: node.title, kind: node.kind)
        }
    }
}

@MainActor
private struct NodeAutomationSection: View {
    @Binding var node: WorkflowNode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption("自动化")
            Toggle("参与工作流自动运行", isOn: $node.workflowAutoRunEnabled)
                .font(.caption)
            VStack(alignment: .leading, spacing: 8) {
                Text(node.kind == .consistency ? "黑洞接收区" : "产出弹射 / 黑洞")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if node.kind != .consistency {
                    LabeledContent("角度") {
                        HStack {
                            Slider(value: $node.ejectionAngleDegrees, in: 0...360, step: 1)
                            Text("\(Int(node.ejectionAngleDegrees))°")
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    LabeledContent("力度") {
                        HStack {
                            Slider(value: $node.ejectionForce, in: 80...720, step: 10)
                            Text("\(Int(node.ejectionForce))")
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    LabeledContent("弧度") {
                        HStack {
                            Slider(value: $node.ejectionSpreadDegrees, in: 8...120, step: 1)
                            Text("\(Int(node.ejectionSpreadDegrees))°")
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Toggle("启用黑洞吸收区", isOn: $node.blackHoleEnabled)
                LabeledContent("半径") {
                    HStack {
                        Slider(value: $node.blackHoleRadius, in: 80...360, step: 10)
                        Text("\(Int(node.blackHoleRadius))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!node.blackHoleEnabled)
            }
            .font(.caption)

        }
    }
}

@MainActor
private struct SectionCaption: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

@MainActor
private struct NodeStylePreview: View {
    let style: NodeVisualStyle
    let title: String
    let kind: NodeKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: nodeIcon)
                .font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Node" : title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(style.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background {
            style.backgroundView()
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(style.strokeColor(isSelected: false, isActiveTarget: false), lineWidth: style.strokeWidth)
        }
    }

    private var nodeIcon: String {
        switch kind {
        case .model: "cpu"
        case .agent: "terminal"
        case .consistency: "scope"
        }
    }
}

@MainActor
private struct InspectorCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

@MainActor
private struct ModalityPicker: View {
    let title: String
    @Binding var selection: Set<Modality>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 4)], spacing: 4) {
                ForEach(Modality.allCases) { modality in
                    Toggle(isOn: Binding(
                        get: { selection.contains(modality) },
                        set: { isOn in
                            if isOn {
                                selection.insert(modality)
                            } else {
                                selection.remove(modality)
                            }
                        }
                    )) {
                        Label(modality.title, systemImage: modality.symbolName)
                    }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                }
            }
        }
    }
}

@MainActor
private struct ChatPanel: View {
    @Bindable var store: AppStore
    @Binding var node: WorkflowNode
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(copy.chat)
                    .font(.headline)
                Spacer()
                Button {
                    store.openChatWindow(for: node)
                } label: {
                    Label(copy.openChat, systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(copy.outputSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let lastOutput = node.chat.last(where: { ["assistant", "agent"].contains($0.role) }), !lastOutput.text.isEmpty {
                    Text(lastOutput.text)
                        .font(.callout)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(copy.waitingForOutput)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("特殊模板提示词")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HelpBadge(text: "工作流运行时自动发送这段提示词；手动聊天不会触发。")
                }
                TextField("用于工作流运行的预设提示词，不影响手动聊天", text: $node.specialTemplatePrompt, axis: .vertical)
                    .lineLimit(3...7)
                    .textFieldStyle(.roundedBorder)
                Toggle("工作流运行时自动发送", isOn: $node.sendsSpecialTemplateOnRun)
                    .font(.caption)
            }

            if let draft = node.chat.last, draft.role == "draft", !draft.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.pendingAttachments)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AttachmentList(paths: draft.attachments, allowsDelete: true) { path in
                        store.removePendingAttachment(path: path, from: node)
                        if let selected = store.selectedNode {
                            node = selected
                        }
                    }
                }
            }

            TextField(copy.messageThisNode, text: $node.draftMessage, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    store.attachFiles(to: node)
                    if let selected = store.selectedNode {
                        node = selected
                    }
                } label: {
                    Label(copy.attach, systemImage: "paperclip")
                }
                Spacer()
                if store.isExecuting(node) {
                    Button {
                        store.pauseExecution(for: node)
                    } label: {
                        Label(copy.pause, systemImage: "pause.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        store.sendMessage(from: node)
                        if let selected = store.selectedNode {
                            node = selected
                        }
                    } label: {
                        Label(copy.send, systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

@MainActor
private struct AttachmentList: View {
    let paths: [String]
    let allowsDelete: Bool
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(paths, id: \.self) { path in
                HStack(spacing: 6) {
                    Image(systemName: MediaAsset.inferModality(path: path).symbolName)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(URL(filePath: path).lastPathComponent)
                            .lineLimit(1)
                        Text(NSString(string: path).abbreviatingWithTildeInPath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if allowsDelete {
                        Button(role: .destructive) {
                            onDelete(path)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
            }
        }
    }
}

@MainActor
private struct MediaConsistencyView: View {
    @Bindable var store: AppStore
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(copy.consistencyWindow, isOn: $store.configuration.workflow.consistency.enabled)
                .font(.headline)

            TextField(copy.stylePrompt, text: $store.configuration.workflow.consistency.stylePrompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            TextField(copy.seed, text: $store.configuration.workflow.consistency.seed)
                .textFieldStyle(.roundedBorder)

            DisclosureGroup {
                Toggle("启用一致性验证", isOn: $store.configuration.workflow.consistency.validation.enabled)
                LabeledContent("通过阈值") {
                    HStack {
                        Slider(value: $store.configuration.workflow.consistency.validation.threshold, in: 0.1...1.0, step: 0.05)
                        Text(store.configuration.workflow.consistency.validation.threshold, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Toggle("低分时自动修复", isOn: $store.configuration.workflow.consistency.validation.autoRepair)
                Stepper(value: $store.configuration.workflow.consistency.validation.maxRepairAttempts, in: 0...5) {
                    Text("最多修复 \(store.configuration.workflow.consistency.validation.maxRepairAttempts) 次")
                        .font(.caption)
                }
            } label: {
                HStack {
                    Label("一致性验证", systemImage: "checkmark.seal")
                    HelpBadge(text: "生成节点完成后会基于本次使用的一致性资料给出基础评分；分数低于阈值时进入人工复核。")
                }
            }

            HStack {
                Text(copy.consistencyCategories)
                    .font(.subheadline.bold())
                Spacer()
                Menu {
                    ForEach(ConsistencyCategoryKind.allCases) { kind in
                        Button {
                            store.addConsistencyCategory(kind: kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbolName)
                        }
                    }
                } label: {
                    Label(copy.addConsistencyCategory, systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }

            ForEach(store.configuration.workflow.consistency.categories) { category in
                ConsistencyCategoryCard(store: store, category: category)
            }
        }
        .onChange(of: store.configuration.workflow.consistency) { _, _ in
            store.save()
        }
    }
}

@MainActor
private struct ConsistencyCategoryCard: View {
    @Bindable var store: AppStore
    let category: ConsistencyCategory
    @State private var draft: ConsistencyCategory
    @State private var isExpanded = false
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    init(store: AppStore, category: ConsistencyCategory) {
        self.store = store
        self.category = category
        _draft = State(initialValue: category)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ConsistencyTextInput(
                    title: copy.categoryName,
                    helpText: draft.name.isEmpty ? draft.kind.title : draft.name,
                    prompt: draft.kind.title,
                    text: $draft.name
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.categoryType)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(copy.categoryType, selection: Binding(
                        get: { draft.kind },
                        set: { newKind in
                            draft.kind = newKind
                            draft.name = newKind.title
                            draft.description = ""
                        }
                    )) {
                        ForEach(ConsistencyCategoryKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName)
                                .tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ConsistencyTextInput(
                    title: copy.categoryDescription,
                    helpText: draft.kind.guidance,
                    prompt: copy.categoryDescriptionPrompt,
                    text: $draft.description,
                    lineLimits: 2...5
                )

                if draft.assetPaths.isEmpty {
                    Text(copy.noReferenceAssets)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    AttachmentList(paths: draft.assetPaths, allowsDelete: true) { path in
                        store.removeConsistencyAsset(path: path, from: draft)
                    }
                }

                if !structuredAssets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("结构化资产")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(structuredAssets) { asset in
                            ConsistencyAssetRow(store: store, asset: asset)
                        }
                    }
                }

                HStack {
                    Button {
                        store.addConsistencyAssets(to: draft)
                    } label: {
                        Label(copy.addReferenceAsset, systemImage: "paperclip")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .destructive) {
                        store.deleteConsistencyCategory(draft)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.kind.symbolName)
                    .foregroundStyle(.secondary)
                Text(draft.name.isEmpty ? draft.kind.title : draft.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Text("\(max(draft.assetPaths.count, structuredAssets.count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: draft) { _, newValue in
            if newValue != category {
                store.updateConsistencyCategory(newValue)
            }
        }
        .onChange(of: category) { _, newValue in
            if newValue != draft {
                draft = newValue
            }
        }
    }

    private var structuredAssets: [ConsistencyAsset] {
        store.configuration.workflow.consistency.assets
            .filter { $0.category == draft.kind || draft.assetPaths.contains($0.artifactPath) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

@MainActor
private struct ConsistencyAssetRow: View {
    @Bindable var store: AppStore
    let asset: ConsistencyAsset

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: asset.assetType.symbolName)
                .foregroundStyle(asset.locked ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(asset.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    if asset.canonical {
                        Text("主参考")
                            .foregroundStyle(.green)
                    }
                    if asset.locked {
                        Text("锁定")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("v\(asset.version)")
                    if let sourceNodeId = asset.sourceNodeId {
                        Text(sourceNodeId.uuidString.prefix(6))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.setCanonicalConsistencyAsset(asset.id)
            } label: {
                Image(systemName: asset.canonical ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .help("设为主参考")
            Button {
                store.toggleConsistencyAssetLock(asset.id)
            } label: {
                Image(systemName: asset.locked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderless)
            .help("锁定 / 解锁")
            Button(role: .destructive) {
                store.removeConsistencyAsset(path: asset.artifactPath)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
private struct ConsistencyTextInput: View {
    let title: String
    let helpText: String?
    let prompt: String
    @Binding var text: String
    var lineLimits: ClosedRange<Int> = 1...1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let helpText {
                    HelpBadge(text: helpText)
                }
            }
            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(lineLimits)
                .textFieldStyle(.roundedBorder)
        }
    }
}

@MainActor
private struct AssetLibraryView: View {
    @Bindable var store: AppStore
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        InspectorCard {
            HStack {
                Text(copy.assets)
                    .font(.headline)
                Spacer()
                Text("\(store.configuration.workflow.assets.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.configuration.workflow.assets.isEmpty {
                Text(copy.noAssets)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(store.configuration.workflow.assets) { asset in
                    HStack(spacing: 8) {
                        Image(systemName: asset.modality.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.name)
                                .lineLimit(1)
                            Text(asset.displayPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.deleteAsset(asset)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .font(.caption)
                }
            }
        }
    }
}
