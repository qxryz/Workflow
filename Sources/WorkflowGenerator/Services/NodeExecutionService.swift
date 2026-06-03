import Foundation

struct NodeExecutionService {
    private let acpService = ACPAgentSessionService()
    private let registrationRouter = ModelRegistrationRouter()
    private let assetImporter = WorkspaceAssetImporter()

    func stream(
        messages: [ChatCompletionMessage],
        prompt: String,
        attachments: [String],
        node: WorkflowNode,
        configuration: AppConfiguration,
        workspacePath: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    switch node.kind {
                    case .model:
                        guard node.registeredModelInterfaceId != nil else {
                            yieldError(
                                .noModelConfigured,
                                nodeId: node.id,
                                detail: "Node '\(node.title)' has no registered model interface. Open node configuration and choose a registered interface.",
                                continuation: continuation
                            )
                            return
                        }
                        let workspace = configuration.selectedWorkspaceId.flatMap { id in
                            configuration.workspaces.first { $0.id == id }
                        }
                        try await streamRegisteredModel(
                            messages: messages,
                            prompt: prompt,
                            attachments: attachments,
                            node: node,
                            configuration: configuration,
                            workspace: workspace,
                            continuation: continuation
                        )
                    case .agent:
                        guard let executable = node.agentExecutable,
                              let agent = configuration.agents.first(where: { $0.executable == executable }) else {
                            yieldError(
                                .noAgentConfigured,
                                nodeId: node.id,
                                detail: "Node '\(node.title)' has no agent assigned.",
                                continuation: continuation
                            )
                            return
                        }
                        guard !agent.acpInvocationTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            yieldError(
                                .agentNoAcpCommand,
                                nodeId: node.id,
                                detail: "\(agent.name) missing ACP command.",
                                continuation: continuation
                            )
                            return
                        }
                        try await acpService.streamPrompt(
                            prompt: prompt,
                            attachments: attachments,
                            agent: agent,
                            node: node,
                            workspacePath: workspacePath,
                            continuation: continuation
                        )
                    case .consistency:
                        yieldError(
                            .consistencyNoDirectOutput,
                            nodeId: node.id,
                            detail: "Consistency nodes work in workflow runs only.",
                            continuation: continuation
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func execute(
        prompt: String,
        node: WorkflowNode,
        configuration: AppConfiguration,
        workspacePath: String?
    ) async -> String {
        do {
            switch node.kind {
            case .model:
                guard let interfaceId = node.registeredModelInterfaceId else {
                    return "No registered model interface is configured for this node."
                }
                return try await registrationRouter.invoke(
                    interfaceId: interfaceId,
                    inputs: invocationAssets(prompt: prompt, attachments: []),
                    nodeOverrides: node.modelParameterOverrides,
                    configuration: configuration
                )
                .text
            case .agent:
                guard let executable = node.agentExecutable,
                      let agent = configuration.agents.first(where: { $0.executable == executable }) else {
                    return "No local agent is configured for this node."
                }
                return try await callACPAgent(
                    prompt: prompt,
                    agent: agent,
                    node: node,
                    workspacePath: workspacePath
                )
            case .consistency:
                return "Consistency nodes absorb workflow artifacts during a workflow run."
            }
        } catch {
            return "Execution failed: \(error.localizedDescription)"
        }
    }

    func cancel(node: WorkflowNode) {
        Task { await acpService.cancel(nodeId: node.id) }
    }

    func closeSession(node: WorkflowNode) {
        Task { await acpService.close(nodeId: node.id) }
    }

    func closeAllSessions() {
        Task { await acpService.closeAll() }
    }

    func testACP(agent: AgentConfig, workspacePath: String?) async -> String {
        await acpService.test(agent: agent, workspacePath: workspacePath)
    }

    private func streamRegisteredModel(
        messages: [ChatCompletionMessage],
        prompt: String,
        attachments: [String],
        node: WorkflowNode,
        configuration: AppConfiguration,
        workspace: WorkspaceLocation?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let inputs = invocationAssets(prompt: prompt, attachments: attachments)
        let context: ResolvedModelRegistration
        do {
            guard let interfaceId = node.registeredModelInterfaceId else {
                throw ModelRegistrationError.registrationNotFound
            }
            context = try registrationRouter.resolve(interfaceId: interfaceId, configuration: configuration)
        } catch {
            continuation.yield(error.localizedDescription)
            continuation.finish()
            return
        }

        continuation.yield("使用已注册模型：\(context.registration.title)\n")
        do {
            let response = try await registrationRouter.invoke(
                context: context,
                inputs: inputs,
                nodeOverrides: node.modelParameterOverrides,
                conversationMessages: messages,
                onProgress: { continuation.yield($0.message + "\n") }
            )
            if !response.text.isEmpty {
                continuation.yield(response.text)
                if !response.text.hasSuffix("\n") {
                    continuation.yield("\n")
                }
            }
            let assets = try await assetImporter.importResponse(response, model: context.model, workspace: workspace)
            for asset in assets {
                continuation.yield("[asset] \(asset.path)\n")
            }
            continuation.finish()
        } catch {
            continuation.yield(error.localizedDescription)
            continuation.finish()
        }
    }

    private func yieldError(
        _ code: NodeExecutionErrorCode,
        nodeId: UUID,
        detail: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        let error = NodeExecutionError(code: code, nodeId: nodeId, title: code.suggestionTitle, detail: detail)
        continuation.yield("[NODE_ERROR:\(code.rawValue)]\(error.title)|\(error.detail)|\(error.suggestion)")
        continuation.finish()
    }

    private func callACPAgent(
        prompt: String,
        agent: AgentConfig,
        node: WorkflowNode,
        workspacePath: String?
    ) async throws -> String {
        let collector = LockedTextCollector()
        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                try await acpService.streamPrompt(
                    prompt: prompt,
                    attachments: [],
                    agent: agent,
                    node: node,
                    workspacePath: workspacePath,
                    continuation: continuation
                )
            }
        }
        for try await chunk in stream {
            collector.append(chunk)
        }
        let finalText = collector.value
        return finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(agent.name) completed without text output."
            : finalText
    }
}

struct ChatCompletionMessage: Codable, Hashable {
    let role: String
    let content: String
}

private final class LockedTextCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        lock.unlock()
    }
}

private func invocationAssets(prompt: String, attachments: [String]) -> [InvocationAsset] {
    var assets = [InvocationAsset(type: .text, text: prompt)]
    for path in attachments {
        let modality = MediaAsset.inferModality(path: path)
        let isRemote = path.lowercased().hasPrefix("https://") || path.lowercased().hasPrefix("http://")
        assets.append(
            InvocationAsset(
                type: modality,
                url: isRemote ? path : URL(filePath: path).absoluteString,
                metadata: ["path": path]
            )
        )
    }
    return assets
}
