import XCTest
@testable import WorkflowGenerator

final class ModelRegistrationTests: XCTestCase {
    func testDraftRegistrationIsNotNodeSelectable() {
        XCTAssertFalse(RegistrationStatus.draft.isNodeSelectable)
    }

    func testUnverifiedRegistrationIsNodeSelectable() {
        XCTAssertTrue(RegistrationStatus.unverified.isNodeSelectable)
    }

    func testVerifiedRegistrationIsNodeSelectable() {
        XCTAssertTrue(RegistrationStatus.verified.isNodeSelectable)
    }

    func testDisabledRegistrationIsNotNodeSelectable() {
        XCTAssertFalse(RegistrationStatus.disabled.isNodeSelectable)
    }

    func testWorkflowNodeRoundTripsRegisteredModelInterfaceSelection() throws {
        let registeredModelInterfaceId = UUID()
        let node = makeNode(
            registeredModelInterfaceId: registeredModelInterfaceId,
            modelParameterOverrides: [
                "temperature": "0.4",
                "response_format": "json"
            ]
        )

        let data = try JSONEncoder().encode(node)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(WorkflowNode.self, from: data)

        XCTAssertEqual(json["registeredModelInterfaceId"] as? String, registeredModelInterfaceId.uuidString)
        XCTAssertEqual(json["modelParameterOverrides"] as? [String: String], node.modelParameterOverrides)
        XCTAssertEqual(decoded.registeredModelInterfaceId, registeredModelInterfaceId)
        XCTAssertEqual(decoded.modelParameterOverrides, node.modelParameterOverrides)
    }

    func testWorkflowNodeDefaultsRegisteredModelInterfaceSelectionWhenDecodingLegacyPayload() throws {
        let data = try JSONEncoder().encode(makeNode())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "registeredModelInterfaceId")
        json.removeValue(forKey: "modelParameterOverrides")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(WorkflowNode.self, from: legacyData)

        XCTAssertNil(decoded.registeredModelInterfaceId)
        XCTAssertEqual(decoded.modelParameterOverrides, [:])
    }

    func testRegistrationPresetCarriesProviderId() {
        let provider = ProviderConfig(name: "Test Provider", baseURL: "https://example.com/v1", apiKey: "key")
        let model = ModelConfig(
            name: "Test Model",
            provider: provider.name,
            providerId: provider.id,
            baseURL: provider.baseURL,
            modelId: "test-model",
            supportedModalities: [.text],
            endpointPath: "/chat/completions",
            apiKeyReference: ""
        )

        let registration = ModelRegistrationPresetRegistry.make(model: model, provider: provider, task: .chat)

        XCTAssertEqual(registration.providerId, provider.id)
    }

    func testLegacyModelRegistrationJSONDecodesIntoCanonicalValues() throws {
        let modelId = UUID()
        let providerId = UUID()
        let inputSlotId = UUID()
        let json = """
        {
          "modelId": "\(modelId.uuidString)",
          "providerId": "\(providerId.uuidString)",
          "title": "Legacy Chat",
          "task": "chat",
          "enabled": true,
          "path": "/chat/completions",
          "mode": "streaming",
          "inputSlots": [{
            "id": "\(inputSlotId.uuidString)",
            "label": "Prompt",
            "parameterPath": "messages.0.content",
            "source": "prompt",
            "modality": "text",
            "required": true,
            "acceptsMultiple": false,
            "valueFormat": "automatic",
            "fixedValue": ""
          }],
          "presetKey": "legacy.chat",
          "lastStatus": "Legacy ready"
        }
        """

        let registration = try JSONDecoder().decode(ModelRegistration.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(registration.mode, .sse)
        XCTAssertEqual(registration.status, .unverified)
        XCTAssertEqual(registration.inputCards.map(\.id), [inputSlotId])
        XCTAssertEqual(registration.templateId, "legacy.chat")
        XCTAssertEqual(registration.lastTestSummary, "Legacy ready")
        XCTAssertEqual(registration.interfaceFamily, .conversation)
    }

    func testProviderlessLegacyModelRegistrationDecodesAsDraft() throws {
        let json = """
        {
          "modelId": "\(UUID().uuidString)",
          "title": "Legacy Draft",
          "enabled": true,
          "path": "/chat/completions"
        }
        """

        let registration = try JSONDecoder().decode(ModelRegistration.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(registration.providerId, RegisteredModelInterface.unresolvedProviderId)
        XCTAssertFalse(registration.hasResolvedProvider)
        XCTAssertEqual(registration.status, .draft)
    }

    func testProviderlessDisabledLegacyModelRegistrationStaysDisabled() throws {
        let json = """
        {
          "modelId": "\(UUID().uuidString)",
          "title": "Legacy Disabled",
          "enabled": false,
          "path": "/chat/completions"
        }
        """

        let registration = try JSONDecoder().decode(ModelRegistration.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(registration.providerId, RegisteredModelInterface.unresolvedProviderId)
        XCTAssertFalse(registration.hasResolvedProvider)
        XCTAssertEqual(registration.status, .disabled)
    }

    func testUnknownInvocationModeFailsDecoding() throws {
        let data = try XCTUnwrap(#""future_transport""#.data(using: .utf8))

        XCTAssertThrowsError(try JSONDecoder().decode(InvocationMode.self, from: data)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }
    }

    func testCanonicalModelRegistrationRoundTripKeepsStringTemplateVersion() throws {
        let id = UUID()
        let modelId = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "modelId": "\(modelId.uuidString)",
          "title": "Canonical Chat",
          "templateVersion": "2026-06",
          "interfaceFamily": "conversation",
          "inheritsProviderBaseURL": true,
          "baseURLOverride": "",
          "path": "/chat/completions",
          "method": "POST",
          "requestEncoding": "application/json",
          "mode": "sync",
          "headers": {},
          "modelParameterPath": "model",
          "defaultRequestJSON": "{}",
          "inputCards": [],
          "parameters": [],
          "nodeControls": [],
          "outputSlots": [],
          "status": "draft",
          "lastTestSummary": "Not tested",
          "lastModifiedByUser": false,
          "task": "chat"
        }
        """
        let decoder = JSONDecoder()

        let registration = try decoder.decode(ModelRegistration.self, from: XCTUnwrap(json.data(using: .utf8)))
        let decoded = try decoder.decode(ModelRegistration.self, from: JSONEncoder().encode(registration))

        XCTAssertEqual(decoded.templateVersion, "2026-06")
    }

    func testInvocationAssetRoundTripsBinaryData() throws {
        let asset = InvocationAsset(type: .file, data: Data([0x00, 0x7f, 0xff]))

        let decoded = try JSONDecoder().decode(InvocationAsset.self, from: JSONEncoder().encode(asset))

        XCTAssertEqual(decoded.data, asset.data)
    }

    func testCanonicalInitializerDerivesConversationFamilyForChatTask() {
        let registration = RegisteredModelInterface(
            modelId: UUID(),
            providerId: RegisteredModelInterface.unresolvedProviderId,
            title: "Chat",
            path: "/chat",
            task: .chat
        )

        XCTAssertEqual(registration.interfaceFamily, .conversation)
    }

    func testCanonicalInitializerDerivesSpecialFamilyForNonChatTask() {
        let registration = RegisteredModelInterface(
            modelId: UUID(),
            providerId: RegisteredModelInterface.unresolvedProviderId,
            title: "Image",
            path: "/images",
            task: .textToImage
        )

        XCTAssertEqual(registration.interfaceFamily, .special)
    }

    func testCanonicalInitializerKeepsProviderlessRegistrationAsDraft() {
        let registration = RegisteredModelInterface(
            modelId: UUID(),
            providerId: RegisteredModelInterface.unresolvedProviderId,
            title: "Incomplete",
            path: "/chat",
            status: .verified
        )

        XCTAssertFalse(registration.hasResolvedProvider)
        XCTAssertEqual(registration.status, .draft)
    }

    func testRegistrationPresetUsesUnresolvedProviderForIncompleteModelDraft() {
        let model = ModelConfig(
            name: "Incomplete Model",
            provider: "Unresolved Provider",
            providerId: nil,
            baseURL: "https://example.com/v1",
            modelId: "incomplete-model",
            supportedModalities: [.text],
            endpointPath: "/chat/completions",
            apiKeyReference: ""
        )

        let registration = ModelRegistrationPresetRegistry.make(model: model, provider: nil, task: .chat)

        XCTAssertEqual(registration.providerId, RegisteredModelInterface.unresolvedProviderId)
        XCTAssertFalse(registration.hasResolvedProvider)
        XCTAssertEqual(registration.status, .draft)
    }

    func testParameterAndNodeControlDefinitionsDecodeMissingIds() throws {
        let parameterJSON = #"{"parameterPath":"temperature","title":"Temperature","valueType":"number"}"#
        let controlJSON = #"{"parameterPath":"temperature","title":"Temperature","kind":"slider"}"#

        let parameter = try JSONDecoder().decode(
            RegistrationParameterDefinition.self,
            from: XCTUnwrap(parameterJSON.data(using: .utf8))
        )
        let control = try JSONDecoder().decode(
            NodeControlDefinition.self,
            from: XCTUnwrap(controlJSON.data(using: .utf8))
        )

        XCTAssertFalse(parameter.id.uuidString.isEmpty)
        XCTAssertFalse(control.id.uuidString.isEmpty)
    }

    func testBuiltInTemplatesHaveDocsPollingAndValidNodeControls() {
        for template in ProviderInterfaceTemplateRegistry.all {
            XCTAssertFalse(template.id.isEmpty)
            XCTAssertFalse(template.docs.url.isEmpty, "\(template.id) must link official docs")
            XCTAssertFalse(template.docs.checkedAt.isEmpty, "\(template.id) must record a docs review date")
            for control in template.nodeControls {
                XCTAssertTrue(
                    template.parameters.contains { $0.parameterPath == control.parameterPath },
                    "\(template.id) exposes \(control.parameterPath) without a registered parameter"
                )
            }
            if template.mode == .async {
                XCTAssertNotNil(template.polling, "\(template.id) must define polling")
            }
        }
    }

    func testSeedanceAudioVideoTemplateUsesTaskEndpointAndDurationControl() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "volc.seedance.audiovideo"))

        XCTAssertEqual(template.path, "/contents/generations/tasks")
        XCTAssertEqual(template.mode, .async)
        XCTAssertTrue(template.nodeControls.contains { $0.parameterPath == "duration" })
    }

    func testDashScopeWanVideoTemplateInjectsAsyncHeader() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "aliyun.wan.video"))

        XCTAssertEqual(template.headers["X-DashScope-Async"], "enable")
        XCTAssertEqual(template.mode, .async)
        XCTAssertEqual(template.polling?.intervalSeconds, 15)
    }

    func testMiniMaxVideoTemplateUsesOfficialPollingCadenceAndFailureValue() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "minimax.video"))

        XCTAssertEqual(template.polling?.intervalSeconds, 10)
        XCTAssertTrue(template.polling?.failureValues.contains("Fail") == true)
    }

    func testAliyunQwenImageTemplateExtractsNestedImageURL() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "aliyun.qwen.image"))

        XCTAssertEqual(template.path, "/api/v1/services/aigc/multimodal-generation/generation")
        XCTAssertEqual(template.outputSlots.first?.jsonPath, "output.choices.*.message.content.*.image")
        XCTAssertEqual(template.docs.url, "https://help.aliyun.com/zh/model-studio/qwen-image-api")
    }

    func testMiniMaxChatTemplateUsesCurrentOpenAICompatibleRoute() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "minimax.chat"))

        XCTAssertEqual(template.path, "/chat/completions")
        XCTAssertEqual(template.docs.url, "https://platform.minimaxi.com/docs/api-reference/text-openai-api")
        XCTAssertEqual(template.docs.status, .verified)
    }

    func testMiniMaxM3TemplateRegistersNormalMultimodalChatCards() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "minimax.chat.multimodal"))

        XCTAssertEqual(template.path, "/chat/completions")
        XCTAssertEqual(template.family, .conversation)
        XCTAssertEqual(Set(template.inputCards.map(\.modality)), [.text, .image, .video])
        XCTAssertTrue(template.inputCards.allSatisfy { $0.parameterPath == "messages.0.content" })
        XCTAssertEqual(recommendedIds(providerKey: "minimax", modelId: "MiniMax-M3"), ["minimax.chat.multimodal"])
    }

    func testSpecialProviderTemplatesUseSpecialInterfaceFamily() throws {
        let templateIds = [
            "openai.images",
            "openai.videos",
            "openai.audio.speech",
            "openai.audio.transcriptions",
            "openai.embeddings",
            "volc.seedream.image",
            "volc.seedance.audiovideo",
            "volc.seed3d",
            "aliyun.qwen.image",
            "aliyun.wan.image",
            "aliyun.wan.video",
            "aliyun.tts",
            "aliyun.asr",
            "aliyun.embeddings",
            "aliyun.rerank",
            "minimax.image",
            "minimax.video",
            "minimax.tts",
            "minimax.music"
        ]

        for templateId in templateIds {
            let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: templateId))
            XCTAssertEqual(template.family, .special, "\(templateId) must be a special interface")
        }
    }

    func testBinaryAudioSpeechTemplateUsesSynchronousTransport() throws {
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "openai.audio.speech"))

        XCTAssertEqual(template.mode, .sync)
    }

    func testSystemTemplateReconstructionRestoresDefaultsAndTemplateIdentity() throws {
        let provider = ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "gpt-image-1")
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "openai.images"))
        var edited = RegisteredModelInterface(template: template, model: model, provider: provider, status: .unverified)

        edited.path = "/custom/images"
        edited.defaultRequestJSON = #"{"size":"custom"}"#
        let reset = RegisteredModelInterface(template: template, model: model, provider: provider, status: .draft)

        XCTAssertEqual(reset.templateId, template.id)
        XCTAssertEqual(reset.templateVersion, template.version)
        XCTAssertEqual(reset.path, template.path)
        XCTAssertEqual(reset.defaultRequestJSON, template.defaultRequestJSON)
        XCTAssertEqual(reset.nodeControls, template.nodeControls)
        XCTAssertEqual(reset.task, .textToImage)
        XCTAssertNotEqual(reset.path, edited.path)
        XCTAssertNotEqual(reset.defaultRequestJSON, edited.defaultRequestJSON)
    }

    func testSeedanceTemplateReconstructionKeepsAudioVideoTask() throws {
        let provider = ProviderConfig(name: "Volcengine Ark", baseURL: "https://ark.cn-beijing.volces.com/api/v3", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "doubao-seedance-2-0")
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "volc.seedance.audiovideo"))

        let registration = RegisteredModelInterface(template: template, model: model, provider: provider)

        XCTAssertEqual(registration.task, .multimodalToAudioVideo)
        XCTAssertEqual(registration.outputModalities, [.audioVideo])
    }

    func testSpecialTemplateDefaultsToBaseURLOverrideWhenSuggestionDiffers() throws {
        let provider = ProviderConfig(name: "Aliyun", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "qwen-image")
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "aliyun.qwen.image"))

        let registration = RegisteredModelInterface(template: template, model: model, provider: provider)

        XCTAssertFalse(registration.inheritsProviderBaseURL)
        XCTAssertEqual(registration.baseURLOverride, "https://dashscope.aliyuncs.com")
    }

    func testInputCardMatcherFillsPromptAndImageReferences() throws {
        let cards = [
            ModelRegistrationInputSlot(
                label: "Prompt",
                parameterPath: "input.prompt",
                source: .prompt,
                modality: .text,
                required: true
            ),
            ModelRegistrationInputSlot(
                label: "References",
                parameterPath: "input.reference_images",
                source: .attachment,
                modality: .image,
                required: true,
                acceptsMultiple: true
            )
        ]

        let values = try InputCardMatcher().match(cards: cards, assets: [
            InvocationAsset(type: .text, text: "cinematic portrait"),
            InvocationAsset(type: .image, url: "https://example.com/a.png"),
            InvocationAsset(type: .image, url: "https://example.com/b.png")
        ])

        XCTAssertEqual(values["input.prompt"] as? String, "cinematic portrait")
        XCTAssertEqual(values["input.reference_images"] as? [String], [
            "https://example.com/a.png",
            "https://example.com/b.png"
        ])
    }

    func testInputCardMatcherBuildsConversationContentBlocksWithoutOverwritingPrompt() throws {
        let path = "messages.0.content"
        let values = try InputCardMatcher().match(cards: [
            ModelRegistrationInputSlot(
                label: "Prompt",
                parameterPath: path,
                source: .prompt,
                modality: .text,
                required: true,
                collectsAsArray: true,
                valueTemplateJSON: #"{"type":"text","text":"$value"}"#
            ),
            ModelRegistrationInputSlot(
                label: "Image",
                parameterPath: path,
                source: .attachment,
                modality: .image,
                collectsAsArray: true,
                valueTemplateJSON: #"{"type":"image_url","image_url":{"url":"$value"}}"#
            )
        ], assets: [
            InvocationAsset(type: .text, text: "describe this image"),
            InvocationAsset(type: .image, url: "https://example.com/reference.png")
        ])

        let blocks = try XCTUnwrap(values[path] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["text"] as? String, "describe this image")
        XCTAssertEqual((blocks[1]["image_url"] as? [String: Any])?["url"] as? String, "https://example.com/reference.png")
    }

    func testInputCardMatcherEncodesLocalAttachmentAsBase64WhenSelected() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        let data = Data([0x00, 0x7f, 0xff])
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let values = try InputCardMatcher().match(cards: [
            ModelRegistrationInputSlot(
                label: "Image",
                parameterPath: "input.image",
                source: .attachment,
                modality: .image,
                required: true,
                valueFormat: .base64
            )
        ], assets: [
            InvocationAsset(type: .image, url: fileURL.absoluteString)
        ])

        XCTAssertEqual(values["input.image"] as? String, data.base64EncodedString())
    }

    func testInputCardMatcherAutomaticUsesDataURLForLocalAttachment() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        let data = Data([0x01, 0x02, 0x03])
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let values = try InputCardMatcher().match(cards: [
            ModelRegistrationInputSlot(
                label: "Image",
                parameterPath: "input.image",
                source: .attachment,
                modality: .image,
                required: true
            )
        ], assets: [
            InvocationAsset(type: .image, url: fileURL.absoluteString)
        ])

        XCTAssertEqual(values["input.image"] as? String, "data:image/png;base64,\(data.base64EncodedString())")
    }

    func testInputCardMatcherRejectsLocalAttachmentWhenRemoteURLIsRequired() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try Data([0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertThrowsError(
            try InputCardMatcher().match(cards: [
                ModelRegistrationInputSlot(
                    label: "Image",
                    parameterPath: "input.image_url",
                    source: .attachment,
                    modality: .image,
                    required: true,
                    valueFormat: .url
                )
            ], assets: [
                InvocationAsset(type: .image, url: fileURL.absoluteString)
            ])
        ) { error in
            XCTAssertEqual(error as? ModelRegistrationError, .unsupportedAttachmentFormat("Image", "url"))
        }
    }

    func testInputSlotShowsOnlyMediaAttachmentFormatsForImages() {
        let slot = ModelRegistrationInputSlot(
            label: "Image",
            parameterPath: "input.image",
            source: .attachment,
            modality: .image
        )

        XCTAssertEqual(slot.availableValueFormats, [.automatic, .url, .base64, .dataURL])
    }

    func testInputSlotShowsOnlyStructuredFormatsForJSONAttachments() {
        let slot = ModelRegistrationInputSlot(
            label: "Metadata",
            parameterPath: "input.metadata",
            source: .attachment,
            modality: .json
        )

        XCTAssertEqual(slot.availableValueFormats, [.automatic, .json, .text])
    }

    func testInputSlotShowsNoConversionChoiceForPrompt() {
        let slot = ModelRegistrationInputSlot(
            label: "Prompt",
            parameterPath: "input.prompt",
            source: .prompt,
            modality: .text
        )

        XCTAssertEqual(slot.availableValueFormats, [.automatic])
    }

    func testInputSlotKeepsAllFormatsForGenericFiles() {
        let slot = ModelRegistrationInputSlot(
            label: "File",
            parameterPath: "input.file",
            source: .attachment,
            modality: .file
        )

        XCTAssertEqual(slot.availableValueFormats, ModelRegistrationValueFormat.allCases)
    }

    func testInputSlotResetsUnsupportedFormatAfterModalityChanges() {
        var slot = ModelRegistrationInputSlot(
            label: "Image",
            parameterPath: "input.asset",
            source: .attachment,
            modality: .image,
            valueFormat: .base64
        )

        slot.modality = .json
        slot.normalizeValueFormat()

        XCTAssertEqual(slot.valueFormat, .automatic)
    }

    func testModelPromptDoesNotLeakLocalAttachmentPaths() {
        let prompt = NodePromptBuilder().prompt(
            text: "Describe the reference.",
            attachments: ["/Users/example/Desktop/reference.png"],
            nodeKind: .model
        )

        XCTAssertEqual(prompt, "Describe the reference.")
    }

    func testAgentPromptKeepsLocalAttachmentPaths() {
        let prompt = NodePromptBuilder().prompt(
            text: "Inspect the reference.",
            attachments: ["/Users/example/Desktop/reference.png"],
            nodeKind: .agent
        )

        XCTAssertTrue(prompt.contains("/Users/example/Desktop/reference.png"))
    }

    func testRequestFactoryReadsMultipartLocalFileLazily() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try Data("audio-body".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let request = CompiledInvocationRequest(
            url: URL(string: "https://example.com/upload")!,
            method: .post,
            headers: [:],
            encoding: .multipart,
            payload: [:],
            files: [
                InvocationAsset(
                    type: .audio,
                    url: fileURL.absoluteString,
                    metadata: ["field": "file", "fileName": "clip.mp3"]
                )
            ]
        )

        let body = String(data: try XCTUnwrap(request.urlRequest().httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("audio-body") == true)
        XCTAssertTrue(body?.contains("Content-Type: audio/mpeg") == true)
    }

    func testRequestCompilerAppliesNodeOverrideAfterTemplateDefault() throws {
        let payload = try RequestCompiler().compile(
            baseJSON: #"{"duration":5,"resolution":"720p"}"#,
            modelPath: "model",
            modelId: "seedance-2.0",
            matchedValues: ["input.prompt": "city lights"],
            nodeOverrides: ["duration": "10"]
        )

        XCTAssertEqual(payload["model"] as? String, "seedance-2.0")
        XCTAssertEqual(payload["duration"] as? Int, 10)
        XCTAssertEqual(payload["resolution"] as? String, "720p")
        XCTAssertEqual((payload["input"] as? [String: Any])?["prompt"] as? String, "city lights")
    }

    func testRequestCompilerKeepsConversationHistoryAndCurrentMultimodalBlocks() throws {
        let cards = [
            ModelRegistrationInputSlot(
                label: "Prompt",
                parameterPath: "messages.0.content",
                source: .prompt,
                modality: .text,
                required: true,
                collectsAsArray: true,
                valueTemplateJSON: #"{"type":"text","text":"$value"}"#
            ),
            ModelRegistrationInputSlot(
                label: "Image",
                parameterPath: "messages.0.content",
                source: .attachment,
                modality: .image,
                collectsAsArray: true,
                valueTemplateJSON: #"{"type":"image_url","image_url":{"url":"$value"}}"#
            )
        ]
        let matched = try InputCardMatcher().match(cards: cards, assets: [
            InvocationAsset(type: .text, text: "what changed?"),
            InvocationAsset(type: .image, url: "https://example.com/latest.png")
        ])
        let current = try RequestCompiler().compile(
            baseJSON: #"{"messages":[{"role":"user"}]}"#,
            modelPath: "model",
            modelId: "vision-model",
            matchedValues: matched,
            nodeOverrides: [:]
        )

        let payload = RequestCompiler().injectingConversationHistory(
            [
                ChatCompletionMessage(role: "user", content: "hello"),
                ChatCompletionMessage(role: "assistant", content: "hi"),
                ChatCompletionMessage(role: "user", content: "what changed?")
            ],
            into: current,
            inputCards: cards
        )

        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0]["content"] as? String, "hello")
        XCTAssertEqual(messages[1]["content"] as? String, "hi")
        XCTAssertEqual((messages[2]["content"] as? [[String: Any]])?.count, 2)
    }

    func testResponseNormalizerReadsWildcardAssetURLs() throws {
        let raw: [String: Any] = [
            "output": [
                "results": [
                    ["url": "https://example.com/a.png"],
                    ["url": "https://example.com/b.png"]
                ]
            ]
        ]
        let slots = [
            ModelRegistrationOutputSlot(
                label: "Images",
                kind: .asset,
                modality: .image,
                jsonPath: "output.results.*.url"
            )
        ]

        let response = try ResponseNormalizer().normalize(raw: raw, slots: slots)

        XCTAssertEqual(response.assetURLs, [
            "https://example.com/a.png",
            "https://example.com/b.png"
        ])
    }

    func testAsyncExecutorPollsUntilSuccess() async throws {
        let client = StubInvocationHTTPClient(responses: [
            .json(["task_id": "task-1"]),
            .json(["status": "running"]),
            .json(["status": "completed", "output": ["video_url": "https://example.com/video.mp4"]])
        ])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"
        polling.pollingPath = "/videos/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0
        let request = CompiledInvocationRequest(
            url: URL(string: "https://example.com/videos")!,
            method: .post,
            headers: [:],
            encoding: .json,
            payload: [:],
            files: []
        )

        let result = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
            .execute(request: request, polling: polling)

        XCTAssertEqual(result.json["status"] as? String, "completed")
    }

    func testAsyncExecutorRetriesTransientPollingTimeoutAndReportsTaskProgress() async throws {
        let client = FaultingInvocationHTTPClient(results: [
            .response(.json(["task_id": "task-1"])),
            .failure(URLError(.timedOut)),
            .response(.json(["status": "running"])),
            .response(.json(["status": "completed", "output": ["video_url": "https://example.com/video.mp4"]]))
        ])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"
        polling.pollingPath = "/videos/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0
        let progress = LockedInvocationProgressCollector()

        let result = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
            .execute(
                request: invocationRequest(),
                polling: polling,
                onProgress: progress.append
            )

        XCTAssertEqual(result.json["status"] as? String, "completed")
        XCTAssertEqual(progress.values.first, .submitted(taskId: "task-1"))
        XCTAssertTrue(progress.values.contains(.pollRetry(taskId: "task-1", attempt: 1, maximum: 3)))
        XCTAssertTrue(progress.values.contains(.status(taskId: "task-1", value: "running")))
        XCTAssertTrue(progress.values.contains(.status(taskId: "task-1", value: "completed")))
    }

    func testAsyncExecutorRejectsPollingResponseWithoutStatus() async throws {
        let client = StubInvocationHTTPClient(responses: [
            .json(["task_id": "task-1"]),
            .json(["unexpected": "payload"])
        ])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"
        polling.pollingPath = "/videos/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0

        do {
            _ = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
                .execute(request: invocationRequest(), polling: polling)
            XCTFail("Expected polling response parse failure")
        } catch {
            XCTAssertEqual(error as? ModelRegistrationError, .responseParseFailed("status"))
        }
    }

    func testAsyncExecutorPreservesTaskIdWhenPollingTransportKeepsFailing() async throws {
        let client = FaultingInvocationHTTPClient(results: [
            .response(.json(["task_id": "task-1"])),
            .failure(URLError(.timedOut)),
            .failure(URLError(.networkConnectionLost)),
            .failure(URLError(.notConnectedToInternet))
        ])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"
        polling.pollingPath = "/videos/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0

        do {
            _ = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
                .execute(request: invocationRequest(), polling: polling)
            XCTFail("Expected recoverable polling request failure")
        } catch {
            XCTAssertEqual(
                error as? ModelRegistrationError,
                .asyncPollingRequestFailed(
                    taskId: "task-1",
                    details: URLError(.notConnectedToInternet).localizedDescription
                )
            )
        }
    }

    func testAsyncExecutorExplainsSubmissionTransportFailure() async throws {
        let timeout = URLError(.timedOut)
        let client = FaultingInvocationHTTPClient(results: [.failure(timeout)])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"

        do {
            _ = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
                .execute(request: invocationRequest(), polling: polling)
            XCTFail("Expected async submission failure")
        } catch {
            XCTAssertEqual(
                error as? ModelRegistrationError,
                .asyncSubmitFailed(timeout.localizedDescription)
            )
        }
    }

    func testAsyncExecutorTimeoutPreservesTaskId() async throws {
        let client = StubInvocationHTTPClient(responses: [
            .json(["task_id": "task-1"]),
            .json(["status": "running"])
        ])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"
        polling.pollingPath = "/videos/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0
        polling.maxAttempts = 1

        do {
            _ = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
                .execute(request: invocationRequest(), polling: polling)
            XCTFail("Expected async task timeout")
        } catch {
            XCTAssertEqual(error as? ModelRegistrationError, .asyncTaskTimeout(taskId: "task-1"))
        }
    }

    func testInvocationRequestFactoryCarriesConfiguredTimeout() throws {
        var request = invocationRequest()
        request.timeoutInterval = 12

        XCTAssertEqual(try request.urlRequest().timeoutInterval, 12)
    }

    func testAsyncExecutorUsesShorterTimeoutForPollingRequests() async throws {
        let client = RecordingInvocationHTTPClient(responses: [
            .json(["task_id": "task-1"]),
            .json(["status": "completed"])
        ])
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "task_id"
        polling.pollingPath = "/videos/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0

        _ = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
            .execute(request: invocationRequest(), polling: polling)

        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].timeoutInterval, 20)
    }

    func testAsyncExecutorUsesExplicitPollingBaseURLWithoutDroppingAPIPrefix() async throws {
        let client = RecordingInvocationHTTPClient(responses: [
            .json(["id": "cgt-demo"]),
            .json(["status": "succeeded"])
        ])
        let request = CompiledInvocationRequest(
            url: URL(string: "https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks")!,
            method: .post,
            headers: [:],
            encoding: .json,
            payload: [:],
            files: [],
            pollingBaseURL: URL(string: "https://ark.cn-beijing.volces.com/api/v3")!
        )
        var polling = ModelRegistrationPolling()
        polling.taskIdPath = "id"
        polling.pollingPath = "/contents/generations/tasks/{task_id}"
        polling.statusPath = "status"
        polling.intervalSeconds = 0

        _ = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
            .execute(request: request, polling: polling)

        let requests = await client.recordedRequests()
        XCTAssertEqual(
            requests[1].url?.absoluteString,
            "https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks/cgt-demo"
        )
    }

    func testInvocationProgressMessagesExplainRecoverableAsyncTaskState() {
        XCTAssertEqual(
            InvocationProgress.submitted(taskId: "task-1").message,
            "异步任务已创建：task-1"
        )
        XCTAssertEqual(
            InvocationProgress.status(taskId: "task-1", value: "running").message,
            "异步任务状态：running"
        )
        XCTAssertEqual(
            InvocationProgress.pollRetry(taskId: "task-1", attempt: 2, maximum: 3).message,
            "查询任务状态时网络不稳定，正在重试（2/3）。任务 ID：task-1"
        )
    }

    func testExecutorAccumulatesSSETextEvents() async throws {
        let data = """
        data: {"choices":[{"delta":{"content":"hello "}}]}

        data: {"choices":[{"delta":{"content":"world"}}]}

        data: [DONE]

        """.data(using: .utf8)!
        let client = StubInvocationHTTPClient(responses: [
            InvocationHTTPResponse(statusCode: 200, headers: ["Content-Type": "text/event-stream"], data: data)
        ])
        let request = CompiledInvocationRequest(
            url: URL(string: "https://example.com/chat")!,
            method: .post,
            headers: [:],
            encoding: .json,
            payload: [:],
            files: []
        )

        let result = try await InvocationExecutor(client: client, sleeper: ImmediateSleeper())
            .execute(request: request, polling: nil)

        XCTAssertEqual(result.json["output_text"] as? String, "hello world")
    }

    func testResponseNormalizerCapturesBinaryAsset() throws {
        let data = Data([0x01, 0x02, 0x03])
        let raw = InvocationRawResponse(json: [:], binary: data, contentType: "audio/mpeg")
        let slots = [
            ModelRegistrationOutputSlot(label: "Audio", kind: .asset, modality: .audio, jsonPath: "$binary")
        ]

        let response = try ResponseNormalizer().normalize(raw: raw, slots: slots)

        XCTAssertEqual(response.binaryAssets, [data])
        XCTAssertEqual(response.assets.map(\.modality), [.audio])
    }

    func testRequestFactoryEncodesMultipartFileData() throws {
        let request = CompiledInvocationRequest(
            url: URL(string: "https://example.com/transcriptions")!,
            method: .post,
            headers: [:],
            encoding: .multipart,
            payload: ["model": "whisper-1"],
            files: [
                InvocationAsset(
                    type: .audio,
                    mimeType: "audio/mpeg",
                    data: Data("audio-body".utf8),
                    metadata: ["field": "file", "fileName": "clip.mp3"]
                )
            ]
        )

        let urlRequest = try request.urlRequest()
        let body = String(data: try XCTUnwrap(urlRequest.httpBody), encoding: .utf8)

        XCTAssertTrue(try XCTUnwrap(urlRequest.value(forHTTPHeaderField: "Content-Type")).hasPrefix("multipart/form-data; boundary="))
        XCTAssertTrue(try XCTUnwrap(body).contains(#"name="file"; filename="clip.mp3""#))
        XCTAssertTrue(try XCTUnwrap(body).contains("audio-body"))
    }

    func testWorkspaceImporterUsesGeneratedAssetFolderOutsideWorkflowMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workspace = WorkspaceLocation(
            name: "Demo Workspace",
            path: root.path,
            metadataPath: root.appending(path: ".workflow-Demo Workspace", directoryHint: .isDirectory).path
        )

        let destination = WorkspaceAssetImporter().destinationURL(fileName: "video.mp4", workspace: workspace)

        XCTAssertTrue(destination.path.contains("/.workflow-assets/Demo-Workspace/generated/"))
        XCTAssertFalse(destination.path.contains(".workflow-generated-assets"))
        XCTAssertFalse(destination.path.contains(".workflow-Demo Workspace"))
    }

    func testWorkspaceImporterWritesBinaryGeneratedAsset() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workspace = WorkspaceLocation(name: "Demo", path: root.path, metadataPath: nil)

        let asset = try WorkspaceAssetImporter().write(
            data: Data("audio".utf8),
            suggestedFileName: "speech.mp3",
            workspace: workspace
        )

        XCTAssertEqual(asset.modality, .audio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        XCTAssertEqual(try Data(contentsOf: URL(filePath: asset.path)), Data("audio".utf8))
    }

    @MainActor
    func testWorkspaceDiscoveryIgnoresGeneratedAssetFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: ".workflow-Demo"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".workflow-assets"), withIntermediateDirectories: true)

        let workspaces = WorkspaceService().discoverWorkspaces(in: root)

        XCTAssertEqual(workspaces.map(\.name), ["Demo"])
    }

    func testMigrationCreatesDraftRegistrationsAndIsIdempotent() {
        var configuration = AppConfiguration()
        configuration.modelRegistrations = []

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))
        let firstIds = configuration.modelRegistrations.map(\.id)

        XCTAssertTrue(configuration.modelRegistrations.allSatisfy { $0.status == .draft })
        XCTAssertTrue(configuration.modelRegistrations.allSatisfy { $0.lastTestSummary == "Migrated from legacy model settings" })
        XCTAssertFalse(ProviderMigrationService().migrate(&configuration))
        XCTAssertEqual(configuration.modelRegistrations.map(\.id), firstIds)
    }

    func testMigrationRefreshesUnmodifiedAgnesLegacyDraftsToCurrentTemplates() throws {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let model = ModelConfig(
            name: "agnes-image-2.1-flash",
            provider: provider.name,
            providerId: provider.id,
            baseURL: provider.baseURL,
            modelId: "agnes-image-2.1-flash",
            supportedModalities: [.text, .image],
            inputModalities: [.text, .image],
            outputModalities: [.image],
            endpointKind: .imageGeneration,
            endpointPath: "/images/generations",
            requestParametersJSON: #"{"size":"1024x1024"}"#,
            apiKeyReference: ""
        )
        var legacy = ModelRegistrationPresetRegistry.draft(for: model, provider: provider)
        legacy.templateId = "migrated.imageGeneration"
        legacy.templateVersion = nil
        legacy.title = "Text To Image"
        legacy.lastTestSummary = "Migrated from legacy model settings"
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [legacy]

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))

        let migrated = try XCTUnwrap(configuration.modelRegistrations.first)
        XCTAssertEqual(migrated.id, legacy.id)
        XCTAssertEqual(migrated.templateId, "agnes.image.21")
        XCTAssertEqual(migrated.templateVersion, ProviderInterfaceTemplateRegistry.template(id: "agnes.image.21")?.version)
        XCTAssertEqual(migrated.title, "Agnes AI Image 2.1 Flash")
        XCTAssertEqual(migrated.status, .unverified)
        XCTAssertEqual(migrated.lastTestSummary, "Migrated from legacy model settings")
        XCTAssertFalse(migrated.lastModifiedByUser)
        XCTAssertEqual(migrated.nodeControls.map(\.parameterPath), ["size", "extra_body.response_format"])
    }

    func testMigrationPromotesCurrentAgnesSystemDraftsToUnverified() throws {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "agnes-video-v2.0")
        var registration = try XCTUnwrap(
            ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: model, provider: provider)?.first
        )
        registration.status = .draft
        var configuration = AppConfiguration()
        configuration.providers = ProviderConfig.defaults.map { $0.name == provider.name ? provider : $0 }
        configuration.models = [model]
        configuration.modelRegistrations = [registration]

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))

        let migrated = try XCTUnwrap(configuration.modelRegistrations.first)
        XCTAssertEqual(migrated.templateId, "agnes.video")
        XCTAssertEqual(migrated.status, .unverified)
        XCTAssertEqual(migrated.lastTestSummary, "Ready from Agnes AI model template")
    }

    func testMigrationAddsMissingAgnesDefaultModelIds() throws {
        var agnes = try XCTUnwrap(ProviderConfig.defaults.first { $0.name == "Agnes AI" })
        agnes.defaultModelIds = ["agnes-2.0-flash", "agnes-image-2.1-flash", "agnes-video-v2.0"]
        var configuration = AppConfiguration()
        configuration.providers = ProviderConfig.defaults.map { $0.name == agnes.name ? agnes : $0 }
        configuration.models = []
        configuration.modelRegistrations = []

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))

        let migrated = try XCTUnwrap(configuration.providers.first { $0.name == "Agnes AI" })
        XCTAssertEqual(migrated.defaultModelIds, [
            "agnes-2.0-flash",
            "agnes-image-2.1-flash",
            "agnes-image-2.0-flash",
            "agnes-video-v2.0"
        ])
    }

    func testMigrationDoesNotRefreshUserModifiedAgnesDrafts() {
        let provider = ProviderConfig.defaults.first { $0.name == "Agnes AI" }!
        let model = makeModel(provider: provider, modelId: "agnes-image-2.1-flash")
        var legacy = ModelRegistrationPresetRegistry.draft(for: model, provider: provider)
        legacy.templateId = "migrated.imageGeneration"
        legacy.title = "My Agnes Image"
        legacy.lastModifiedByUser = true
        var configuration = AppConfiguration()
        configuration.providers = ProviderConfig.defaults.map { $0.name == provider.name ? provider : $0 }
        configuration.models = [model]
        configuration.modelRegistrations = [legacy]

        XCTAssertFalse(ProviderMigrationService().migrate(&configuration))
        XCTAssertEqual(configuration.modelRegistrations.first?.templateId, "migrated.imageGeneration")
        XCTAssertEqual(configuration.modelRegistrations.first?.title, "My Agnes Image")
    }

    func testDefaultProvidersOnlyContainSupportedCatalog() {
        XCTAssertEqual(
            ProviderConfig.defaults.map(\.name),
            ["Agnes AI", "OpenAI", "MiniMax Coding Plan", "火山引擎", "阿里云百炼", "DeepSeek"]
        )
    }

    func testMigrationRemovesRetiredProvidersAndOwnedModels() {
        let retired = [
            ProviderConfig(name: "OpenCode Zen", baseURL: "https://retired.example/zen", apiKey: "key"),
            ProviderConfig(name: "OpenCode Go", baseURL: "https://retired.example/go", apiKey: "key"),
            ProviderConfig(name: "Kimi", baseURL: "https://retired.example/kimi", apiKey: "key"),
            ProviderConfig(name: "Moonshot", baseURL: "https://retired.example/moonshot", apiKey: "key")
        ]
        let retained = ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "key")
        let retiredModel = makeModel(provider: retired[0], modelId: "retired-model")
        let retainedModel = makeModel(provider: retained, modelId: "gpt-5")
        var retiredRegistration = ModelRegistrationPresetRegistry.make(model: retiredModel, provider: retired[0], task: .chat)
        retiredRegistration.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = retired + [retained]
        configuration.models = [retiredModel, retainedModel]
        configuration.modelRegistrations = [retiredRegistration]

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))

        XCTAssertFalse(configuration.providers.contains { ["OpenCode Zen", "OpenCode Go", "Kimi", "Moonshot"].contains($0.name) })
        XCTAssertFalse(configuration.models.contains { $0.id == retiredModel.id })
        XCTAssertFalse(configuration.modelRegistrations.contains { $0.modelId == retiredModel.id })
        XCTAssertTrue(configuration.models.contains { $0.id == retainedModel.id })
    }

    func testSystemInterfaceTemplatesExcludeRetiredProviders() {
        let retiredKeys = Set(["opencode", "kimi"])

        XCTAssertTrue(
            ProviderInterfaceTemplateRegistry.all.allSatisfy { !retiredKeys.contains($0.providerKey) }
        )
    }

    func testRouterDoesNotSelectDraftRegistration() throws {
        let provider = ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "gpt-5")
        var draft = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "openai.chat")),
            model: model,
            provider: provider
        )
        draft.status = .draft
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [draft]

        XCTAssertThrowsError(
            try ModelRegistrationRouter().resolve(
                modelId: model.id,
                desiredOutputModalities: [.text],
                inputs: [InvocationAsset(type: .text, text: "hello")],
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(error as? ModelRegistrationError, .registrationNotFound)
        }
    }

    func testRouterResolvesTheRegisteredInterfaceSelectedByNode() throws {
        let provider = ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "gpt-5")
        var responses = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "openai.responses")),
            model: model,
            provider: provider
        )
        responses.status = .unverified
        var chat = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "openai.chat")),
            model: model,
            provider: provider
        )
        chat.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [responses, chat]

        let context = try ModelRegistrationRouter().resolve(
            interfaceId: chat.id,
            configuration: configuration
        )

        XCTAssertEqual(context.registration.id, chat.id)
        XCTAssertEqual(context.registration.path, "/chat/completions")
    }

    func testRouterCompilesSelectedInterfaceWithNodeOverrides() throws {
        let provider = ProviderConfig(name: "Volcengine Ark", baseURL: "https://ark.cn-beijing.volces.com/api/v3", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "doubao-seedance-2-0")
        var registration = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "volc.seedance.audiovideo")),
            model: model,
            provider: provider
        )
        registration.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [registration]

        let payload = try ModelRegistrationRouter().compiledPayload(
            interfaceId: registration.id,
            inputs: [InvocationAsset(type: .text, text: "night city")],
            nodeOverrides: ["duration": "10"],
            configuration: configuration
        )

        XCTAssertEqual(payload["model"] as? String, model.modelId)
        XCTAssertEqual(payload["duration"] as? Int, 10)
        let content = try XCTUnwrap(payload["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "night city")
        XCTAssertNil(payload["aspect_ratio"])
        XCTAssertEqual(payload["ratio"] as? String, "adaptive")
    }

    func testMigrationNormalizesLegacyTaskContentCardsWithoutModelSpecialCases() throws {
        let provider = ProviderConfig(name: "Volcengine Ark", baseURL: "https://ark.cn-beijing.volces.com/api/v3", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "custom-task-model")
        var registration = RegisteredModelInterface(
            modelId: model.id,
            providerId: provider.id,
            title: "Legacy task interface",
            path: "/contents/generations/tasks",
            defaultRequestJSON: #"{"aspect_ratio":"16:9"}"#,
            inputCards: [
                ModelRegistrationInputSlot(label: "Prompt", parameterPath: "content.0.text", source: .prompt, modality: .text),
                ModelRegistrationInputSlot(label: "Image", parameterPath: "content.0.image_url", source: .attachment, modality: .image)
            ],
            nodeControls: [
                NodeControlDefinition(parameterPath: "aspect_ratio", title: "Aspect Ratio", kind: .picker, defaultValue: "16:9")
            ]
        )
        registration.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [registration]

        XCTAssertTrue(ProviderMigrationService().migrate(&configuration))

        let migrated = try XCTUnwrap(configuration.modelRegistrations.first { $0.id == registration.id })
        XCTAssertTrue(migrated.inputCards.allSatisfy { $0.parameterPath == "content" })
        XCTAssertTrue(migrated.inputCards.allSatisfy(\.collectsAsArray))
        XCTAssertEqual(migrated.inputCards[0].valueTemplateJSON, #"{"type":"text","text":"$value"}"#)
        XCTAssertEqual(migrated.inputCards[1].valueTemplateJSON, #"{"type":"image_url","image_url":{"url":"$value"}}"#)
        XCTAssertFalse(migrated.defaultRequestJSON.contains("aspect_ratio"))
        XCTAssertTrue(migrated.defaultRequestJSON.contains(#""ratio":"16:9""#))
        XCTAssertEqual(migrated.nodeControls.first?.parameterPath, "ratio")
    }

    func testTaskContentBlocksKeepEachMultimodalAttachmentAsItsOwnTypedItem() throws {
        let provider = ProviderConfig(name: "Volcengine Ark", baseURL: "https://ark.cn-beijing.volces.com/api/v3", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "custom-task-model")
        var registration = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "volc.seedance.audiovideo")),
            model: model,
            provider: provider
        )
        registration.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [registration]

        let payload = try ModelRegistrationRouter().compiledPayload(
            interfaceId: registration.id,
            inputs: [
                InvocationAsset(type: .text, text: "Reference edit"),
                InvocationAsset(type: .image, url: "https://example.com/reference.png"),
                InvocationAsset(type: .audio, url: "https://example.com/music.mp3"),
                InvocationAsset(type: .video, url: "https://example.com/source.mp4")
            ],
            configuration: configuration
        )

        let content = try XCTUnwrap(payload["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["type"] as? String }, ["text", "image_url", "audio_url", "video_url"])
    }

    func testInputWrapperTemplateRecommendationsStayCompactAndPreferVolcengineTypedVideo() throws {
        let slot = ModelRegistrationInputSlot(
            label: "Video",
            parameterPath: "content",
            source: .attachment,
            modality: .video
        )

        let templates = InputWrapperTemplateRegistry.recommended(
            for: slot,
            interfaceTemplateId: "volc.seedance.audiovideo"
        )

        XCTAssertLessThanOrEqual(templates.count, 4)
        XCTAssertEqual(templates.first?.id, "volc.task.video_url")
        XCTAssertEqual(templates.first?.wrapperJSON, #"{"type":"video_url","video_url":{"url":"$value"}}"#)
    }

    func testApplyingInputWrapperTemplateOnlyChangesAdvancedMappingFields() throws {
        var slot = ModelRegistrationInputSlot(
            label: "Image",
            parameterPath: "custom.images",
            source: .attachment,
            modality: .image,
            required: true,
            valueFormat: .base64
        )
        let template = try XCTUnwrap(InputWrapperTemplateRegistry.template(id: "openai.responses.input_image"))

        template.apply(to: &slot)

        XCTAssertEqual(slot.parameterPath, "custom.images")
        XCTAssertEqual(slot.source, .attachment)
        XCTAssertEqual(slot.modality, .image)
        XCTAssertTrue(slot.required)
        XCTAssertEqual(slot.valueFormat, .base64)
        XCTAssertTrue(slot.collectsAsArray)
        XCTAssertEqual(slot.valueTemplateJSON, #"{"type":"input_image","image_url":"$value"}"#)
    }

    func testInputWrapperTemplatesKeepProtocolSpecificFieldShapes() throws {
        XCTAssertEqual(
            try XCTUnwrap(InputWrapperTemplateRegistry.template(id: "openai.responses.input_image")).wrapperJSON,
            #"{"type":"input_image","image_url":"$value"}"#
        )
        XCTAssertEqual(
            try XCTUnwrap(InputWrapperTemplateRegistry.template(id: "aliyun.native.audio")).wrapperJSON,
            #"{"audio":"$value"}"#
        )
    }

    func testAdditionalInputWrapperTemplatesStayWithinTheCurrentProtocol() {
        let slot = ModelRegistrationInputSlot(
            label: "Video",
            parameterPath: "content",
            source: .attachment,
            modality: .video
        )

        let templates = InputWrapperTemplateRegistry.additional(
            for: slot,
            interfaceTemplateId: "volc.seedance.audiovideo"
        )

        XCTAssertTrue(templates.allSatisfy { $0.protocolFamily == .volcengineTask || $0.protocolFamily == .direct })
    }

    func testProviderTemplateRecommendationsRouteKnownModelFamilies() {
        XCTAssertEqual(recommendedIds(providerKey: "agnes", modelId: "agnes-2.0-flash"), ["agnes.chat", "agnes.chat.streaming"])
        XCTAssertEqual(recommendedIds(providerKey: "agnes", modelId: "agnes-image-2.1-flash"), ["agnes.image.21"])
        XCTAssertEqual(recommendedIds(providerKey: "agnes", modelId: "agnes-image-2.0-flash"), ["agnes.image.20"])
        XCTAssertEqual(recommendedIds(providerKey: "agnes", modelId: "agnes-video-v2.0"), ["agnes.video"])

        XCTAssertEqual(recommendedIds(providerKey: "openai", modelId: "gpt-image-1"), ["openai.images"])
        XCTAssertEqual(recommendedIds(providerKey: "openai", modelId: "sora-2"), ["openai.videos"])
        XCTAssertEqual(recommendedIds(providerKey: "openai", modelId: "whisper-1"), ["openai.audio.transcriptions"])
        XCTAssertEqual(recommendedIds(providerKey: "openai", modelId: "text-embedding-3-large"), ["openai.embeddings"])
        XCTAssertEqual(recommendedIds(providerKey: "openai", modelId: "gpt-5"), ["openai.responses", "openai.chat"])

        XCTAssertEqual(recommendedIds(providerKey: "volc", modelId: "doubao-seedream-4-0"), ["volc.seedream.image"])
        XCTAssertEqual(recommendedIds(providerKey: "volc", modelId: "doubao-seedance-2-0"), ["volc.seedance.audiovideo"])
        XCTAssertEqual(recommendedIds(providerKey: "volc", modelId: "seed3d-1-0"), ["volc.seed3d"])
        XCTAssertEqual(recommendedIds(providerKey: "volc", modelId: "doubao-seed-2-0-pro"), ["volc.chat"])

        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "qwen-image-plus"), ["aliyun.qwen.image"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "wanx2.1-t2v-turbo"), ["aliyun.wan.video"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "qwen-omni-turbo"), ["aliyun.qwen.omni"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "cosyvoice-v2"), ["aliyun.tts"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "paraformer-v2"), ["aliyun.asr"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "text-embedding-v4"), ["aliyun.embeddings"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "gte-rerank-v2"), ["aliyun.rerank"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "qwen-vl-max"), ["aliyun.multimodal"])
        XCTAssertEqual(recommendedIds(providerKey: "aliyun", modelId: "qwen-plus"), ["aliyun.compatible.chat"])

        XCTAssertEqual(recommendedIds(providerKey: "deepseek", modelId: "deepseek-reasoner"), ["deepseek.reasoning"])
        XCTAssertEqual(recommendedIds(providerKey: "deepseek", modelId: "deepseek-chat"), ["deepseek.chat"])
        XCTAssertEqual(recommendedIds(providerKey: "minimax", modelId: "speech-02-hd"), ["minimax.tts"])
        XCTAssertEqual(recommendedIds(providerKey: "minimax", modelId: "hailuo-02"), ["minimax.video"])
        XCTAssertEqual(recommendedIds(providerKey: "minimax", modelId: "music-2.0"), ["minimax.music"])
        XCTAssertEqual(recommendedIds(providerKey: "custom", modelId: "vendor-model"), ["custom.chat"])
    }

    func testAgnesChatTemplateCompilesToolThinkingAndStreamingParameters() throws {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "agnes-2.0-flash")
        var registration = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "agnes.chat")),
            model: model,
            provider: provider
        )
        registration.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [registration]

        let payload = try ModelRegistrationRouter().compiledPayload(
            interfaceId: registration.id,
            inputs: [InvocationAsset(type: .text, text: "Build a launch checklist.")],
            nodeOverrides: [
                "stream": "true",
                "tools": #"[{"type":"function","function":{"name":"search_docs"}}]"#,
                "tool_choice": #""auto""#,
                "chat_template_kwargs.enable_thinking": "true",
                "thinking.type": "enabled",
                "thinking.budget_tokens": "2048"
            ],
            configuration: configuration
        )

        XCTAssertEqual(payload["model"] as? String, "agnes-2.0-flash")
        XCTAssertEqual((payload["messages"] as? [[String: Any]])?.first?["content"] as? String, "Build a launch checklist.")
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertEqual((payload["tools"] as? [[String: Any]])?.first?["type"] as? String, "function")
        XCTAssertEqual(payload["tool_choice"] as? String, "auto")
        XCTAssertEqual((payload["chat_template_kwargs"] as? [String: Any])?["enable_thinking"] as? Bool, true)
        XCTAssertEqual((payload["thinking"] as? [String: Any])?["type"] as? String, "enabled")
        XCTAssertEqual((payload["thinking"] as? [String: Any])?["budget_tokens"] as? Int, 2048)
    }

    func testAgnesModelSpecificRegistrationFactoryUsesModelIdTemplates() throws {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let chat = makeModel(provider: provider, modelId: "agnes-2.0-flash")
        let image21 = makeModel(provider: provider, modelId: "agnes-image-2.1-flash")
        let image20 = makeModel(provider: provider, modelId: "agnes-image-2.0-flash")
        let video = makeModel(provider: provider, modelId: "agnes-video-v2.0")

        XCTAssertEqual(
            ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: chat, provider: provider)?.map(\.templateId),
            ["agnes.chat", "agnes.chat.streaming"]
        )
        XCTAssertEqual(
            ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: image21, provider: provider)?.map(\.templateId),
            ["agnes.image.21"]
        )
        XCTAssertEqual(
            ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: image20, provider: provider)?.map(\.templateId),
            ["agnes.image.20"]
        )
        XCTAssertEqual(
            ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: video, provider: provider)?.map(\.templateId),
            ["agnes.video"]
        )
        XCTAssertEqual(
            ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: chat, provider: provider)?.first?.status,
            .unverified
        )
    }

    func testAgnesImageTemplatesCompileVersionSpecificParameters() throws {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let image21 = makeModel(provider: provider, modelId: "agnes-image-2.1-flash")
        var image21Registration = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "agnes.image.21")),
            model: image21,
            provider: provider
        )
        image21Registration.status = .unverified
        var configuration21 = AppConfiguration()
        configuration21.providers = [provider]
        configuration21.models = [image21]
        configuration21.modelRegistrations = [image21Registration]

        let image21Payload = try ModelRegistrationRouter().compiledPayload(
            interfaceId: image21Registration.id,
            inputs: [
                InvocationAsset(type: .text, text: "A crisp product render."),
                InvocationAsset(type: .image, url: "https://example.com/reference.png")
            ],
            nodeOverrides: ["size": "768x1024"],
            configuration: configuration21
        )

        XCTAssertEqual(image21Payload["model"] as? String, "agnes-image-2.1-flash")
        XCTAssertEqual(image21Payload["prompt"] as? String, "A crisp product render.")
        XCTAssertEqual(image21Payload["size"] as? String, "768x1024")
        let image21Extra = try XCTUnwrap(image21Payload["extra_body"] as? [String: Any])
        XCTAssertEqual(image21Extra["response_format"] as? String, "url")
        XCTAssertEqual(image21Extra["image"] as? [String], ["https://example.com/reference.png"])
        XCTAssertNil(image21Payload["seed"])
        XCTAssertNil(image21Payload["tags"])

        let image20 = makeModel(provider: provider, modelId: "agnes-image-2.0-flash")
        var image20Registration = RegisteredModelInterface(
            template: try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "agnes.image.20")),
            model: image20,
            provider: provider
        )
        image20Registration.status = .unverified
        var configuration20 = AppConfiguration()
        configuration20.providers = [provider]
        configuration20.models = [image20]
        configuration20.modelRegistrations = [image20Registration]

        let image20Payload = try ModelRegistrationRouter().compiledPayload(
            interfaceId: image20Registration.id,
            inputs: [
                InvocationAsset(type: .text, text: "Combine both references."),
                InvocationAsset(type: .image, url: "https://example.com/a.png"),
                InvocationAsset(type: .image, url: "https://example.com/b.png")
            ],
            nodeOverrides: [
                "seed": "1234",
                "tags": #"["img2img","compose"]"#
            ],
            configuration: configuration20
        )

        XCTAssertEqual(image20Payload["model"] as? String, "agnes-image-2.0-flash")
        XCTAssertEqual(image20Payload["tags"] as? [String], ["img2img", "compose"])
        XCTAssertEqual(image20Payload["seed"] as? Int, 1234)
        let image20Extra = try XCTUnwrap(image20Payload["extra_body"] as? [String: Any])
        XCTAssertEqual(image20Extra["image"] as? [String], ["https://example.com/a.png", "https://example.com/b.png"])
    }

    func testAgnesVideoTemplateCompilesAsyncKeyframeParameters() throws {
        let provider = ProviderConfig(name: "Agnes AI", baseURL: "https://apihub.agnes-ai.com/v1", apiKey: "key")
        let model = makeModel(provider: provider, modelId: "agnes-video-v2.0")
        let template = try XCTUnwrap(ProviderInterfaceTemplateRegistry.template(id: "agnes.video"))
        var registration = RegisteredModelInterface(template: template, model: model, provider: provider)
        registration.status = .unverified
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        configuration.models = [model]
        configuration.modelRegistrations = [registration]

        let payload = try ModelRegistrationRouter().compiledPayload(
            interfaceId: registration.id,
            inputs: [
                InvocationAsset(type: .text, text: "Camera push through a neon hallway."),
                InvocationAsset(type: .image, url: "https://example.com/cover.png"),
                InvocationAsset(type: .reference, url: "https://example.com/start.png"),
                InvocationAsset(type: .reference, url: "https://example.com/end.png")
            ],
            nodeOverrides: [
                "mode": "keyframes",
                "extra_body.mode": "keyframes",
                "num_frames": "241",
                "frame_rate": "30",
                "negative_prompt": "low quality"
            ],
            configuration: configuration
        )

        XCTAssertEqual(payload["model"] as? String, "agnes-video-v2.0")
        XCTAssertEqual(payload["prompt"] as? String, "Camera push through a neon hallway.")
        XCTAssertEqual(payload["image"] as? String, "https://example.com/cover.png")
        XCTAssertEqual(payload["mode"] as? String, "keyframes")
        XCTAssertEqual(payload["num_frames"] as? Int, 241)
        XCTAssertEqual(payload["frame_rate"] as? Int, 30)
        XCTAssertEqual(payload["negative_prompt"] as? String, "low quality")
        XCTAssertEqual((payload["extra_body"] as? [String: Any])?["mode"] as? String, "keyframes")
        XCTAssertEqual((payload["extra_body"] as? [String: Any])?["image"] as? [String], [
            "https://example.com/start.png",
            "https://example.com/end.png"
        ])
        XCTAssertEqual(registration.mode, .async)
        XCTAssertEqual(registration.polling?.pollingPath, "/videos/{task_id}")
        XCTAssertTrue(registration.outputSlots.contains { $0.jsonPath == "remixed_from_video_id" })
    }

    private func recommendedIds(providerKey: String, modelId: String) -> [String] {
        ProviderInterfaceTemplateRegistry.recommended(providerKey: providerKey, modelId: modelId).map(\.id)
    }

    private func makeModel(provider: ProviderConfig, modelId: String) -> ModelConfig {
        ModelConfig(
            name: modelId,
            provider: provider.name,
            providerId: provider.id,
            baseURL: provider.baseURL,
            modelId: modelId,
            supportedModalities: [.text],
            apiKeyReference: ""
        )
    }

    private func makeNode(
        registeredModelInterfaceId: UUID? = nil,
        modelParameterOverrides: [String: String] = [:]
    ) -> WorkflowNode {
        WorkflowNode(
            title: "Registered Model",
            description: "",
            kind: .model,
            modelId: nil,
            agentExecutable: nil,
            position: CanvasPoint(x: 0, y: 0),
            inputModalities: [.text],
            outputModalities: [.text],
            chat: [],
            draftMessage: "",
            registeredModelInterfaceId: registeredModelInterfaceId,
            modelParameterOverrides: modelParameterOverrides
        )
    }

    private func invocationRequest() -> CompiledInvocationRequest {
        CompiledInvocationRequest(
            url: URL(string: "https://example.com/videos")!,
            method: .post,
            headers: [:],
            encoding: .json,
            payload: [:],
            files: []
        )
    }
}

actor StubInvocationHTTPClient: InvocationHTTPClient {
    private var responses: [InvocationHTTPResponse]

    init(responses: [InvocationHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> InvocationHTTPResponse {
        responses.removeFirst()
    }
}

struct ImmediateSleeper: InvocationSleeper {
    func sleep(seconds: Int) async throws {}
}

enum FaultingInvocationHTTPResult {
    case response(InvocationHTTPResponse)
    case failure(URLError)
}

actor FaultingInvocationHTTPClient: InvocationHTTPClient {
    private var results: [FaultingInvocationHTTPResult]

    init(results: [FaultingInvocationHTTPResult]) {
        self.results = results
    }

    func send(_ request: URLRequest) async throws -> InvocationHTTPResponse {
        switch results.removeFirst() {
        case .response(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

actor RecordingInvocationHTTPClient: InvocationHTTPClient {
    private var responses: [InvocationHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [InvocationHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> InvocationHTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

final class LockedInvocationProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: [InvocationProgress] = []

    var values: [InvocationProgress] {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }

    func append(_ value: InvocationProgress) {
        lock.lock()
        progress.append(value)
        lock.unlock()
    }
}
