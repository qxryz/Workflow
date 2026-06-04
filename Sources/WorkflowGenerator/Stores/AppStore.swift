import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    var configuration: AppConfiguration
    var isScanningAgents = false
    var isExecutingNode = false
    var executingNodeIds: Set<UUID> = []
    var showsSaveConfirmation = false
    var agentACPStatuses: [UUID: String] = [:]
    var settingsSelection = SettingsSelection()

    private let persistence = PersistenceService()
    private let agentScanner = AgentScannerService()
    private let workspaceService = WorkspaceService()
    private let nodeExecution = NodeExecutionService()
    private let providerService = ProviderService()
    private let chatWindowService = ChatWindowService()
    private let workflowGraphService = WorkflowGraphService()
    private let spatialRouteResolver = SpatialArtifactRouteResolver()
    private let consistencyContextCompiler = ConsistencyContextCompiler()
    private let consistencyAssetIngestion = ConsistencyAssetIngestionService()
    private let providerMigration = ProviderMigrationService()
    private var undoRedo = UndoRedoCoordinator()
    private var executionTasks: [UUID: Task<Void, Never>] = [:]
    private var workflowRunTask: Task<Void, Never>?
    private var activeResponseMessageIds: [UUID: UUID] = [:]
    private let canvasPasteboardType = NSPasteboard.PasteboardType("com.workflowgenerator.canvas-clipboard")
    private var saveDebouncer: Task<Void, Never>?
    private let saveDebounceInterval: Duration = .milliseconds(200)
    @ObservationIgnored private var cachedSpatialRoutes: [SpatialArtifactRoute]?
    @ObservationIgnored private var lastNodesHash: Int?
    @ObservationIgnored private var lastPropagationMode: WorkflowAssetPropagationMode?

    init() {
        configuration = persistence.load() ?? AppConfiguration()
        if providerMigration.migrate(&configuration) {
            persistence.save(configuration)
        }
        reconcileModelRegistrations()
        if providerMigration.normalizeAgents(&configuration) { persistence.save(configuration) }
        if configuration.defaultModelId == nil {
            configuration.defaultModelId = configuration.models.first?.id
        }
        prepareSelectedWorkspaceStorage()
        if let workspace = selectedWorkspace, let workflow = workspaceService.readWorkflow(for: workspace) {
            configuration.workflow = workflow
        } else if selectedWorkspace != nil, configuration.workflow.nodes.isEmpty {
            seedStarterWorkflow()
        } else if selectedWorkspace == nil {
            configuration.workflow = WorkflowDocument()
        }
        migrateLegacyWorkflowScopedSettingsIfNeeded()
        save()
    }

    var selectedNode: WorkflowNode? {
        guard let selectedNodeId = configuration.workflow.selectedNodeId else { return nil }
        return configuration.workflow.nodes.first { $0.id == selectedNodeId }
    }

    var activeAgentSessionNodes: [WorkflowNode] {
        configuration.workflow.nodes.filter { node in
            node.kind == .agent &&
            node.hasStartedPersistentChat &&
            node.usesPersistentChat &&
            node.agentExecutable?.isEmpty == false
        }
    }

    var hasMediaWorkflow: Bool {
        configuration.workflow.nodes.contains { node in
            !node.inputModalities.isDisjoint(with: [.image, .video, .audio]) ||
            !node.outputModalities.isDisjoint(with: [.image, .video, .audio])
        }
    }

    var selectedWorkspace: WorkspaceLocation? {
        guard let id = configuration.selectedWorkspaceId else { return configuration.workspaces.first }
        return configuration.workspaces.first { $0.id == id }
    }

    var canUndo: Bool { undoRedo.canUndo }
    var canRedo: Bool { undoRedo.canRedo }
    var undoCount: Int { undoRedo.undoCount }
    var redoCount: Int { undoRedo.redoCount }
    var undoMaxCount: Int { UndoRedoCoordinator.maxCount }
    var isRunningWorkflow: Bool { configuration.workflow.runState.status == .running }
    var isWaitingForNextLevel: Bool { configuration.workflow.runState.status == .waitingForNextLevel }

    func recordUndoSnapshot() {
        guard selectedWorkspace != nil else { return }
        undoRedo.recordSnapshot(configuration.workflow)
    }

    private func reconcileModelRegistrations() {
        var didChange = false
        let modelIds = Set(configuration.models.map(\.id))
        let previousCount = configuration.modelRegistrations.count
        configuration.modelRegistrations.removeAll { !modelIds.contains($0.modelId) }
        didChange = previousCount != configuration.modelRegistrations.count
        for model in configuration.models where !configuration.modelRegistrations.contains(where: { $0.modelId == model.id }) {
            let provider = model.providerId.flatMap { id in configuration.providers.first { $0.id == id } }
            if let registrations = ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: model, provider: provider) {
                configuration.modelRegistrations.append(contentsOf: registrations)
            } else {
                var draft = ModelRegistrationPresetRegistry.draft(for: model, provider: provider)
                draft.status = .draft
                draft.lastTestSummary = "Migrated from legacy model settings"
                configuration.modelRegistrations.append(draft)
            }
            didChange = true
        }
        if didChange {
            persistence.save(configuration)
        }
    }

    func undoWorkflow() {
        guard let previous = undoRedo.performUndo(current: configuration.workflow) else { return }
        configuration.workflow = previous
        save()
    }

    func redoWorkflow() {
        guard let next = undoRedo.performRedo(current: configuration.workflow) else { return }
        configuration.workflow = next
        save()
    }

    func addNode(kind: NodeKind) {
        guard selectedWorkspace != nil else { return }
        recordUndoSnapshot()
        let index = configuration.workflow.nodes.count + 1
        let title: String
        let description: String
        let outputModalities: Set<Modality>
        let agentExecutable: String?
        switch kind {
        case .model:
            title = "Model Node \(index)"
            description = "Describe what this node should do."
            outputModalities = [.text]
            agentExecutable = configuration.agents.first(where: \.isAvailable)?.executable ?? AgentConfig.candidates.first?.executable
        case .agent:
            title = "Agent Node \(index)"
            description = "Ask a local agent to work on this step."
            outputModalities = [.file]
            agentExecutable = configuration.agents.first(where: \.isAvailable)?.executable ?? AgentConfig.candidates.first?.executable
        case .consistency:
            title = "Consistency \(index)"
            description = "Collect incoming assets for later reference."
            outputModalities = []
            agentExecutable = nil
        }
        let defaultModelId = (kind == .agent || kind == .consistency) ? nil : configuration.defaultModelId
        let defaultRegisteredInterfaceId = defaultModelId.flatMap { modelId in
            selectableRegisteredInterfaces(for: modelId).first?.id
        }
        let node = WorkflowNode(
            title: title,
            description: description,
            kind: kind,
            modelId: defaultModelId,
            agentExecutable: agentExecutable,
            position: CanvasPoint(x: 420 + Double(index * 34), y: 280 + Double(index * 28)),
            inputModalities: [.text],
            outputModalities: outputModalities,
            chat: [],
            draftMessage: "",
            registeredModelInterfaceId: defaultRegisteredInterfaceId,
            visualStyle: kind == .consistency ? .signal : .glass
        )
        configuration.workflow.nodes.append(node)
        configuration.workflow.selectedNodeId = node.id
        save()
    }

    func updateNode(_ node: WorkflowNode) {
        guard selectedWorkspace != nil else { return }
        guard let index = configuration.workflow.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        var normalized = node
        switch node.kind {
        case .model:
            normalized.agentExecutable = nil
            if let interfaceId = normalized.registeredModelInterfaceId,
               let registration = configuration.modelRegistrations.first(where: { $0.id == interfaceId }) {
                normalized.modelId = registration.modelId
                normalized.inputModalities = Set(registration.inputCards.map(\.modality))
                normalized.outputModalities = registration.outputModalities
            } else if normalized.modelId == nil {
                normalized.modelId = configuration.defaultModelId
            }
        case .agent:
            normalized.modelId = nil
            normalized.registeredModelInterfaceId = nil
            normalized.modelParameterOverrides = [:]
            normalized.outputModalities = normalized.outputModalities.isEmpty ? [.file] : normalized.outputModalities
        case .consistency:
            normalized.agentExecutable = nil
            normalized.modelId = nil
            normalized.registeredModelInterfaceId = nil
            normalized.modelParameterOverrides = [:]
            normalized.outputModalities = []
            normalized.blackHoleEnabled = true
        }
        if normalized.kind == .model,
           normalized.registeredModelInterfaceId == nil,
           let modelId = normalized.modelId,
           let model = configuration.models.first(where: { $0.id == modelId }) {
            if normalized.inputModalities == [.text] || normalized.inputModalities.isEmpty {
                normalized.inputModalities = model.inputModalities
            }
            if normalized.outputModalities == [.text] || normalized.outputModalities.isEmpty {
                normalized.outputModalities = model.outputModalities
            }
        }
        if configuration.workflow.nodes[index] != normalized {
            recordUndoSnapshot()
        }
        configuration.workflow.nodes[index] = normalized
        save()
    }

    private func replaceNodeWithoutUndo(_ node: WorkflowNode) {
        guard let index = configuration.workflow.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        var updated = node
        enforceChatLimit(&updated.chat)
        configuration.workflow.nodes[index] = updated
        save()
    }

    private func enforceChatLimit(_ chat: inout [ChatMessage]) {
        let maxMessages = 200
        if chat.count > maxMessages {
            chat.removeFirst(chat.count - maxMessages)
        }
    }

    private func appendToMessage(nodeId: UUID, messageId: UUID, text: String, persist: Bool = true) {
        guard let nodeIndex = configuration.workflow.nodes.firstIndex(where: { $0.id == nodeId }),
              let messageIndex = configuration.workflow.nodes[nodeIndex].chat.firstIndex(where: { $0.id == messageId }) else { return }
        configuration.workflow.nodes[nodeIndex].chat[messageIndex].text += text
        let assetPaths = assetPaths(in: text)
        if !assetPaths.isEmpty {
            let existing = Set(configuration.workflow.nodes[nodeIndex].chat[messageIndex].attachments)
            let newPaths = assetPaths.filter { !existing.contains($0) }
            configuration.workflow.nodes[nodeIndex].chat[messageIndex].attachments.append(contentsOf: newPaths)
            addAssets(newPaths.map { path in
                MediaAsset(
                    name: URL(filePath: path).lastPathComponent,
                    path: path,
                    modality: MediaAsset.inferModality(path: path)
                )
            })
            let role = configuration.workflow.nodes[nodeIndex].chat[messageIndex].role
            if ["assistant", "agent"].contains(role) {
                popGeneratedAssets(newPaths, from: nodeId)
            }
        }
        if persist {
            save()
        }
    }

    private func assetPaths(in text: String) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []

        func append(_ rawPath: String) {
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "]")))
            guard !path.isEmpty, !seen.contains(path) else { return }
            guard FileManager.default.fileExists(atPath: path) else { return }
            seen.insert(path)
            paths.append(path)
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("[asset] ") {
                append(String(line.dropFirst("[asset] ".count)))
            } else if line.hasPrefix("[file written:") {
                append(String(line.dropFirst("[file written:".count)))
            }
        }
        return paths
    }

    private func persistentMessages(for node: WorkflowNode, fallbackPrompt: String) -> [ChatCompletionMessage] {
        guard node.kind == .model, node.usesPersistentChat else {
            return [ChatCompletionMessage(role: "user", content: fallbackPrompt)]
        }
        let messages = node.chat.compactMap { message -> ChatCompletionMessage? in
            guard message.role != "draft", !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let role: String
            switch message.role {
            case "user":
                role = "user"
            case "assistant", "agent":
                role = "assistant"
            default:
                return nil
            }
            return ChatCompletionMessage(role: role, content: message.text)
        }
        return messages.isEmpty ? [ChatCompletionMessage(role: "user", content: fallbackPrompt)] : messages
    }

    func selectNode(_ id: UUID) {
        guard selectedWorkspace != nil else { return }
        configuration.workflow.selectedNodeId = id
        configuration.workflow.selectedCanvasElementId = nil
        configuration.workflow.selectedNodeIds = [id]
        configuration.workflow.selectedCanvasElementIds = []
        save()
    }

    func setNodePosition(id: UUID, position: CanvasPoint, persist: Bool = true) {
        guard selectedWorkspace != nil else { return }
        guard let index = configuration.workflow.nodes.firstIndex(where: { $0.id == id }) else { return }
        configuration.workflow.nodes[index].position = position
        refreshConnections(affectedNodeIds: [id])
        if persist { save() }
    }

    func moveSelectedItems(nodeDelta: CGSize = .zero, elementDelta: CGSize = .zero, persist: Bool = false) {
        let movedNodeIds = configuration.workflow.selectedNodeIds
        let movedElementIds = configuration.workflow.selectedCanvasElementIds
        for index in configuration.workflow.nodes.indices where configuration.workflow.selectedNodeIds.contains(configuration.workflow.nodes[index].id) {
            configuration.workflow.nodes[index].position.x += nodeDelta.width
            configuration.workflow.nodes[index].position.y += nodeDelta.height
        }
        for index in configuration.workflow.canvasElements.indices where configuration.workflow.selectedCanvasElementIds.contains(configuration.workflow.canvasElements[index].id) {
            configuration.workflow.canvasElements[index].position.x += elementDelta.width
            configuration.workflow.canvasElements[index].position.y += elementDelta.height
        }
        refreshConnections(affectedNodeIds: movedNodeIds, affectedElementIds: movedElementIds)
        if persist { save() }
    }

    func snapSelectedItemsToGrid(gridSize: Double, persist: Bool = false) {
        let grid = max(gridSize, 1)
        let movedNodeIds = configuration.workflow.selectedNodeIds
        let movedElementIds = configuration.workflow.selectedCanvasElementIds
        for index in configuration.workflow.nodes.indices where configuration.workflow.selectedNodeIds.contains(configuration.workflow.nodes[index].id) {
            configuration.workflow.nodes[index].position.x = (configuration.workflow.nodes[index].position.x / grid).rounded() * grid
            configuration.workflow.nodes[index].position.y = (configuration.workflow.nodes[index].position.y / grid).rounded() * grid
        }
        for index in configuration.workflow.canvasElements.indices where configuration.workflow.selectedCanvasElementIds.contains(configuration.workflow.canvasElements[index].id) {
            configuration.workflow.canvasElements[index].position.x = (configuration.workflow.canvasElements[index].position.x / grid).rounded() * grid
            configuration.workflow.canvasElements[index].position.y = (configuration.workflow.canvasElements[index].position.y / grid).rounded() * grid
        }
        refreshConnections(affectedNodeIds: movedNodeIds, affectedElementIds: movedElementIds)
        if persist { save() }
    }

    func deleteSelectedNode() {
        guard selectedWorkspace != nil else { return }
        guard let id = configuration.workflow.selectedNodeId else { return }
        recordUndoSnapshot()
        configuration.workflow.nodes.removeAll { $0.id == id }
        configuration.workflow.selectedNodeId = configuration.workflow.nodes.first?.id
        save()
    }

    func sendMessage(from node: WorkflowNode) {
        guard selectedWorkspace != nil else { return }
        guard let nodeIndex = configuration.workflow.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        var updated = configuration.workflow.nodes[nodeIndex]
        let trimmed = updated.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let attachments = pendingAttachments(for: updated)
        if updated.chat.last?.role == "draft" {
            updated.chat.removeLast()
        }
        updated.chat.append(ChatMessage(role: "user", text: trimmed, attachments: attachments))
        let executionText = NodePromptBuilder().prompt(text: trimmed, attachments: attachments, nodeKind: updated.kind)
        let requestMessages = persistentMessages(for: updated, fallbackPrompt: executionText)
        let assistantRole = updated.kind == .agent ? "agent" : "assistant"
        let assistantId = UUID()
        updated.chat.append(ChatMessage(id: assistantId, role: assistantRole, text: "", attachments: []))
        enforceChatLimit(&updated.chat)
        if updated.usesPersistentChat {
            updated.hasStartedPersistentChat = true
            if updated.kind == .model, updated.persistentModelId == nil {
                updated.persistentModelId = updated.modelId
            }
        }
        updated.draftMessage = ""
        replaceNodeWithoutUndo(updated)

        executingNodeIds.insert(updated.id)
        isExecutingNode = true
        let nodeId = updated.id
        let task = Task {
            do {
                let stream = nodeExecution.stream(
                messages: requestMessages,
                prompt: executionText,
                attachments: attachments,
                node: updated,
                configuration: configuration,
                workspacePath: selectedWorkspace?.path
            )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        appendToMessage(nodeId: nodeId, messageId: assistantId, text: chunk, persist: false)
                    }
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        appendToMessage(nodeId: nodeId, messageId: assistantId, text: "Execution failed: \(error.localizedDescription)")
                        if updated.kind == .agent {
                            markAgentSessionInactive(nodeId: nodeId)
                        }
                    }
                }
            }
            await MainActor.run {
                executingNodeIds.remove(nodeId)
                executionTasks[nodeId] = nil
                activeResponseMessageIds[nodeId] = nil
                isExecutingNode = !executingNodeIds.isEmpty
                save()
            }
        }
        executionTasks[nodeId] = task
        activeResponseMessageIds[nodeId] = assistantId
    }

    func openChatWindow(for node: WorkflowNode) {
        chatWindowService.open(store: self, nodeId: node.id)
    }

    func applyAppearanceToChatWindows() {
        chatWindowService.applyAppearance(store: self)
    }

    func openModelSettings(for modelId: UUID?) {
        guard let modelId, configuration.models.contains(where: { $0.id == modelId }) else { return }
        settingsSelection.tab = .models
        settingsSelection.modelId = modelId
    }

    func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func isExecuting(_ node: WorkflowNode) -> Bool {
        executingNodeIds.contains(node.id)
    }

    func pauseExecution(for node: WorkflowNode) {
        guard executingNodeIds.contains(node.id) else { return }
        executionTasks[node.id]?.cancel()
        nodeExecution.cancel(node: node)
        if let messageId = activeResponseMessageIds[node.id] {
            appendToMessage(nodeId: node.id, messageId: messageId, text: AppCopy(locale: configuration.language).responsePaused)
        }
        executingNodeIds.remove(node.id)
        executionTasks[node.id] = nil
        activeResponseMessageIds[node.id] = nil
        isExecutingNode = !executingNodeIds.isEmpty
        save()
    }

    func startWorkflowRun() {
        guard selectedWorkspace != nil, workflowRunTask == nil else { return }
        if configuration.workflow.runState.status == .waitingForNextLevel,
           let runId = configuration.workflow.runState.runId {
            configuration.workflow.runState.status = .running
            configuration.workflow.runState.completedAt = nil
            appendWorkflowLog("Workflow run resumed at Level \(configuration.workflow.runState.currentLevel).", level: .info)
            save()
            workflowRunTask = Task {
                await runWorkflow(runId: runId, startingLevel: configuration.workflow.runState.currentLevel)
            }
            return
        }

        let spatialRoutes = resolvedSpatialArtifactRoutesForCurrentWorkflow()
        let graph: WorkflowGraph
        do {
            graph = try workflowGraphService.build(from: configuration.workflow, spatialRoutes: spatialRoutes)
        } catch {
            configuration.workflow.runState = WorkflowRunState(status: .failed, completedAt: Date(), lastError: error.localizedDescription)
            appendWorkflowLog(error.localizedDescription, level: .error)
            save()
            return
        }
        syncWorkflowRunInputDefinitions(saveImmediately: false, graph: graph)
        let issues = validateWorkflowRunInputs()
        guard issues.isEmpty else {
            configuration.workflow.runState = WorkflowRunState(status: .failed, completedAt: Date(), lastError: issues.joined(separator: "\n"))
            for issue in issues {
                appendWorkflowLog(issue, level: .error)
            }
            save()
            return
        }

        let runId = UUID()
        let firstLevel = graph.orderedLevels.first ?? 0
        let levelStatuses = Dictionary(uniqueKeysWithValues: graph.orderedLevels.map { ($0, WorkflowLevelStatus.pending) })
        configuration.workflow.runState = WorkflowRunState(
            runId: runId,
            status: .running,
            startedAt: Date(),
            completedAt: nil,
            currentLevel: firstLevel,
            continuousRunNodes: configuration.workflow.automationSettings.continuousRunNodes,
            runInputs: currentWorkflowRunInputs(),
            levelStatuses: levelStatuses,
            resolvedSpatialArtifactRoutes: spatialRoutes,
            runConsistencySnapshot: configuration.workflow.consistency.assets,
            runConsistencyDelta: [],
            activeNodeIds: [],
            reviewNodeIds: [],
            records: configuration.workflow.nodes.map {
                WorkflowNodeRunRecord(nodeId: $0.id, level: graph.nodeLevels[$0.id, default: 0], status: $0.workflowAutoRunEnabled ? .pending : .skipped)
            },
            logs: configuration.workflow.runState.logs,
            lastError: nil
        )
        if !configuration.workflow.automationSettings.manualTriggerEnabled {
            configuration.workflow.automationSettings.manualTriggerEnabled = true
        }
        appendWorkflowLog("Workflow run started.", level: .info)
        save()
        workflowRunTask = Task {
            await runWorkflow(runId: runId, startingLevel: firstLevel)
        }
    }

    func stopWorkflowRun() {
        workflowRunTask?.cancel()
        workflowRunTask = nil
        cancelAllExecutions(markPaused: false)
        configuration.workflow.runState.status = .cancelled
        configuration.workflow.runState.completedAt = Date()
        configuration.workflow.runState.activeNodeIds = []
        configuration.workflow.runState.levelStatuses[configuration.workflow.runState.currentLevel] = .cancelled
        for index in configuration.workflow.runState.records.indices where configuration.workflow.runState.records[index].status == .running {
            configuration.workflow.runState.records[index].status = .cancelled
            configuration.workflow.runState.records[index].completedAt = Date()
        }
        appendWorkflowLog("Workflow run cancelled.", level: .warning)
        save()
    }

    func rerunCurrentLevel() {
        guard configuration.workflow.runState.status == .waitingForNextLevel,
              let runId = configuration.workflow.runState.runId,
              workflowRunTask == nil else { return }
        let nextLevel = configuration.workflow.runState.currentLevel
        let completedLevel = configuration.workflow.runState.records
            .map(\.level)
            .filter { $0 < nextLevel }
            .max()
        guard let targetLevel = completedLevel else { return }
        for index in configuration.workflow.runState.records.indices where configuration.workflow.runState.records[index].level == targetLevel {
            configuration.workflow.runState.records[index].status = .pending
            configuration.workflow.runState.records[index].startedAt = nil
            configuration.workflow.runState.records[index].completedAt = nil
            configuration.workflow.runState.records[index].outputText = ""
            configuration.workflow.runState.records[index].outputAssetPaths = []
            configuration.workflow.runState.records[index].error = nil
            configuration.workflow.runState.records[index].message = ""
        }
        configuration.workflow.runState.levelStatuses[targetLevel] = .pending
        configuration.workflow.runState.currentLevel = targetLevel
        configuration.workflow.runState.status = .running
        configuration.workflow.runState.completedAt = nil
        appendWorkflowLog("Re-running Level \(targetLevel).", level: .info)
        save()
        workflowRunTask = Task {
            await runWorkflow(runId: runId, startingLevel: targetLevel)
        }
    }

    func syncWorkflowRunInputDefinitions(saveImmediately: Bool = true) {
        let graph = try? workflowGraphService.build(from: configuration.workflow)
        syncWorkflowRunInputDefinitions(saveImmediately: saveImmediately, graph: graph)
    }

    func addWorkflowRunInputDefinition() {
        configuration.workflow.runInputDefinitions.append(WorkflowRunInputDefinition(
            name: "input_\(configuration.workflow.runInputDefinitions.count + 1)",
            inputType: .text,
            description: "Manual workflow input.",
            passesToRun: true
        ))
        save()
    }

    func deleteWorkflowRunInputDefinition(id: UUID) {
        configuration.workflow.runInputDefinitions.removeAll { $0.id == id }
        save()
    }

    func updateLogicEdgeConfiguration(id: UUID, configuration draft: WorkflowLogicEdgeConfiguration) {
        guard let index = configuration.workflow.canvasElements.firstIndex(where: { $0.id == id }),
              configuration.workflow.canvasElements[index].isLogicConnection else { return }
        var edge = draft
        edge.id = id
        edge.sourceNodeId = configuration.workflow.canvasElements[index].startAnchor?.targetKind == .node ? configuration.workflow.canvasElements[index].startAnchor?.targetId : nil
        edge.targetNodeId = configuration.workflow.canvasElements[index].endAnchor?.targetKind == .node ? configuration.workflow.canvasElements[index].endAnchor?.targetId : nil
        recordUndoSnapshot()
        configuration.workflow.canvasElements[index].logicEdge = edge
        configuration.workflow.canvasElements[index].text = edge.displayName
        save()
    }

    func previewSpatialArtifactRoutes() -> [SpatialArtifactRoute] {
        resolvedSpatialArtifactRoutesForCurrentWorkflow()
    }

    func incomingSpatialRouteCount(for nodeId: UUID) -> Int {
        previewSpatialArtifactRoutes().filter { $0.targetNodeId == nodeId }.count
    }

    func consistencyAssetCount(for nodeId: UUID) -> Int {
        configuration.workflow.consistency.assets.filter { $0.sourceNodeId == nodeId }.count
    }

    func addWorkflowVariable() {
        configuration.workflow.workflowVariables.append(WorkflowVariable(name: "variable_\(configuration.workflow.workflowVariables.count + 1)", value: ""))
        save()
    }

    func deleteWorkflowVariable(id: UUID) {
        configuration.workflow.workflowVariables.removeAll { $0.id == id }
        save()
    }

    func addWorkflowSecret() {
        configuration.workflow.workflowSecrets.append(WorkflowSecret(name: "SECRET_\(configuration.workflow.workflowSecrets.count + 1)", value: ""))
        save()
    }

    func deleteWorkflowSecret(id: UUID) {
        configuration.workflow.workflowSecrets.removeAll { $0.id == id }
        save()
    }

    func clearWorkflowLogs() {
        configuration.workflow.runState.logs.removeAll()
        configuration.workflow.runState.records.removeAll()
        configuration.workflow.runState.reviewNodeIds.removeAll()
        configuration.workflow.runState.lastError = nil
        if configuration.workflow.runState.status != .running {
            configuration.workflow.runState.status = .idle
            configuration.workflow.runState.runId = nil
        }
        save()
    }

    private func runWorkflow(runId: UUID, startingLevel: Int) async {
        defer {
            workflowRunTask = nil
            isExecutingNode = !executingNodeIds.isEmpty
            save()
        }
        let spatialRoutes = configuration.workflow.runState.resolvedSpatialArtifactRoutes
        let graph: WorkflowGraph
        do {
            graph = try workflowGraphService.build(from: configuration.workflow, spatialRoutes: spatialRoutes)
        } catch {
            finishWorkflowRun(status: .failed, error: error.localizedDescription)
            return
        }
        let incomingEdges = graph.incomingEdges
        let outgoingEdges = graph.outgoingEdges
        let incomingSpatialRoutes = graph.incomingSpatialRoutes

        for level in graph.orderedLevels where level >= startingLevel {
            if Task.isCancelled {
                finishWorkflowRun(status: .cancelled)
                return
            }
            configuration.workflow.runState.currentLevel = level
            configuration.workflow.runState.levelStatuses[level] = .running
            appendWorkflowLog("Level \(level) started.", level: .info)
            save()

            let levelNodeIds = graph.levels[level, default: []]
            var runnable: [(nodeId: UUID, runInput: WorkflowNodeRunInput)] = []
            for nodeId in levelNodeIds {
                guard let node = configuration.workflow.nodes.first(where: { $0.id == nodeId }) else { continue }
                if !node.workflowAutoRunEnabled {
                    setWorkflowNodeStatus(nodeId, status: .skipped, message: "Node auto-run is disabled.")
                    continue
                }
                let edges = incomingEdges[nodeId, default: []]
                let spatial = incomingSpatialRoutes[nodeId, default: []]
                guard dependenciesAreSatisfied(for: nodeId, incomingEdges: edges, incomingSpatialRoutes: spatial) else {
                    setWorkflowNodeStatus(nodeId, status: .waiting, message: "Waiting for upstream dependency policy.")
                    continue
                }
                let nodeRunInput = makeNodeRunInput(node: node, level: level, incomingEdges: edges, incomingSpatialRoutes: spatial, runId: runId)
                if !nodeRunInput.allIncomingArtifacts.isEmpty {
                    addPendingAttachments(
                        nodeRunInput.allIncomingArtifacts,
                        to: nodeId,
                        draftMessage: "Workflow inputs from upstream nodes and spatial routes.",
                        saveImmediately: false
                    )
                }
                runnable.append((nodeId, nodeRunInput))
            }

            guard !runnable.isEmpty else {
                configuration.workflow.runState.levelStatuses[level] = .waiting
                configuration.workflow.runState.status = .waitingForReview
                appendWorkflowLog("Level \(level) has no runnable nodes. Manual confirmation is required.", level: .warning)
                save()
                return
            }

            await withTaskGroup(of: (UUID, WorkflowExecutionResult).self) { group in
                for item in runnable {
                    group.addTask {
                        let result = await self.executeWorkflowNode(nodeId: item.nodeId, runInput: item.runInput)
                        return (item.nodeId, result)
                    }
                }
                for await (nodeId, result) in group {
                    if result.succeeded {
                        let finalNodeStatus: WorkflowNodeRunStatus = result.consistencyValidation?.passed == false ? .waitingForReview : .succeeded
                        setWorkflowNodeStatus(
                            nodeId,
                            status: finalNodeStatus,
                            outputAssetPaths: result.assetPaths,
                            outputText: result.outputText,
                            absorbedAssetsCount: result.absorbedAssetsCount,
                            createdConsistencyAssetIds: result.createdConsistencyAssetIds,
                            updatedConsistencyAssetIds: result.updatedConsistencyAssetIds,
                            skippedAssets: result.skippedAssets,
                            conflicts: result.conflicts,
                            consistencyValidation: result.consistencyValidation,
                            message: result.summary
                        )
                        if result.consistencyValidation?.passed == false {
                            configuration.workflow.runState.reviewNodeIds.insert(nodeId)
                            appendWorkflowLog("\(nodeTitle(for: nodeId)) needs consistency review.", level: .warning, nodeId: nodeId)
                        }
                        if outgoingEdges[nodeId, default: []].isEmpty,
                           configuration.workflow.automationSettings.manualReviewWhenNoLogicTarget {
                            configuration.workflow.runState.reviewNodeIds.insert(nodeId)
                            setWorkflowNodeStatus(
                                nodeId,
                                status: .waitingForReview,
                                outputAssetPaths: result.assetPaths,
                                outputText: result.outputText,
                                message: "No outgoing logic target. Waiting for manual review."
                            )
                            appendWorkflowLog("\(nodeTitle(for: nodeId)) has no outgoing logic target; marked for manual review.", level: .warning, nodeId: nodeId)
                        }
                    } else {
                        let message = result.errorMessage ?? "Node execution failed."
                        setWorkflowNodeStatus(nodeId, status: .failed, outputText: result.outputText, error: message, message: message)
                        appendWorkflowLog(message, level: .error, nodeId: nodeId)
                    }
                }
            }

            if let failedRecord = configuration.workflow.runState.records.first(where: { $0.level == level && $0.status == .failed }),
               configuration.workflow.automationSettings.stopOnNodeError {
                configuration.workflow.runState.levelStatuses[level] = .failed
                finishWorkflowRun(status: .failed, error: failedRecord.error ?? failedRecord.message)
                return
            }

            let levelRecords = configuration.workflow.runState.records.filter { $0.level == level }
            if levelRecords.contains(where: { $0.status == .failed }) {
                configuration.workflow.runState.levelStatuses[level] = .failed
            } else if levelRecords.contains(where: { $0.status == .waiting || $0.status == .waitingForReview }) {
                configuration.workflow.runState.levelStatuses[level] = .waiting
            } else {
                configuration.workflow.runState.levelStatuses[level] = .success
            }

            if !configuration.workflow.runState.continuousRunNodes,
               let nextLevel = graph.orderedLevels.first(where: { $0 > level }) {
                configuration.workflow.runState.currentLevel = nextLevel
                configuration.workflow.runState.status = .waitingForNextLevel
                appendWorkflowLog("Workflow paused before Level \(nextLevel). Click Play to continue.", level: .info)
                save()
                return
            }
        }

        let finalStatus: WorkflowRunStatus = configuration.workflow.runState.reviewNodeIds.isEmpty ? .completed : .waitingForReview
        finishWorkflowRun(status: finalStatus)
    }

    private func executeWorkflowNode(nodeId: UUID, runInput: WorkflowNodeRunInput) async -> WorkflowExecutionResult {
        guard let nodeIndex = configuration.workflow.nodes.firstIndex(where: { $0.id == nodeId }) else {
            return WorkflowExecutionResult(succeeded: false, summary: "", outputText: "", assetPaths: [], errorMessage: "Node disappeared before execution.")
        }
        var node = configuration.workflow.nodes[nodeIndex]
        if node.kind == .consistency {
            return await executeConsistencyNode(node: node, runInput: runInput)
        }
        let prompt = runInput.finalPrompt
        let inputAssetPaths = runInput.allIncomingArtifacts
        let executionText = NodePromptBuilder().prompt(text: prompt, attachments: inputAssetPaths, nodeKind: node.kind)
        let userMessage = ChatMessage(role: "user", text: prompt, attachments: inputAssetPaths)
        let assistantRole = node.kind == .agent ? "agent" : "assistant"
        let assistantId = UUID()
        node.chat.append(userMessage)
        node.chat.append(ChatMessage(id: assistantId, role: assistantRole, text: "", attachments: []))
        enforceChatLimit(&node.chat)
        if node.usesPersistentChat {
            node.hasStartedPersistentChat = true
            if node.kind == .model, node.persistentModelId == nil {
                node.persistentModelId = node.modelId
            }
        }
        configuration.workflow.nodes[nodeIndex] = node
        setWorkflowNodeStatus(nodeId, status: .running, input: runInput, inputAssetPaths: inputAssetPaths, message: "Running \(node.title).")
        executingNodeIds.insert(nodeId)
        activeResponseMessageIds[nodeId] = assistantId
        isExecutingNode = true
        save()

        var output = ""
        do {
            let stream = nodeExecution.stream(
                messages: [ChatCompletionMessage(role: "user", content: executionText)],
                prompt: executionText,
                attachments: inputAssetPaths,
                node: node,
                configuration: configuration,
                workspacePath: selectedWorkspace?.path
            )
            for try await chunk in stream {
                if Task.isCancelled { throw CancellationError() }
                output += chunk
                appendToMessage(nodeId: nodeId, messageId: assistantId, text: chunk, persist: false)
            }
            let paths = assetPaths(in: output)
            let validation = consistencyAssetIngestion.validationResult(
                for: output,
                assetPaths: paths,
                context: runInput.consistencyContext,
                settings: configuration.workflow.consistency.validation
            )
            executingNodeIds.remove(nodeId)
            activeResponseMessageIds[nodeId] = nil
            isExecutingNode = !executingNodeIds.isEmpty
            return WorkflowExecutionResult(succeeded: true, summary: workflowOutputSummary(output), outputText: output, assetPaths: paths, errorMessage: nil, consistencyValidation: validation)
        } catch {
            executingNodeIds.remove(nodeId)
            activeResponseMessageIds[nodeId] = nil
            isExecutingNode = !executingNodeIds.isEmpty
            if !Task.isCancelled {
                appendToMessage(nodeId: nodeId, messageId: assistantId, text: "Execution failed: \(error.localizedDescription)", persist: false)
            }
            return WorkflowExecutionResult(succeeded: false, summary: "", outputText: output, assetPaths: [], errorMessage: error.localizedDescription)
        }
    }

    private func setWorkflowNodeStatus(
        _ nodeId: UUID,
        status: WorkflowNodeRunStatus,
        input: WorkflowNodeRunInput? = nil,
        inputAssetPaths: [String]? = nil,
        outputAssetPaths: [String]? = nil,
        outputText: String? = nil,
        error: String? = nil,
        absorbedAssetsCount: Int? = nil,
        createdConsistencyAssetIds: [UUID]? = nil,
        updatedConsistencyAssetIds: [UUID]? = nil,
        skippedAssets: [String]? = nil,
        conflicts: [ConsistencyConflict]? = nil,
        consistencyValidation: ConsistencyValidationResult? = nil,
        message: String = ""
    ) {
        if let index = configuration.workflow.runState.records.firstIndex(where: { $0.nodeId == nodeId }) {
            configuration.workflow.runState.records[index].status = status
            if status == .running, configuration.workflow.runState.records[index].startedAt == nil {
                configuration.workflow.runState.records[index].startedAt = Date()
            }
            if [.succeeded, .failed, .skipped, .waitingForReview, .cancelled].contains(status) {
                configuration.workflow.runState.records[index].completedAt = Date()
            }
            if let input {
                configuration.workflow.runState.records[index].input = input
            }
            if let inputAssetPaths {
                configuration.workflow.runState.records[index].inputAssetPaths = inputAssetPaths
            }
            if let outputAssetPaths {
                configuration.workflow.runState.records[index].outputAssetPaths = outputAssetPaths
            }
            if let outputText {
                configuration.workflow.runState.records[index].outputText = outputText
            }
            if let error {
                configuration.workflow.runState.records[index].error = error
            }
            if let absorbedAssetsCount {
                configuration.workflow.runState.records[index].absorbedAssetsCount = absorbedAssetsCount
            }
            if let createdConsistencyAssetIds {
                configuration.workflow.runState.records[index].createdConsistencyAssetIds = createdConsistencyAssetIds
            }
            if let updatedConsistencyAssetIds {
                configuration.workflow.runState.records[index].updatedConsistencyAssetIds = updatedConsistencyAssetIds
            }
            if let skippedAssets {
                configuration.workflow.runState.records[index].skippedAssets = skippedAssets
            }
            if let conflicts {
                configuration.workflow.runState.records[index].conflicts = conflicts
            }
            if let consistencyValidation {
                configuration.workflow.runState.records[index].consistencyValidation = consistencyValidation
            }
            if !message.isEmpty {
                configuration.workflow.runState.records[index].message = message
                configuration.workflow.runState.records[index].logs.append(message)
            }
        } else {
            configuration.workflow.runState.records.append(WorkflowNodeRunRecord(
                nodeId: nodeId,
                level: input?.level ?? 0,
                status: status,
                startedAt: status == .running ? Date() : nil,
                completedAt: [.succeeded, .failed, .skipped, .waitingForReview, .cancelled].contains(status) ? Date() : nil,
                input: input,
                inputAssetPaths: inputAssetPaths ?? [],
                outputAssetPaths: outputAssetPaths ?? [],
                outputText: outputText ?? "",
                error: error,
                logs: message.isEmpty ? [] : [message],
                message: message,
                absorbedAssetsCount: absorbedAssetsCount ?? 0,
                createdConsistencyAssetIds: createdConsistencyAssetIds ?? [],
                updatedConsistencyAssetIds: updatedConsistencyAssetIds ?? [],
                skippedAssets: skippedAssets ?? [],
                conflicts: conflicts ?? [],
                consistencyValidation: consistencyValidation
            ))
        }
        if status == .running {
            configuration.workflow.runState.activeNodeIds.insert(nodeId)
        } else {
            configuration.workflow.runState.activeNodeIds.remove(nodeId)
        }
        appendWorkflowLog(message.isEmpty ? "Node \(status.rawValue): \(nodeTitle(for: nodeId))" : message, level: status == .failed ? .error : .info, nodeId: nodeId)
    }

    private func finishWorkflowRun(status: WorkflowRunStatus, error: String? = nil) {
        configuration.workflow.runState.status = status
        configuration.workflow.runState.completedAt = Date()
        configuration.workflow.runState.activeNodeIds = []
        configuration.workflow.runState.lastError = error
        if let error {
            appendWorkflowLog(error, level: .error)
        } else {
            appendWorkflowLog("Workflow run \(status.rawValue).", level: status == .completed ? .info : .warning)
        }
    }

    private func appendWorkflowLog(_ message: String, level: WorkflowLogLevel, nodeId: UUID? = nil) {
        guard configuration.workflow.workflowDebugSettings.keepRunLogs || level == .error else { return }
        guard configuration.workflow.workflowDebugSettings.verboseLogging || level != .info else { return }
        configuration.workflow.runState.logs.append(WorkflowLogEntry(level: level, nodeId: nodeId, message: message))
        let limit = max(50, configuration.workflow.workflowDebugSettings.maxLogEntries)
        if configuration.workflow.runState.logs.count > limit {
            configuration.workflow.runState.logs.removeFirst(configuration.workflow.runState.logs.count - limit)
        }
    }

    private func workflowPrompt(for node: WorkflowNode, runInput: WorkflowNodeRunInput) -> String {
        var sections: [String] = []
        if configuration.workflow.automationSettings.autoSendTemplatePrompt,
           node.sendsSpecialTemplateOnRun,
           !node.specialTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(node.specialTemplatePrompt)
        } else if !node.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(node.description)
        } else {
            sections.append("Run this workflow node.")
        }
        if !runInput.parentOutputs.isEmpty {
            sections.append("Parent outputs:\n" + runInput.parentOutputs.map { parent in
                var lines = ["- \(nodeTitle(for: parent.parentNodeId)): \(workflowOutputSummary(parent.text))"]
                if !parent.artifacts.isEmpty {
                    lines.append("  artifacts: \(parent.artifacts.joined(separator: ", "))")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n"))
        }
        if !runInput.edgeInputs.isEmpty {
            sections.append("Logic edge inputs:\n" + runInput.edgeInputs.map { edge in
                "- \(edge.displayName.isEmpty ? edge.edgeId.uuidString : edge.displayName): payload=\(edge.payload), artifacts=\(edge.artifacts.joined(separator: ", "))"
            }.joined(separator: "\n"))
        }
        if !runInput.spatialArtifactInputs.isEmpty {
            sections.append("Spatial artifact inputs:\n" + runInput.spatialArtifactInputs.map { route in
                var lines = ["- \(nodeTitle(for: route.sourceNodeId)) -> \(nodeTitle(for: route.targetNodeId)) via \(route.createdBy)"]
                if !route.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  text: \(workflowOutputSummary(route.text))")
                }
                if !route.json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  json: \(route.json)")
                }
                if !route.artifacts.isEmpty {
                    lines.append("  artifacts: \(route.artifacts.joined(separator: ", "))")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n"))
        }
        if !runInput.runInputs.isEmpty {
            sections.append("Run inputs:\n" + runInput.runInputs.map { "- \($0.key): \($0.value)" }.sorted().joined(separator: "\n"))
        }
        if configuration.workflow.consistency.enabled, !runInput.consistencyContext.globalPrompt.isEmpty {
            sections.append("Consistency context:\n\(compiledConsistencyContextText(runInput.consistencyContext))")
        }
        let variables = configuration.workflow.workflowVariables.filter(\.isEnabled)
        if !variables.isEmpty {
            sections.append("Variables:\n" + variables.map { "- \($0.name): \($0.value)" }.joined(separator: "\n"))
        }
        if !configuration.workflow.workflowSecrets.filter(\.isEnabled).isEmpty {
            sections.append("Secrets available by name in Settings. Do not reveal secret values in final output.")
        }
        let inputAssetPaths = runInput.allIncomingArtifacts
        if !inputAssetPaths.isEmpty {
            sections.append("Input assets:\n" + inputAssetPaths.map { "- \($0)" }.joined(separator: "\n"))
        }
        return resolveWorkflowTemplate(sections.joined(separator: "\n\n"), node: node)
    }

    private func resolveWorkflowTemplate(_ template: String, node: WorkflowNode) -> String {
        var output = template
        let runId = configuration.workflow.runState.runId?.uuidString.lowercased() ?? ""
        output = output.replacingOccurrences(of: "{{run.id}}", with: runId)
        output = output.replacingOccurrences(of: "{{node.id}}", with: node.id.uuidString.lowercased())
        output = output.replacingOccurrences(of: "{{node.title}}", with: node.title)
        for variable in configuration.workflow.workflowVariables where variable.isEnabled {
            output = output.replacingOccurrences(of: "{{\(variable.name)}}", with: variable.value)
            output = output.replacingOccurrences(of: "{{var.\(variable.name)}}", with: variable.value)
        }
        for (key, value) in configuration.workflow.runState.runInputs {
            output = output.replacingOccurrences(of: "{{input.\(key)}}", with: value)
            output = output.replacingOccurrences(of: "{{runInput.\(key)}}", with: value)
        }
        for secret in configuration.workflow.workflowSecrets where secret.isEnabled {
            output = output.replacingOccurrences(of: "{{secret.\(secret.name)}}", with: secret.value)
        }
        return output
    }

    private func makeNodeRunInput(node: WorkflowNode, level: Int, incomingEdges: [WorkflowGraphEdge], incomingSpatialRoutes: [SpatialArtifactRoute], runId: UUID) -> WorkflowNodeRunInput {
        let parentOutputs = incomingEdges.compactMap { edge -> WorkflowParentOutput? in
            guard let parentRecord = configuration.workflow.runState.records.first(where: { $0.nodeId == edge.sourceNodeId }) else { return nil }
            return WorkflowParentOutput(
                parentNodeId: edge.sourceNodeId,
                text: parentRecord.outputText.isEmpty ? parentRecord.message : parentRecord.outputText,
                json: parentRecord.outputJSON,
                artifacts: mappedArtifacts(parentRecord.outputAssetPaths, using: edge.configuration)
            )
        }
        let edgeInputs = incomingEdges.compactMap { edge -> WorkflowEdgeRunInput? in
            guard let parentRecord = configuration.workflow.runState.records.first(where: { $0.nodeId == edge.sourceNodeId }) else { return nil }
            return WorkflowEdgeRunInput(
                edgeId: edge.id,
                displayName: edge.configuration.displayName,
                payload: mappedPayload(from: parentRecord, using: edge.configuration),
                artifacts: mappedArtifacts(parentRecord.outputAssetPaths, using: edge.configuration)
            )
        }
        let spatialInputs = incomingSpatialRoutes.compactMap { route -> SpatialArtifactInput? in
            guard let parentRecord = configuration.workflow.runState.records.first(where: { $0.nodeId == route.sourceNodeId }) else { return nil }
            let text = route.transfersText ? mappedSpatialPayload(from: parentRecord, using: route) : ""
            let json = route.transfersText ? parentRecord.outputJSON : ""
            let artifacts = parentRecord.outputAssetPaths.filter { route.acceptedTypes.contains(MediaAsset.inferModality(path: $0)) }
            guard !artifacts.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return SpatialArtifactInput(
                routeId: route.id,
                sourceNodeId: route.sourceNodeId,
                targetNodeId: route.targetNodeId,
                text: text,
                json: json,
                artifacts: artifacts,
                sourceFan: route.sourceFan,
                targetBlackhole: route.targetBlackhole
            )
        }
        let variables = Dictionary(uniqueKeysWithValues: configuration.workflow.workflowVariables.filter(\.isEnabled).map { ($0.name, $0.value) })
        let secretNames = configuration.workflow.workflowSecrets.filter(\.isEnabled).map(\.name)
        let allIncomingArtifacts = Array(Set(parentOutputs.flatMap(\.artifacts) + edgeInputs.flatMap(\.artifacts) + spatialInputs.flatMap(\.artifacts))).sorted()
        let consistencyContext = compileConsistencyContext(for: node, runInputs: configuration.workflow.runState.runInputs)
        var runInput = WorkflowNodeRunInput(
            nodeId: node.id,
            runId: runId,
            level: level,
            parentOutputs: parentOutputs,
            edgeInputs: edgeInputs,
            spatialArtifactInputs: spatialInputs,
            allIncomingArtifacts: allIncomingArtifacts,
            runInputs: configuration.workflow.runState.runInputs,
            variables: variables,
            secretNames: secretNames,
            consistencyContext: consistencyContext,
            useDefaultLLM: node.kind == .consistency ? node.consistencyConfig.useDefaultLLM : nil,
            consistencyWriteConfig: node.kind == .consistency ? node.consistencyConfig : nil,
            specialTemplatePrompt: node.specialTemplatePrompt,
            finalPrompt: ""
        )
        runInput.finalPrompt = workflowPrompt(for: node, runInput: runInput)
        return runInput
    }

    private func mappedPayload(from parentRecord: WorkflowNodeRunRecord, using edge: WorkflowLogicEdgeConfiguration) -> String {
        let mapping = edge.payloadMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        if mapping.isEmpty || mapping == "{}" {
            return parentRecord.outputText.isEmpty ? parentRecord.message : parentRecord.outputText
        }
        return """
        mapping: \(mapping)
        text: \(parentRecord.outputText.isEmpty ? parentRecord.message : parentRecord.outputText)
        json: \(parentRecord.outputJSON)
        """
    }

    private func mappedSpatialPayload(from parentRecord: WorkflowNodeRunRecord, using route: SpatialArtifactRoute) -> String {
        let text = parentRecord.outputText.isEmpty ? parentRecord.message : parentRecord.outputText
        let mapping = route.payloadMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mapping.isEmpty, mapping != "{}" else { return text }
        return """
        mapping: \(mapping)
        text: \(text)
        json: \(parentRecord.outputJSON)
        """
    }

    private func mappedArtifacts(_ artifacts: [String], using edge: WorkflowLogicEdgeConfiguration) -> [String] {
        let mapping = edge.artifactMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mapping.isEmpty, mapping != "{}" else { return artifacts }
        let lower = mapping.lowercased()
        return artifacts.filter { path in
            let modality = MediaAsset.inferModality(path: path).rawValue.lowercased()
            return lower.contains(modality) || lower.contains(URL(filePath: path).pathExtension.lowercased())
        }
    }

    private func dependenciesAreSatisfied(for nodeId: UUID, incomingEdges: [WorkflowGraphEdge], incomingSpatialRoutes: [SpatialArtifactRoute]) -> Bool {
        guard !incomingEdges.isEmpty || !incomingSpatialRoutes.isEmpty else { return true }
        if incomingEdges.contains(where: { $0.configuration.runPolicy == .manual || $0.configuration.dependencyPolicy == .manual }) {
            return false
        }
        let logicSatisfied: Bool
        if incomingEdges.isEmpty {
            logicSatisfied = true
        } else {
            let parentRecords = incomingEdges.compactMap { edge in
                configuration.workflow.runState.records.first(where: { $0.nodeId == edge.sourceNodeId }).map { (edge, $0) }
            }
            guard parentRecords.count == incomingEdges.count else { return false }
            let conditionMatched = parentRecords.filter { edge, record in edgeAllowsFlow(edge.configuration, parentRecord: record) }
            guard !conditionMatched.isEmpty else { return false }
            if incomingEdges.contains(where: { $0.configuration.dependencyPolicy == .anySuccess }) {
                logicSatisfied = conditionMatched.contains { _, record in record.status == .succeeded }
            } else if incomingEdges.allSatisfy({ $0.configuration.dependencyPolicy == .allDone }) {
                logicSatisfied = conditionMatched.count == incomingEdges.count && conditionMatched.allSatisfy { _, record in nodeRunIsDone(record.status) }
            } else {
                logicSatisfied = conditionMatched.count == incomingEdges.count && conditionMatched.allSatisfy { _, record in [.succeeded, .skipped].contains(record.status) }
            }
        }
        let spatialSatisfied = incomingSpatialRoutes.filter(\.createsDependency).allSatisfy { route in
            guard let record = configuration.workflow.runState.records.first(where: { $0.nodeId == route.sourceNodeId }) else { return false }
            return record.status == .succeeded || record.status == .skipped
        }
        return logicSatisfied && spatialSatisfied
    }

    private func edgeAllowsFlow(_ edge: WorkflowLogicEdgeConfiguration, parentRecord: WorkflowNodeRunRecord) -> Bool {
        guard edge.enabled else { return false }
        if edge.runPolicy == .manual { return false }
        let condition = edge.condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard edge.runPolicy == .condition, !condition.isEmpty else { return true }
        let haystack = "\(parentRecord.outputText)\n\(parentRecord.outputJSON)\n\(parentRecord.message)".lowercased()
        return haystack.contains(condition.lowercased())
    }

    private func nodeRunIsDone(_ status: WorkflowNodeRunStatus) -> Bool {
        [.succeeded, .failed, .skipped, .waitingForReview, .cancelled].contains(status)
    }

    private func resolvedSpatialArtifactRoutesForCurrentWorkflow() -> [SpatialArtifactRoute] {
        let currentMode = configuration.workflow.automationSettings.assetPropagationMode
        let currentHash = configuration.workflow.nodes.hashValue
        
        if let cached = cachedSpatialRoutes,
           lastNodesHash == currentHash,
           lastPropagationMode == currentMode {
            return cached
        }
        
        let routes = spatialRouteResolver.resolve(
            nodes: configuration.workflow.nodes,
            mode: currentMode
        )
        
        cachedSpatialRoutes = routes
        lastNodesHash = currentHash
        lastPropagationMode = currentMode
        
        return routes
    }

    private func compileConsistencyContext(for node: WorkflowNode, runInputs: [String: String]) -> ConsistencyContext {
        consistencyContextCompiler.compile(
            profile: configuration.workflow.consistency,
            snapshot: configuration.workflow.runState.runConsistencySnapshot,
            delta: configuration.workflow.runState.runConsistencyDelta,
            node: node
        )
    }

    private func compiledConsistencyContextText(_ context: ConsistencyContext) -> String {
        consistencyContextCompiler.render(context)
    }

    private func executeConsistencyNode(node: WorkflowNode, runInput: WorkflowNodeRunInput) async -> WorkflowExecutionResult {
        let config = runInput.consistencyWriteConfig ?? node.consistencyConfig
        let accepted = config.acceptedArtifactTypes
        let incoming = runInput.allIncomingArtifacts.filter { accepted.contains(MediaAsset.inferModality(path: $0)) }
        guard !incoming.isEmpty else {
            return WorkflowExecutionResult(
                succeeded: true,
                summary: "No accepted artifacts reached the consistency node.",
                outputText: "Consistency node found no accepted incoming artifacts.",
                assetPaths: [],
                errorMessage: nil,
                absorbedAssetsCount: 0
            )
        }

        var existingPaths = Set(configuration.workflow.consistency.assets.map(\.artifactPath))
        var createdAssetIds: [UUID] = []
        var updatedAssetIds: [UUID] = []
        var skipped: [String] = []
        var conflicts: [ConsistencyConflict] = []
        for path in incoming {
            if config.autoDeduplicate, existingPaths.contains(path) {
                if config.allowOverwrite || config.writePolicy == .replace || config.writePolicy == .merge {
                    let updated = updateExistingConsistencyAsset(path: path, node: node, config: config, llmSummary: nil)
                    updatedAssetIds.append(contentsOf: updated)
                    continue
                }
                skipped.append(path)
                let conflict = ConsistencyConflict(
                    type: .duplicate,
                    category: config.defaultCategory ?? consistencyAssetIngestion.defaultConsistencyKind(for: MediaAsset.inferModality(path: path)),
                    assetIds: configuration.workflow.consistency.assets.filter { $0.artifactPath == path }.map(\.id),
                    severity: .low,
                    message: "Duplicate consistency asset skipped: \(URL(filePath: path).lastPathComponent)"
                )
                conflicts.append(conflict)
                configuration.workflow.consistency.conflicts.append(conflict)
                continue
            }
            let asset = consistencyAssetIngestion.makeAsset(
                path: path,
                node: node,
                runId: runInput.runId,
                sourceNodeId: sourceNodeId(for: path, runInput: runInput),
                sourceRouteId: sourceRouteId(for: path, runInput: runInput),
                config: config,
                categoryName: { [weak self] kind in self?.categoryName(for: kind) ?? kind.title },
                llmSummary: nil
            )
            let isFirstEntityVersion = !configuration.workflow.consistency.entities.contains { $0.category == asset.category && $0.name == asset.name }
            var writableAsset = asset
            writableAsset.canonical = isFirstEntityVersion
            configuration.workflow.consistency.assets.append(writableAsset)
            configuration.workflow.runState.runConsistencyDelta.append(writableAsset)
            upsertConsistencyEntity(for: writableAsset)
            appendConsistencyPath(path, to: writableAsset.category)
            createdAssetIds.append(writableAsset.id)
            existingPaths.insert(path)
        }

        let output = "Absorbed \(createdAssetIds.count) consistency assets. Skipped \(skipped.count) duplicate or unsupported assets."
        return WorkflowExecutionResult(
            succeeded: true,
            summary: output,
            outputText: output,
            assetPaths: [],
            errorMessage: nil,
            absorbedAssetsCount: createdAssetIds.count,
            createdConsistencyAssetIds: createdAssetIds,
            updatedConsistencyAssetIds: updatedAssetIds,
            skippedAssets: skipped,
            conflicts: conflicts
        )
    }

    private func updateExistingConsistencyAsset(path: String, node: WorkflowNode, config: ConsistencyNodeConfiguration, llmSummary: String?) -> [UUID] {
        var updated: [UUID] = []
        for index in configuration.workflow.consistency.assets.indices where configuration.workflow.consistency.assets[index].artifactPath == path {
            if configuration.workflow.consistency.assets[index].locked, config.conflictPolicy == .preferLocked {
                continue
            }
            configuration.workflow.consistency.assets[index].updatedAt = Date()
            configuration.workflow.consistency.assets[index].locked = configuration.workflow.consistency.assets[index].locked || config.lockWrittenAssets
            if let llmSummary, !llmSummary.isEmpty {
                configuration.workflow.consistency.assets[index].description = llmSummary
                configuration.workflow.consistency.assets[index].promptSnippets.positive = [llmSummary]
                configuration.workflow.consistency.assets[index].metadata["updatedByNode"] = node.id.uuidString
            }
            updated.append(configuration.workflow.consistency.assets[index].id)
        }
        return updated
    }

    private func categoryName(for kind: ConsistencyCategoryKind) -> String {
        configuration.workflow.consistency.categories.first(where: { $0.kind == kind })?.name ?? kind.title
    }

    private func sourceRouteId(for path: String, runInput: WorkflowNodeRunInput) -> UUID? {
        if let spatial = runInput.spatialArtifactInputs.first(where: { $0.artifacts.contains(path) }) {
            return spatial.routeId
        }
        if let edge = runInput.edgeInputs.first(where: { $0.artifacts.contains(path) }) {
            return edge.edgeId
        }
        return nil
    }

    private func sourceNodeId(for path: String, runInput: WorkflowNodeRunInput) -> UUID? {
        if let spatial = runInput.spatialArtifactInputs.first(where: { $0.artifacts.contains(path) }) {
            return spatial.sourceNodeId
        }
        if let parent = runInput.parentOutputs.first(where: { $0.artifacts.contains(path) }) {
            return parent.parentNodeId
        }
        return nil
    }

    private func appendConsistencyPath(_ path: String, to kind: ConsistencyCategoryKind) {
        if !configuration.workflow.consistency.referenceAssets.contains(path) {
            configuration.workflow.consistency.referenceAssets.append(path)
        }
        if let index = configuration.workflow.consistency.categories.firstIndex(where: { $0.kind == kind }) {
            if !configuration.workflow.consistency.categories[index].assetPaths.contains(path) {
                configuration.workflow.consistency.categories[index].assetPaths.append(path)
            }
        } else {
            configuration.workflow.consistency.categories.append(ConsistencyCategory(name: kind.title, kind: kind, description: "", assetPaths: [path]))
        }
    }

    private func upsertConsistencyEntity(for asset: ConsistencyAsset) {
        if let index = configuration.workflow.consistency.entities.firstIndex(where: { $0.category == asset.category && $0.name == asset.name }) {
            configuration.workflow.consistency.entities[index].versions.append(asset.id)
            if asset.canonical || configuration.workflow.consistency.entities[index].canonicalAssetId == nil {
                configuration.workflow.consistency.entities[index].canonicalAssetId = asset.id
            }
            if asset.locked {
                configuration.workflow.consistency.entities[index].lockedAssetIds.append(asset.id)
            }
        } else {
            configuration.workflow.consistency.entities.append(ConsistencyEntity(
                id: asset.entityId,
                category: asset.category,
                name: asset.name,
                versions: [asset.id],
                canonicalAssetId: asset.id,
                lockedAssetIds: asset.locked ? [asset.id] : []
            ))
        }
    }

    private func currentWorkflowRunInputs() -> [String: String] {
        var inputs: [String: String] = [:]
        for definition in configuration.workflow.runInputDefinitions where definition.passesToRun {
            inputs[definition.name] = definition.resolvedValue
        }
        return inputs
    }

    private func validateWorkflowRunInputs() -> [String] {
        var seen = Set<String>()
        var issues: [String] = []
        for definition in configuration.workflow.runInputDefinitions where definition.passesToRun {
            if seen.contains(definition.name) {
                issues.append("Duplicate workflow input name: \(definition.name)")
            }
            seen.insert(definition.name)
            guard definition.passesToRun, definition.isRequired, definition.resolvedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            issues.append("Required workflow input is empty: \(definition.name)")
        }
        return issues
    }

    private func syncWorkflowRunInputDefinitions(saveImmediately: Bool, graph: WorkflowGraph?) {
        var definitions = configuration.workflow.runInputDefinitions
        let existingNames = Set(definitions.map(\.name))
        let startIds = graph?.startNodeIds ?? configuration.workflow.nodes.map(\.id)
        for node in configuration.workflow.nodes where startIds.contains(node.id) {
            let name = "node.\(safeInputName(node.title)).input"
            guard !existingNames.contains(name) else { continue }
            definitions.append(WorkflowRunInputDefinition(
                name: name,
                inputType: node.inputModalities.contains(.file) ? .file : .textarea,
                defaultValue: node.draftMessage,
                currentValue: "",
                isRequired: false,
                description: "起始节点 \(node.title) 的运行输入；可在节点模板中用 {{input.\(name)}} 引用。",
                sourceNodeId: node.id,
                passesToRun: true
            ))
        }
        configuration.workflow.runInputDefinitions = definitions
        if saveImmediately {
            save()
        }
    }

    private func safeInputName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return name.isEmpty ? "input" : name
    }

    private func workflowOutputSummary(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Node completed without text output." }
        let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        return String(oneLine.prefix(240))
    }

    private func nodeTitle(for nodeId: UUID) -> String {
        configuration.workflow.nodes.first(where: { $0.id == nodeId })?.title ?? nodeId.uuidString
    }

    func setPersistentChatEnabled(_ isEnabled: Bool, for node: WorkflowNode) {
        guard var updated = configuration.workflow.nodes.first(where: { $0.id == node.id }) else { return }
        updated.usesPersistentChat = isEnabled
        if !isEnabled {
            updated.hasStartedPersistentChat = false
        }
        replaceNodeWithoutUndo(updated)
    }

    func resetPersistentChat(for node: WorkflowNode) {
        pauseExecution(for: node)
        guard var updated = configuration.workflow.nodes.first(where: { $0.id == node.id }) else { return }
        updated.chat.removeAll()
        updated.draftMessage = ""
        updated.hasStartedPersistentChat = false
        updated.persistentSessionId = UUID().uuidString.lowercased()
        updated.persistentModelId = nil
        nodeExecution.closeSession(node: node)
        replaceNodeWithoutUndo(updated)
    }

    private func markAgentSessionInactive(nodeId: UUID) {
        guard var updated = configuration.workflow.nodes.first(where: { $0.id == nodeId }),
              updated.kind == .agent else { return }
        updated.hasStartedPersistentChat = false
        updated.persistentSessionId = UUID().uuidString.lowercased()
        nodeExecution.closeSession(node: updated)
        replaceNodeWithoutUndo(updated)
    }

    func addModel() {
        let model = ModelConfig(name: "Custom Model", provider: "OpenAI Compatible", providerId: nil, baseURL: "https://", modelId: "model-id", supportedModalities: [.text], inputModalities: [.text], outputModalities: [.text], endpointKind: .chatCompletions, endpointPath: ModelEndpointKind.chatCompletions.defaultPath, requestParametersJSON: "{}", apiKeyReference: "API_KEY")
        configuration.models.append(model)
        configuration.modelRegistrations.append(ModelRegistrationPresetRegistry.draft(for: model, provider: nil))
        configuration.defaultModelId = configuration.defaultModelId ?? model.id
        save()
    }

    func updateModel(_ model: ModelConfig) {
        guard let index = configuration.models.firstIndex(where: { $0.id == model.id }) else { return }
        configuration.models[index] = model
        save()
    }

    func registrations(for model: ModelConfig) -> [ModelRegistration] {
        configuration.modelRegistrations.filter { $0.modelId == model.id }
    }

    func beginRegistration(for model: ModelConfig) -> ModelRegistrationWizardDraft {
        let provider = model.providerId.flatMap { id in configuration.providers.first { $0.id == id } }
        let recommended = ProviderInterfaceTemplateRegistry
            .recommended(providerKey: provider?.name ?? model.provider, modelId: model.modelId)
            .first
        let registration: RegisteredModelInterface
        if let provider, let recommended {
            registration = RegisteredModelInterface(template: recommended, model: model, provider: provider)
        } else {
            registration = ModelRegistrationPresetRegistry.draft(for: model, provider: provider)
        }
        return ModelRegistrationWizardDraft(registration: registration, selectedTemplateId: recommended?.id)
    }

    func beginEditingRegistration(_ registration: RegisteredModelInterface) -> ModelRegistrationWizardDraft {
        ModelRegistrationWizardDraft(registration: registration, selectedTemplateId: registration.templateId)
    }

    func applyTemplate(_ template: ProviderInterfaceTemplate, to draft: inout ModelRegistrationWizardDraft) {
        guard let model = configuration.models.first(where: { $0.id == draft.registration.modelId }),
              let provider = model.providerId.flatMap({ id in configuration.providers.first { $0.id == id } }) else {
            return
        }
        let id = draft.registration.id
        var applied = RegisteredModelInterface(template: template, model: model, provider: provider)
        applied.id = id
        draft.registration = applied
        draft.selectedTemplateId = template.id
    }

    func saveRegistration(_ draft: ModelRegistrationWizardDraft, as status: RegistrationStatus) {
        var registration = draft.registration
        registration.status = status
        registration.lastModifiedByUser = true
        if let index = configuration.modelRegistrations.firstIndex(where: { $0.id == registration.id }) {
            configuration.modelRegistrations[index] = registration
        } else {
            configuration.modelRegistrations.append(registration)
        }
        save()
    }

    func resetRegistrationToTemplate(_ registrationId: UUID) {
        guard let index = configuration.modelRegistrations.firstIndex(where: { $0.id == registrationId }),
              let templateId = configuration.modelRegistrations[index].templateId,
              let template = ProviderInterfaceTemplateRegistry.template(id: templateId),
              let model = configuration.models.first(where: { $0.id == configuration.modelRegistrations[index].modelId }),
              let provider = model.providerId.flatMap({ id in configuration.providers.first { $0.id == id } }) else {
            return
        }
        let previous = configuration.modelRegistrations[index]
        var reset = RegisteredModelInterface(template: template, model: model, provider: provider)
        reset.id = previous.id
        reset.status = .draft
        reset.lastTestSummary = "Reset from system template"
        configuration.modelRegistrations[index] = reset
        save()
    }

    func selectableRegisteredInterfaces(for modelId: UUID? = nil) -> [RegisteredModelInterface] {
        configuration.modelRegistrations.filter { registration in
            registration.status.isNodeSelectable &&
            (modelId == nil || registration.modelId == modelId)
        }
    }

    func addModelRegistration(to model: ModelConfig, task: ModelTask = .chat) {
        let provider = model.providerId.flatMap { id in configuration.providers.first { $0.id == id } }
        configuration.modelRegistrations.append(ModelRegistrationPresetRegistry.make(model: model, provider: provider, task: task))
        save()
    }

    func updateModelRegistration(_ registration: ModelRegistration) {
        guard let index = configuration.modelRegistrations.firstIndex(where: { $0.id == registration.id }) else { return }
        var updated = registration
        updated.lastModifiedByUser = true
        configuration.modelRegistrations[index] = updated
        save()
    }

    func deleteModelRegistration(_ registration: ModelRegistration) {
        configuration.modelRegistrations.removeAll { $0.id == registration.id }
        save()
    }

    func resetModelRegistration(_ registration: ModelRegistration) {
        if registration.templateId.flatMap(ProviderInterfaceTemplateRegistry.template(id:)) != nil {
            resetRegistrationToTemplate(registration.id)
            return
        }
        guard let model = configuration.models.first(where: { $0.id == registration.modelId }),
              let index = configuration.modelRegistrations.firstIndex(where: { $0.id == registration.id }) else { return }
        let provider = model.providerId.flatMap { id in configuration.providers.first { $0.id == id } }
        var replacement = ModelRegistrationPresetRegistry.make(model: model, provider: provider, task: registration.task, presetKey: registration.presetKey)
        replacement.id = registration.id
        configuration.modelRegistrations[index] = replacement
        save()
    }

    func validateModelRegistration(_ registration: ModelRegistration) {
        guard let model = configuration.models.first(where: { $0.id == registration.modelId }),
              let providerId = model.providerId,
              let provider = configuration.providers.first(where: { $0.id == providerId }),
              let index = configuration.modelRegistrations.firstIndex(where: { $0.id == registration.id }) else { return }
        var updated = registration
        let context = ResolvedModelRegistration(model: model, provider: provider, registration: updated)
        do {
            _ = try ModelRegistrationRouter().requestURL(context: context)
            updated.lastStatus = provider.apiKey.isEmpty ? "地址可用，待填写 API Key" : "配置可用"
            updated.status = .unverified
        } catch {
            updated.lastStatus = error.localizedDescription
        }
        updated.lastTestedAt = Date()
        configuration.modelRegistrations[index] = updated
        save()
    }

    func updateModelInferenceRule(_ rule: ModelInferenceRule) {
        guard let index = configuration.modelInferenceRules.firstIndex(where: { $0.id == rule.id }) else { return }
        configuration.modelInferenceRules[index] = rule
        save()
    }

    func addModelInferenceRule() {
        configuration.modelInferenceRules.append(ModelInferenceRule(name: "Custom Rule", keywords: ["keyword"], endpointKind: .chatCompletions, inputModalities: [.text], outputModalities: [.text]))
        save()
    }

    func deleteModelInferenceRule(_ rule: ModelInferenceRule) {
        configuration.modelInferenceRules.removeAll { $0.id == rule.id }
        save()
    }

    func resetModelInferenceRules() {
        configuration.modelInferenceRules = ModelInferenceRule.defaults
        save()
    }

    func deleteModel(_ model: ModelConfig) {
        configuration.models.removeAll { $0.id == model.id }
        configuration.modelRegistrations.removeAll { $0.modelId == model.id }
        if configuration.defaultModelId == model.id {
            configuration.defaultModelId = configuration.models.first?.id
        }
        for index in configuration.workflow.nodes.indices where configuration.workflow.nodes[index].modelId == model.id {
            configuration.workflow.nodes[index].modelId = configuration.defaultModelId
        }
        save()
    }

    func addProvider(from preset: ProviderConfig) {
        var provider = preset
        provider.id = UUID()
        provider.apiKey = ""
        provider.fetchedModelIds = []
        provider.lastStatus = "Not tested"
        configuration.providers.append(provider)
        save()
    }

    func updateProvider(_ provider: ProviderConfig) {
        guard let index = configuration.providers.firstIndex(where: { $0.id == provider.id }) else { return }
        configuration.providers[index] = provider
        save()
    }

    func updateLanguage(_ language: AppLanguage) {
        configuration.language = language
        save()
    }

    func deleteProvider(_ provider: ProviderConfig) {
        configuration.providers.removeAll { $0.id == provider.id }
        configuration.models.removeAll { $0.providerId == provider.id }
        let modelIds = Set(configuration.models.map(\.id))
        configuration.modelRegistrations.removeAll { !modelIds.contains($0.modelId) }
        configuration.endpointProfiles.removeAll { $0.providerId == provider.id }
        configuration.modelCapabilities.removeAll { !modelIds.contains($0.modelId) }
        save()
    }

    func fetchProviderModels(_ provider: ProviderConfig) {
        if var current = configuration.providers.first(where: { $0.id == provider.id }) {
            current.lastStatus = "Fetching models..."
            updateProvider(current)
        }
        Task {
            let result = await providerService.fetchModels(provider: provider)
            await MainActor.run {
                guard var current = configuration.providers.first(where: { $0.id == provider.id }) else { return }
                switch result {
                case .success(let ids):
                    current.fetchedModelIds = ids
                    current.lastStatus = ids.isEmpty ? "Connected, no models returned" : "Connected: \(ids.count) models"
                case .failure(let error):
                    current.lastStatus = "Failed: \(error.localizedDescription)"
                }
                updateProvider(current)
            }
        }
    }

    func testProviderConnection(_ provider: ProviderConfig) {
        fetchProviderModels(provider)
    }

    func addFetchedModel(_ modelId: String, from provider: ProviderConfig) {
        guard !configuration.models.contains(where: { $0.providerId == provider.id && $0.modelId == modelId }) else { return }
        let inference = inferredModelProfile(for: modelId)
        let endpointPreset = ProviderEndpointCatalog.preset(providerName: provider.name, endpointKind: inference.endpointKind)
        let shouldOverrideBaseURL = ProviderEndpointCatalog.shouldOverrideBaseURL(providerName: provider.name, endpointKind: inference.endpointKind)
        let usesAsyncTask = ProviderEndpointCatalog.defaultUsesAsyncTask(providerName: provider.name, endpointKind: inference.endpointKind, modelId: modelId)
        let baseURL = shouldOverrideBaseURL
            ? ProviderEndpointCatalog.preferredBaseURL(providerName: provider.name, providerBaseURL: provider.baseURL, endpointKind: inference.endpointKind)
            : provider.baseURL
        let model = ModelConfig(
            name: modelId,
            provider: provider.name,
            providerId: provider.id,
            baseURL: baseURL,
            modelId: modelId,
            supportedModalities: inference.input.union(inference.output),
            inputModalities: inference.input,
            outputModalities: inference.output,
            endpointKind: inference.endpointKind,
            endpointPath: endpointPreset.endpointPath,
            requestParametersJSON: endpointPreset.requestParametersJSON,
            apiKeyReference: provider.apiKey.isEmpty ? "API_KEY" : "",
            overridesProviderBaseURL: shouldOverrideBaseURL,
            usesAsyncTask: usesAsyncTask
        )
        configuration.models.append(model)
        if let registrations = ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: model, provider: provider) {
            configuration.modelRegistrations.append(contentsOf: registrations)
        } else {
            configuration.modelRegistrations.append(ModelRegistrationPresetRegistry.draft(for: model, provider: provider))
        }
        configuration.defaultModelId = configuration.defaultModelId ?? model.id
        save()
    }

    func addDefaultModel(_ modelId: String, from provider: ProviderConfig) {
        addFetchedModel(modelId, from: provider)
    }

    func toggleProviderModel(_ modelId: String, from provider: ProviderConfig) {
        if let model = configuration.models.first(where: { $0.providerId == provider.id && $0.modelId == modelId }) {
            deleteModel(model)
        } else {
            addFetchedModel(modelId, from: provider)
        }
    }

    private func inferredModelProfile(for modelId: String) -> (input: Set<Modality>, output: Set<Modality>, endpointKind: ModelEndpointKind) {
        let lowercased = modelId.lowercased()
        if let rule = configuration.modelInferenceRules.first(where: { rule in
            rule.keywords.contains { keyword in
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !trimmed.isEmpty && lowercased.contains(trimmed)
            }
        }) {
            return (rule.inputModalities, rule.outputModalities, rule.endpointKind)
        }
        return ([.text], [.text], .chatCompletions)
    }

    func scanAgents() {
        isScanningAgents = true
        let existingAgents = configuration.agents
        Task {
            let scanned = await agentScanner.scan(candidates: AgentConfig.candidates)
            await MainActor.run {
                configuration.agents = scanned.map { scannedAgent in
                    var merged = scannedAgent
                    if let existing = existingAgents.first(where: { $0.executable == scannedAgent.executable }) {
                        merged.invocationTemplate = existing.invocationTemplate
                        merged.acpInvocationTemplate = existing.acpInvocationTemplate.isEmpty ? scannedAgent.acpInvocationTemplate : existing.acpInvocationTemplate
                    }
                    return merged
                }
                isScanningAgents = false
                save()
            }
        }
    }

    func updateAgent(_ agent: AgentConfig) {
        guard let index = configuration.agents.firstIndex(where: { $0.id == agent.id }) else { return }
        configuration.agents[index] = agent
        save()
    }

    func testAgentACP(_ agent: AgentConfig) {
        agentACPStatuses[agent.id] = "Testing ACP..."
        Task {
            let status = await nodeExecution.testACP(agent: agent, workspacePath: selectedWorkspace?.path)
            await MainActor.run {
                agentACPStatuses[agent.id] = status
            }
        }
    }

    func deleteAgent(_ agent: AgentConfig) {
        configuration.agents.removeAll { $0.id == agent.id }
        for index in configuration.workflow.nodes.indices where configuration.workflow.nodes[index].agentExecutable == agent.executable {
            configuration.workflow.nodes[index].agentExecutable = configuration.agents.first?.executable
        }
        save()
    }

    func createWorkspace() {
        saveCurrentWorkflowToSelectedWorkspace()
        guard let workspace = workspaceService.createWorkspace() else { return }
        registerAndSelectWorkspace(workspace, workflow: WorkflowDocument(name: workspace.name))
        seedStarterWorkflow()
        save()
    }

    func openExistingWorkspace() {
        saveCurrentWorkflowToSelectedWorkspace()
        guard let workspace = workspaceService.openExistingWorkspace() else { return }
        let workflow = workspaceService.readWorkflow(for: workspace) ?? starterWorkflow(named: workspace.name)
        registerAndSelectWorkspace(workspace, workflow: workflow)
        save()
    }

    private func registerAndSelectWorkspace(_ workspace: WorkspaceLocation, workflow: WorkflowDocument) {
        let key = workspace.metadataPath ?? workspace.path
        if let index = configuration.workspaces.firstIndex(where: { ($0.metadataPath ?? $0.path) == key }) {
            configuration.workspaces[index] = workspace
        } else {
            configuration.workspaces.append(workspace)
        }
        configuration.selectedWorkspaceId = workspace.id
        configuration.workflow = WorkflowDocument(name: workspace.name)
        configuration.workflow = workflow
    }

    func chooseWorkspaceFolder() {
        createWorkspace()
    }

    func deleteWorkspace(_ workspace: WorkspaceLocation) {
        configuration.workspaces.removeAll { $0.id == workspace.id }
        if configuration.selectedWorkspaceId == workspace.id {
            configuration.selectedWorkspaceId = configuration.workspaces.first?.id
            if let next = selectedWorkspace, let workflow = workspaceService.readWorkflow(for: next) {
                configuration.workflow = workflow
            } else {
                configuration.workflow = WorkflowDocument()
            }
        }
        save()
    }

    func selectWorkspace(_ workspace: WorkspaceLocation) {
        saveCurrentWorkflowToSelectedWorkspace()
        configuration.selectedWorkspaceId = workspace.id
        prepareSelectedWorkspaceStorage()
        configuration.workflow = workspaceService.readWorkflow(for: workspace) ?? starterWorkflow(named: workspace.name)
        undoRedo.clear()
        save()
    }

    func updateWorkspaceName(_ workspace: WorkspaceLocation, name: String) {
        guard let index = configuration.workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        let updated = workspaceService.renamedWorkspace(workspace, name: name)
        configuration.workspaces[index] = updated
        if configuration.selectedWorkspaceId == updated.id {
            configuration.workflow.name = updated.name
        }
        save()
    }

    func openSelectedWorkspaceInFinder() {
        guard let workspace = selectedWorkspace else { return }
        workspaceService.openFinder(path: workspace.path)
    }

    func openSelectedWorkspaceInVSCode() {
        guard let workspace = selectedWorkspace else { return }
        workspaceService.openVSCode(path: workspace.path)
    }

    func openSelectedWorkspaceInTerminal() {
        guard let workspace = selectedWorkspace else { return }
        workspaceService.openTerminal(path: workspace.path)
    }

    func launchAgentTUI(_ agent: AgentConfig) {
        workspaceService.launchAgentTUI(agent: agent, workspacePath: selectedWorkspace?.path)
    }

    func attachFiles(to node: WorkflowNode) {
        guard selectedWorkspace != nil else { return }
        let assets = workspaceService.chooseFiles()
        guard !assets.isEmpty else { return }
        addAssets(assets)
        addPendingAttachments(assets.map(\.path), to: node.id, draftMessage: "Use the attached files.")
    }

    func attachFileURLs(_ urls: [URL], to nodeId: UUID) {
        guard selectedWorkspace != nil else { return }
        let assets = urls.map { url in
            MediaAsset(
                name: url.lastPathComponent,
                path: url.path(percentEncoded: false),
                modality: MediaAsset.inferModality(path: url.path(percentEncoded: false))
            )
        }
        guard !assets.isEmpty else { return }
        addAssets(assets)

        if let node = configuration.workflow.nodes.first(where: { $0.id == nodeId }),
           node.kind == .consistency {
            importConsistencyAssets(assets.map(\.path), node: node)
        } else {
            addPendingAttachments(assets.map(\.path), to: nodeId, draftMessage: "Use the dropped files.")
        }
    }

    private func importConsistencyAssets(_ paths: [String], node: WorkflowNode) {
        let config = node.consistencyConfig
        var existingPaths = Set(configuration.workflow.consistency.assets.map(\.artifactPath))
        let categoryName: (ConsistencyCategoryKind) -> String = { [weak self] kind in
            self?.categoryName(for: kind) ?? kind.title
        }
        for path in paths {
            guard config.acceptedArtifactTypes.contains(MediaAsset.inferModality(path: path)) else { continue }
            if config.autoDeduplicate, existingPaths.contains(path) {
                if !config.allowOverwrite, config.writePolicy != .replace { continue }
                configuration.workflow.consistency.assets.removeAll { $0.artifactPath == path }
            }
            let asset = consistencyAssetIngestion.makeAsset(
                path: path,
                node: node,
                runId: UUID(),
                sourceNodeId: nil,
                sourceRouteId: nil,
                config: config,
                categoryName: categoryName,
                llmSummary: nil
            )
            let isFirst = !configuration.workflow.consistency.entities.contains {
                $0.category == asset.category && $0.name == asset.name
            }
            var writable = asset
            writable.canonical = isFirst
            configuration.workflow.consistency.assets.append(writable)
            upsertConsistencyEntity(for: writable)
            appendConsistencyPath(path, to: writable.category)
            existingPaths.insert(path)
        }
        save()
    }

    func addDroppedFilesToCanvas(_ urls: [URL], at point: CGPoint) {
        guard selectedWorkspace != nil else { return }
        let assets = urls.map { url in
            let path = url.path(percentEncoded: false)
            return MediaAsset(name: url.lastPathComponent, path: path, modality: MediaAsset.inferModality(path: path))
        }
        guard !assets.isEmpty else { return }
        recordUndoSnapshot()
        addAssets(assets)
        for (index, asset) in assets.enumerated() {
            let kind = canvasElementKind(for: asset.modality)
            let offset = Double(index * 30)
            appendCanvasAssetElement(
                path: asset.path,
                kind: kind,
                position: CanvasPoint(x: point.x + offset, y: point.y + offset),
                sourceNodeId: nil
            )
        }
        save()
    }

    @discardableResult
    func absorbCanvasAssetsIfNeeded(ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        var didAbsorb = false
        for id in ids {
            guard let element = configuration.workflow.canvasElements.first(where: { $0.id == id }),
                  let path = element.assetPath else { continue }
            guard let target = absorbingNode(for: element.position, excluding: element.sourceNodeId) else { continue }
            if target.kind == .consistency {
                importConsistencyAssets([path], node: target)
            } else {
                addPendingAttachments([path], to: target.id, draftMessage: "Use the absorbed asset.", saveImmediately: false)
            }
            didAbsorb = true
        }
        if didAbsorb {
            save()
        }
        return didAbsorb
    }

    func absorbingNodeId(for point: CanvasPoint, excluding sourceNodeId: UUID? = nil) -> UUID? {
        absorbingNode(for: point, excluding: sourceNodeId)?.id
    }

    func removePendingAttachment(path: String, from node: WorkflowNode) {
        var updated = node
        guard let last = updated.chat.indices.last, updated.chat[last].role == "draft" else { return }
        updated.chat[last].attachments.removeAll { $0 == path }
        if updated.chat[last].attachments.isEmpty {
            updated.chat.remove(at: last)
        }
        updateNode(updated)
    }

    func addConsistencyAssets() {
        guard selectedWorkspace != nil else { return }
        let assets = workspaceService.chooseFiles()
        guard !assets.isEmpty else { return }
        addAssets(assets)
        addConsistencyAssetPaths(assets.map(\.path), to: defaultConsistencyCategoryId(for: nil))
    }

    func addConsistencyAssets(modality: Modality) {
        guard selectedWorkspace != nil else { return }
        let assets = workspaceService.chooseFiles(for: modality)
        guard !assets.isEmpty else { return }
        addAssets(assets)
        addConsistencyAssetPaths(assets.map(\.path), to: defaultConsistencyCategoryId(for: modality))
    }

    func addConsistencyAssets(to category: ConsistencyCategory) {
        guard selectedWorkspace != nil else { return }
        let modality = category.kind.preferredModalities.first
        let assets = modality.map { workspaceService.chooseFiles(for: $0) } ?? workspaceService.chooseFiles()
        guard !assets.isEmpty else { return }
        addAssets(assets)
        addConsistencyAssetPaths(assets.map(\.path), to: category.id)
    }

    func removeConsistencyAsset(path: String, from category: ConsistencyCategory? = nil) {
        let removedIds = Set(configuration.workflow.consistency.assets.filter { $0.artifactPath == path }.map(\.id))
        configuration.workflow.consistency.referenceAssets.removeAll { $0 == path }
        configuration.workflow.consistency.assets.removeAll { $0.artifactPath == path }
        for index in configuration.workflow.consistency.entities.indices {
            configuration.workflow.consistency.entities[index].versions.removeAll { removedIds.contains($0) }
            configuration.workflow.consistency.entities[index].lockedAssetIds.removeAll { removedIds.contains($0) }
            if let canonical = configuration.workflow.consistency.entities[index].canonicalAssetId, removedIds.contains(canonical) {
                configuration.workflow.consistency.entities[index].canonicalAssetId = configuration.workflow.consistency.entities[index].versions.first
            }
        }
        if let category {
            guard let index = configuration.workflow.consistency.categories.firstIndex(where: { $0.id == category.id }) else { return }
            configuration.workflow.consistency.categories[index].assetPaths.removeAll { $0 == path }
        } else {
            for index in configuration.workflow.consistency.categories.indices {
                configuration.workflow.consistency.categories[index].assetPaths.removeAll { $0 == path }
            }
        }
        save()
    }

    func toggleConsistencyAssetLock(_ assetId: UUID) {
        guard let index = configuration.workflow.consistency.assets.firstIndex(where: { $0.id == assetId }) else { return }
        configuration.workflow.consistency.assets[index].locked.toggle()
        configuration.workflow.consistency.assets[index].updatedAt = Date()
        if let entityIndex = configuration.workflow.consistency.entities.firstIndex(where: { $0.id == configuration.workflow.consistency.assets[index].entityId }) {
            if configuration.workflow.consistency.assets[index].locked {
                if !configuration.workflow.consistency.entities[entityIndex].lockedAssetIds.contains(assetId) {
                    configuration.workflow.consistency.entities[entityIndex].lockedAssetIds.append(assetId)
                }
            } else {
                configuration.workflow.consistency.entities[entityIndex].lockedAssetIds.removeAll { $0 == assetId }
            }
        }
        save()
    }

    func setCanonicalConsistencyAsset(_ assetId: UUID) {
        guard let asset = configuration.workflow.consistency.assets.first(where: { $0.id == assetId }) else { return }
        for index in configuration.workflow.consistency.assets.indices where configuration.workflow.consistency.assets[index].entityId == asset.entityId {
            configuration.workflow.consistency.assets[index].canonical = configuration.workflow.consistency.assets[index].id == assetId
            configuration.workflow.consistency.assets[index].updatedAt = Date()
        }
        if let entityIndex = configuration.workflow.consistency.entities.firstIndex(where: { $0.id == asset.entityId }) {
            configuration.workflow.consistency.entities[entityIndex].canonicalAssetId = assetId
        }
        save()
    }

    func addConsistencyCategory(kind: ConsistencyCategoryKind = .custom) {
        let template = ConsistencyCategory.defaults.first { $0.kind == kind }
        let existingNames = Set(configuration.workflow.consistency.categories.map(\.name))
        let baseName = template?.name ?? kind.title
        configuration.workflow.consistency.categories.append(
            ConsistencyCategory(
                name: uniqueName(baseName, existing: existingNames),
                kind: kind,
                description: template?.description ?? "",
                assetPaths: []
            )
        )
        save()
    }

    func updateConsistencyCategory(_ category: ConsistencyCategory) {
        guard let index = configuration.workflow.consistency.categories.firstIndex(where: { $0.id == category.id }) else { return }
        configuration.workflow.consistency.categories[index] = category
        save()
    }

    func deleteConsistencyCategory(_ category: ConsistencyCategory) {
        configuration.workflow.consistency.categories.removeAll { $0.id == category.id }
        save()
    }

    func deleteAsset(_ asset: MediaAsset) {
        configuration.workflow.assets.removeAll { $0.id == asset.id || $0.path == asset.path }
        let removedElementIds = Set(configuration.workflow.canvasElements.filter { $0.assetPath == asset.path }.map(\.id))
        configuration.workflow.canvasElements.removeAll { $0.assetPath == asset.path || isConnector($0, attachedToAny: removedElementIds) }
        configuration.workflow.consistency.referenceAssets.removeAll { $0 == asset.path }
        for index in configuration.workflow.consistency.categories.indices {
            configuration.workflow.consistency.categories[index].assetPaths.removeAll { $0 == asset.path }
        }
        for index in configuration.workflow.nodes.indices {
            configuration.workflow.nodes[index].chat = configuration.workflow.nodes[index].chat.compactMap { message in
                var updated = message
                updated.attachments.removeAll { $0 == asset.path }
                if updated.role == "draft", updated.attachments.isEmpty {
                    return nil
                }
                return updated
            }
        }
        save()
    }

    private func addConsistencyAssetPaths(_ paths: [String], to categoryId: UUID?) {
        guard !paths.isEmpty else { return }
        let existingReferenceAssets = Set(configuration.workflow.consistency.referenceAssets)
        configuration.workflow.consistency.referenceAssets.append(contentsOf: paths.filter { !existingReferenceAssets.contains($0) })
        guard let categoryId,
              let index = configuration.workflow.consistency.categories.firstIndex(where: { $0.id == categoryId }) else {
            save()
            return
        }
        let existingCategoryAssets = Set(configuration.workflow.consistency.categories[index].assetPaths)
        configuration.workflow.consistency.categories[index].assetPaths.append(contentsOf: paths.filter { !existingCategoryAssets.contains($0) })
        save()
    }

    private func defaultConsistencyCategoryId(for modality: Modality?) -> UUID? {
        let preferredKinds: [ConsistencyCategoryKind]
        switch modality {
        case .image:
            preferredKinds = [.character, .visualStyle, .product, .scene]
        case .video, .audioVideo:
            preferredKinds = [.motion, .scene, .character]
        case .audio, .music:
            preferredKinds = [.voice, .music, .sound]
        case .text:
            preferredKinds = [.visualStyle, .custom]
        case .json, .embedding, .scores, .threeD, .mask, .bbox, .reference, .unknown:
            preferredKinds = [.custom, .visualStyle]
        case .file:
            preferredKinds = [.custom, .product]
        case nil:
            preferredKinds = [.visualStyle, .character, .custom]
        }
        for kind in preferredKinds {
            if let id = configuration.workflow.consistency.categories.first(where: { $0.kind == kind })?.id {
                return id
            }
        }
        if configuration.workflow.consistency.categories.isEmpty {
            configuration.workflow.consistency.categories = ConsistencyCategory.defaults
        }
        return configuration.workflow.consistency.categories.first?.id
    }

    private func uniqueName(_ baseName: String, existing: Set<String>) -> String {
        guard existing.contains(baseName) else { return baseName }
        var index = 2
        while existing.contains("\(baseName) \(index)") {
            index += 1
        }
        return "\(baseName) \(index)"
    }

    func selectCanvasTool(_ tool: CanvasTool) {
        configuration.selectedCanvasTool = tool
        save()
    }

    func setNodeInspectorAutoOpenLocked(_ isLocked: Bool) {
        configuration.locksNodeInspectorAutoOpen = isLocked
        save()
    }

    func updateArtboardColor(_ hex: String) {
        configuration.boardSettings.artboardColorHex = normalizedHex(hex)
        updateSelectedElementsIfMatching(kinds: [.artboard], color: configuration.boardSettings.artboardColorHex)
        save()
    }

    func updateShapeColor(_ hex: String) {
        configuration.boardSettings.shapeColorHex = normalizedHex(hex)
        updateSelectedElementsIfMatching(kinds: [.rectangle, .line, .arrow, .ellipse, .polygon, .star], color: configuration.boardSettings.shapeColorHex)
        save()
    }

    func updatePenColor(_ hex: String) {
        recordUndoSnapshot()
        configuration.boardSettings.penColorHex = normalizedHex(hex)
        save()
    }

    func updateTextColor(_ hex: String) {
        recordUndoSnapshot()
        configuration.boardSettings.textColorHex = normalizedHex(hex)
        for index in configuration.workflow.canvasElements.indices where configuration.workflow.selectedCanvasElementIds.contains(configuration.workflow.canvasElements[index].id) && configuration.workflow.canvasElements[index].kind == .text {
            configuration.workflow.canvasElements[index].colorHex = configuration.boardSettings.textColorHex
        }
        save()
    }

    func updateSelectedElementColor(_ hex: String) {
        recordUndoSnapshot()
        for index in configuration.workflow.canvasElements.indices where configuration.workflow.selectedCanvasElementIds.contains(configuration.workflow.canvasElements[index].id) {
            configuration.workflow.canvasElements[index].colorHex = hex
        }
        save()
    }

    private func updateSelectedElementsIfMatching(kinds: Set<CanvasElementKind>, color: String) {
        recordUndoSnapshot()
        for index in configuration.workflow.canvasElements.indices where configuration.workflow.selectedCanvasElementIds.contains(configuration.workflow.canvasElements[index].id) && kinds.contains(configuration.workflow.canvasElements[index].kind) {
            configuration.workflow.canvasElements[index].colorHex = color
        }
    }

    func saveColorPreset(_ hex: String) {
        let normalized = normalizedHex(hex)
        guard !configuration.boardSettings.colorPresets.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else { return }
        configuration.boardSettings.colorPresets.append(normalized)
        save()
    }

    func deleteColorPreset(_ hex: String) {
        configuration.boardSettings.colorPresets.removeAll { $0.caseInsensitiveCompare(hex) == .orderedSame }
        if configuration.boardSettings.colorPresets.isEmpty {
            configuration.boardSettings.colorPresets = ["#111111", "#FFFFFF"]
        }
        save()
    }

    func createLogicConnection(from startAnchor: CanvasAnchorRef, to endAnchor: CanvasAnchorRef) {
        guard startAnchor.targetId != endAnchor.targetId || startAnchor.targetKind != endAnchor.targetKind else { return }
        guard !isConsistencyNodeAnchor(startAnchor) else { return }
        guard let start = anchorPosition(for: startAnchor), let end = anchorPosition(for: endAnchor) else { return }
        let frame = connectorFrame(from: start, to: end)
        let element = CanvasElement(
            kind: .arrow,
            position: CanvasPoint(x: frame.midX, y: frame.midY),
            size: CanvasSize(width: frame.width, height: frame.height),
            pathPoints: localConnectorPoints(from: start, to: end, in: frame),
            strokeWidth: 3,
            colorHex: configuration.boardSettings.penColorHex,
            startAnchor: startAnchor,
            endAnchor: endAnchor,
            isLogicConnection: true,
            logicEdge: WorkflowLogicEdgeConfiguration(
                sourceNodeId: startAnchor.targetKind == .node ? startAnchor.targetId : nil,
                targetNodeId: endAnchor.targetKind == .node ? endAnchor.targetId : nil,
                sourcePort: "output",
                sourceHandle: startAnchor.side.rawValue,
                targetPort: "input",
                targetHandle: endAnchor.side.rawValue
            )
        )
        guard logicConnectionCanBeAdded(element) else { return }
        recordUndoSnapshot()
        configuration.workflow.canvasElements.append(element)
        configuration.workflow.selectedCanvasElementId = element.id
        configuration.workflow.selectedCanvasElementIds = [element.id]
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedNodeId = nil
        save()
    }

    private func logicConnectionCanBeAdded(_ element: CanvasElement) -> Bool {
        var draft = configuration.workflow
        draft.canvasElements.append(element)
        let spatialRoutes = spatialRouteResolver.resolve(nodes: draft.nodes, mode: draft.automationSettings.assetPropagationMode)
        do {
            _ = try workflowGraphService.build(from: draft, spatialRoutes: spatialRoutes)
            return true
        } catch WorkflowGraphError.cycleDetected {
            let message = "This logic arrow would create a workflow loop. Break the loop or use a manual review node instead."
            configuration.workflow.runState.lastError = message
            appendWorkflowLog(message, level: .warning)
            save()
            return false
        } catch {
            let message = error.localizedDescription
            configuration.workflow.runState.lastError = message
            appendWorkflowLog(message, level: .warning)
            save()
            return false
        }
    }

    func createAttachedArrowConnection(from startAnchor: CanvasAnchorRef, to endAnchor: CanvasAnchorRef) {
        guard startAnchor.targetId != endAnchor.targetId || startAnchor.targetKind != endAnchor.targetKind else { return }
        guard !isConsistencyNodeAnchor(startAnchor) else { return }
        guard let start = anchorPosition(for: startAnchor), let end = anchorPosition(for: endAnchor) else { return }
        recordUndoSnapshot()
        let frame = connectorFrame(from: start, to: end)
        let element = CanvasElement(
            kind: .arrow,
            position: CanvasPoint(x: frame.midX, y: frame.midY),
            size: CanvasSize(width: frame.width, height: frame.height),
            pathPoints: localConnectorPoints(from: start, to: end, in: frame),
            strokeWidth: 2.4,
            colorHex: configuration.boardSettings.shapeColorHex,
            startAnchor: startAnchor,
            endAnchor: endAnchor,
            isLogicConnection: false
        )
        configuration.workflow.canvasElements.append(element)
        configuration.workflow.selectedCanvasElementId = element.id
        configuration.workflow.selectedCanvasElementIds = [element.id]
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedNodeId = nil
        save()
    }

    private func isConsistencyNodeAnchor(_ anchor: CanvasAnchorRef) -> Bool {
        guard anchor.targetKind == .node,
              let node = configuration.workflow.nodes.first(where: { $0.id == anchor.targetId }) else {
            return false
        }
        return node.kind == .consistency
    }

    func uploadCanvasImage() {
        guard selectedWorkspace != nil else { return }
        let assets = workspaceService.chooseFiles(for: .image)
        guard !assets.isEmpty else { return }
        addAssets(assets)
        for (offset, asset) in assets.enumerated() {
            addCanvasElement(kind: .image, at: CanvasPoint(x: 520 + Double(offset * 28), y: 360 + Double(offset * 28)), assetPath: asset.path)
        }
        save()
    }

    func uploadCanvasVideo() {
        guard selectedWorkspace != nil else { return }
        let assets = workspaceService.chooseFiles(for: .video)
        guard !assets.isEmpty else { return }
        addAssets(assets)
        for (offset, asset) in assets.enumerated() {
            addCanvasElement(kind: .video, at: CanvasPoint(x: 560 + Double(offset * 28), y: 400 + Double(offset * 28)), assetPath: asset.path)
        }
        save()
    }

    func uploadCanvasAudio() {
        guard selectedWorkspace != nil else { return }
        let assets = workspaceService.chooseFiles(for: .audio)
        guard !assets.isEmpty else { return }
        addAssets(assets)
        for (offset, asset) in assets.enumerated() {
            addCanvasElement(kind: .audio, at: CanvasPoint(x: 600 + Double(offset * 28), y: 440 + Double(offset * 28)), assetPath: asset.path)
        }
        save()
    }

    func handleCanvasTap(at point: CGPoint) {
        guard selectedWorkspace != nil else { return }
        switch configuration.selectedCanvasTool {
        case .rectangle:
            addCanvasElement(kind: .rectangle, at: CanvasPoint(x: point.x, y: point.y))
        case .line:
            addCanvasElement(kind: .line, at: CanvasPoint(x: point.x, y: point.y))
        case .arrow:
            addCanvasElement(kind: .arrow, at: CanvasPoint(x: point.x, y: point.y))
        case .ellipse:
            addCanvasElement(kind: .ellipse, at: CanvasPoint(x: point.x, y: point.y))
        case .polygon:
            addCanvasElement(kind: .polygon, at: CanvasPoint(x: point.x, y: point.y))
        case .star:
            addCanvasElement(kind: .star, at: CanvasPoint(x: point.x, y: point.y))
        case .pen:
            addCanvasElement(kind: .pen, at: CanvasPoint(x: point.x, y: point.y))
        case .text:
            addCanvasElement(kind: .text, at: CanvasPoint(x: point.x, y: point.y))
        default:
            configuration.workflow.selectedCanvasElementId = nil
            save()
        }
    }

    func createCanvasElement(tool: CanvasTool, from start: CGPoint, to end: CGPoint) {
        guard selectedWorkspace != nil, let kind = canvasElementKind(for: tool) else { return }
        recordUndoSnapshot()
        if kind == .line || kind == .arrow {
            addConnectorElement(kind: kind, from: start, to: end)
            return
        }
        let frame = normalizedCanvasFrame(from: start, to: end, minimumSize: kind == .text ? CGSize(width: 160, height: 48) : CGSize(width: 28, height: 28))
        addCanvasElement(
            kind: kind,
            at: CanvasPoint(x: frame.midX, y: frame.midY),
            size: CanvasSize(width: frame.width, height: frame.height)
        )
    }

    func createPenElement(points: [CGPoint]) {
        guard selectedWorkspace != nil, points.count > 1 else { return }
        recordUndoSnapshot()
        let processed = configuration.boardSettings.smoothPen ? smooth(points: points) : points
        let minX = processed.map(\.x).min() ?? 0
        let minY = processed.map(\.y).min() ?? 0
        let maxX = processed.map(\.x).max() ?? minX + 1
        let maxY = processed.map(\.y).max() ?? minY + 1
        let width = max(maxX - minX, 28)
        let height = max(maxY - minY, 28)
        let localPoints = processed.map { CanvasPoint(x: $0.x - minX, y: $0.y - minY) }
        addCanvasElement(
            kind: .pen,
            at: CanvasPoint(x: minX + width / 2, y: minY + height / 2),
            size: CanvasSize(width: width, height: height),
            pathPoints: localPoints,
            colorHex: configuration.boardSettings.penColorHex,
            strokeWidth: configuration.boardSettings.penWidth
        )
    }

    func selectItems(in rect: CGRect) {
        let nodeIds = configuration.workflow.nodes.filter { node in
            rect.contains(CGPoint(x: node.position.x, y: node.position.y))
        }.map(\.id)
        let elementIds = configuration.workflow.canvasElements.filter { element in
            rect.intersects(CGRect(
                x: element.position.x - element.size.width / 2,
                y: element.position.y - element.size.height / 2,
                width: element.size.width,
                height: element.size.height
            ))
        }.map(\.id)
        configuration.workflow.selectedNodeIds = Set(nodeIds)
        configuration.workflow.selectedCanvasElementIds = Set(elementIds)
        configuration.workflow.selectedNodeId = nodeIds.first
        configuration.workflow.selectedCanvasElementId = elementIds.first
        save()
    }

    func clearCanvasSelection() {
        configuration.workflow.selectedNodeId = nil
        configuration.workflow.selectedCanvasElementId = nil
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedCanvasElementIds = []
        save()
    }

    func selectCanvasElement(_ id: UUID) {
        configuration.workflow.selectedCanvasElementId = id
        configuration.workflow.selectedNodeId = nil
        configuration.workflow.selectedCanvasElementIds = [id]
        configuration.workflow.selectedNodeIds = []
        save()
    }

    func setCanvasElementPosition(id: UUID, position: CanvasPoint, persist: Bool = true) {
        guard let index = configuration.workflow.canvasElements.firstIndex(where: { $0.id == id }) else { return }
        configuration.workflow.canvasElements[index].position = position
        refreshConnections(affectedElementIds: [id])
        if persist { save() }
    }

    func updateCanvasElementText(id: UUID, text: String) {
        guard let index = configuration.workflow.canvasElements.firstIndex(where: { $0.id == id }) else { return }
        if configuration.workflow.canvasElements[index].text != text {
            recordUndoSnapshot()
        }
        configuration.workflow.canvasElements[index].text = text
        save()
    }

    func updateCanvasElementSize(id: UUID, size: CanvasSize) {
        guard let index = configuration.workflow.canvasElements.firstIndex(where: { $0.id == id }) else { return }
        configuration.workflow.canvasElements[index].size = size
        refreshConnections(affectedElementIds: [id])
        save()
    }

    func deleteSelectedCanvasElement() {
        let ids = configuration.workflow.selectedCanvasElementIds
        guard !ids.isEmpty else { return }
        recordUndoSnapshot()
        configuration.workflow.canvasElements.removeAll { ids.contains($0.id) || isConnector($0, attachedToAny: ids) }
        configuration.workflow.selectedCanvasElementId = nil
        configuration.workflow.selectedCanvasElementIds = []
        save()
    }

    func deleteSelectedCanvasItems() {
        let nodeIds = configuration.workflow.selectedNodeIds
        let elementIds = configuration.workflow.selectedCanvasElementIds
        guard !nodeIds.isEmpty || !elementIds.isEmpty else { return }
        recordUndoSnapshot()
        deleteCanvasItems(nodeIds: nodeIds, elementIds: elementIds)
        save()
    }

    private func deleteCanvasItems(nodeIds: Set<UUID>, elementIds: Set<UUID>) {
        configuration.workflow.nodes.removeAll { nodeIds.contains($0.id) }
        configuration.workflow.canvasElements.removeAll { element in
            elementIds.contains(element.id) ||
            isConnector(element, attachedToAny: elementIds) ||
            isConnector(element, attachedToAnyNodes: nodeIds)
        }
        configuration.workflow.selectedNodeId = nil
        configuration.workflow.selectedCanvasElementId = nil
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedCanvasElementIds = []
    }

    func copyCanvasItems(fallbackNodeId: UUID? = nil, fallbackElementId: UUID? = nil) {
        guard selectedWorkspace != nil else { return }
        let selection = clipboardSelection(fallbackNodeId: fallbackNodeId, fallbackElementId: fallbackElementId)
        guard !selection.nodeIds.isEmpty || !selection.elementIds.isEmpty else { return }
        let payload = makeCanvasClipboardPayload(nodeIds: selection.nodeIds, elementIds: selection.elementIds)
        writeCanvasClipboard(payload)
    }

    func cutCanvasItems(fallbackNodeId: UUID? = nil, fallbackElementId: UUID? = nil) {
        guard selectedWorkspace != nil else { return }
        let selection = clipboardSelection(fallbackNodeId: fallbackNodeId, fallbackElementId: fallbackElementId)
        guard !selection.nodeIds.isEmpty || !selection.elementIds.isEmpty else { return }
        let payload = makeCanvasClipboardPayload(nodeIds: selection.nodeIds, elementIds: selection.elementIds)
        writeCanvasClipboard(payload)
        recordUndoSnapshot()
        deleteCanvasItems(nodeIds: selection.nodeIds, elementIds: selection.elementIds)
        save()
    }

    func pasteCanvasItems(at point: CanvasPoint? = nil) {
        guard selectedWorkspace != nil, let payload = readCanvasClipboard() else { return }
        recordUndoSnapshot()
        let target = point ?? CanvasPoint(x: 560, y: 360)
        let bounds = clipboardBounds(nodes: payload.nodes, elements: payload.elements)
        let sourceCenter = bounds.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: target.x - 40, y: target.y - 40)
        let delta = CGSize(width: target.x - sourceCenter.x, height: target.y - sourceCenter.y)
        var nodeIdMap: [UUID: UUID] = [:]
        var elementIdMap: [UUID: UUID] = [:]
        var pastedNodeIds: Set<UUID> = []
        var pastedElementIds: Set<UUID> = []

        let pastedNodes = payload.nodes.map { node in
            var clone = node
            let newId = UUID()
            nodeIdMap[node.id] = newId
            pastedNodeIds.insert(newId)
            clone.id = newId
            clone.title = uniqueNodeTitle(node.title)
            clone.position.x += delta.width
            clone.position.y += delta.height
            clone.chat.removeAll()
            clone.draftMessage = ""
            clone.hasStartedPersistentChat = false
            clone.persistentSessionId = UUID().uuidString.lowercased()
            clone.persistentModelId = nil
            return clone
        }

        for element in payload.elements {
            elementIdMap[element.id] = UUID()
        }
        let pastedElements = payload.elements.compactMap { element -> CanvasElement? in
            var clone = element
            guard let newId = elementIdMap[element.id] else { return nil }
            clone.id = newId
            pastedElementIds.insert(newId)
            clone.position.x += delta.width
            clone.position.y += delta.height
            clone.sourceNodeId = clone.sourceNodeId.flatMap { nodeIdMap[$0] }
            clone.startAnchor = remappedAnchor(clone.startAnchor, nodeIdMap: nodeIdMap, elementIdMap: elementIdMap)
            clone.endAnchor = remappedAnchor(clone.endAnchor, nodeIdMap: nodeIdMap, elementIdMap: elementIdMap)
            if clone.isLogicConnection, var edge = clone.logicEdge {
                edge.id = newId
                edge.sourceNodeId = clone.startAnchor?.targetKind == .node ? clone.startAnchor?.targetId : nil
                edge.targetNodeId = clone.endAnchor?.targetKind == .node ? clone.endAnchor?.targetId : nil
                clone.logicEdge = edge
            }
            if element.isLogicConnection, (clone.startAnchor == nil || clone.endAnchor == nil) {
                return nil
            }
            return clone
        }

        configuration.workflow.nodes.append(contentsOf: pastedNodes)
        configuration.workflow.canvasElements.append(contentsOf: pastedElements)
        configuration.workflow.selectedNodeIds = pastedNodeIds
        configuration.workflow.selectedNodeId = pastedNodeIds.first
        configuration.workflow.selectedCanvasElementIds = pastedElementIds
        configuration.workflow.selectedCanvasElementId = pastedElementIds.first
        save()
    }

    var canPasteCanvasItems: Bool {
        readCanvasClipboard() != nil
    }

    private func clipboardSelection(fallbackNodeId: UUID?, fallbackElementId: UUID?) -> (nodeIds: Set<UUID>, elementIds: Set<UUID>) {
        if let fallbackNodeId, !configuration.workflow.selectedNodeIds.contains(fallbackNodeId) {
            return ([fallbackNodeId], [])
        }
        if let fallbackElementId, !configuration.workflow.selectedCanvasElementIds.contains(fallbackElementId) {
            return ([], [fallbackElementId])
        }
        return (configuration.workflow.selectedNodeIds, configuration.workflow.selectedCanvasElementIds)
    }

    private func makeCanvasClipboardPayload(nodeIds: Set<UUID>, elementIds: Set<UUID>) -> CanvasClipboardPayload {
        var resolvedElementIds = elementIds
        for element in configuration.workflow.canvasElements where element.kind == .line || element.kind == .arrow {
            if elementIds.contains(element.id) || connectorEndpointsAreSelected(element, nodeIds: nodeIds, elementIds: elementIds) {
                resolvedElementIds.insert(element.id)
            }
        }
        return CanvasClipboardPayload(
            nodes: configuration.workflow.nodes.filter { nodeIds.contains($0.id) },
            elements: configuration.workflow.canvasElements.filter { resolvedElementIds.contains($0.id) }
        )
    }

    private func connectorEndpointsAreSelected(_ element: CanvasElement, nodeIds: Set<UUID>, elementIds: Set<UUID>) -> Bool {
        guard let startAnchor = element.startAnchor, let endAnchor = element.endAnchor else { return false }
        return anchorIsSelected(startAnchor, nodeIds: nodeIds, elementIds: elementIds) &&
            anchorIsSelected(endAnchor, nodeIds: nodeIds, elementIds: elementIds)
    }

    private func anchorIsSelected(_ anchor: CanvasAnchorRef, nodeIds: Set<UUID>, elementIds: Set<UUID>) -> Bool {
        switch anchor.targetKind {
        case .node:
            nodeIds.contains(anchor.targetId)
        case .element:
            elementIds.contains(anchor.targetId)
        }
    }

    private func writeCanvasClipboard(_ payload: CanvasClipboardPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: canvasPasteboardType)
    }

    private func readCanvasClipboard() -> CanvasClipboardPayload? {
        guard let data = NSPasteboard.general.data(forType: canvasPasteboardType) else { return nil }
        return try? JSONDecoder().decode(CanvasClipboardPayload.self, from: data)
    }

    private func remappedAnchor(_ anchor: CanvasAnchorRef?, nodeIdMap: [UUID: UUID], elementIdMap: [UUID: UUID]) -> CanvasAnchorRef? {
        guard let anchor else { return nil }
        switch anchor.targetKind {
        case .node:
            guard let targetId = nodeIdMap[anchor.targetId] else { return nil }
            return CanvasAnchorRef(targetKind: .node, targetId: targetId, side: anchor.side)
        case .element:
            guard let targetId = elementIdMap[anchor.targetId] else { return nil }
            return CanvasAnchorRef(targetKind: .element, targetId: targetId, side: anchor.side)
        }
    }

    private func clipboardBounds(nodes: [WorkflowNode], elements: [CanvasElement]) -> CGRect? {
        var rect = CGRect.null
        for node in nodes {
            rect = rect.union(CGRect(x: node.position.x - 130, y: node.position.y - 75, width: 260, height: 150))
        }
        for element in elements {
            rect = rect.union(CGRect(
                x: element.position.x - element.size.width / 2,
                y: element.position.y - element.size.height / 2,
                width: element.size.width,
                height: element.size.height
            ))
        }
        return rect.isNull ? nil : rect
    }

    private func uniqueNodeTitle(_ title: String) -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Node" : title
        let existing = Set(configuration.workflow.nodes.map(\.title))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) Copy \(index)") {
            index += 1
        }
        return "\(base) Copy \(index)"
    }

    func applyArtboardPreset(_ preset: ArtboardPreset) {
        configuration.artboardPreset = preset
        if preset != .custom {
            configuration.workflow.artboardSize = preset.size
        }
        save()
    }

    func updateBoardSettings(_ settings: CanvasBoardSettings) {
        configuration.boardSettings = settings
        save()
    }

    func updateArtboardSize(width: Double? = nil, height: Double? = nil) {
        configuration.artboardPreset = .custom
        if let width { configuration.workflow.artboardSize.width = width }
        if let height { configuration.workflow.artboardSize.height = height }
        save()
    }

    func updateCanvasViewport(offset: CGSize, zoomScale: Double, persist: Bool = false) {
        configuration.workflow.canvasViewport = CanvasViewportState(
            offsetX: offset.width,
            offsetY: offset.height,
            zoomScale: zoomScale
        )
        if persist {
            save()
        }
    }

    func resetCurrentWorkspace() {
        guard let workspace = selectedWorkspace else { return }
        cancelAllExecutions(markPaused: false)
        nodeExecution.closeAllSessions()
        configuration.workflow = starterWorkflow(named: workspace.name)
        undoRedo.clear()
        save()
    }

    func resetAppConfiguration() {
        cancelAllExecutions(markPaused: false)
        nodeExecution.closeAllSessions()
        configuration = AppConfiguration()
        settingsSelection = SettingsSelection()
        undoRedo.clear()
        agentACPStatuses.removeAll()
        if providerMigration.migrate(&configuration) { persistence.save(configuration) }
        if providerMigration.normalizeAgents(&configuration) { persistence.save(configuration) }
        save()
    }

    func modelName(for id: UUID?) -> String {
        guard let id, let model = configuration.models.first(where: { $0.id == id }) else { return "Default model" }
        return model.name
    }

    func save() {
        saveDebouncer?.cancel()
        saveDebouncer = Task {
            try? await Task.sleep(for: saveDebounceInterval)
            guard !Task.isCancelled else { return }
            let config = configuration
            let workspace = selectedWorkspace
            await Task.detached {
                self.persistence.save(config)
            }.value
            if let workspace {
                workspaceService.writeWorkflow(config.workflow, for: workspace)
            }
        }
    }

    func flushPendingSave() {
        saveDebouncer?.cancel()
        persistence.save(configuration)
        if let workspace = selectedWorkspace {
            workspaceService.writeWorkflow(configuration.workflow, for: workspace)
        }
    }

    func saveWorkflowWithConfirmation() {
        save()
        showsSaveConfirmation = true
    }

    func refreshCurrentWorkspace() {
        guard let workspace = selectedWorkspace else { return }
        cancelAllExecutions(markPaused: false)
        configuration.workflow = workspaceService.readWorkflow(for: workspace) ?? starterWorkflow(named: workspace.name)
        save()
    }

    func refreshWorkbench() {
        let selectedId = configuration.selectedWorkspaceId
        cancelAllExecutions(markPaused: false)
        configuration = persistence.load() ?? AppConfiguration()
        if providerMigration.migrate(&configuration) { persistence.save(configuration) }
        if providerMigration.normalizeAgents(&configuration) { persistence.save(configuration) }
        configuration.selectedWorkspaceId = selectedId ?? configuration.selectedWorkspaceId
        if let workspace = selectedWorkspace {
            configuration.workflow = workspaceService.readWorkflow(for: workspace) ?? starterWorkflow(named: workspace.name)
        } else {
            configuration.workflow = WorkflowDocument()
        }
        save()
    }

    private func cancelAllExecutions(markPaused: Bool) {
        workflowRunTask?.cancel()
        workflowRunTask = nil
        for nodeId in executingNodeIds {
            executionTasks[nodeId]?.cancel()
            if markPaused, let messageId = activeResponseMessageIds[nodeId] {
                appendToMessage(nodeId: nodeId, messageId: messageId, text: AppCopy(locale: configuration.language).responsePaused)
            }
        }
        executionTasks.removeAll()
        activeResponseMessageIds.removeAll()
        executingNodeIds.removeAll()
        isExecutingNode = false
    }

    private func seedStarterWorkflow() {
        configuration.workflow = starterWorkflow(named: selectedWorkspace?.name ?? configuration.workflow.name)
    }

    private func prepareSelectedWorkspaceStorage() {
        guard let id = configuration.selectedWorkspaceId,
              let index = configuration.workspaces.firstIndex(where: { $0.id == id }) else { return }
        configuration.workspaces[index] = workspaceService.preparedWorkspace(configuration.workspaces[index])
    }

    private func migrateLegacyWorkflowScopedSettingsIfNeeded() {
        var didMigrate = false
        if configuration.workflow.workflowVariables.isEmpty, !configuration.workflowVariables.isEmpty {
            configuration.workflow.workflowVariables = configuration.workflowVariables
            configuration.workflowVariables.removeAll()
            didMigrate = true
        }
        if configuration.workflow.workflowSecrets.isEmpty, !configuration.workflowSecrets.isEmpty {
            configuration.workflow.workflowSecrets = configuration.workflowSecrets
            configuration.workflowSecrets.removeAll()
            didMigrate = true
        }
        if configuration.workflow.workflowDebugSettings == WorkflowDebugSettings(),
           configuration.workflowDebugSettings != WorkflowDebugSettings() {
            configuration.workflow.workflowDebugSettings = configuration.workflowDebugSettings
            configuration.workflowDebugSettings = WorkflowDebugSettings()
            didMigrate = true
        }
        if didMigrate, let workspace = selectedWorkspace {
            workspaceService.writeWorkflow(configuration.workflow, for: workspace)
        }
    }

    private func saveCurrentWorkflowToSelectedWorkspace() {
        guard let workspace = selectedWorkspace else { return }
        workspaceService.writeWorkflow(configuration.workflow, for: workspace)
    }

    private func starterWorkflow(named name: String) -> WorkflowDocument {
        let modelId = configuration.defaultModelId ?? configuration.models.first?.id
        var workflow = WorkflowDocument(name: name)
        workflow.nodes = [
            WorkflowNode(title: "Prompt Planner", description: "Break a creative request into structured steps.", kind: .model, modelId: modelId, agentExecutable: nil, position: CanvasPoint(x: 260, y: 240), inputModalities: [.text], outputModalities: [.text], chat: [], draftMessage: ""),
            WorkflowNode(title: "Image Generator", description: "Generate consistent image assets from the plan.", kind: .model, modelId: modelId, agentExecutable: nil, position: CanvasPoint(x: 620, y: 360), inputModalities: [.text, .image], outputModalities: [.image], chat: [], draftMessage: ""),
            WorkflowNode(title: "Local Agent Review", description: "Ask a desktop coding/design agent to inspect outputs.", kind: .agent, modelId: nil, agentExecutable: "codex", position: CanvasPoint(x: 980, y: 250), inputModalities: [.text, .file], outputModalities: [.text, .file], chat: [], draftMessage: "")
        ]
        workflow.selectedNodeId = workflow.nodes.first?.id
        return workflow
    }

    private func addAssets(_ assets: [MediaAsset]) {
        for asset in assets where !configuration.workflow.assets.contains(where: { $0.path == asset.path }) {
            configuration.workflow.assets.append(asset)
        }
    }

    private func addPendingAttachments(_ paths: [String], to nodeId: UUID, draftMessage: String, saveImmediately: Bool = true) {
        guard !paths.isEmpty,
              let nodeIndex = configuration.workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        let existing = Set(configuration.workflow.nodes[nodeIndex].chat.last?.attachments ?? [])
        let newPaths = paths.filter { !existing.contains($0) }
        guard !newPaths.isEmpty else { return }
        if configuration.workflow.nodes[nodeIndex].draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration.workflow.nodes[nodeIndex].draftMessage = draftMessage
        }
        if configuration.workflow.nodes[nodeIndex].chat.isEmpty || configuration.workflow.nodes[nodeIndex].chat.last?.role != "draft" {
            configuration.workflow.nodes[nodeIndex].chat.append(ChatMessage(role: "draft", text: "Pending attachments", attachments: newPaths))
            enforceChatLimit(&configuration.workflow.nodes[nodeIndex].chat)
        } else if let last = configuration.workflow.nodes[nodeIndex].chat.indices.last {
            configuration.workflow.nodes[nodeIndex].chat[last].attachments.append(contentsOf: newPaths)
        }
        if saveImmediately {
            save()
        }
    }

    private func popGeneratedAssets(_ paths: [String], from nodeId: UUID) {
        guard !paths.isEmpty,
              let node = configuration.workflow.nodes.first(where: { $0.id == nodeId }) else { return }
        let existingCanvasAssets = Set(configuration.workflow.canvasElements.compactMap(\.assetPath))
        for (index, path) in paths.enumerated() where !existingCanvasAssets.contains(path) {
            let position = ejectionPosition(from: node, index: index)
            appendCanvasAssetElement(
                path: path,
                kind: canvasElementKind(for: MediaAsset.inferModality(path: path)),
                position: position,
                sourceNodeId: node.id
            )
            if let target = absorbingNode(for: position, excluding: node.id) {
                addPendingAttachments([path], to: target.id, draftMessage: "Use the absorbed output.", saveImmediately: false)
            }
        }
    }

    private func ejectionPosition(from node: WorkflowNode, index: Int) -> CanvasPoint {
        let spread = max(0, min(node.ejectionSpreadDegrees, 140))
        let angleOffset = ejectionAngleOffset(index: index, spreadDegrees: spread)
        let radians = (node.ejectionAngleDegrees + angleOffset) * .pi / 180
        let force = max(80, min(node.ejectionForce, 720))
        let unit = CGPoint(x: cos(radians), y: sin(radians))
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let stagger = Double(index) * 34
        return CanvasPoint(
            x: node.position.x + unit.x * (force + stagger * 0.35) + perpendicular.x * stagger,
            y: node.position.y + unit.y * (force + stagger * 0.35) + perpendicular.y * stagger
        )
    }

    private func ejectionAngleOffset(index: Int, spreadDegrees: Double) -> Double {
        guard index > 0, spreadDegrees > 0 else { return 0 }
        let ring = Double((index + 1) / 2)
        let direction = index.isMultiple(of: 2) ? -1.0 : 1.0
        return direction * min(spreadDegrees / 2, ring * 12)
    }

    private func appendCanvasAssetElement(path: String, kind: CanvasElementKind, position: CanvasPoint, sourceNodeId: UUID?) {
        let size: CanvasSize
        switch kind {
        case .image, .video:
            size = CanvasSize(width: 240, height: 160)
        case .audio:
            size = CanvasSize(width: 260, height: 96)
        case .file:
            size = CanvasSize(width: 210, height: 126)
        default:
            size = CanvasSize(width: 180, height: 110)
        }
        let element = CanvasElement(
            kind: kind,
            position: position,
            size: size,
            assetPath: path,
            sourceNodeId: sourceNodeId
        )
        configuration.workflow.canvasElements.append(element)
        configuration.workflow.selectedCanvasElementId = element.id
        configuration.workflow.selectedCanvasElementIds = [element.id]
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedNodeId = nil
    }

    private func absorbingNode(for point: CanvasPoint, excluding sourceNodeId: UUID?) -> WorkflowNode? {
        configuration.workflow.nodes
            .filter { $0.id != sourceNodeId }
            .min { first, second in
                absorptionDistance(from: point, to: first) < absorptionDistance(from: point, to: second)
            }
            .flatMap { node in
                absorptionDistance(from: point, to: node) <= absorptionThreshold(for: node) ? node : nil
            }
    }

    private func absorptionDistance(from point: CanvasPoint, to node: WorkflowNode) -> Double {
        hypot(point.x - node.position.x, point.y - node.position.y)
    }

    private func absorptionThreshold(for node: WorkflowNode) -> Double {
        let cardHalfDiagonal = sqrt(130.0 * 130.0 + 75.0 * 75.0)
        guard node.blackHoleEnabled else { return cardHalfDiagonal }
        return max(cardHalfDiagonal, node.blackHoleRadius)
    }

    private func canvasElementKind(for modality: Modality) -> CanvasElementKind {
        switch modality {
        case .image:
            .image
        case .video, .audioVideo:
            .video
        case .audio, .music:
            .audio
        case .file:
            .file
        case .json, .embedding, .scores, .threeD, .mask, .bbox, .reference, .unknown:
            .file
        case .text:
            .text
        }
    }

    private func addConnectorElement(kind: CanvasElementKind, from start: CGPoint, to end: CGPoint) {
        let startPoint = start
        let endPoint = end
        let frame = connectorFrame(from: startPoint, to: endPoint)
        let localPoints = localConnectorPoints(from: startPoint, to: endPoint, in: frame)
        let element = CanvasElement(
            kind: kind,
            position: CanvasPoint(x: frame.midX, y: frame.midY),
            size: CanvasSize(width: frame.width, height: frame.height),
            pathPoints: localPoints,
            strokeWidth: 2.4,
            colorHex: configuration.boardSettings.shapeColorHex
        )
        configuration.workflow.canvasElements.append(element)
        configuration.workflow.selectedCanvasElementId = element.id
        configuration.workflow.selectedCanvasElementIds = [element.id]
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedNodeId = nil
        save()
    }

    private func addCanvasElement(kind: CanvasElementKind, at position: CanvasPoint, size overrideSize: CanvasSize? = nil, assetPath: String? = nil, pathPoints: [CanvasPoint] = [], colorHex: String = "#111111", strokeWidth: Double = 2) {
        let size: CanvasSize
        let text: String?
        if let overrideSize {
            size = overrideSize
            text = kind == .text ? "Text" : nil
        } else {
            switch kind {
            case .line, .arrow:
                size = CanvasSize(width: 180, height: 70)
                text = nil
            case .text:
                size = CanvasSize(width: 180, height: 54)
                text = "Text"
            case .image, .video:
                size = CanvasSize(width: 240, height: 160)
                text = nil
            case .audio:
                size = CanvasSize(width: 260, height: 96)
                text = nil
            case .file:
                size = CanvasSize(width: 210, height: 126)
                text = nil
            case .pen:
                size = CanvasSize(width: 190, height: 90)
                text = nil
            default:
                size = CanvasSize(width: 150, height: 100)
                text = nil
            }
        }
        let resolvedColor: String
        if kind == .text && colorHex == "#111111" {
            resolvedColor = configuration.boardSettings.textColorHex
        } else if kind == .artboard && colorHex == "#111111" {
            resolvedColor = configuration.boardSettings.artboardColorHex
        } else if colorHex == "#111111", [.rectangle, .line, .arrow, .ellipse, .polygon, .star].contains(kind) {
            resolvedColor = configuration.boardSettings.shapeColorHex
        } else {
            resolvedColor = colorHex
        }
        let element = CanvasElement(kind: kind, position: position, size: size, text: text, assetPath: assetPath, pathPoints: pathPoints, strokeWidth: strokeWidth, colorHex: resolvedColor)
        configuration.workflow.canvasElements.append(element)
        configuration.workflow.selectedCanvasElementId = element.id
        configuration.workflow.selectedCanvasElementIds = [element.id]
        configuration.workflow.selectedNodeIds = []
        configuration.workflow.selectedNodeId = nil
        save()
    }

    private func isConnector(_ element: CanvasElement, attachedToAny elementIds: Set<UUID>) -> Bool {
        guard element.kind == .line || element.kind == .arrow else { return false }
        return [element.startAnchor, element.endAnchor].contains { anchor in
            anchor?.targetKind == .element && elementIds.contains(anchor?.targetId ?? UUID())
        }
    }

    private func isConnector(_ element: CanvasElement, attachedToAnyNodes nodeIds: Set<UUID>) -> Bool {
        guard element.kind == .line || element.kind == .arrow else { return false }
        return [element.startAnchor, element.endAnchor].contains { anchor in
            anchor?.targetKind == .node && nodeIds.contains(anchor?.targetId ?? UUID())
        }
    }

    private func refreshConnections(affectedNodeIds: Set<UUID> = [], affectedElementIds: Set<UUID> = []) {
        for index in configuration.workflow.canvasElements.indices {
            guard configuration.workflow.canvasElements[index].kind == .line || configuration.workflow.canvasElements[index].kind == .arrow else { continue }
            let element = configuration.workflow.canvasElements[index]
            guard shouldRefreshConnection(element, affectedNodeIds: affectedNodeIds, affectedElementIds: affectedElementIds) else { continue }
            guard let start = element.startAnchor.flatMap(anchorPosition(for:)),
                  let end = element.endAnchor.flatMap(anchorPosition(for:)) else {
                continue
            }
            let frame = connectorFrame(from: start, to: end)
            configuration.workflow.canvasElements[index].position = CanvasPoint(x: frame.midX, y: frame.midY)
            configuration.workflow.canvasElements[index].size = CanvasSize(width: frame.width, height: frame.height)
            configuration.workflow.canvasElements[index].pathPoints = localConnectorPoints(from: start, to: end, in: frame)
        }
    }

    private func shouldRefreshConnection(_ element: CanvasElement, affectedNodeIds: Set<UUID>, affectedElementIds: Set<UUID>) -> Bool {
        guard !affectedNodeIds.isEmpty || !affectedElementIds.isEmpty else { return true }
        return [element.startAnchor, element.endAnchor].contains { anchor in
            guard let anchor else { return false }
            switch anchor.targetKind {
            case .node:
                return affectedNodeIds.contains(anchor.targetId)
            case .element:
                return affectedElementIds.contains(anchor.targetId)
            }
        }
    }

    private func nearestAnchor(to point: CGPoint) -> CanvasAnchorRef? {
        let candidates = anchorCandidates()
        guard let nearest = candidates.min(by: { distance($0.point, point) < distance($1.point, point) }),
              distance(nearest.point, point) <= 34 else {
            return nil
        }
        return nearest.anchor
    }

    private func anchorPosition(for ref: CanvasAnchorRef) -> CGPoint? {
        switch ref.targetKind {
        case .node:
            guard let node = configuration.workflow.nodes.first(where: { $0.id == ref.targetId }) else { return nil }
            return anchorPoint(center: node.position, size: CanvasSize(width: 260, height: 150), side: ref.side)
        case .element:
            guard let element = configuration.workflow.canvasElements.first(where: { $0.id == ref.targetId }) else { return nil }
            return anchorPoint(center: element.position, size: element.size, side: ref.side)
        }
    }

    private func anchorCandidates() -> [(anchor: CanvasAnchorRef, point: CGPoint)] {
        let nodeAnchors = configuration.workflow.nodes.flatMap { node in
            CanvasAnchorSide.allCases.map { side in
                (
                    CanvasAnchorRef(targetKind: .node, targetId: node.id, side: side),
                    anchorPoint(center: node.position, size: CanvasSize(width: 260, height: 150), side: side)
                )
            }
        }
        let elementAnchors = configuration.workflow.canvasElements
            .filter { ![CanvasElementKind.line, .arrow, .pen].contains($0.kind) }
            .flatMap { element in
                CanvasAnchorSide.allCases.map { side in
                    (
                        CanvasAnchorRef(targetKind: .element, targetId: element.id, side: side),
                        anchorPoint(center: element.position, size: element.size, side: side)
                    )
                }
            }
        return nodeAnchors + elementAnchors
    }

    private func anchorPoint(center: CanvasPoint, size: CanvasSize, side: CanvasAnchorSide) -> CGPoint {
        switch side {
        case .top:
            CGPoint(x: center.x, y: center.y - size.height / 2)
        case .right:
            CGPoint(x: center.x + size.width / 2, y: center.y)
        case .bottom:
            CGPoint(x: center.x, y: center.y + size.height / 2)
        case .left:
            CGPoint(x: center.x - size.width / 2, y: center.y)
        }
    }

    private func connectorFrame(from start: CGPoint, to end: CGPoint) -> CGRect {
        let inset = 20.0
        let minX = min(start.x, end.x) - inset
        let minY = min(start.y, end.y) - inset
        let width = max(abs(end.x - start.x) + inset * 2, 44)
        let height = max(abs(end.y - start.y) + inset * 2, 44)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func localConnectorPoints(from start: CGPoint, to end: CGPoint, in frame: CGRect) -> [CanvasPoint] {
        [
            CanvasPoint(x: start.x - frame.minX, y: start.y - frame.minY),
            CanvasPoint(x: end.x - frame.minX, y: end.y - frame.minY)
        ]
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func normalizedHex(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6 else { return "#111111" }
        return "#\(cleaned)"
    }

    private func canvasElementKind(for tool: CanvasTool) -> CanvasElementKind? {
        switch tool {
        case .grid: .artboard
        case .rectangle: .rectangle
        case .line: .line
        case .arrow: .arrow
        case .ellipse: .ellipse
        case .polygon: .polygon
        case .star: .star
        case .pen: .pen
        case .text: .text
        default: nil
        }
    }

    private func smooth(points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var output = [points[0]]
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]
            output.append(CGPoint(x: (previous.x + current.x + next.x) / 3, y: (previous.y + current.y + next.y) / 3))
        }
        output.append(points[points.count - 1])
        return output
    }

    private func normalizedCanvasFrame(from start: CGPoint, to end: CGPoint, minimumSize: CGSize) -> CGRect {
        var width = abs(end.x - start.x)
        var height = abs(end.y - start.y)
        let originX = min(start.x, end.x)
        let originY = min(start.y, end.y)

        if width < minimumSize.width { width = minimumSize.width }
        if height < minimumSize.height { height = minimumSize.height }

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func pendingAttachments(for node: WorkflowNode) -> [String] {
        guard node.chat.last?.role == "draft" else { return [] }
        return node.chat.last?.attachments ?? []
    }

}

private extension Array where Element == ModelCapability {
    func uniquedByTask() -> [ModelCapability] {
        var seen: Set<ModelTask> = []
        return filter { capability in
            seen.insert(capability.task).inserted
        }
    }
}

private struct CanvasClipboardPayload: Codable {
    var nodes: [WorkflowNode]
    var elements: [CanvasElement]
}

private struct WorkflowExecutionResult {
    var succeeded: Bool
    var summary: String
    var outputText: String
    var assetPaths: [String]
    var errorMessage: String?
    var absorbedAssetsCount: Int = 0
    var createdConsistencyAssetIds: [UUID] = []
    var updatedConsistencyAssetIds: [UUID] = []
    var skippedAssets: [String] = []
    var conflicts: [ConsistencyConflict] = []
    var consistencyValidation: ConsistencyValidationResult?
}
