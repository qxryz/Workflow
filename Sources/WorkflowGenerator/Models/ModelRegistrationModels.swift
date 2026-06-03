import Foundation

struct InvocationAsset: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString.lowercased()
    var type: Modality
    var mimeType = ""
    var url = ""
    var base64 = ""
    var data: Data?
    var text = ""
    var json = ""
    var metadata: [String: String] = [:]
}

enum InterfaceFamily: String, Codable, CaseIterable, Identifiable {
    case conversation
    case special

    var id: String { rawValue }
}

enum RegistrationStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case unverified
    case verified
    case disabled

    var id: String { rawValue }

    var isNodeSelectable: Bool {
        self == .unverified || self == .verified
    }
}

enum RequestEncoding: String, Codable, CaseIterable, Identifiable {
    case json = "application/json"
    case multipart = "multipart/form-data"
    case octetStream = "application/octet-stream"

    var id: String { rawValue }
}

enum InvocationMode: String, Codable, CaseIterable, Identifiable {
    case sync
    case sse
    case async
    case websocket

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sync: "同步"
        case .sse: "流式"
        case .async: "异步任务"
        case .websocket: "WebSocket"
        }
    }

    static var streaming: InvocationMode { .sse }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "streaming" {
            self = .sse
            return
        }
        guard let mode = InvocationMode(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported invocation mode: \(rawValue)"
            )
        }
        self = mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

typealias ModelRegistrationMode = InvocationMode

enum NodeControlKind: String, Codable, CaseIterable, Identifiable {
    case text
    case number
    case slider
    case toggle
    case picker

    var id: String { rawValue }
}

struct RegistrationParameterDefinition: Identifiable, Codable, Hashable {
    var id = UUID()
    var parameterPath: String
    var title: String
    var valueType: String
    var defaultValue = ""
    var required = false
    var help = ""

    private enum CodingKeys: String, CodingKey {
        case id, parameterPath, title, valueType, defaultValue, required, help
    }

    init(
        id: UUID = UUID(),
        parameterPath: String,
        title: String,
        valueType: String,
        defaultValue: String = "",
        required: Bool = false,
        help: String = ""
    ) {
        self.id = id
        self.parameterPath = parameterPath
        self.title = title
        self.valueType = valueType
        self.defaultValue = defaultValue
        self.required = required
        self.help = help
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        parameterPath = try container.decode(String.self, forKey: .parameterPath)
        title = try container.decode(String.self, forKey: .title)
        valueType = try container.decode(String.self, forKey: .valueType)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue) ?? ""
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        help = try container.decodeIfPresent(String.self, forKey: .help) ?? ""
    }
}

struct NodeControlDefinition: Identifiable, Codable, Hashable {
    var id = UUID()
    var parameterPath: String
    var title: String
    var kind: NodeControlKind
    var defaultValue = ""
    var minimum: Double?
    var maximum: Double?
    var choices: [String] = []
    var help = ""

    private enum CodingKeys: String, CodingKey {
        case id, parameterPath, title, kind, defaultValue, minimum, maximum, choices, help
    }

    init(
        id: UUID = UUID(),
        parameterPath: String,
        title: String,
        kind: NodeControlKind,
        defaultValue: String = "",
        minimum: Double? = nil,
        maximum: Double? = nil,
        choices: [String] = [],
        help: String = ""
    ) {
        self.id = id
        self.parameterPath = parameterPath
        self.title = title
        self.kind = kind
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.choices = choices
        self.help = help
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        parameterPath = try container.decode(String.self, forKey: .parameterPath)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(NodeControlKind.self, forKey: .kind)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue) ?? ""
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        help = try container.decodeIfPresent(String.self, forKey: .help) ?? ""
    }
}

enum ModelRegistrationSlotSource: String, Codable, CaseIterable, Identifiable {
    case prompt
    case attachment
    case fixedValue = "fixed_value"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .prompt: "提示词"
        case .attachment: "附件"
        case .fixedValue: "固定值"
        }
    }
}

enum ModelRegistrationValueFormat: String, Codable, CaseIterable, Identifiable {
    case automatic
    case url
    case base64
    case dataURL = "data_url"
    case text
    case json

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .url: "Remote URL"
        case .base64: "Base64"
        case .dataURL: "Data URL"
        case .text: "Text"
        case .json: "JSON"
        }
    }
}

struct ModelRegistrationInputSlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var parameterPath: String
    var source: ModelRegistrationSlotSource
    var modality: Modality
    var required = false
    var acceptsMultiple = false
    var valueFormat: ModelRegistrationValueFormat = .automatic
    var fixedValue = ""
    var collectsAsArray = false
    var valueTemplateJSON = ""

    private enum CodingKeys: String, CodingKey {
        case id, label, parameterPath, source, modality, required, acceptsMultiple, valueFormat, fixedValue
        case collectsAsArray, valueTemplateJSON
    }

    init(
        id: UUID = UUID(),
        label: String,
        parameterPath: String,
        source: ModelRegistrationSlotSource,
        modality: Modality,
        required: Bool = false,
        acceptsMultiple: Bool = false,
        valueFormat: ModelRegistrationValueFormat = .automatic,
        fixedValue: String = "",
        collectsAsArray: Bool = false,
        valueTemplateJSON: String = ""
    ) {
        self.id = id
        self.label = label
        self.parameterPath = parameterPath
        self.source = source
        self.modality = modality
        self.required = required
        self.acceptsMultiple = acceptsMultiple
        self.valueFormat = valueFormat
        self.fixedValue = fixedValue
        self.collectsAsArray = collectsAsArray
        self.valueTemplateJSON = valueTemplateJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decode(String.self, forKey: .label)
        parameterPath = try container.decode(String.self, forKey: .parameterPath)
        source = try container.decode(ModelRegistrationSlotSource.self, forKey: .source)
        modality = try container.decode(Modality.self, forKey: .modality)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        acceptsMultiple = try container.decodeIfPresent(Bool.self, forKey: .acceptsMultiple) ?? false
        valueFormat = try container.decodeIfPresent(ModelRegistrationValueFormat.self, forKey: .valueFormat) ?? .automatic
        fixedValue = try container.decodeIfPresent(String.self, forKey: .fixedValue) ?? ""
        collectsAsArray = try container.decodeIfPresent(Bool.self, forKey: .collectsAsArray) ?? false
        valueTemplateJSON = try container.decodeIfPresent(String.self, forKey: .valueTemplateJSON) ?? ""
    }

    var availableValueFormats: [ModelRegistrationValueFormat] {
        guard source == .attachment else { return [.automatic] }
        return switch modality {
        case .image, .video, .audio, .audioVideo, .music, .threeD, .mask, .reference:
            [.automatic, .url, .base64, .dataURL]
        case .json, .embedding, .scores, .bbox:
            [.automatic, .json, .text]
        case .text:
            [.automatic, .text]
        case .file, .unknown:
            ModelRegistrationValueFormat.allCases
        }
    }

    mutating func normalizeValueFormat() {
        guard !availableValueFormats.contains(valueFormat) else { return }
        valueFormat = .automatic
    }
}

enum ModelRegistrationOutputKind: String, Codable, CaseIterable, Identifiable {
    case text
    case asset
    case taskId = "task_id"
    case raw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "文本"
        case .asset: "资产"
        case .taskId: "任务 ID"
        case .raw: "原始响应"
        }
    }
}

struct ModelRegistrationOutputSlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var kind: ModelRegistrationOutputKind
    var modality: Modality
    var jsonPath: String
}

struct ModelRegistrationPolling: Codable, Hashable {
    var taskIdPath = "output.task_id"
    var pollingPath = "/api/v1/tasks/{task_id}"
    var method: EndpointHTTPMethod = .get
    var statusPath = "output.task_status"
    var successValues = ["SUCCEEDED", "succeeded", "success", "completed"]
    var failureValues = ["FAILED", "failed", "cancelled", "expired"]
    var intervalSeconds = 3
    var maxAttempts = 100

    private enum CodingKeys: String, CodingKey {
        case taskIdPath, pollingPath, method, statusPath, successValues, failureValues, intervalSeconds, maxAttempts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskIdPath = try container.decodeIfPresent(String.self, forKey: .taskIdPath) ?? "output.task_id"
        pollingPath = try container.decodeIfPresent(String.self, forKey: .pollingPath) ?? "/api/v1/tasks/{task_id}"
        method = try container.decodeIfPresent(EndpointHTTPMethod.self, forKey: .method) ?? .get
        statusPath = try container.decodeIfPresent(String.self, forKey: .statusPath) ?? "output.task_status"
        successValues = try container.decodeIfPresent([String].self, forKey: .successValues) ?? ["SUCCEEDED", "succeeded", "success", "completed"]
        failureValues = try container.decodeIfPresent([String].self, forKey: .failureValues) ?? ["FAILED", "failed", "cancelled", "expired"]
        intervalSeconds = try container.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 3
        maxAttempts = try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 100
    }
}

struct RegisteredModelInterface: Identifiable, Codable, Hashable {
    static let unresolvedProviderId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var id: UUID
    var modelId: UUID
    // The sentinel is draft-only compatibility; disabled legacy records remain disabled when decoded.
    var providerId: UUID {
        didSet {
            status = Self.normalizedStatus(status, providerId: providerId)
        }
    }
    var title: String
    var templateId: String?
    var templateVersion: String?
    var interfaceFamily: InterfaceFamily
    var inheritsProviderBaseURL: Bool
    var baseURLOverride: String
    var path: String
    var method: EndpointHTTPMethod
    var requestEncoding: RequestEncoding
    var mode: InvocationMode
    var headers: [String: String]
    var modelParameterPath: String
    var defaultRequestJSON: String
    var inputCards: [ModelRegistrationInputSlot]
    var parameters: [RegistrationParameterDefinition]
    var nodeControls: [NodeControlDefinition]
    var outputSlots: [ModelRegistrationOutputSlot]
    var polling: ModelRegistrationPolling?
    var status: RegistrationStatus {
        didSet {
            let normalized = Self.normalizedStatus(status, providerId: providerId)
            if status != normalized {
                status = normalized
            }
        }
    }
    var lastTestSummary: String
    var lastTestedAt: Date?
    var lastModifiedByUser: Bool

    var task: ModelTask

    var outputModalities: Set<Modality> {
        Set(outputSlots.filter { $0.kind == .asset || $0.kind == .text }.map(\.modality))
    }

    var hasResolvedProvider: Bool {
        providerId != Self.unresolvedProviderId
    }

    var enabled: Bool {
        get { status != .disabled }
        set {
            if !newValue {
                status = .disabled
            } else if status == .disabled {
                status = .unverified
            }
        }
    }

    var inputSlots: [ModelRegistrationInputSlot] {
        get { inputCards }
        set { inputCards = newValue }
    }

    var presetKey: String? {
        get { templateId }
        set { templateId = newValue }
    }

    var lastStatus: String {
        get { lastTestSummary }
        set { lastTestSummary = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case providerId
        case title
        case templateId
        case templateVersion
        case interfaceFamily
        case inheritsProviderBaseURL
        case baseURLOverride
        case path
        case method
        case requestEncoding
        case mode
        case headers
        case modelParameterPath
        case defaultRequestJSON
        case inputCards
        case parameters
        case nodeControls
        case outputSlots
        case polling
        case status
        case lastTestSummary
        case lastTestedAt
        case lastModifiedByUser
        case task
        case enabled
        case inputSlots
        case presetKey
        case lastStatus
    }

    init(
        id: UUID = UUID(),
        modelId: UUID,
        providerId: UUID,
        title: String,
        templateId: String? = nil,
        templateVersion: String? = nil,
        interfaceFamily: InterfaceFamily? = nil,
        inheritsProviderBaseURL: Bool = true,
        baseURLOverride: String = "",
        path: String,
        method: EndpointHTTPMethod = .post,
        requestEncoding: RequestEncoding = .json,
        mode: InvocationMode = .sync,
        headers: [String: String] = [:],
        modelParameterPath: String = "model",
        defaultRequestJSON: String = "{}",
        inputCards: [ModelRegistrationInputSlot] = [],
        parameters: [RegistrationParameterDefinition] = [],
        nodeControls: [NodeControlDefinition] = [],
        outputSlots: [ModelRegistrationOutputSlot] = [],
        polling: ModelRegistrationPolling? = nil,
        status: RegistrationStatus = .draft,
        lastTestSummary: String = "未测试",
        lastTestedAt: Date? = nil,
        lastModifiedByUser: Bool = false,
        task: ModelTask = .chat
    ) {
        self.id = id
        self.modelId = modelId
        self.providerId = providerId
        self.title = title
        self.templateId = templateId
        self.templateVersion = templateVersion
        self.interfaceFamily = interfaceFamily ?? (task.taskGroup == .chat ? .conversation : .special)
        self.inheritsProviderBaseURL = inheritsProviderBaseURL
        self.baseURLOverride = baseURLOverride
        self.path = path
        self.method = method
        self.requestEncoding = requestEncoding
        self.mode = mode
        self.headers = headers
        self.modelParameterPath = modelParameterPath
        self.defaultRequestJSON = defaultRequestJSON
        self.inputCards = inputCards
        self.parameters = parameters
        self.nodeControls = nodeControls
        self.outputSlots = outputSlots
        self.polling = polling
        self.status = Self.normalizedStatus(status, providerId: providerId)
        self.lastTestSummary = lastTestSummary
        self.lastTestedAt = lastTestedAt
        self.lastModifiedByUser = lastModifiedByUser
        self.task = task
    }

    init(
        id: UUID = UUID(),
        modelId: UUID,
        title: String,
        task: ModelTask,
        enabled: Bool = true,
        inheritsProviderBaseURL: Bool = true,
        baseURLOverride: String = "",
        path: String,
        method: EndpointHTTPMethod = .post,
        mode: ModelRegistrationMode = .sync,
        headers: [String: String] = [:],
        modelParameterPath: String = "model",
        defaultRequestJSON: String = "{}",
        inputSlots: [ModelRegistrationInputSlot],
        outputSlots: [ModelRegistrationOutputSlot],
        polling: ModelRegistrationPolling? = nil,
        presetKey: String? = nil,
        lastStatus: String = "未测试",
        lastTestedAt: Date? = nil,
        lastModifiedByUser: Bool = false
    ) {
        self.init(
            id: id,
            modelId: modelId,
            providerId: Self.unresolvedProviderId,
            title: title,
            templateId: presetKey,
            interfaceFamily: task.taskGroup == .chat ? .conversation : .special,
            inheritsProviderBaseURL: inheritsProviderBaseURL,
            baseURLOverride: baseURLOverride,
            path: path,
            method: method,
            mode: mode,
            headers: headers,
            modelParameterPath: modelParameterPath,
            defaultRequestJSON: defaultRequestJSON,
            inputCards: inputSlots,
            outputSlots: outputSlots,
            polling: polling,
            status: enabled ? .unverified : .disabled,
            lastTestSummary: lastStatus,
            lastTestedAt: lastTestedAt,
            lastModifiedByUser: lastModifiedByUser,
            task: task
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        modelId = try container.decode(UUID.self, forKey: .modelId)
        providerId = try container.decodeIfPresent(UUID.self, forKey: .providerId) ?? Self.unresolvedProviderId
        title = try container.decode(String.self, forKey: .title)
        templateId = try container.decodeIfPresent(String.self, forKey: .templateId)
            ?? container.decodeIfPresent(String.self, forKey: .presetKey)
        templateVersion = try container.decodeIfPresent(String.self, forKey: .templateVersion)
        task = try container.decodeIfPresent(ModelTask.self, forKey: .task) ?? .chat
        interfaceFamily = try container.decodeIfPresent(InterfaceFamily.self, forKey: .interfaceFamily)
            ?? (task.taskGroup == .chat ? .conversation : .special)
        inheritsProviderBaseURL = try container.decodeIfPresent(Bool.self, forKey: .inheritsProviderBaseURL) ?? true
        baseURLOverride = try container.decodeIfPresent(String.self, forKey: .baseURLOverride) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        method = try container.decodeIfPresent(EndpointHTTPMethod.self, forKey: .method) ?? .post
        requestEncoding = try container.decodeIfPresent(RequestEncoding.self, forKey: .requestEncoding) ?? .json
        mode = try container.decodeIfPresent(InvocationMode.self, forKey: .mode) ?? .sync
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        modelParameterPath = try container.decodeIfPresent(String.self, forKey: .modelParameterPath) ?? "model"
        defaultRequestJSON = try container.decodeIfPresent(String.self, forKey: .defaultRequestJSON) ?? "{}"
        inputCards = try container.decodeIfPresent([ModelRegistrationInputSlot].self, forKey: .inputCards)
            ?? container.decodeIfPresent([ModelRegistrationInputSlot].self, forKey: .inputSlots)
            ?? []
        parameters = try container.decodeIfPresent([RegistrationParameterDefinition].self, forKey: .parameters) ?? []
        nodeControls = try container.decodeIfPresent([NodeControlDefinition].self, forKey: .nodeControls) ?? []
        outputSlots = try container.decodeIfPresent([ModelRegistrationOutputSlot].self, forKey: .outputSlots) ?? []
        polling = try container.decodeIfPresent(ModelRegistrationPolling.self, forKey: .polling)
        let decodedStatus = try container.decodeIfPresent(RegistrationStatus.self, forKey: .status)
            ?? ((try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true) ? .unverified : .disabled)
        status = Self.normalizedStatus(decodedStatus, providerId: providerId)
        lastTestSummary = try container.decodeIfPresent(String.self, forKey: .lastTestSummary)
            ?? container.decodeIfPresent(String.self, forKey: .lastStatus)
            ?? "未测试"
        lastTestedAt = try container.decodeIfPresent(Date.self, forKey: .lastTestedAt)
        lastModifiedByUser = try container.decodeIfPresent(Bool.self, forKey: .lastModifiedByUser) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(templateId, forKey: .templateId)
        try container.encodeIfPresent(templateVersion, forKey: .templateVersion)
        try container.encode(interfaceFamily, forKey: .interfaceFamily)
        try container.encode(inheritsProviderBaseURL, forKey: .inheritsProviderBaseURL)
        try container.encode(baseURLOverride, forKey: .baseURLOverride)
        try container.encode(path, forKey: .path)
        try container.encode(method, forKey: .method)
        try container.encode(requestEncoding, forKey: .requestEncoding)
        try container.encode(mode, forKey: .mode)
        try container.encode(headers, forKey: .headers)
        try container.encode(modelParameterPath, forKey: .modelParameterPath)
        try container.encode(defaultRequestJSON, forKey: .defaultRequestJSON)
        try container.encode(inputCards, forKey: .inputCards)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(nodeControls, forKey: .nodeControls)
        try container.encode(outputSlots, forKey: .outputSlots)
        try container.encodeIfPresent(polling, forKey: .polling)
        try container.encode(status, forKey: .status)
        try container.encode(lastTestSummary, forKey: .lastTestSummary)
        try container.encodeIfPresent(lastTestedAt, forKey: .lastTestedAt)
        try container.encode(lastModifiedByUser, forKey: .lastModifiedByUser)
        try container.encode(task, forKey: .task)
    }

    private static func normalizedStatus(_ status: RegistrationStatus, providerId: UUID) -> RegistrationStatus {
        providerId == unresolvedProviderId && status.isNodeSelectable ? .draft : status
    }

    func resolvedBaseURL(provider: ProviderConfig) -> String {
        inheritsProviderBaseURL ? provider.baseURL : baseURLOverride
    }
}

typealias ModelRegistration = RegisteredModelInterface

enum ModelRegistrationPresetRegistry {
    static func draft(for model: ModelConfig, provider: ProviderConfig?) -> ModelRegistration {
        make(model: model, provider: provider, task: inferredTask(for: model), presetKey: "migrated.\(model.endpointKind.rawValue)")
    }

    static func make(model: ModelConfig, provider: ProviderConfig?, task: ModelTask, presetKey: String? = nil) -> ModelRegistration {
        let providerName = provider?.name ?? model.provider
        let endpointKind = task.legacyEndpointKind
        let path = recommendedPath(providerName: providerName, task: task, fallback: model.endpointPath.isEmpty ? endpointKind.defaultPath : model.endpointPath)
        let isAsync = endpointKind == .videoTask || ProviderEndpointCatalog.defaultUsesAsyncTask(providerName: providerName, endpointKind: endpointKind, modelId: model.modelId)
        var headers: [String: String] = [:]
        if ProviderEndpointCatalog.normalizedProviderName(providerName) == "aliyun", isAsync {
            headers["X-DashScope-Async"] = "enable"
        }
        return ModelRegistration(
            modelId: model.id,
            providerId: provider?.id ?? model.providerId ?? RegisteredModelInterface.unresolvedProviderId,
            title: task.title,
            templateId: presetKey,
            interfaceFamily: task.taskGroup == .chat ? .conversation : .special,
            inheritsProviderBaseURL: !model.overridesProviderBaseURL,
            baseURLOverride: model.baseURL,
            path: path,
            mode: isAsync ? .async : (task == .chat ? .streaming : .sync),
            headers: headers,
            defaultRequestJSON: model.requestParametersJSON.isEmpty ? "{}" : model.requestParametersJSON,
            inputCards: defaultInputSlots(for: task),
            outputSlots: defaultOutputSlots(for: task),
            polling: isAsync ? ModelRegistrationPolling() : nil,
            task: task
        )
    }

    private static func inferredTask(for model: ModelConfig) -> ModelTask {
        switch model.endpointKind {
        case .chatCompletions, .responses: .chat
        case .imageGeneration: .textToImage
        case .imageEdit: .imageEdit
        case .videoTask: .textToVideo
        case .audioTranscription: .speechToText
        case .audioSpeech: .textToSpeech
        case .embeddings: .embeddingText
        case .custom: .chat
        }
    }

    private static func recommendedPath(providerName: String, task: ModelTask, fallback: String) -> String {
        let provider = ProviderEndpointCatalog.normalizedProviderName(providerName)
        if provider == "aliyun", task == .textToVideo || task == .imageToVideo {
            return "/api/v1/services/aigc/video-generation/video-synthesis"
        }
        return fallback
    }

    static func defaultInputSlots(for task: ModelTask) -> [ModelRegistrationInputSlot] {
        var slots: [ModelRegistrationInputSlot] = []
        if task.defaultInputModalities.contains(.text) {
            slots.append(ModelRegistrationInputSlot(label: "提示词", parameterPath: promptPath(for: task), source: .prompt, modality: .text, required: true))
        }
        for modality in task.defaultInputModalities.subtracting([.text]).sorted(by: { $0.rawValue < $1.rawValue }) {
            slots.append(ModelRegistrationInputSlot(label: modality.title, parameterPath: defaultParameterPath(for: modality), source: .attachment, modality: modality, required: true))
        }
        return slots
    }

    static func defaultOutputSlots(for task: ModelTask) -> [ModelRegistrationOutputSlot] {
        task.defaultOutputModalities.map { modality in
            if modality == .text {
                return ModelRegistrationOutputSlot(label: "文本", kind: .text, modality: .text, jsonPath: "choices.0.message.content")
            }
            return ModelRegistrationOutputSlot(label: modality.title, kind: .asset, modality: modality, jsonPath: defaultOutputPath(for: modality))
        }
    }

    private static func promptPath(for task: ModelTask) -> String {
        switch task {
        case .chat, .reasoningChat, .agentChat, .visionChat, .videoUnderstanding, .audioUnderstanding, .documentUnderstanding, .omniChat, .structuredOutput, .toolCall:
            "messages.0.content"
        case .textToSpeech:
            "input"
        default:
            "input.prompt"
        }
    }

    private static func defaultParameterPath(for modality: Modality) -> String {
        switch modality {
        case .image: "input.image_url"
        case .video: "input.video_url"
        case .audio: "input.audio_url"
        case .file: "input.file_url"
        case .reference: "input.reference_url"
        case .mask: "input.mask_url"
        default: "input.\(modality.rawValue)"
        }
    }

    private static func defaultOutputPath(for modality: Modality) -> String {
        switch modality {
        case .image: "output.results.*.url"
        case .video, .audioVideo: "content.video_url"
        case .audio, .music: "output.audio.url"
        default: "output"
        }
    }
}
