import XCTest
@testable import WorkflowGenerator

final class WorkflowRoutingTests: XCTestCase {
    func testFanToBlackholeRouteIsResolvedInWorldCoordinates() {
        let source = makeNode(title: "Source", position: CanvasPoint(x: 0, y: 0), angle: 0, force: 320, spread: 40)
        let target = makeNode(title: "Target", position: CanvasPoint(x: 260, y: 0), blackHoleRadius: 90)

        let routes = SpatialArtifactRouteResolver().resolve(nodes: [source, target], mode: .bigMouth)

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes.first?.sourceNodeId, source.id)
        XCTAssertEqual(routes.first?.targetNodeId, target.id)
    }

    func testFanToBlackholeRouteRejectsOutsideSector() {
        let source = makeNode(title: "Source", position: CanvasPoint(x: 0, y: 0), angle: 0, force: 320, spread: 24)
        let target = makeNode(title: "Target", position: CanvasPoint(x: 0, y: 260), blackHoleRadius: 80)

        let routes = SpatialArtifactRouteResolver().resolve(nodes: [source, target], mode: .bigMouth)

        XCTAssertTrue(routes.isEmpty)
    }

    func testSpatialRouteCreatesGraphDependencyLevel() throws {
        let source = makeNode(title: "Source", position: CanvasPoint(x: 0, y: 0))
        let target = makeNode(title: "Target", position: CanvasPoint(x: 260, y: 0))
        var workflow = WorkflowDocument(name: "Spatial Route Test")
        workflow.nodes = [source, target]
        let route = SpatialArtifactRoute(
            sourceNodeId: source.id,
            targetNodeId: target.id,
            sourceFan: SpatialFanSnapshot(angle: 0, radius: 320, spreadDegrees: 40),
            targetBlackhole: SpatialBlackholeSnapshot(receiverId: target.id, radius: 90)
        )

        let graph = try WorkflowGraphService().build(from: workflow, spatialRoutes: [route])

        XCTAssertEqual(graph.nodeLevels[source.id], 0)
        XCTAssertEqual(graph.nodeLevels[target.id], 1)
        XCTAssertEqual(graph.incomingSpatialRoutes[target.id]?.count, 1)
    }

    func testWorkflowGraphRejectsLogicCycles() {
        let first = makeNode(title: "First", position: CanvasPoint(x: 0, y: 0))
        let second = makeNode(title: "Second", position: CanvasPoint(x: 260, y: 0))
        var workflow = WorkflowDocument(name: "Cycle Test")
        workflow.nodes = [first, second]
        workflow.canvasElements = [
            logicEdge(from: first.id, to: second.id),
            logicEdge(from: second.id, to: first.id)
        ]

        XCTAssertThrowsError(try WorkflowGraphService().build(from: workflow)) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("DAG"))
        }
    }

    func testSpatialRoutesCarryTextByDefaultForBigMouthMode() {
        let source = makeNode(title: "Source", position: CanvasPoint(x: 0, y: 0), angle: 0, force: 320, spread: 40)
        let target = makeNode(title: "Target", position: CanvasPoint(x: 260, y: 0), blackHoleRadius: 90)

        let route = SpatialArtifactRouteResolver().resolve(nodes: [source, target], mode: .bigMouth).first

        XCTAssertEqual(route?.artifactOnly, false)
        XCTAssertEqual(route?.transfersText, true)
        XCTAssertEqual(route?.payloadMapping, "{}")
    }

    func testAppConfigurationDoesNotPersistWorkflowPayloadInGlobalConfig() throws {
        var configuration = AppConfiguration()
        configuration.workflow = WorkflowDocument(name: "Workspace Only")
        configuration.workflow.workflowVariables = [WorkflowVariable(name: "project_scope", value: "private")]

        let data = try JSONEncoder().encode(configuration)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("Workspace Only"))
        XCTAssertFalse(json.contains("project_scope"))
        XCTAssertFalse(json.contains("workflowVariables"))
    }

    func testDashScopeVideoPresetInjectsAsyncHeader() {
        let provider = ProviderConfig(name: "阿里云百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "key")
        let video = ProviderEndpointPresetRegistry.profiles(for: provider).first { $0.presetKey == "aliyun.video_task" }

        XCTAssertEqual(video?.mode, .async)
        XCTAssertEqual(video?.requiredHeaders?["X-DashScope-Async"], "enable")
    }

    func testSystemPresetDeleteLifecycleIsSoftDisable() {
        let provider = ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "key")
        var endpoint = ProviderEndpointPresetRegistry.profiles(for: provider).first { $0.presetKey == "openai.images" }!

        endpoint.enabled = false
        endpoint.isDeleted = true
        endpoint.disabledAt = Date()

        XCTAssertEqual(endpoint.effectiveSource, .systemPreset)
        XCTAssertFalse(endpoint.isActive)
        XCTAssertEqual(endpoint.presetKey, "openai.images")
        XCTAssertEqual(endpoint.isRestorable, true)
    }

    func testUnknownDocsStatusIsNotVerified() {
        let provider = ProviderConfig(name: "Custom Provider", baseURL: "https://example.com/v1", apiKey: "")
        let custom = ProviderEndpointPresetRegistry.profiles(for: provider)

        XCTAssertTrue(custom.allSatisfy { $0.docs?.status != .verified })
    }

    func testDeepSeekPresetsAreTextOnly() {
        let provider = ProviderConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com", apiKey: "key")
        let tasks = Set(ProviderEndpointPresetRegistry.profiles(for: provider).flatMap(\.supportedTasks))

        XCTAssertTrue(tasks.contains(.chat))
        XCTAssertTrue(tasks.contains(.reasoningChat))
        XCTAssertFalse(tasks.contains(.textToImage))
        XCTAssertFalse(tasks.contains(.textToVideo))
        XCTAssertFalse(tasks.contains(.textToSpeech))
    }

    func testRetiredProviderFallsBackToGenericCompatibilityProfiles() {
        let provider = ProviderConfig(name: "Retired Vendor", baseURL: "https://example.com/v1", apiKey: "key")
        let profiles = ProviderEndpointPresetRegistry.profiles(for: provider)

        XCTAssertEqual(profiles.first?.presetKey, "custom.chat")
        XCTAssertTrue(profiles.allSatisfy { $0.docs?.status != .verified })
    }

    func testMiniMaxChinaPresetsSeparateLanguageSpeechVideoImageMusic() {
        let provider = ProviderConfig(name: "MiniMax Coding Plan", baseURL: "https://api.minimaxi.com/v1", apiKey: "key")
        let profiles = ProviderEndpointPresetRegistry.profiles(for: provider)

        XCTAssertEqual(profiles.first { $0.presetKey == "minimax.chat" }?.taskGroup, .chat)
        XCTAssertEqual(profiles.first { $0.presetKey == "minimax.tts" }?.supportedTasks, [.textToSpeech])
        XCTAssertEqual(profiles.first { $0.presetKey == "minimax.video" }?.taskGroup, .video)
        XCTAssertEqual(profiles.first { $0.presetKey == "minimax.image" }?.taskGroup, .image)
        XCTAssertEqual(profiles.first { $0.presetKey == "minimax.music" }?.taskGroup, .music)
    }

    func testAgnesAIPresetsCoverAdvancedTextImageAndVideoModels() {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let profiles = ProviderEndpointPresetRegistry.profiles(for: provider)

        XCTAssertEqual(profiles.map(\.presetKey), ["agnes.chat", "agnes.image.21", "agnes.image.20", "agnes.video"])
        XCTAssertEqual(profiles.first { $0.presetKey == "agnes.chat" }?.path, "/chat/completions")
        XCTAssertEqual(profiles.first { $0.presetKey == "agnes.image.21" }?.path, "/images/generations")
        XCTAssertEqual(profiles.first { $0.presetKey == "agnes.image.20" }?.supportedTasks, [.imageToImage, .imageEdit])
        XCTAssertEqual(profiles.first { $0.presetKey == "agnes.video" }?.polling?.pollingPath, "/videos/{task_id}")
        XCTAssertTrue(profiles.first { $0.presetKey == "agnes.video" }?.supportedTasks.contains(.referenceToVideo) == true)
        XCTAssertTrue(profiles.allSatisfy { $0.docs?.status == .verified })
    }

    func testModelRegistrationCardsFillNestedRequestParameters() throws {
        var fixture = modelRegistrationFixture(task: .textToVideo)
        fixture.configuration.modelRegistrations[0].inputSlots = [
            ModelRegistrationInputSlot(label: "提示词", parameterPath: "input.prompt", source: .prompt, modality: .text, required: true),
            ModelRegistrationInputSlot(label: "配乐", parameterPath: "input.audio_url", source: .attachment, modality: .audio, required: true)
        ]
        let inputs = [
            InvocationAsset(type: .text, text: "夜晚城市"),
            InvocationAsset(type: .audio, url: "https://example.com/music.mp3")
        ]
        let router = ModelRegistrationRouter()
        let context = try router.resolve(modelId: fixture.model.id, desiredOutputModalities: [.video], inputs: inputs, configuration: fixture.configuration)
        let payload = try router.buildPayload(context: context, inputs: inputs)

        XCTAssertEqual((payload["input"] as? [String: Any])?["prompt"] as? String, "夜晚城市")
        XCTAssertEqual((payload["input"] as? [String: Any])?["audio_url"] as? String, "https://example.com/music.mp3")
    }

    func testModelRegistrationTableSelectsMostSpecificRecipe() throws {
        var fixture = modelRegistrationFixture(task: .textToImage)
        var imageToImage = ModelRegistrationPresetRegistry.make(
            model: fixture.model,
            provider: fixture.configuration.providers[0],
            task: .imageToImage
        )
        imageToImage.status = .unverified
        fixture.configuration.modelRegistrations.append(imageToImage)
        let inputs = [
            InvocationAsset(type: .text, text: "调整风格"),
            InvocationAsset(type: .image, url: "https://example.com/reference.png")
        ]

        let context = try ModelRegistrationRouter().resolve(
            modelId: fixture.model.id,
            desiredOutputModalities: [.image],
            inputs: inputs,
            configuration: fixture.configuration
        )

        XCTAssertEqual(context.registration.task, .imageToImage)
    }

    func testAsyncModelRegistrationKeepsPollingConfiguration() {
        let fixture = modelRegistrationFixture(task: .textToVideo)
        let registration = fixture.configuration.modelRegistrations[0]

        XCTAssertEqual(registration.mode, .async)
        XCTAssertNotNil(registration.polling)
    }

    func testLegacyModelMigrationCreatesEditableRegistrationDraft() {
        var configuration = AppConfiguration()
        configuration.modelRegistrations = []

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))
        XCTAssertEqual(Set(configuration.modelRegistrations.map(\.modelId)), Set(configuration.models.map(\.id)))
        XCTAssertTrue(configuration.modelRegistrations.allSatisfy { !$0.inputSlots.isEmpty && !$0.outputSlots.isEmpty })
    }

    private func makeNode(
        title: String,
        position: CanvasPoint,
        angle: Double = 0,
        force: Double = 320,
        spread: Double = 34,
        blackHoleRadius: Double = 170
    ) -> WorkflowNode {
        WorkflowNode(
            title: title,
            description: "",
            kind: .model,
            modelId: nil,
            agentExecutable: nil,
            position: position,
            inputModalities: [.text],
            outputModalities: [.image],
            chat: [],
            draftMessage: "",
            ejectionAngleDegrees: angle,
            ejectionForce: force,
            ejectionSpreadDegrees: spread,
            blackHoleRadius: blackHoleRadius
        )
    }

    private func logicEdge(from sourceId: UUID, to targetId: UUID) -> CanvasElement {
        let start = CanvasAnchorRef(targetKind: .node, targetId: sourceId, side: .right)
        let end = CanvasAnchorRef(targetKind: .node, targetId: targetId, side: .left)
        return CanvasElement(
            kind: .arrow,
            position: CanvasPoint(x: 130, y: 0),
            size: CanvasSize(width: 260, height: 44),
            pathPoints: [CanvasPoint(x: 0, y: 22), CanvasPoint(x: 260, y: 22)],
            startAnchor: start,
            endAnchor: end,
            isLogicConnection: true,
            logicEdge: WorkflowLogicEdgeConfiguration(sourceNodeId: sourceId, targetNodeId: targetId)
        )
    }

    private func invocationFixture(modelId: String, providerName: String, task: ModelTask) -> (configuration: AppConfiguration, model: ModelConfig) {
        var configuration = AppConfiguration()
        let baseURL: String
        switch ProviderEndpointCatalog.normalizedProviderName(providerName) {
        case "openai": baseURL = "https://api.openai.com/v1"
        case "aliyun": baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case "deepseek": baseURL = "https://api.deepseek.com"
        case "minimax": baseURL = "https://api.minimaxi.com/v1"
        default: baseURL = "https://ark.cn-beijing.volces.com/api/v3"
        }
        let provider = ProviderConfig(
            name: providerName,
            baseURL: baseURL,
            apiKey: "test-key",
            symbolName: "network"
        )
        let endpoint = ProviderEndpointPresetRegistry.profiles(for: provider).first { $0.supportedTasks.contains(task) && $0.isActive }
            ?? ProviderEndpointPresetRegistry.profiles(for: provider).first { $0.supportedTasks.contains(task) }!
        let model = ModelConfig(
            name: modelId,
            provider: provider.name,
            providerId: provider.id,
            baseURL: provider.baseURL,
            modelId: modelId,
            supportedModalities: task.defaultInputModalities.union(task.defaultOutputModalities),
            inputModalities: task.defaultInputModalities,
            outputModalities: task.defaultOutputModalities,
            endpointKind: task.legacyEndpointKind,
            endpointPath: endpoint.path,
            requestParametersJSON: "{}",
            apiKeyReference: ""
        )
        let capability = ModelCapability(
            modelId: model.id,
            task: task,
            inputModalities: task.defaultInputModalities,
            outputModalities: task.defaultOutputModalities,
            endpointProfileId: endpoint.id,
            parameterSchemaId: task.defaultSchemaId,
            defaultParams: "{}",
            confidence: .manual,
            enabled: true
        )
        configuration.providers = [provider]
        configuration.endpointProfiles = [endpoint]
        configuration.models = [model]
        configuration.modelCapabilities = [capability]
        configuration.parameterSchemas = ParameterSchema.genericDefaults
        return (configuration, model)
    }

    private func modelRegistrationFixture(task: ModelTask) -> (configuration: AppConfiguration, model: ModelConfig) {
        var fixture = invocationFixture(modelId: "registered-model", providerName: "阿里云百炼", task: task)
        var registration = ModelRegistrationPresetRegistry.make(
            model: fixture.model,
            provider: fixture.configuration.providers[0],
            task: task
        )
        registration.status = .unverified
        fixture.configuration.modelRegistrations = [registration]
        return fixture
    }
}
