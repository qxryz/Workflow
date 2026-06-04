import SwiftUI

@MainActor
struct WorkflowSettingsView: View {
    @Bindable var store: AppStore

    private var isChinese: Bool {
        store.configuration.language == .zhCN
    }

    var body: some View {
        Form {
            Section {
                Toggle(isChinese ? "允许手动运行工作流" : "Allow manual workflow runs", isOn: $store.configuration.workflow.automationSettings.manualTriggerEnabled)
                Toggle(isChinese ? "连续运行节点" : "Continuous node execution", isOn: $store.configuration.workflow.automationSettings.continuousRunNodes)
                    .quickHelp(isChinese ? "打开时会自动从当前 Level 跑到下一个 Level；关闭时每跑完一级就暂停，用户再次点击播放继续。" : "When enabled the run advances through levels automatically; when disabled it pauses after each level until Play is clicked again.")
                Picker(isChinese ? "资产传播" : "Asset propagation", selection: $store.configuration.workflow.automationSettings.assetPropagationMode) {
                    ForEach(WorkflowAssetPropagationMode.allCases) { mode in
                        Text(assetPropagationTitle(mode)).tag(mode)
                    }
                }
                .quickHelp(isChinese ? "箭头传递：只按逻辑箭头传递文本和资产。弹射接收：仍按逻辑箭头表达流程，同时把扇形命中的黑洞接收区解析为空间路由；空间路由会传父节点文本、JSON 和符合类型的资产。" : "Logic edge transfer sends text and assets only through logic edges. Fan receiver transfer keeps logic edges as process intent and resolves fan-to-receiver hits as spatial routes carrying parent text, JSON, and matching assets.")
                Toggle(isChinese ? "运行时自动发送节点特殊模板提示词" : "Send node template prompts during runs", isOn: $store.configuration.workflow.automationSettings.autoSendTemplatePrompt)
                Toggle(isChinese ? "没有逻辑目标时进入人工审查" : "Send leaf outputs to manual review", isOn: $store.configuration.workflow.automationSettings.manualReviewWhenNoLogicTarget)
                Toggle(isChinese ? "节点错误时停止整个工作流" : "Stop workflow on node error", isOn: $store.configuration.workflow.automationSettings.stopOnNodeError)
                HStack {
                    Button {
                        store.startWorkflowRun()
                    } label: {
                        Label(runButtonTitle, systemImage: "play.circle")
                    }
                    .disabled(store.isRunningWorkflow || !store.configuration.workflow.automationSettings.manualTriggerEnabled)

                    Button(role: .destructive) {
                        store.stopWorkflowRun()
                    } label: {
                        Label(isChinese ? "停止" : "Stop", systemImage: "stop.circle")
                    }
                    .disabled(!store.isRunningWorkflow)

                    Button {
                        store.syncWorkflowRunInputDefinitions()
                    } label: {
                        Label(isChinese ? "同步输入项" : "Sync Inputs", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .quickHelp(isChinese ? "重新扫描当前工作流，把起始节点、手动输入、变量占位等需要在运行前填写的内容整理到“运行输入表单”。已有填写值会尽量保留。" : "Scan the current workflow again and collect start-node/manual-input placeholders into the Run Input Form. Existing values are preserved when possible.")
                }
            } header: {
                HStack {
                    Text(isChinese ? "运行与触发" : "Run & Triggers")
                    HelpBadge(text: isChinese ? "这里控制工作流如何启动、是否连续跨 Level 运行，以及信息如何在节点之间传递。工作流按 DAG 执行：起点和终点自动从依赖关系推断，形成循环的逻辑箭头会被拒绝。" : "Controls workflow start behavior, level-by-level execution, and how information moves between nodes. Runs are DAG-based: starts and ends are inferred from dependencies; cyclic logic arrows are rejected.")
                }
            }

            Section {
                WorkflowGraphSummary(store: store, isChinese: isChinese)
            } header: {
                Label(isChinese ? "执行层级 / 缩略图" : "Execution Levels", systemImage: "square.stack.3d.up")
                    .quickHelp(isChinese ? "按工作流依赖分层展示。没有上游依赖的是 Level 0；同一级节点可以并行。启用弹射接收时，命中的接收区也会参与层级计算。" : "Shows workflow levels. Nodes with no upstream dependency are Level 0; nodes on the same level can run in parallel. Fan receiver routes can also affect levels.")
            }

            Section {
                if store.configuration.workflow.runInputDefinitions.isEmpty {
                    ContentUnavailableView(isChinese ? "还没有运行输入项" : "No run inputs yet", systemImage: "text.badge.plus")
                        .frame(minHeight: 120)
                } else {
                    ForEach($store.configuration.workflow.runInputDefinitions) { $definition in
                        WorkflowRunInputRow(
                            definition: $definition,
                            nodeTitle: nodeTitle(for: definition.sourceNodeId),
                            isChinese: isChinese,
                            delete: { store.deleteWorkflowRunInputDefinition(id: definition.id) }
                        )
                    }
                }
                Button {
                    store.addWorkflowRunInputDefinition()
                } label: {
                    Label(isChinese ? "创建运行输入" : "Create Run Input", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text(isChinese ? "运行输入表单" : "Run Input Form")
                    HelpBadge(text: isChinese ? "这里的值会在点击播放时进入当前 Workflow Run 的 runInputs，并可用 {{input.name}} 在节点特殊模板提示词中引用。必填项为空会禁止启动。" : "Values here are captured into the current Workflow Run's runInputs when Play is clicked. Reference them with {{input.name}}. Required empty inputs block the run.")
                }
            }

            Section(isChinese ? "变量 / 参数" : "Variables / Parameters") {
                Text(isChinese ? "在节点特殊模板提示词中使用 {{name}} 或 {{var.name}}。" : "Use {{name}} or {{var.name}} inside node template prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($store.configuration.workflow.workflowVariables) { $variable in
                    WorkflowKeyValueRow(
                        title: $variable.name,
                        value: $variable.value,
                        notes: $variable.notes,
                        isEnabled: $variable.isEnabled,
                        valueIsSecret: false,
                        delete: { store.deleteWorkflowVariable(id: variable.id) }
                    )
                }
                Button {
                    store.addWorkflowVariable()
                } label: {
                    Label(isChinese ? "创建变量" : "Create Variable", systemImage: "plus")
                }
            }

            Section(isChinese ? "Secret" : "Secrets") {
                Text(isChinese ? "用 {{secret.NAME}} 引用。注意：发给模型或 Agent 时会展开为真实值。" : "Reference with {{secret.NAME}}. It expands before sending to the model or agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($store.configuration.workflow.workflowSecrets) { $secret in
                    WorkflowKeyValueRow(
                        title: $secret.name,
                        value: $secret.value,
                        notes: $secret.notes,
                        isEnabled: $secret.isEnabled,
                        valueIsSecret: true,
                        delete: { store.deleteWorkflowSecret(id: secret.id) }
                    )
                }
                Button {
                    store.addWorkflowSecret()
                } label: {
                    Label(isChinese ? "创建 Secret" : "Create Secret", systemImage: "key")
                }
            }

            Section(isChinese ? "日志与调试" : "Logs & Debugging") {
                Toggle(isChinese ? "详细日志" : "Verbose logs", isOn: $store.configuration.workflow.workflowDebugSettings.verboseLogging)
                Toggle(isChinese ? "保留运行日志" : "Keep run logs", isOn: $store.configuration.workflow.workflowDebugSettings.keepRunLogs)
                Stepper(value: $store.configuration.workflow.workflowDebugSettings.maxLogEntries, in: 50...2000, step: 50) {
                    Text(isChinese ? "最多 \(store.configuration.workflow.workflowDebugSettings.maxLogEntries) 条日志" : "Keep \(store.configuration.workflow.workflowDebugSettings.maxLogEntries) log entries")
                }
                Button(role: .destructive) {
                    store.clearWorkflowLogs()
                } label: {
                    Label(isChinese ? "清空日志" : "Clear Logs", systemImage: "trash")
                }
                WorkflowLogList(store: store, isChinese: isChinese)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.syncWorkflowRunInputDefinitions()
        }
        .onChange(of: store.configuration.workflow.automationSettings) { _, _ in store.save() }
        .onChange(of: store.configuration.workflow.runInputDefinitions) { _, _ in store.save() }
        .onChange(of: store.configuration.workflow.workflowVariables) { _, _ in store.save() }
        .onChange(of: store.configuration.workflow.workflowSecrets) { _, _ in store.save() }
        .onChange(of: store.configuration.workflow.workflowDebugSettings) { _, _ in store.save() }
    }

    private var runButtonTitle: String {
        if store.configuration.workflow.runState.status == .waitingForNextLevel {
            return isChinese ? "继续下一 Level" : "Run Next Level"
        }
        return isChinese ? "运行工作流" : "Run Workflow"
    }

    private func assetPropagationTitle(_ mode: WorkflowAssetPropagationMode) -> String {
        switch mode {
        case .classic:
            isChinese ? "箭头传递" : "Logic edge transfer"
        case .bigMouth:
            isChinese ? "弹射接收" : "Fan receiver transfer"
        }
    }

    private func nodeTitle(for id: UUID?) -> String {
        guard let id,
              let node = store.configuration.workflow.nodes.first(where: { $0.id == id }) else {
            return isChinese ? "手动" : "Manual"
        }
        return node.title
    }
}

@MainActor
private struct WorkflowRunInputRow: View {
    @Binding var definition: WorkflowRunInputDefinition
    let nodeTitle: String
    let isChinese: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                TextField(isChinese ? "输入项名称" : "Input name", text: $definition.name)
                Picker("", selection: $definition.inputType) {
                    ForEach(WorkflowRunInputType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .labelsHidden()
                Toggle(isChinese ? "必填" : "Required", isOn: $definition.isRequired)
                    .toggleStyle(.checkbox)
                Toggle(isChinese ? "作为运行参数" : "Pass", isOn: $definition.passesToRun)
                    .toggleStyle(.checkbox)
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Text(isChinese ? "来源" : "Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nodeTitle)
                    .font(.caption.weight(.semibold))
                HelpBadge(text: definition.description.isEmpty ? (isChinese ? "这个输入会在运行开始时冻结到 runInputs。" : "This input is captured into runInputs when a run starts.") : definition.description)
            }

            TextField(isChinese ? "默认值" : "Default value", text: $definition.defaultValue, axis: .vertical)
                .lineLimit(1...3)
            TextField(isChinese ? "当前值" : "Current value", text: $definition.currentValue, axis: .vertical)
                .lineLimit(1...5)
            TextField(isChinese ? "说明文案" : "Description", text: $definition.description, axis: .vertical)
                .lineLimit(1...3)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

@MainActor
private struct WorkflowGraphSummary: View {
    @Bindable var store: AppStore
    let isChinese: Bool

    var body: some View {
        if let graph = try? WorkflowGraphService().build(from: store.configuration.workflow, spatialRoutes: store.previewSpatialArtifactRoutes()) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WorkflowMetricBadge(title: isChinese ? "节点" : "Nodes", value: "\(graph.nodeIds.count)")
                    WorkflowMetricBadge(title: isChinese ? "逻辑箭头" : "Logic", value: "\(graph.edges.count)")
                    WorkflowMetricBadge(title: isChinese ? "空间路由" : "Spatial", value: "\(graph.spatialRoutes.count)")
                    WorkflowMetricBadge(title: isChinese ? "当前 Level" : "Current", value: "\(store.configuration.workflow.runState.currentLevel)")
                    WorkflowMetricBadge(title: isChinese ? "状态" : "Status", value: store.configuration.workflow.runState.status.title)
                }
                ForEach(graph.orderedLevels, id: \.self) { level in
                    WorkflowLevelRow(
                        level: level,
                        nodeIds: graph.levels[level, default: []],
                        store: store,
                        isChinese: isChinese
                    )
                }
            }
        } else {
            Text(isChinese ? "存在循环依赖，暂时无法生成执行层级。请断开至少一条回路；起点和终点会从无上游/无下游节点自动推断。" : "A dependency cycle exists, so execution levels cannot be generated. Break at least one loop; starts and ends are inferred from nodes with no upstream or downstream dependency.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

@MainActor
private struct WorkflowLevelRow: View {
    let level: Int
    let nodeIds: [UUID]
    @Bindable var store: AppStore
    let isChinese: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Level \(level)")
                    .font(.subheadline.weight(.semibold))
                Text(levelState.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(levelColor.opacity(0.12), in: Capsule())
                if nodeIds.count > 1 {
                    Text(isChinese ? "并行节点" : "Parallel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(nodeIds, id: \.self) { nodeId in
                    NodeRunBadge(
                        title: nodeTitle(for: nodeId),
                        status: status(for: nodeId),
                        isCurrent: store.configuration.workflow.runState.currentLevel == level
                    )
                }
            }
        }
        .padding(10)
        .background(levelColor.opacity(store.configuration.workflow.runState.currentLevel == level ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var levelState: WorkflowLevelStatus {
        store.configuration.workflow.runState.levelStatuses[level] ?? .pending
    }

    private var levelColor: Color {
        switch levelState {
        case .pending: .secondary
        case .running: .blue
        case .success: .green
        case .waiting: .orange
        case .failed: .red
        case .skipped: .secondary
        case .cancelled: .red
        }
    }

    private func nodeTitle(for id: UUID) -> String {
        store.configuration.workflow.nodes.first { $0.id == id }?.title ?? id.uuidString
    }

    private func status(for id: UUID) -> WorkflowNodeRunStatus {
        store.configuration.workflow.runState.records.first { $0.nodeId == id }?.status ?? .pending
    }
}

@MainActor
private struct NodeRunBadge: View {
    let title: String
    let status: WorkflowNodeRunStatus
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
                .lineLimit(1)
            Text(statusTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.secondary.opacity(isCurrent ? 0.16 : 0.09), in: Capsule())
    }

    private var statusTitle: String {
        switch status {
        case .pending: "pending"
        case .waiting: "waiting"
        case .running: "running"
        case .succeeded: "success"
        case .waitingForReview: "review"
        case .failed: "failed"
        case .skipped: "skipped"
        case .cancelled: "cancelled"
        }
    }

    private var color: Color {
        switch status {
        case .pending: .secondary
        case .waiting, .waitingForReview: .orange
        case .running: .blue
        case .succeeded: .green
        case .failed, .cancelled: .red
        case .skipped: .secondary
        }
    }
}

@MainActor
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct WorkflowMetricBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
private struct WorkflowKeyValueRow: View {
    @Binding var title: String
    @Binding var value: String
    @Binding var notes: String
    @Binding var isEnabled: Bool
    let valueIsSecret: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                TextField("Name", text: $title)
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            if valueIsSecret {
                SecureField("Value", text: $value)
            } else {
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(1...4)
            }
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(1...3)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct WorkflowLogList: View {
    @Bindable var store: AppStore
    let isChinese: Bool

    var body: some View {
        let logs = store.configuration.workflow.runState.logs.suffix(80).reversed()
        if logs.isEmpty {
            ContentUnavailableView(isChinese ? "还没有日志" : "No logs yet", systemImage: "list.bullet.rectangle")
                .frame(minHeight: 120)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(logs)) { log in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(log.level.rawValue.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(color(for: log.level))
                                Spacer()
                                Text(log.createdAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(log.message)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 260)
        }
    }

    private func color(for level: WorkflowLogLevel) -> Color {
        switch level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
