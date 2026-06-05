import Foundation

enum NodeExecutionErrorCode: String, Codable, CaseIterable, Identifiable {
    case noModelConfigured = "NO_MODEL_CONFIGURED"
    case noAgentConfigured = "NO_AGENT_CONFIGURED"
    case apiKeyMissing = "API_KEY_MISSING"
    case httpError = "HTTP_ERROR"
    case modalityMismatch = "MODALITY_MISMATCH"
    case consistencyNoDirectOutput = "CONSISTENCY_NO_DIRECT_OUTPUT"
    case customEndpointNotSupported = "CUSTOM_ENDPOINT_NOT_SUPPORTED"
    case agentNoAcpCommand = "AGENT_NO_ACP_COMMAND"
    case invocationError = "INVOCATION_ERROR"
    case timeout = "TIMEOUT"
    case unknown = "UNKNOWN"

    var id: String { rawValue }
    var suggestionTitle: String {
        switch self {
        case .noModelConfigured: "未配置模型"
        case .noAgentConfigured: "未配置 Agent"
        case .apiKeyMissing: "API Key 缺失"
        case .httpError: "HTTP 请求失败"
        case .modalityMismatch: "模态不匹配"
        case .consistencyNoDirectOutput: "一致性节点限制"
        case .customEndpointNotSupported: "不支持自定义端点"
        case .agentNoAcpCommand: "缺少 ACP 命令"
        case .invocationError: "调用路由错误"
        case .timeout: "请求超时"
        case .unknown: "未知错误"
        }
    }
    var symbolName: String {
        switch self {
        case .noModelConfigured, .noAgentConfigured, .agentNoAcpCommand: "wrench.adjustable"
        case .apiKeyMissing: "key.slash"
        case .httpError: "antenna.radiowaves.left.and.right.slash"
        case .modalityMismatch: "square.on.square.intersection.dashed"
        case .consistencyNoDirectOutput: "archivebox.slash"
        case .customEndpointNotSupported: "link.badge.plus"
        case .invocationError: "arrow.triangle.branch"
        case .timeout: "clock.badge.exclamationmark"
        case .unknown: "exclamationmark.triangle"
        }
    }
    var defaultSuggestion: String {
        switch self {
        case .noModelConfigured: "在设置 > 模型中为节点分配一个模型。"
        case .noAgentConfigured: "在设置 > Agent 中配置一个本地 Agent。"
        case .apiKeyMissing: "在设置 > 提供商中填写 API Key，或设置对应的环境变量。"
        case .httpError: "检查网络连接和 API 端点状态。"
        case .modalityMismatch: "调整节点的输入/输出模态，或切换支持所需模态的模型。"
        case .consistencyNoDirectOutput: "一致性节点仅在运行工作流时吸收资产，不直接生成输出。"
        case .customEndpointNotSupported: "自定义端点需要在设置中配置具体的适配器。"
        case .agentNoAcpCommand: "在设置 > Agent > 高级中配置 ACP 启动命令。"
        case .invocationError: "检查端点配置和模型能力匹配。"
        case .timeout: "增加超时时间或降低请求复杂度。"
        case .unknown: "请查看日志获取详细信息。"
        }
    }
}

struct NodeExecutionError: Identifiable, Codable, Hashable {
    var id = UUID()
    var code: NodeExecutionErrorCode
    var nodeId: UUID
    var title: String
    var detail: String
    var suggestion: String
    var timestamp = Date()

    init(code: NodeExecutionErrorCode, nodeId: UUID, title: String, detail: String) {
        self.code = code
        self.nodeId = nodeId
        self.title = title
        self.detail = detail
        self.suggestion = code.defaultSuggestion
    }
}

enum NodeKind: String, Codable, CaseIterable, Identifiable {
    case model
    case agent
    case consistency

    var id: String { rawValue }
    var title: String {
        switch self {
        case .model: "Model"
        case .agent: "Agent"
        case .consistency: "Consistency"
        }
    }
}

enum NodeVisualStyle: String, Codable, CaseIterable, Identifiable {
    case glass
    case signal
    case paper
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "玻璃"
        case .signal: "信号"
        case .paper: "纸片"
        case .terminal: "终端"
        }
    }

    var description: String {
        switch self {
        case .glass: "轻薄半透明，适合常规模型节点。"
        case .signal: "更亮的描边和发光，适合关键生成节点。"
        case .paper: "高对比白底，适合说明与规划节点。"
        case .terminal: "深色命令行质感，适合本地 Agent。"
        }
    }
}

struct ConsistencyNodeConfiguration: Codable, Hashable {
    var useDefaultLLM = true
    var defaultModelId: UUID?
    var acceptedArtifactTypes: Set<Modality> = Set(Modality.allCases)
    var defaultCategory: ConsistencyCategoryKind?
    var autoClassify = true
    var autoDeduplicate = true
    var extractAnchors = true
    var allowOverwrite = false
    var lockWrittenAssets = false
    var writePolicy: ConsistencyWritePolicy = .merge
    var conflictPolicy: ConsistencyConflictPolicy = .preferLocked
}


enum ProviderAuthType: String, Codable, CaseIterable, Identifiable {
    case bearer
    case apiKeyHeader = "api_key_header"
    case queryKey = "query_key"
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bearer: "Bearer"
        case .apiKeyHeader: "API Key Header"
        case .queryKey: "Query Key"
        case .custom: "Custom"
        }
    }
}

enum ProviderVideoRequestStyle: String {
    case prompt
    case volcContent
    case aliTask
    case minimaxTask
}

enum ProviderImageRequestStyle: String {
    case prompt
    case aliTask
}

struct ProviderEndpointPreset: Hashable {
    var providerName: String
    var endpointKind: ModelEndpointKind
    var endpointPath: String
    var requestParametersJSON: String
    var videoStyle: ProviderVideoRequestStyle?
    var notes: String
}

enum ProviderEndpointCatalog {
    static func preset(providerName: String, endpointKind: ModelEndpointKind) -> ProviderEndpointPreset {
        let key = normalizedProviderName(providerName)
        let path = endpointPath(providerKey: key, endpointKind: endpointKind)
        return ProviderEndpointPreset(
            providerName: providerName,
            endpointKind: endpointKind,
            endpointPath: path,
            requestParametersJSON: requestParametersJSON(providerKey: key, endpointKind: endpointKind),
            videoStyle: videoStyle(providerKey: key),
            notes: notes(providerKey: key, endpointKind: endpointKind)
        )
    }

    static func endpointPath(providerName: String, endpointKind: ModelEndpointKind) -> String {
        endpointPath(providerKey: normalizedProviderName(providerName), endpointKind: endpointKind)
    }

    static func requestParametersJSON(providerName: String, endpointKind: ModelEndpointKind) -> String {
        requestParametersJSON(providerKey: normalizedProviderName(providerName), endpointKind: endpointKind)
    }

    static func shouldOverrideBaseURL(providerName: String, endpointKind: ModelEndpointKind) -> Bool {
        let providerKey = normalizedProviderName(providerName)
        return providerKey == "aliyun" && [
            ModelEndpointKind.imageGeneration,
            .imageEdit,
            .videoTask,
            .audioSpeech,
            .audioTranscription
        ].contains(endpointKind)
    }

    static func preferredBaseURL(providerName: String, providerBaseURL: String, endpointKind: ModelEndpointKind) -> String {
        guard shouldOverrideBaseURL(providerName: providerName, endpointKind: endpointKind) else {
            return providerBaseURL
        }
        let lowercasedBase = providerBaseURL.lowercased()
        if lowercasedBase.contains("dashscope-us") {
            return "https://dashscope-us.aliyuncs.com"
        }
        if lowercasedBase.contains("dashscope-intl") {
            return "https://dashscope-intl.aliyuncs.com"
        }
        return "https://dashscope.aliyuncs.com"
    }

    static func defaultUsesAsyncTask(providerName: String, endpointKind: ModelEndpointKind, modelId: String) -> Bool {
        let providerKey = normalizedProviderName(providerName)
        guard providerKey == "aliyun" else {
            return endpointKind == .videoTask
        }
        let id = modelId.lowercased()
        if id.contains("qwen-image-2.0") || id.contains("qwen-image-2") {
            return false
        }
        switch endpointKind {
        case .imageGeneration, .imageEdit, .videoTask:
            return true
        case .audioTranscription:
            return id.contains("filetrans") || id.contains("sensevoice")
        default:
            return false
        }
    }

    static func videoStyle(providerName: String) -> ProviderVideoRequestStyle {
        videoStyle(providerKey: normalizedProviderName(providerName))
    }

    static func imageStyle(providerName: String) -> ProviderImageRequestStyle {
        normalizedProviderName(providerName) == "aliyun" ? .aliTask : .prompt
    }

    static func normalizedProviderName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("agnes") || lower.contains("sapiens") { return "agnes" }
        if lower.contains("火山") || lower.contains("volc") || lower.contains("ark") { return "volc" }
        if lower.contains("阿里") || lower.contains("百炼") || lower.contains("dashscope") || lower.contains("aliyun") { return "aliyun" }
        if lower.contains("minimax") { return "minimax" }
        if lower.contains("deepseek") { return "deepseek" }
        if lower.contains("openai") { return "openai" }
        return "generic"
    }

    private static func endpointPath(providerKey: String, endpointKind: ModelEndpointKind) -> String {
        switch providerKey {
        case "volc":
            switch endpointKind {
            case .chatCompletions: return "/chat/completions"
            case .imageGeneration, .imageEdit: return "/images/generations"
            case .videoTask: return "/contents/generations/tasks"
            case .embeddings: return "/embeddings"
            default: return endpointKind.defaultPath
            }
        case "aliyun":
            switch endpointKind {
            case .chatCompletions: return "/chat/completions"
            case .responses: return "/responses"
            case .imageGeneration: return "/api/v1/services/aigc/image-generation/generation"
            case .imageEdit: return "/api/v1/services/aigc/image2image/image-synthesis"
            case .videoTask: return "/api/v1/services/aigc/video-generation/video-synthesis"
            case .audioSpeech: return "/api/v1/services/aigc/multimodal-generation/generation"
            case .audioTranscription: return "/api/v1/services/aigc/multimodal-generation/generation"
            case .embeddings: return "/embeddings"
            default: return endpointKind.defaultPath
            }
        case "minimax":
            switch endpointKind {
            case .chatCompletions: return "/chat/completions"
            case .imageGeneration, .imageEdit: return "/image_generation"
            case .videoTask: return "/video_generation"
            case .audioSpeech: return "/t2a_v2"
            case .audioTranscription: return "/audio/transcriptions"
            case .embeddings: return "/embeddings"
            default: return endpointKind.defaultPath
            }
        case "agnes":
            switch endpointKind {
            case .chatCompletions: return "/chat/completions"
            case .imageGeneration, .imageEdit: return "/images/generations"
            case .videoTask: return "/videos"
            default: return endpointKind.defaultPath
            }
        case "openai":
            switch endpointKind {
            case .videoTask: return "/videos"
            default: return endpointKind.defaultPath
            }
        default:
            return endpointKind.defaultPath
        }
    }

    private static func requestParametersJSON(providerKey: String, endpointKind: ModelEndpointKind) -> String {
        switch (providerKey, endpointKind) {
        case ("deepseek", .chatCompletions):
            return "{\n  \"thinking\": {\"type\": \"enabled\"},\n  \"reasoning_effort\": \"high\"\n}"
        case ("volc", .imageGeneration), ("volc", .imageEdit):
            return "{\n  \"size\": \"2048x2048\",\n  \"response_format\": \"b64_json\",\n  \"watermark\": false\n}"
        case ("volc", .videoTask):
            return "{\n  \"ratio\": \"16:9\",\n  \"duration\": 5,\n  \"watermark\": false\n}"
        case ("aliyun", .imageGeneration), ("aliyun", .imageEdit):
            return "{\n  \"parameters\": {\n    \"size\": \"2K\",\n    \"n\": 1,\n    \"watermark\": false,\n    \"thinking_mode\": true\n  }\n}"
        case ("aliyun", .videoTask):
            return "{\n  \"parameters\": {\n    \"size\": \"1280*720\",\n    \"duration\": 5\n  }\n}"
        case ("aliyun", .audioSpeech):
            return "{\n  \"input\": {\n    \"voice\": \"Cherry\",\n    \"language_type\": \"Chinese\"\n  }\n}"
        case ("aliyun", .audioTranscription):
            return "{\n  \"parameters\": {\n    \"asr_options\": {\n      \"enable_itn\": false\n    }\n  }\n}"
        case ("minimax", .imageGeneration), ("minimax", .imageEdit):
            return "{\n  \"aspect_ratio\": \"1:1\",\n  \"n\": 1,\n  \"response_format\": \"url\"\n}"
        case ("minimax", .videoTask):
            return "{\n  \"duration\": 6,\n  \"resolution\": \"1080P\"\n}"
        case ("minimax", .audioSpeech):
            return "{\n  \"voice_setting\": {\n    \"voice_id\": \"male-qn-qingse\",\n    \"speed\": 1,\n    \"vol\": 1,\n    \"pitch\": 0\n  },\n  \"audio_setting\": {\n    \"sample_rate\": 32000,\n    \"bitrate\": 128000,\n    \"format\": \"mp3\"\n  }\n}"
        case ("agnes", .chatCompletions):
            return "{\n  \"temperature\": 0.7,\n  \"top_p\": 1,\n  \"max_tokens\": 1024,\n  \"stream\": false,\n  \"tools\": [],\n  \"tool_choice\": \"auto\",\n  \"chat_template_kwargs\": {\n    \"enable_thinking\": false\n  },\n  \"thinking\": {\n    \"type\": \"disabled\",\n    \"budget_tokens\": 2048\n  }\n}"
        case ("agnes", .imageGeneration), ("agnes", .imageEdit):
            return "{\n  \"size\": \"1024x768\",\n  \"seed\": -1,\n  \"tags\": [\"img2img\"],\n  \"extra_body\": {\n    \"image\": [],\n    \"response_format\": \"url\"\n  }\n}"
        case ("agnes", .videoTask):
            return "{\n  \"image\": \"\",\n  \"mode\": \"ti2vid\",\n  \"height\": 768,\n  \"width\": 1152,\n  \"num_frames\": 121,\n  \"frame_rate\": 24,\n  \"seed\": -1,\n  \"negative_prompt\": \"\",\n  \"extra_body\": {\n    \"image\": [],\n    \"mode\": \"keyframes\"\n  }\n}"
        case ("openai", .imageGeneration), ("openai", .imageEdit):
            return "{\n  \"size\": \"1024x1024\",\n  \"response_format\": \"b64_json\"\n}"
        case ("openai", .videoTask):
            return "{\n  \"seconds\": 4,\n  \"size\": \"1280x720\"\n}"
        default:
            return ModelConfig.defaultRequestParametersJSON(for: endpointKind)
        }
    }

    private static func videoStyle(providerKey: String) -> ProviderVideoRequestStyle {
        switch providerKey {
        case "volc": return .volcContent
        case "aliyun": return .aliTask
        case "minimax": return .minimaxTask
        default: return .prompt
        }
    }

    private static func notes(providerKey: String, endpointKind: ModelEndpointKind) -> String {
        switch providerKey {
        case "deepseek":
            return "DeepSeek is OpenAI-compatible for text. Thinking models can use thinking and reasoning_effort."
        case "volc":
            return "火山方舟按 /api/v3 分类：Chat、图片、视频异步任务、向量化分别走不同 endpoint。"
        case "aliyun":
            return "百炼文本走 OpenAI-compatible；图像/视频多数是 DashScope async task style endpoint。"
        case "minimax":
            return "MiniMax 覆盖文本、语音、图片、视频、音乐；非文本端点通常需要专门参数。"
        case "agnes":
            return "Agnes AI uses OpenAI-compatible chat, image generation, and asynchronous video endpoints at apihub.agnes-ai.com/v1."
        case "openai":
            return "OpenAI supports Responses/Chat, Images, Videos, Audio, and Embeddings with separate endpoints."
        default:
            return "Generic OpenAI-compatible defaults."
        }
    }
}

struct ModelInferenceRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var keywords: [String]
    var endpointKind: ModelEndpointKind
    var inputModalities: Set<Modality>
    var outputModalities: Set<Modality>

    static let defaults: [ModelInferenceRule] = [
        ModelInferenceRule(name: "Image generation", keywords: ["seedream", "image", "img", "wanx", "t2i", "qwen-image", "z-image", "flux", "gpt-image", "dall-e"], endpointKind: .imageGeneration, inputModalities: [.text, .image], outputModalities: [.image]),
        ModelInferenceRule(name: "Video generation", keywords: ["seedance", "video", "t2v", "i2v", "sora", "veo", "kling"], endpointKind: .videoTask, inputModalities: [.text, .image, .video], outputModalities: [.video]),
        ModelInferenceRule(name: "Text to speech", keywords: ["tts", "speech", "audio"], endpointKind: .audioSpeech, inputModalities: [.text], outputModalities: [.audio]),
        ModelInferenceRule(name: "Speech to text", keywords: ["asr", "whisper", "transcribe", "transcription"], endpointKind: .audioTranscription, inputModalities: [.audio], outputModalities: [.text]),
        ModelInferenceRule(name: "Embeddings", keywords: ["embedding", "embed", "text-embedding"], endpointKind: .embeddings, inputModalities: [.text], outputModalities: [.file])
    ]
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case zhCN
    case enUS

    var id: String { rawValue }
    var title: String {
        switch self {
        case .zhCN: "中文"
        case .enUS: "English"
        }
    }

    var shortTitle: String {
        switch self {
        case .zhCN: "CN"
        case .enUS: "EN"
        }
    }
}

enum CanvasTool: String, Codable, CaseIterable, Identifiable {
    case select
    case move
    case image
    case video
    case audio
    case grid
    case rectangle
    case line
    case arrow
    case ellipse
    case polygon
    case star
    case pen
    case text

    var id: String { rawValue }
    var title: String {
        switch self {
        case .select: "Select"
        case .move: "Move"
        case .image: "Upload Image"
        case .video: "Upload Video"
        case .audio: "Upload Audio"
        case .grid: "Artboard"
        case .rectangle: "Rectangle"
        case .line: "Line"
        case .arrow: "Arrow"
        case .ellipse: "Ellipse"
        case .polygon: "Polygon"
        case .star: "Star"
        case .pen: "Pen"
        case .text: "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .move: "hand.point.up.left"
        case .image: "photo.badge.plus"
        case .video: "video.badge.plus"
        case .audio: "waveform.badge.plus"
        case .grid: "number"
        case .rectangle: "rectangle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .ellipse: "circle"
        case .polygon: "triangle"
        case .star: "star"
        case .pen: "pencil.tip"
        case .text: "textformat"
        }
    }

    var keyboardHint: String? {
        switch self {
        case .rectangle: "R"
        case .line: "L"
        case .arrow: "⇧L"
        case .ellipse: "O"
        case .pen: "P"
        case .text: "T"
        default: nil
        }
    }
}

struct ModelConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var provider: String
    var providerId: UUID?
    var baseURL: String
    var modelId: String
    var supportedModalities: Set<Modality>
    var inputModalities: Set<Modality>
    var outputModalities: Set<Modality>
    var endpointKind: ModelEndpointKind
    var endpointPath: String
    var requestParametersJSON: String
    var apiKeyReference: String
    var overridesProviderBaseURL: Bool
    var usesAsyncTask: Bool
    var family: String
    var source: ModelSource
    var enabled: Bool

    static let defaults: [ModelConfig] = [
        ModelConfig(name: "Default LLM", provider: "OpenAI Compatible", providerId: nil, baseURL: "https://api.openai.com/v1", modelId: "gpt-4.1", supportedModalities: [.text, .image], inputModalities: [.text, .image], outputModalities: [.text], endpointKind: .chatCompletions, endpointPath: ModelEndpointKind.chatCompletions.defaultPath, requestParametersJSON: "{}", apiKeyReference: "OPENAI_API_KEY"),
        ModelConfig(name: "Creative Image", provider: "Custom Image API", providerId: nil, baseURL: "https://example.com/v1", modelId: "image-model", supportedModalities: [.text, .image], inputModalities: [.text, .image], outputModalities: [.image], endpointKind: .imageGeneration, endpointPath: ModelEndpointKind.imageGeneration.defaultPath, requestParametersJSON: ModelConfig.defaultRequestParametersJSON(for: .imageGeneration), apiKeyReference: "IMAGE_API_KEY")
    ]

    static func defaultRequestParametersJSON(for endpointKind: ModelEndpointKind) -> String {
        switch endpointKind {
        case .imageGeneration, .imageEdit:
            "{\n  \"size\": \"2048x2048\",\n  \"response_format\": \"b64_json\"\n}"
        case .videoTask:
            "{\n  \"ratio\": \"16:9\",\n  \"duration\": 5,\n  \"watermark\": false\n}"
        case .audioSpeech:
            "{\n  \"voice\": \"alloy\",\n  \"response_format\": \"mp3\"\n}"
        default:
            "{}"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case providerId
        case baseURL
        case modelId
        case supportedModalities
        case inputModalities
        case outputModalities
        case endpointKind
        case endpointPath
        case requestParametersJSON
        case apiKeyReference
        case overridesProviderBaseURL
        case usesAsyncTask
        case family
        case source
        case enabled
    }

    init(
        id: UUID = UUID(),
        name: String,
        provider: String,
        providerId: UUID?,
        baseURL: String,
        modelId: String,
        supportedModalities: Set<Modality>,
        inputModalities: Set<Modality>? = nil,
        outputModalities: Set<Modality>? = nil,
        endpointKind: ModelEndpointKind = .chatCompletions,
        endpointPath: String? = nil,
        requestParametersJSON: String = "{}",
        apiKeyReference: String,
        overridesProviderBaseURL: Bool = false,
        usesAsyncTask: Bool = false,
        family: String = "",
        source: ModelSource = .manual,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.providerId = providerId
        self.baseURL = baseURL
        self.modelId = modelId
        self.supportedModalities = supportedModalities
        self.inputModalities = inputModalities ?? supportedModalities
        self.outputModalities = outputModalities ?? supportedModalities
        self.endpointKind = endpointKind
        self.endpointPath = endpointPath ?? endpointKind.defaultPath
        self.requestParametersJSON = requestParametersJSON
        self.apiKeyReference = apiKeyReference
        self.overridesProviderBaseURL = overridesProviderBaseURL
        self.usesAsyncTask = usesAsyncTask
        self.family = family
        self.source = source
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(String.self, forKey: .provider)
        providerId = try container.decodeIfPresent(UUID.self, forKey: .providerId)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        modelId = try container.decode(String.self, forKey: .modelId)
        supportedModalities = try container.decodeIfPresent(Set<Modality>.self, forKey: .supportedModalities) ?? [.text]
        inputModalities = try container.decodeIfPresent(Set<Modality>.self, forKey: .inputModalities) ?? supportedModalities
        outputModalities = try container.decodeIfPresent(Set<Modality>.self, forKey: .outputModalities) ?? supportedModalities
        endpointKind = try container.decodeIfPresent(ModelEndpointKind.self, forKey: .endpointKind) ?? (outputModalities == [.text] ? .chatCompletions : .custom)
        endpointPath = try container.decodeIfPresent(String.self, forKey: .endpointPath) ?? endpointKind.defaultPath
        let decodedParameters = try container.decodeIfPresent(String.self, forKey: .requestParametersJSON)
        requestParametersJSON = decodedParameters?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? decodedParameters!
            : ModelConfig.defaultRequestParametersJSON(for: endpointKind)
        apiKeyReference = try container.decode(String.self, forKey: .apiKeyReference)
        overridesProviderBaseURL = try container.decodeIfPresent(Bool.self, forKey: .overridesProviderBaseURL) ?? false
        usesAsyncTask = try container.decodeIfPresent(Bool.self, forKey: .usesAsyncTask)
            ?? ProviderEndpointCatalog.defaultUsesAsyncTask(providerName: provider, endpointKind: endpointKind, modelId: modelId)
        family = try container.decodeIfPresent(String.self, forKey: .family) ?? ""
        source = try container.decodeIfPresent(ModelSource.self, forKey: .source) ?? .manual
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct ProviderConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var symbolName: String = "network"
    var defaultModelIds: [String] = []
    var notes: String = ""
    var documentationURL: String = ""
    var fetchedModelIds: [String] = []
    var lastStatus: String = "Not tested"
    var modelListEndpoint: String = "/models"
    var authType: ProviderAuthType = .bearer
    var enabled: Bool = true

    static let defaults: [ProviderConfig] = [
        ProviderConfig(
            name: "Agnes AI",
            baseURL: "https://apihub.agnes-ai.com/v1",
            apiKey: "",
            symbolName: "wand.and.stars",
            defaultModelIds: ["agnes-2.0-flash", "agnes-image-2.1-flash", "agnes-image-2.0-flash", "agnes-video-v2.0"],
            documentationURL: "https://agnes-ai.com/doc",
            notes: "Agnes AI by Sapiens AI. Recommended full-modal provider with OpenAI-compatible text, image, and video APIs."
        ),
        ProviderConfig(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "",
            symbolName: "sparkles",
            defaultModelIds: ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex"],
            documentationURL: "https://platform.openai.com/docs",
            notes: "OpenAI official API. Uses Bearer auth and /models for discovery."
        ),
        ProviderConfig(
            name: "MiniMax Coding Plan",
            baseURL: "https://api.minimaxi.com/v1",
            apiKey: "",
            symbolName: "waveform.path.ecg",
            defaultModelIds: ["MiniMax-M2.7", "MiniMax-M2.7-highspeed"],
            documentationURL: "https://platform.minimaxi.com/docs/api-reference/text-openai-api",
            notes: "Use the Token Plan key. OpenAI-compatible endpoint; Anthropic-compatible is available separately at /anthropic for Claude-style tools."
        ),
        ProviderConfig(
            name: "火山引擎",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            apiKey: "",
            symbolName: "flame",
            defaultModelIds: ["doubao-seed-2.0-pro", "deepseek-v3-2-251201"],
            documentationURL: "https://www.volcengine.com/docs/82379",
            notes: "火山方舟常规在线推理入口，支持 Chat、图片、视频等方舟 API。"
        ),
        ProviderConfig(
            name: "阿里云百炼",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            apiKey: "",
            symbolName: "cloud",
            defaultModelIds: ["qwen3.6-plus", "qwen3.5-plus", "qwen-plus", "qwen-max"],
            documentationURL: "https://help.aliyun.com/zh/model-studio",
            notes: "文本模型使用 /compatible-mode/v1；万相图片/视频会自动路由到 DashScope /api/v1/services/aigc/... 任务接口。"
        ),
        ProviderConfig(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            apiKey: "",
            symbolName: "brain.head.profile",
            defaultModelIds: ["deepseek-v4-pro", "deepseek-v4-flash"],
            documentationURL: "https://api-docs.deepseek.com",
            notes: "OpenAI-compatible. DeepSeek V4 supports thinking via reasoning_effort and extra_body thinking when the client exposes those fields."
        )
    ]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case apiKey
        case symbolName
        case defaultModelIds
        case notes
        case documentationURL
        case fetchedModelIds
        case lastStatus
        case modelListEndpoint
        case authType
        case enabled
    }

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKey: String,
        symbolName: String = "network",
        defaultModelIds: [String] = [],
        documentationURL: String = "",
        notes: String = "",
        fetchedModelIds: [String] = [],
        lastStatus: String = "Not tested",
        modelListEndpoint: String = "/models",
        authType: ProviderAuthType = .bearer,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.symbolName = symbolName
        self.defaultModelIds = defaultModelIds
        self.documentationURL = documentationURL
        self.notes = notes
        self.fetchedModelIds = fetchedModelIds
        self.lastStatus = lastStatus
        self.modelListEndpoint = modelListEndpoint
        self.authType = authType
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "network"
        defaultModelIds = try container.decodeIfPresent([String].self, forKey: .defaultModelIds) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        documentationURL = try container.decodeIfPresent(String.self, forKey: .documentationURL) ?? ProviderConfig.defaultDocumentationURL(for: name)
        fetchedModelIds = try container.decodeIfPresent([String].self, forKey: .fetchedModelIds) ?? []
        lastStatus = try container.decodeIfPresent(String.self, forKey: .lastStatus) ?? "Not tested"
        modelListEndpoint = try container.decodeIfPresent(String.self, forKey: .modelListEndpoint) ?? "/models"
        authType = try container.decodeIfPresent(ProviderAuthType.self, forKey: .authType) ?? .bearer
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    static func defaultDocumentationURL(for name: String) -> String {
        defaults.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.documentationURL ?? ""
    }
}

struct AgentConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var executable: String
    var path: String?
    var isAvailable: Bool
    var invocationTemplate: String
    var acpInvocationTemplate: String = ""

    static let candidates: [AgentConfig] = [
        AgentConfig(name: "Claude CLI", executable: "claude", path: nil, isAvailable: false, invocationTemplate: "{executable}", acpInvocationTemplate: "npx -y @agentclientprotocol/claude-agent-acp@0.37.0"),
        AgentConfig(name: "Codex CLI", executable: "codex", path: nil, isAvailable: false, invocationTemplate: "{executable}", acpInvocationTemplate: "npx -y @zed-industries/codex-acp@0.14.0"),
        AgentConfig(name: "OpenClaw", executable: "openclaw", path: nil, isAvailable: false, invocationTemplate: "{executable}", acpInvocationTemplate: "{executable} --acp"),
        AgentConfig(name: "OpenCode", executable: "opencode", path: nil, isAvailable: false, invocationTemplate: "{executable}", acpInvocationTemplate: "{executable} acp"),
        AgentConfig(name: "Gemini CLI", executable: "gemini", path: nil, isAvailable: false, invocationTemplate: "{executable}", acpInvocationTemplate: "{executable} --acp"),
        AgentConfig(name: "Qwen Code", executable: "qwen", path: nil, isAvailable: false, invocationTemplate: "{executable}", acpInvocationTemplate: "{executable} --acp")
    ]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case executable
        case path
        case isAvailable
        case invocationTemplate
        case acpInvocationTemplate
    }

    init(id: UUID = UUID(), name: String, executable: String, path: String?, isAvailable: Bool, invocationTemplate: String, acpInvocationTemplate: String = "") {
        self.id = id
        self.name = name
        self.executable = executable
        self.path = path
        self.isAvailable = isAvailable
        self.invocationTemplate = invocationTemplate
        self.acpInvocationTemplate = acpInvocationTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        executable = try container.decode(String.self, forKey: .executable)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? false
        invocationTemplate = try container.decodeIfPresent(String.self, forKey: .invocationTemplate) ?? "{executable}"
        acpInvocationTemplate = try container.decodeIfPresent(String.self, forKey: .acpInvocationTemplate) ?? ""
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var role: String
    var text: String
    var attachments: [String]
    var createdAt = Date()
}

struct WorkflowNode: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var description: String
    var kind: NodeKind
    var modelId: UUID?
    var registeredModelInterfaceId: UUID?
    var modelParameterOverrides: [String: String]
    var agentExecutable: String?
    var position: CanvasPoint
    var inputModalities: Set<Modality>
    var outputModalities: Set<Modality>
    var chat: [ChatMessage]
    var draftMessage: String
    var usesPersistentChat = true
    var hasStartedPersistentChat = false
    var persistentSessionId: String
    var persistentModelId: UUID?
    var specialTemplatePrompt: String = ""
    var ejectionAngleDegrees: Double = 0
    var ejectionForce: Double = 320
    var ejectionSpreadDegrees: Double = 34
    var blackHoleEnabled: Bool = true
    var blackHoleRadius: Double = 170
    var referenceURL: String = ""
    var visualStyle: NodeVisualStyle = .glass
    var workflowAutoRunEnabled: Bool = true
    var sendsSpecialTemplateOnRun: Bool = true
    var consistencyConfig = ConsistencyNodeConfiguration()
    var lastError: NodeExecutionError?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case kind
        case modelId
        case registeredModelInterfaceId
        case modelParameterOverrides
        case agentExecutable
        case position
        case inputModalities
        case outputModalities
        case chat
        case draftMessage
        case usesPersistentChat
        case hasStartedPersistentChat
        case persistentSessionId
        case persistentModelId
        case specialTemplatePrompt
        case ejectionAngleDegrees
        case ejectionForce
        case ejectionSpreadDegrees
        case blackHoleEnabled
        case blackHoleRadius
        case referenceURL
        case visualStyle
        case workflowAutoRunEnabled
        case sendsSpecialTemplateOnRun
        case consistencyConfig
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        kind: NodeKind,
        modelId: UUID?,
        agentExecutable: String?,
        position: CanvasPoint,
        inputModalities: Set<Modality>,
        outputModalities: Set<Modality>,
        chat: [ChatMessage],
        draftMessage: String,
        registeredModelInterfaceId: UUID? = nil,
        modelParameterOverrides: [String: String] = [:],
        usesPersistentChat: Bool = true,
        hasStartedPersistentChat: Bool = false,
        persistentSessionId: String = UUID().uuidString.lowercased(),
        persistentModelId: UUID? = nil,
        specialTemplatePrompt: String = "",
        ejectionAngleDegrees: Double = 0,
        ejectionForce: Double = 320,
        ejectionSpreadDegrees: Double = 34,
        blackHoleEnabled: Bool = true,
        blackHoleRadius: Double = 170,
        referenceURL: String = "",
        visualStyle: NodeVisualStyle = .glass,
        workflowAutoRunEnabled: Bool = true,
        sendsSpecialTemplateOnRun: Bool = true,
        consistencyConfig: ConsistencyNodeConfiguration = ConsistencyNodeConfiguration()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.modelId = modelId
        self.registeredModelInterfaceId = registeredModelInterfaceId
        self.modelParameterOverrides = modelParameterOverrides
        self.agentExecutable = agentExecutable
        self.position = position
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.chat = chat
        self.draftMessage = draftMessage
        self.usesPersistentChat = usesPersistentChat
        self.hasStartedPersistentChat = hasStartedPersistentChat
        self.persistentSessionId = persistentSessionId
        self.persistentModelId = persistentModelId
        self.specialTemplatePrompt = specialTemplatePrompt
        self.ejectionAngleDegrees = ejectionAngleDegrees
        self.ejectionForce = ejectionForce
        self.ejectionSpreadDegrees = ejectionSpreadDegrees
        self.blackHoleEnabled = blackHoleEnabled
        self.blackHoleRadius = blackHoleRadius
        self.referenceURL = referenceURL
        self.visualStyle = visualStyle
        self.workflowAutoRunEnabled = workflowAutoRunEnabled
        self.sendsSpecialTemplateOnRun = sendsSpecialTemplateOnRun
        self.consistencyConfig = consistencyConfig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        kind = try container.decode(NodeKind.self, forKey: .kind)
        modelId = try container.decodeIfPresent(UUID.self, forKey: .modelId)
        registeredModelInterfaceId = try container.decodeIfPresent(UUID.self, forKey: .registeredModelInterfaceId)
        modelParameterOverrides = try container.decodeIfPresent([String: String].self, forKey: .modelParameterOverrides) ?? [:]
        agentExecutable = try container.decodeIfPresent(String.self, forKey: .agentExecutable)
        position = try container.decode(CanvasPoint.self, forKey: .position)
        inputModalities = try container.decode(Set<Modality>.self, forKey: .inputModalities)
        outputModalities = try container.decode(Set<Modality>.self, forKey: .outputModalities)
        chat = try container.decode([ChatMessage].self, forKey: .chat)
        draftMessage = try container.decode(String.self, forKey: .draftMessage)
        usesPersistentChat = try container.decodeIfPresent(Bool.self, forKey: .usesPersistentChat) ?? true
        hasStartedPersistentChat = try container.decodeIfPresent(Bool.self, forKey: .hasStartedPersistentChat) ?? false
        persistentSessionId = try container.decodeIfPresent(String.self, forKey: .persistentSessionId) ?? UUID().uuidString.lowercased()
        persistentModelId = try container.decodeIfPresent(UUID.self, forKey: .persistentModelId)
        specialTemplatePrompt = try container.decodeIfPresent(String.self, forKey: .specialTemplatePrompt) ?? ""
        ejectionAngleDegrees = try container.decodeIfPresent(Double.self, forKey: .ejectionAngleDegrees) ?? 0
        ejectionForce = try container.decodeIfPresent(Double.self, forKey: .ejectionForce) ?? 320
        ejectionSpreadDegrees = try container.decodeIfPresent(Double.self, forKey: .ejectionSpreadDegrees) ?? 34
        blackHoleEnabled = try container.decodeIfPresent(Bool.self, forKey: .blackHoleEnabled) ?? true
        blackHoleRadius = try container.decodeIfPresent(Double.self, forKey: .blackHoleRadius) ?? 170
        referenceURL = try container.decodeIfPresent(String.self, forKey: .referenceURL) ?? ""
        visualStyle = try container.decodeIfPresent(NodeVisualStyle.self, forKey: .visualStyle) ?? .glass
        workflowAutoRunEnabled = try container.decodeIfPresent(Bool.self, forKey: .workflowAutoRunEnabled) ?? true
        sendsSpecialTemplateOnRun = try container.decodeIfPresent(Bool.self, forKey: .sendsSpecialTemplateOnRun) ?? true
        consistencyConfig = try container.decodeIfPresent(ConsistencyNodeConfiguration.self, forKey: .consistencyConfig) ?? ConsistencyNodeConfiguration()
    }
}

struct CanvasPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct CanvasSize: Codable, Hashable {
    var width: Double
    var height: Double
}

enum CanvasElementKind: String, Codable, Hashable {
    case artboard
    case rectangle
    case line
    case arrow
    case ellipse
    case polygon
    case star
    case pen
    case text
    case image
    case video
    case audio
    case file
}

enum CanvasAnchorSide: String, Codable, Hashable, CaseIterable {
    case top
    case right
    case bottom
    case left
}

enum CanvasAnchorTargetKind: String, Codable, Hashable {
    case node
    case element
}

struct CanvasAnchorRef: Codable, Hashable {
    var targetKind: CanvasAnchorTargetKind
    var targetId: UUID
    var side: CanvasAnchorSide
}

enum WorkflowEdgeRunPolicy: String, Codable, Hashable, CaseIterable, Identifiable {
    case always
    case condition
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "Always"
        case .condition: "Condition"
        case .manual: "Manual"
        }
    }
}

enum WorkflowDependencyPolicy: String, Codable, Hashable, CaseIterable, Identifiable {
    case allSuccess = "all_success"
    case anySuccess = "any_success"
    case allDone = "all_done"
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allSuccess: "All Success"
        case .anySuccess: "Any Success"
        case .allDone: "All Done"
        case .manual: "Manual"
        }
    }
}

struct WorkflowLogicEdgeConfiguration: Codable, Hashable {
    var id = UUID()
    var sourceNodeId: UUID?
    var targetNodeId: UUID?
    var sourcePort = "output"
    var sourceHandle = ""
    var targetPort = "input"
    var targetHandle = ""
    var displayName = ""
    var description = ""
    var condition = ""
    var payloadMapping = "{}"
    var artifactMapping = "{}"
    var runPolicy: WorkflowEdgeRunPolicy = .always
    var dependencyPolicy: WorkflowDependencyPolicy = .allSuccess
    var enabled = true

    init(
        id: UUID = UUID(),
        sourceNodeId: UUID? = nil,
        targetNodeId: UUID? = nil,
        sourcePort: String = "output",
        sourceHandle: String = "",
        targetPort: String = "input",
        targetHandle: String = "",
        displayName: String = "",
        description: String = "",
        condition: String = "",
        payloadMapping: String = "{}",
        artifactMapping: String = "{}",
        runPolicy: WorkflowEdgeRunPolicy = .always,
        dependencyPolicy: WorkflowDependencyPolicy = .allSuccess,
        enabled: Bool = true
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.sourcePort = sourcePort
        self.sourceHandle = sourceHandle
        self.targetPort = targetPort
        self.targetHandle = targetHandle
        self.displayName = displayName
        self.description = description
        self.condition = condition
        self.payloadMapping = payloadMapping
        self.artifactMapping = artifactMapping
        self.runPolicy = runPolicy
        self.dependencyPolicy = dependencyPolicy
        self.enabled = enabled
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = AppAppearanceMode(rawValue: value) ?? .dark
    }

    var defaultCanvasBackgroundHex: String {
        switch self {
        case .light: "#F5F5F7"
        case .dark: "#1C1C1E"
        }
    }
}

extension CanvasBoardSettings {
    var effectiveCanvasBackgroundHex: String {
        switch appearanceMode {
        case .light:
            return canvasBackgroundHex.caseInsensitiveCompare(AppAppearanceMode.dark.defaultCanvasBackgroundHex) == .orderedSame ? AppAppearanceMode.light.defaultCanvasBackgroundHex : canvasBackgroundHex
        case .dark:
            return canvasBackgroundHex.caseInsensitiveCompare(AppAppearanceMode.light.defaultCanvasBackgroundHex) == .orderedSame ? AppAppearanceMode.dark.defaultCanvasBackgroundHex : canvasBackgroundHex
        }
    }
}

enum CanvasPatternStyle: String, Codable, CaseIterable, Identifiable {
    case grid
    case dots
    case blueprint
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "方格"
        case .dots: "点阵"
        case .blueprint: "蓝图"
        case .none: "无图案"
        }
    }
}

struct CanvasBoardSettings: Codable, Hashable {
    var gridSize: Double = 32
    var gridOpacity: Double = 0.12
    var snapToGrid: Bool = true
    var smoothPen: Bool = true
    var appearanceMode: AppAppearanceMode = .dark
    var themeAccentHex: String = "#0A84FF"
    var canvasBackgroundHex: String = "#1C1C1E"
    var canvasPattern: CanvasPatternStyle = .grid
    var artboardColorHex: String = "#FFFFFF"
    var shapeColorHex: String = "#111111"
    var penColorHex: String = "#111111"
    var textColorHex: String = "#111111"
    var penWidth: Double = 3
    var colorPresets: [String] = ["#111111", "#FFFFFF", "#EF4444", "#F97316", "#EAB308", "#22C55E", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899"]

    init(gridSize: Double = 32, gridOpacity: Double = 0.12, snapToGrid: Bool = true, smoothPen: Bool = true, appearanceMode: AppAppearanceMode = .dark, themeAccentHex: String = "#0A84FF", canvasBackgroundHex: String = "#1C1C1E", canvasPattern: CanvasPatternStyle = .grid, artboardColorHex: String = "#FFFFFF", shapeColorHex: String = "#111111", penColorHex: String = "#111111", textColorHex: String = "#111111", penWidth: Double = 3, colorPresets: [String] = ["#111111", "#FFFFFF", "#EF4444", "#F97316", "#EAB308", "#22C55E", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899"]) {
        self.gridSize = gridSize
        self.gridOpacity = gridOpacity
        self.snapToGrid = snapToGrid
        self.smoothPen = smoothPen
        self.appearanceMode = appearanceMode
        self.themeAccentHex = themeAccentHex
        self.canvasBackgroundHex = canvasBackgroundHex
        self.canvasPattern = canvasPattern
        self.artboardColorHex = artboardColorHex
        self.shapeColorHex = shapeColorHex
        self.penColorHex = penColorHex
        self.textColorHex = textColorHex
        self.penWidth = penWidth
        self.colorPresets = colorPresets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gridSize = try container.decodeIfPresent(Double.self, forKey: .gridSize) ?? 32
        gridOpacity = try container.decodeIfPresent(Double.self, forKey: .gridOpacity) ?? 0.12
        snapToGrid = try container.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        smoothPen = try container.decodeIfPresent(Bool.self, forKey: .smoothPen) ?? true
        appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .dark
        themeAccentHex = try container.decodeIfPresent(String.self, forKey: .themeAccentHex) ?? "#0A84FF"
        canvasBackgroundHex = try container.decodeIfPresent(String.self, forKey: .canvasBackgroundHex) ?? "#1C1C1E"
        canvasPattern = try container.decodeIfPresent(CanvasPatternStyle.self, forKey: .canvasPattern) ?? .grid
        artboardColorHex = try container.decodeIfPresent(String.self, forKey: .artboardColorHex) ?? "#FFFFFF"
        shapeColorHex = try container.decodeIfPresent(String.self, forKey: .shapeColorHex) ?? "#111111"
        penColorHex = try container.decodeIfPresent(String.self, forKey: .penColorHex) ?? "#111111"
        textColorHex = try container.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#111111"
        penWidth = try container.decodeIfPresent(Double.self, forKey: .penWidth) ?? 3
        colorPresets = try container.decodeIfPresent([String].self, forKey: .colorPresets) ?? ["#111111", "#FFFFFF", "#EF4444", "#F97316", "#EAB308", "#22C55E", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899"]
    }
}

struct CanvasElement: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: CanvasElementKind
    var position: CanvasPoint
    var size: CanvasSize
    var text: String?
    var assetPath: String?
    var pathPoints: [CanvasPoint] = []
    var strokeWidth: Double = 2
    var colorHex: String = "#111111"
    var startAnchor: CanvasAnchorRef?
    var endAnchor: CanvasAnchorRef?
    var isLogicConnection = false
    var logicEdge: WorkflowLogicEdgeConfiguration?
    var sourceNodeId: UUID?

    init(
        id: UUID = UUID(),
        kind: CanvasElementKind,
        position: CanvasPoint,
        size: CanvasSize,
        text: String? = nil,
        assetPath: String? = nil,
        pathPoints: [CanvasPoint] = [],
        strokeWidth: Double = 2,
        colorHex: String = "#111111",
        startAnchor: CanvasAnchorRef? = nil,
        endAnchor: CanvasAnchorRef? = nil,
        isLogicConnection: Bool = false,
        logicEdge: WorkflowLogicEdgeConfiguration? = nil,
        sourceNodeId: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.size = size
        self.text = text
        self.assetPath = assetPath
        self.pathPoints = pathPoints
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
        self.startAnchor = startAnchor
        self.endAnchor = endAnchor
        self.isLogicConnection = isLogicConnection
        if isLogicConnection {
            var resolvedEdge = logicEdge ?? WorkflowLogicEdgeConfiguration(
                id: id,
                sourceNodeId: startAnchor?.targetKind == .node ? startAnchor?.targetId : nil,
                targetNodeId: endAnchor?.targetKind == .node ? endAnchor?.targetId : nil
            )
            resolvedEdge.id = id
            self.logicEdge = resolvedEdge
        } else {
            self.logicEdge = logicEdge
        }
        self.sourceNodeId = sourceNodeId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(CanvasElementKind.self, forKey: .kind)
        position = try container.decode(CanvasPoint.self, forKey: .position)
        size = try container.decode(CanvasSize.self, forKey: .size)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        assetPath = try container.decodeIfPresent(String.self, forKey: .assetPath)
        pathPoints = try container.decodeIfPresent([CanvasPoint].self, forKey: .pathPoints) ?? []
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#111111"
        startAnchor = try container.decodeIfPresent(CanvasAnchorRef.self, forKey: .startAnchor)
        endAnchor = try container.decodeIfPresent(CanvasAnchorRef.self, forKey: .endAnchor)
        isLogicConnection = try container.decodeIfPresent(Bool.self, forKey: .isLogicConnection) ?? false
        logicEdge = try container.decodeIfPresent(WorkflowLogicEdgeConfiguration.self, forKey: .logicEdge)
        if isLogicConnection, logicEdge == nil {
            logicEdge = WorkflowLogicEdgeConfiguration(
                id: id,
                sourceNodeId: startAnchor?.targetKind == .node ? startAnchor?.targetId : nil,
                targetNodeId: endAnchor?.targetKind == .node ? endAnchor?.targetId : nil
            )
        }
        if isLogicConnection {
            logicEdge?.id = id
            logicEdge?.sourceNodeId = startAnchor?.targetKind == .node ? startAnchor?.targetId : nil
            logicEdge?.targetNodeId = endAnchor?.targetKind == .node ? endAnchor?.targetId : nil
        }
        sourceNodeId = try container.decodeIfPresent(UUID.self, forKey: .sourceNodeId)
    }
}

enum ArtboardPreset: String, Codable, CaseIterable, Identifiable {
    case square
    case portrait
    case widescreen
    case landscape
    case verticalVideo
    case a4
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: "1:1"
        case .portrait: "2:3"
        case .widescreen: "16:9"
        case .landscape: "3:2"
        case .verticalVideo: "9:16"
        case .a4: "A4"
        case .custom: "Custom"
        }
    }

    var size: CanvasSize {
        switch self {
        case .square: CanvasSize(width: 1024, height: 1024)
        case .portrait: CanvasSize(width: 1024, height: 1536)
        case .widescreen: CanvasSize(width: 1920, height: 1080)
        case .landscape: CanvasSize(width: 1536, height: 1024)
        case .verticalVideo: CanvasSize(width: 1080, height: 1920)
        case .a4: CanvasSize(width: 1240, height: 1754)
        case .custom: CanvasSize(width: 1024, height: 1024)
        }
    }
}

struct MediaAsset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var modality: Modality
    var addedAt = Date()

    var displayPath: String {
        NSString(string: path).abbreviatingWithTildeInPath
    }

    static func inferModality(path: String) -> Modality {
        let ext = URL(filePath: path).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff"].contains(ext) { return .image }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) { return .video }
        if ["mp3", "wav", "m4a", "aac", "flac", "aiff"].contains(ext) { return .audio }
        if ["txt", "md", "json", "csv", "rtf"].contains(ext) { return .text }
        return .file
    }
}

struct WorkflowDocument: Codable, Hashable {
    var id = UUID()
    var name = "Untitled Workflow"
    var nodes: [WorkflowNode] = []
    var canvasElements: [CanvasElement] = []
    var artboardSize = CanvasSize(width: 1024, height: 1024)
    var canvasViewport = CanvasViewportState()
    var selectedNodeId: UUID?
    var selectedCanvasElementId: UUID?
    var selectedNodeIds: Set<UUID> = []
    var selectedCanvasElementIds: Set<UUID> = []
    var assets: [MediaAsset] = []
    var consistency = MediaConsistencyProfile()
    var automationSettings = WorkflowAutomationSettings()
    var runInputDefinitions: [WorkflowRunInputDefinition] = []
    var runState = WorkflowRunState()
    var workflowVariables: [WorkflowVariable] = []
    var workflowSecrets: [WorkflowSecret] = []
    var workflowDebugSettings = WorkflowDebugSettings()

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nodes
        case canvasElements
        case artboardSize
        case canvasViewport
        case selectedNodeId
        case selectedCanvasElementId
        case selectedNodeIds
        case selectedCanvasElementIds
        case assets
        case consistency
        case automationSettings
        case runInputDefinitions
        case runState
        case workflowVariables
        case workflowSecrets
        case workflowDebugSettings
    }

    init(name: String = "Untitled Workflow") {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Workflow"
        nodes = try container.decodeIfPresent([WorkflowNode].self, forKey: .nodes) ?? []
        canvasElements = try container.decodeIfPresent([CanvasElement].self, forKey: .canvasElements) ?? []
        artboardSize = try container.decodeIfPresent(CanvasSize.self, forKey: .artboardSize) ?? CanvasSize(width: 1024, height: 1024)
        canvasViewport = try container.decodeIfPresent(CanvasViewportState.self, forKey: .canvasViewport) ?? CanvasViewportState()
        selectedNodeId = try container.decodeIfPresent(UUID.self, forKey: .selectedNodeId)
        selectedCanvasElementId = try container.decodeIfPresent(UUID.self, forKey: .selectedCanvasElementId)
        selectedNodeIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedNodeIds) ?? []
        selectedCanvasElementIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedCanvasElementIds) ?? []
        assets = try container.decodeIfPresent([MediaAsset].self, forKey: .assets) ?? []
        consistency = try container.decodeIfPresent(MediaConsistencyProfile.self, forKey: .consistency) ?? MediaConsistencyProfile()
        automationSettings = try container.decodeIfPresent(WorkflowAutomationSettings.self, forKey: .automationSettings) ?? WorkflowAutomationSettings()
        runInputDefinitions = try container.decodeIfPresent([WorkflowRunInputDefinition].self, forKey: .runInputDefinitions) ?? []
        runState = try container.decodeIfPresent(WorkflowRunState.self, forKey: .runState) ?? WorkflowRunState()
        workflowVariables = try container.decodeIfPresent([WorkflowVariable].self, forKey: .workflowVariables) ?? []
        workflowSecrets = try container.decodeIfPresent([WorkflowSecret].self, forKey: .workflowSecrets) ?? []
        workflowDebugSettings = try container.decodeIfPresent(WorkflowDebugSettings.self, forKey: .workflowDebugSettings) ?? WorkflowDebugSettings()
    }
}

struct CanvasViewportState: Codable, Hashable {
    var offsetX = 10000.0
    var offsetY = 10000.0
    var zoomScale = 1.0
}

enum WorkflowAssetPropagationMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case classic
    case bigMouth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "经典"
        case .bigMouth: "大胃王"
        }
    }
}

struct WorkflowAutomationSettings: Codable, Hashable {
    var manualTriggerEnabled = true
    var autoSendTemplatePrompt = true
    var manualReviewWhenNoLogicTarget = true
    var stopOnNodeError = true
    var continuousRunNodes = true
    var assetPropagationMode: WorkflowAssetPropagationMode = .classic

    enum CodingKeys: String, CodingKey {
        case manualTriggerEnabled
        case autoSendTemplatePrompt
        case manualReviewWhenNoLogicTarget
        case stopOnNodeError
        case continuousRunNodes
        case assetPropagationMode
    }

    init(
        manualTriggerEnabled: Bool = true,
        autoSendTemplatePrompt: Bool = true,
        manualReviewWhenNoLogicTarget: Bool = true,
        stopOnNodeError: Bool = true,
        continuousRunNodes: Bool = true,
        assetPropagationMode: WorkflowAssetPropagationMode = .classic
    ) {
        self.manualTriggerEnabled = manualTriggerEnabled
        self.autoSendTemplatePrompt = autoSendTemplatePrompt
        self.manualReviewWhenNoLogicTarget = manualReviewWhenNoLogicTarget
        self.stopOnNodeError = stopOnNodeError
        self.continuousRunNodes = continuousRunNodes
        self.assetPropagationMode = assetPropagationMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manualTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .manualTriggerEnabled) ?? true
        autoSendTemplatePrompt = try container.decodeIfPresent(Bool.self, forKey: .autoSendTemplatePrompt) ?? true
        manualReviewWhenNoLogicTarget = try container.decodeIfPresent(Bool.self, forKey: .manualReviewWhenNoLogicTarget) ?? true
        stopOnNodeError = try container.decodeIfPresent(Bool.self, forKey: .stopOnNodeError) ?? true
        continuousRunNodes = try container.decodeIfPresent(Bool.self, forKey: .continuousRunNodes) ?? true
        assetPropagationMode = try container.decodeIfPresent(WorkflowAssetPropagationMode.self, forKey: .assetPropagationMode) ?? .classic
    }
}

enum WorkflowRunStatus: String, Codable, Hashable, CaseIterable, Identifiable {
    case idle
    case running
    case waitingForNextLevel
    case completed
    case waitingForReview
    case failed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .waitingForNextLevel: "Next Level"
        case .completed: "Completed"
        case .waitingForReview: "Review"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

enum WorkflowNodeRunStatus: String, Codable, Hashable {
    case pending
    case waiting
    case running
    case succeeded
    case waitingForReview
    case failed
    case skipped
    case cancelled
}

enum WorkflowLevelStatus: String, Codable, Hashable, CaseIterable, Identifiable {
    case pending
    case running
    case success
    case waiting
    case failed
    case skipped
    case cancelled

    var id: String { rawValue }
}

enum WorkflowRunInputType: String, Codable, Hashable, CaseIterable, Identifiable {
    case text
    case textarea
    case number
    case boolean
    case select
    case file
    case image
    case video
    case voice
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .textarea: "Textarea"
        case .number: "Number"
        case .boolean: "Boolean"
        case .select: "Select"
        case .file: "File"
        case .image: "Image"
        case .video: "Video"
        case .voice: "Voice / Music"
        case .json: "JSON"
        }
    }
}

struct WorkflowRunInputDefinition: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var inputType: WorkflowRunInputType = .text
    var defaultValue = ""
    var currentValue = ""
    var isRequired = false
    var description = ""
    var sourceNodeId: UUID?
    var passesToRun = true

    var resolvedValue: String {
        currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultValue : currentValue
    }
}

struct WorkflowParentOutput: Identifiable, Codable, Hashable {
    var id = UUID()
    var parentNodeId: UUID
    var text = ""
    var json = ""
    var artifacts: [String] = []
}

struct WorkflowEdgeRunInput: Identifiable, Codable, Hashable {
    var id = UUID()
    var edgeId: UUID
    var displayName = ""
    var payload = ""
    var artifacts: [String] = []
}

struct SpatialFanSnapshot: Codable, Hashable {
    var angle: Double
    var radius: Double
    var spreadDegrees: Double
}

struct SpatialBlackholeSnapshot: Codable, Hashable {
    var receiverId: UUID
    var radius: Double
}

struct SpatialArtifactRoute: Identifiable, Codable, Hashable {
    var id = UUID()
    var sourceNodeId: UUID
    var targetNodeId: UUID
    var routeType = "fan_to_blackhole"
    var artifactOnly = false
    var transfersText = true
    var payloadMapping = "{}"
    var createsDependency = true
    var enabled = true
    var sourceFan: SpatialFanSnapshot
    var targetBlackhole: SpatialBlackholeSnapshot
    var acceptedTypes: Set<Modality> = Set(Modality.allCases)

    enum CodingKeys: String, CodingKey {
        case id
        case sourceNodeId
        case targetNodeId
        case routeType
        case artifactOnly
        case transfersText
        case payloadMapping
        case createsDependency
        case enabled
        case sourceFan
        case targetBlackhole
        case acceptedTypes
    }

    init(
        id: UUID = UUID(),
        sourceNodeId: UUID,
        targetNodeId: UUID,
        routeType: String = "fan_to_blackhole",
        artifactOnly: Bool = false,
        transfersText: Bool = true,
        payloadMapping: String = "{}",
        createsDependency: Bool = true,
        enabled: Bool = true,
        sourceFan: SpatialFanSnapshot,
        targetBlackhole: SpatialBlackholeSnapshot,
        acceptedTypes: Set<Modality> = Set(Modality.allCases)
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.routeType = routeType
        self.artifactOnly = artifactOnly
        self.transfersText = transfersText
        self.payloadMapping = payloadMapping
        self.createsDependency = createsDependency
        self.enabled = enabled
        self.sourceFan = sourceFan
        self.targetBlackhole = targetBlackhole
        self.acceptedTypes = acceptedTypes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceNodeId = try container.decode(UUID.self, forKey: .sourceNodeId)
        targetNodeId = try container.decode(UUID.self, forKey: .targetNodeId)
        routeType = try container.decodeIfPresent(String.self, forKey: .routeType) ?? "fan_to_blackhole"
        artifactOnly = try container.decodeIfPresent(Bool.self, forKey: .artifactOnly) ?? false
        transfersText = try container.decodeIfPresent(Bool.self, forKey: .transfersText) ?? true
        payloadMapping = try container.decodeIfPresent(String.self, forKey: .payloadMapping) ?? "{}"
        createsDependency = try container.decodeIfPresent(Bool.self, forKey: .createsDependency) ?? true
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sourceFan = try container.decode(SpatialFanSnapshot.self, forKey: .sourceFan)
        targetBlackhole = try container.decode(SpatialBlackholeSnapshot.self, forKey: .targetBlackhole)
        acceptedTypes = try container.decodeIfPresent(Set<Modality>.self, forKey: .acceptedTypes) ?? Set(Modality.allCases)
    }
}

struct SpatialArtifactInput: Identifiable, Codable, Hashable {
    var id = UUID()
    var routeId: UUID
    var sourceNodeId: UUID
    var targetNodeId: UUID
    var text = ""
    var json = ""
    var artifacts: [String] = []
    var createdBy = "fan_to_blackhole"
    var sourceFan: SpatialFanSnapshot
    var targetBlackhole: SpatialBlackholeSnapshot

    enum CodingKeys: String, CodingKey {
        case id
        case routeId
        case sourceNodeId
        case targetNodeId
        case text
        case json
        case artifacts
        case createdBy
        case sourceFan
        case targetBlackhole
    }

    init(
        id: UUID = UUID(),
        routeId: UUID,
        sourceNodeId: UUID,
        targetNodeId: UUID,
        text: String = "",
        json: String = "",
        artifacts: [String] = [],
        createdBy: String = "fan_to_blackhole",
        sourceFan: SpatialFanSnapshot,
        targetBlackhole: SpatialBlackholeSnapshot
    ) {
        self.id = id
        self.routeId = routeId
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.text = text
        self.json = json
        self.artifacts = artifacts
        self.createdBy = createdBy
        self.sourceFan = sourceFan
        self.targetBlackhole = targetBlackhole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        routeId = try container.decode(UUID.self, forKey: .routeId)
        sourceNodeId = try container.decode(UUID.self, forKey: .sourceNodeId)
        targetNodeId = try container.decode(UUID.self, forKey: .targetNodeId)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        json = try container.decodeIfPresent(String.self, forKey: .json) ?? ""
        artifacts = try container.decodeIfPresent([String].self, forKey: .artifacts) ?? []
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? "fan_to_blackhole"
        sourceFan = try container.decode(SpatialFanSnapshot.self, forKey: .sourceFan)
        targetBlackhole = try container.decode(SpatialBlackholeSnapshot.self, forKey: .targetBlackhole)
    }
}

struct WorkflowNodeRunInput: Codable, Hashable {
    var nodeId: UUID
    var runId: UUID
    var level: Int
    var parentOutputs: [WorkflowParentOutput] = []
    var edgeInputs: [WorkflowEdgeRunInput] = []
    var spatialArtifactInputs: [SpatialArtifactInput] = []
    var allIncomingArtifacts: [String] = []
    var runInputs: [String: String] = [:]
    var variables: [String: String] = [:]
    var secretNames: [String] = []
    var consistencyContext = ConsistencyContext()
    var useDefaultLLM: Bool?
    var consistencyWriteConfig: ConsistencyNodeConfiguration?
    var specialTemplatePrompt = ""
    var finalPrompt = ""
}

enum WorkflowLogLevel: String, Codable, Hashable, CaseIterable, Identifiable {
    case info
    case warning
    case error

    var id: String { rawValue }
}

struct WorkflowNodeRunRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var nodeId: UUID
    var level = 0
    var status: WorkflowNodeRunStatus
    var startedAt: Date?
    var completedAt: Date?
    var input: WorkflowNodeRunInput?
    var inputAssetPaths: [String] = []
    var outputAssetPaths: [String] = []
    var outputText = ""
    var outputJSON = ""
    var error: String?
    var logs: [String] = []
    var message: String = ""
    var absorbedAssetsCount = 0
    var createdConsistencyAssetIds: [UUID] = []
    var updatedConsistencyAssetIds: [UUID] = []
    var skippedAssets: [String] = []
    var conflicts: [ConsistencyConflict] = []
    var consistencyValidation: ConsistencyValidationResult?

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId
        case level
        case status
        case startedAt
        case completedAt
        case input
        case inputAssetPaths
        case outputAssetPaths
        case outputText
        case outputJSON
        case error
        case logs
        case message
        case absorbedAssetsCount
        case createdConsistencyAssetIds
        case updatedConsistencyAssetIds
        case skippedAssets
        case conflicts
        case consistencyValidation
    }

    init(
        id: UUID = UUID(),
        nodeId: UUID,
        level: Int = 0,
        status: WorkflowNodeRunStatus,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        input: WorkflowNodeRunInput? = nil,
        inputAssetPaths: [String] = [],
        outputAssetPaths: [String] = [],
        outputText: String = "",
        outputJSON: String = "",
        error: String? = nil,
        logs: [String] = [],
        message: String = "",
        absorbedAssetsCount: Int = 0,
        createdConsistencyAssetIds: [UUID] = [],
        updatedConsistencyAssetIds: [UUID] = [],
        skippedAssets: [String] = [],
        conflicts: [ConsistencyConflict] = [],
        consistencyValidation: ConsistencyValidationResult? = nil
    ) {
        self.id = id
        self.nodeId = nodeId
        self.level = level
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.input = input
        self.inputAssetPaths = inputAssetPaths
        self.outputAssetPaths = outputAssetPaths
        self.outputText = outputText
        self.outputJSON = outputJSON
        self.error = error
        self.logs = logs
        self.message = message
        self.absorbedAssetsCount = absorbedAssetsCount
        self.createdConsistencyAssetIds = createdConsistencyAssetIds
        self.updatedConsistencyAssetIds = updatedConsistencyAssetIds
        self.skippedAssets = skippedAssets
        self.conflicts = conflicts
        self.consistencyValidation = consistencyValidation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nodeId = try container.decode(UUID.self, forKey: .nodeId)
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 0
        status = try container.decodeIfPresent(WorkflowNodeRunStatus.self, forKey: .status) ?? .pending
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        input = try container.decodeIfPresent(WorkflowNodeRunInput.self, forKey: .input)
        inputAssetPaths = try container.decodeIfPresent([String].self, forKey: .inputAssetPaths) ?? []
        outputAssetPaths = try container.decodeIfPresent([String].self, forKey: .outputAssetPaths) ?? []
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText) ?? ""
        outputJSON = try container.decodeIfPresent(String.self, forKey: .outputJSON) ?? ""
        error = try container.decodeIfPresent(String.self, forKey: .error)
        logs = try container.decodeIfPresent([String].self, forKey: .logs) ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        absorbedAssetsCount = try container.decodeIfPresent(Int.self, forKey: .absorbedAssetsCount) ?? 0
        createdConsistencyAssetIds = try container.decodeIfPresent([UUID].self, forKey: .createdConsistencyAssetIds) ?? []
        updatedConsistencyAssetIds = try container.decodeIfPresent([UUID].self, forKey: .updatedConsistencyAssetIds) ?? []
        skippedAssets = try container.decodeIfPresent([String].self, forKey: .skippedAssets) ?? []
        conflicts = try container.decodeIfPresent([ConsistencyConflict].self, forKey: .conflicts) ?? []
        consistencyValidation = try container.decodeIfPresent(ConsistencyValidationResult.self, forKey: .consistencyValidation)
    }
}

struct WorkflowLogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var level: WorkflowLogLevel
    var nodeId: UUID?
    var message: String
}

struct WorkflowRunState: Codable, Hashable {
    var runId: UUID?
    var status: WorkflowRunStatus = .idle
    var startedAt: Date?
    var completedAt: Date?
    var currentLevel = 0
    var continuousRunNodes = true
    var runInputs: [String: String] = [:]
    var levelStatuses: [Int: WorkflowLevelStatus] = [:]
    var resolvedSpatialArtifactRoutes: [SpatialArtifactRoute] = []
    var runConsistencySnapshot: [ConsistencyAsset] = []
    var runConsistencyDelta: [ConsistencyAsset] = []
    var activeNodeIds: Set<UUID> = []
    var reviewNodeIds: Set<UUID> = []
    var records: [WorkflowNodeRunRecord] = []
    var logs: [WorkflowLogEntry] = []
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case runId
        case status
        case startedAt
        case completedAt
        case currentLevel
        case continuousRunNodes
        case runInputs
        case levelStatuses
        case resolvedSpatialArtifactRoutes
        case runConsistencySnapshot
        case runConsistencyDelta
        case activeNodeIds
        case reviewNodeIds
        case records
        case logs
        case lastError
    }

    init(
        runId: UUID? = nil,
        status: WorkflowRunStatus = .idle,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        currentLevel: Int = 0,
        continuousRunNodes: Bool = true,
        runInputs: [String: String] = [:],
        levelStatuses: [Int: WorkflowLevelStatus] = [:],
        resolvedSpatialArtifactRoutes: [SpatialArtifactRoute] = [],
        runConsistencySnapshot: [ConsistencyAsset] = [],
        runConsistencyDelta: [ConsistencyAsset] = [],
        activeNodeIds: Set<UUID> = [],
        reviewNodeIds: Set<UUID> = [],
        records: [WorkflowNodeRunRecord] = [],
        logs: [WorkflowLogEntry] = [],
        lastError: String? = nil
    ) {
        self.runId = runId
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.currentLevel = currentLevel
        self.continuousRunNodes = continuousRunNodes
        self.runInputs = runInputs
        self.levelStatuses = levelStatuses
        self.resolvedSpatialArtifactRoutes = resolvedSpatialArtifactRoutes
        self.runConsistencySnapshot = runConsistencySnapshot
        self.runConsistencyDelta = runConsistencyDelta
        self.activeNodeIds = activeNodeIds
        self.reviewNodeIds = reviewNodeIds
        self.records = records
        self.logs = logs
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try container.decodeIfPresent(UUID.self, forKey: .runId)
        status = try container.decodeIfPresent(WorkflowRunStatus.self, forKey: .status) ?? .idle
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        currentLevel = try container.decodeIfPresent(Int.self, forKey: .currentLevel) ?? 0
        continuousRunNodes = try container.decodeIfPresent(Bool.self, forKey: .continuousRunNodes) ?? true
        runInputs = try container.decodeIfPresent([String: String].self, forKey: .runInputs) ?? [:]
        levelStatuses = try container.decodeIfPresent([Int: WorkflowLevelStatus].self, forKey: .levelStatuses) ?? [:]
        resolvedSpatialArtifactRoutes = try container.decodeIfPresent([SpatialArtifactRoute].self, forKey: .resolvedSpatialArtifactRoutes) ?? []
        runConsistencySnapshot = try container.decodeIfPresent([ConsistencyAsset].self, forKey: .runConsistencySnapshot) ?? []
        runConsistencyDelta = try container.decodeIfPresent([ConsistencyAsset].self, forKey: .runConsistencyDelta) ?? []
        activeNodeIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .activeNodeIds) ?? []
        reviewNodeIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .reviewNodeIds) ?? []
        records = try container.decodeIfPresent([WorkflowNodeRunRecord].self, forKey: .records) ?? []
        logs = try container.decodeIfPresent([WorkflowLogEntry].self, forKey: .logs) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct WorkflowVariable: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var value: String
    var notes: String = ""
    var isEnabled = true
}

struct WorkflowSecret: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var value: String
    var notes: String = ""
    var isEnabled = true
}

struct WorkflowDebugSettings: Codable, Hashable {
    var verboseLogging = true
    var keepRunLogs = true
    var maxLogEntries = 500
}

struct WorkspaceLocation: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var metadataPath: String?

    var displayPath: String {
        NSString(string: path).abbreviatingWithTildeInPath
    }

    var workflowDirectoryName: String {
        ".workflow-\(name)"
    }
}

enum SettingsTab: Hashable {
    case general
    case appearance
    case providers
    case models
    case workflow
    case agents
    case reset
}

struct SettingsSelection: Hashable {
    var tab: SettingsTab = .general
    var modelId: UUID?
}

struct AppConfiguration: Codable, Hashable {
    var models: [ModelConfig] = ModelConfig.defaults
    var providers: [ProviderConfig] = ProviderConfig.defaults
    var endpointProfiles: [EndpointProfile] = []
    var modelCapabilities: [ModelCapability] = []
    var parameterSchemas: [ParameterSchema] = ParameterSchema.genericDefaults
    var capabilityDetectionRules: [CapabilityDetectionRule] = CapabilityDetectionRule.defaults
    var modelRegistrations: [ModelRegistration] = []
    var modelInferenceRules: [ModelInferenceRule] = ModelInferenceRule.defaults
    var language: AppLanguage = .zhCN
    var defaultModelId: UUID?
    var agents: [AgentConfig] = AgentConfig.candidates
    var workspaces: [WorkspaceLocation] = []
    var selectedWorkspaceId: UUID?
    var selectedCanvasTool: CanvasTool = .select
    var showsCanvasGrid = true
    var locksNodeInspectorAutoOpen = false
    var artboardPreset: ArtboardPreset = .square
    var boardSettings = CanvasBoardSettings()
    var workflow = WorkflowDocument()
    var workflowVariables: [WorkflowVariable] = []
    var workflowSecrets: [WorkflowSecret] = []
    var workflowDebugSettings = WorkflowDebugSettings()

    enum CodingKeys: String, CodingKey {
        case models
        case providers
        case endpointProfiles
        case modelCapabilities
        case parameterSchemas
        case capabilityDetectionRules
        case modelRegistrations
        case modelInferenceRules
        case language
        case defaultModelId
        case agents
        case workspaces
        case selectedWorkspaceId
        case selectedCanvasTool
        case showsCanvasGrid
        case locksNodeInspectorAutoOpen
        case artboardPreset
        case boardSettings
        case workflow
        case workflowVariables
        case workflowSecrets
        case workflowDebugSettings
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([ModelConfig].self, forKey: .models) ?? ModelConfig.defaults
        providers = try container.decodeIfPresent([ProviderConfig].self, forKey: .providers) ?? ProviderConfig.defaults
        endpointProfiles = try container.decodeIfPresent([EndpointProfile].self, forKey: .endpointProfiles) ?? []
        modelCapabilities = try container.decodeIfPresent([ModelCapability].self, forKey: .modelCapabilities) ?? []
        parameterSchemas = try container.decodeIfPresent([ParameterSchema].self, forKey: .parameterSchemas) ?? ParameterSchema.genericDefaults
        capabilityDetectionRules = try container.decodeIfPresent([CapabilityDetectionRule].self, forKey: .capabilityDetectionRules) ?? CapabilityDetectionRule.defaults
        modelRegistrations = try container.decodeIfPresent([ModelRegistration].self, forKey: .modelRegistrations) ?? []
        modelInferenceRules = try container.decodeIfPresent([ModelInferenceRule].self, forKey: .modelInferenceRules) ?? ModelInferenceRule.defaults
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhCN
        defaultModelId = try container.decodeIfPresent(UUID.self, forKey: .defaultModelId)
        agents = try container.decodeIfPresent([AgentConfig].self, forKey: .agents) ?? AgentConfig.candidates
        workspaces = try container.decodeIfPresent([WorkspaceLocation].self, forKey: .workspaces) ?? []
        selectedWorkspaceId = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceId)
        selectedCanvasTool = try container.decodeIfPresent(CanvasTool.self, forKey: .selectedCanvasTool) ?? .select
        showsCanvasGrid = try container.decodeIfPresent(Bool.self, forKey: .showsCanvasGrid) ?? true
        locksNodeInspectorAutoOpen = try container.decodeIfPresent(Bool.self, forKey: .locksNodeInspectorAutoOpen) ?? false
        artboardPreset = try container.decodeIfPresent(ArtboardPreset.self, forKey: .artboardPreset) ?? .square
        boardSettings = try container.decodeIfPresent(CanvasBoardSettings.self, forKey: .boardSettings) ?? CanvasBoardSettings()
        workflow = try container.decodeIfPresent(WorkflowDocument.self, forKey: .workflow) ?? WorkflowDocument()
        workflowVariables = try container.decodeIfPresent([WorkflowVariable].self, forKey: .workflowVariables) ?? []
        workflowSecrets = try container.decodeIfPresent([WorkflowSecret].self, forKey: .workflowSecrets) ?? []
        workflowDebugSettings = try container.decodeIfPresent(WorkflowDebugSettings.self, forKey: .workflowDebugSettings) ?? WorkflowDebugSettings()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(models, forKey: .models)
        try container.encode(providers, forKey: .providers)
        try container.encode(endpointProfiles, forKey: .endpointProfiles)
        try container.encode(modelCapabilities, forKey: .modelCapabilities)
        try container.encode(parameterSchemas, forKey: .parameterSchemas)
        try container.encode(capabilityDetectionRules, forKey: .capabilityDetectionRules)
        try container.encode(modelRegistrations, forKey: .modelRegistrations)
        try container.encode(modelInferenceRules, forKey: .modelInferenceRules)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(defaultModelId, forKey: .defaultModelId)
        try container.encode(agents, forKey: .agents)
        try container.encode(workspaces, forKey: .workspaces)
        try container.encodeIfPresent(selectedWorkspaceId, forKey: .selectedWorkspaceId)
        try container.encode(selectedCanvasTool, forKey: .selectedCanvasTool)
        try container.encode(showsCanvasGrid, forKey: .showsCanvasGrid)
        try container.encode(locksNodeInspectorAutoOpen, forKey: .locksNodeInspectorAutoOpen)
        try container.encode(artboardPreset, forKey: .artboardPreset)
        try container.encode(boardSettings, forKey: .boardSettings)
    }
}
