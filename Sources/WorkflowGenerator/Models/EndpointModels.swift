import Foundation

// MARK: - Endpoint Kinds

enum ModelEndpointKind: String, Codable, CaseIterable, Identifiable {
    case chatCompletions
    case responses
    case imageGeneration
    case imageEdit
    case videoTask
    case audioTranscription
    case audioSpeech
    case embeddings
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .chatCompletions: "Chat Completions"
        case .responses: "Responses"
        case .imageGeneration: "Image Generation"
        case .imageEdit: "Image Edit"
        case .videoTask: "Video Task"
        case .audioTranscription: "Audio Transcription"
        case .audioSpeech: "Audio Speech"
        case .embeddings: "Embeddings"
        case .custom: "Custom Endpoint"
        }
    }

    var defaultPath: String {
        switch self {
        case .chatCompletions: "/chat/completions"
        case .responses: "/responses"
        case .imageGeneration: "/images/generations"
        case .imageEdit: "/images/edits"
        case .videoTask: "/contents/generations/tasks"
        case .audioTranscription: "/audio/transcriptions"
        case .audioSpeech: "/audio/speech"
        case .embeddings: "/embeddings"
        case .custom: ""
        }
    }
}

// MARK: - Endpoint Configuration

enum EndpointTaskGroup: String, Codable, CaseIterable, Identifiable {
    case chat
    case image
    case video
    case audioVideo = "audio_video"
    case audio
    case embedding
    case rerank
    case music
    case threeD = "three_d"
    case file
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .audioVideo: "Audio-Video"
        case .threeD: "3D"
        default: rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }
}

enum EndpointHTTPMethod: String, Codable, CaseIterable, Identifiable {
    case get = "GET"
    case post = "POST"
    var id: String { rawValue }
}

enum EndpointMode: String, Codable, CaseIterable, Identifiable {
    case sync
    case async
    case streaming
    case websocket
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum EndpointRequestContentType: String, Codable, CaseIterable, Identifiable {
    case json = "application/json"
    case multipart = "multipart/form-data"
    case octetStream = "application/octet-stream"
    var id: String { rawValue }
    var title: String { rawValue }
}

enum EndpointAuthType: String, Codable, CaseIterable, Identifiable {
    case inheritFromProvider = "inherit_from_provider"
    case bearer
    case apiKeyHeader = "api_key_header"
    case queryKey = "query_key"
    case custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inheritFromProvider: "Inherit from provider"
        case .bearer: "Bearer"
        case .apiKeyHeader: "API Key Header"
        case .queryKey: "Query Key"
        case .custom: "Custom"
        }
    }
}

enum EndpointProfileSource: String, Codable, CaseIterable, Identifiable {
    case systemPreset = "system_preset"
    case userCustom = "user_custom"
    case migrated
    case imported
    var id: String { rawValue }
}

enum DocsStatus: String, Codable, CaseIterable, Identifiable {
    case verified
    case needsReview = "needs_review"
    case unknown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .verified: "Verified"
        case .needsReview: "Needs Review"
        case .unknown: "Unknown"
        }
    }
}

struct EndpointDocsMetadata: Codable, Hashable {
    var title = ""
    var url = ""
    var checkedAt = ""
    var status: DocsStatus = .unknown
    var notes = ""
}

struct EndpointRegion: Identifiable, Codable, Hashable {
    var id: String { regionId }
    var regionId: String
    var label: String
    var baseURL: String
    var notes = ""
}

struct RegionPolicy: Codable, Hashable {
    var requiresSameRegionApiKey = false
    var supportedRegions: [EndpointRegion] = []
}

// MARK: - Model Task

enum ModelTask: String, Codable, CaseIterable, Identifiable, Hashable {
    case chat
    case reasoningChat = "reasoning_chat"
    case agentChat = "agent_chat"
    case visionChat = "vision_chat"
    case videoUnderstanding = "video_understanding"
    case audioUnderstanding = "audio_understanding"
    case documentUnderstanding = "document_understanding"
    case omniChat = "omni_chat"
    case structuredOutput = "structured_output"
    case toolCall = "tool_call"
    case textToImage = "text_to_image"
    case imageToImage = "image_to_image"
    case imageEdit = "image_edit"
    case imageVariation = "image_variation"
    case imageInpaint = "image_inpaint"
    case imageOutpaint = "image_outpaint"
    case imageProcess = "image_process"
    case ocr
    case textToVideo = "text_to_video"
    case imageToVideo = "image_to_video"
    case videoToVideo = "video_to_video"
    case referenceToVideo = "reference_to_video"
    case videoEdit = "video_edit"
    case textToAudioVideo = "text_to_audiovideo"
    case imageToAudioVideo = "image_to_audiovideo"
    case audioToAudioVideo = "audio_to_audiovideo"
    case videoToAudioVideo = "video_to_audiovideo"
    case multimodalToAudioVideo = "multimodal_to_audiovideo"
    case lipSync = "lip_sync"
    case audioDrivenVideo = "audio_driven_video"
    case textToSpeech = "text_to_speech"
    case speechToText = "speech_to_text"
    case speechToSpeech = "speech_to_speech"
    case audioTranslation = "audio_translation"
    case audioCaptioning = "audio_captioning"
    case liveTranslate = "live_translate"
    case embeddingText = "embedding_text"
    case embeddingMultimodal = "embedding_multimodal"
    case rerank
    case musicGeneration = "music_generation"
    case textTo3D = "text_to_3d"
    case imageTo3D = "image_to_3d"
    case fileUpload = "file_upload"
    case unknown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .textTo3D: "Text to 3D"
        case .imageTo3D: "Image to 3D"
        case .audioToAudioVideo: "Audio to AudioVideo"
        case .imageToAudioVideo: "Image to AudioVideo"
        case .multimodalToAudioVideo: "Multimodal to AudioVideo"
        case .textToAudioVideo: "Text to AudioVideo"
        case .videoToAudioVideo: "Video to AudioVideo"
        default:
            rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }

    var taskGroup: EndpointTaskGroup {
        switch self {
        case .chat, .reasoningChat, .agentChat, .visionChat, .videoUnderstanding, .audioUnderstanding, .documentUnderstanding, .omniChat, .structuredOutput, .toolCall: .chat
        case .textToImage, .imageToImage, .imageEdit, .imageVariation, .imageInpaint, .imageOutpaint, .imageProcess, .ocr: .image
        case .textToVideo, .imageToVideo, .videoToVideo, .referenceToVideo, .videoEdit: .video
        case .textToAudioVideo, .imageToAudioVideo, .audioToAudioVideo, .videoToAudioVideo, .multimodalToAudioVideo, .lipSync, .audioDrivenVideo: .audioVideo
        case .textToSpeech, .speechToText, .speechToSpeech, .audioTranslation, .audioCaptioning, .liveTranslate: .audio
        case .embeddingText, .embeddingMultimodal: .embedding
        case .rerank: .rerank
        case .musicGeneration: .music
        case .textTo3D, .imageTo3D: .threeD
        case .fileUpload: .file
        case .unknown: .custom
        }
    }

    var defaultInputModalities: Set<Modality> {
        switch self {
        case .chat, .reasoningChat, .agentChat, .structuredOutput, .toolCall, .textToImage, .textToVideo, .textToAudioVideo, .textToSpeech, .embeddingText, .rerank, .musicGeneration, .textTo3D: [.text]
        case .visionChat, .imageToImage, .imageEdit, .imageVariation, .imageInpaint, .imageOutpaint, .imageProcess, .imageToVideo, .imageToAudioVideo, .imageTo3D, .ocr: [.text, .image]
        case .videoUnderstanding, .videoToVideo, .videoEdit, .videoToAudioVideo: [.text, .video]
        case .audioUnderstanding, .audioToAudioVideo, .speechToText, .audioTranslation, .audioCaptioning, .speechToSpeech, .liveTranslate: [.audio]
        case .documentUnderstanding, .fileUpload: [.file]
        case .omniChat, .multimodalToAudioVideo: [.text, .image, .audio, .video]
        case .referenceToVideo: [.text, .reference]
        case .lipSync: [.video, .audio]
        case .audioDrivenVideo: [.audio, .image]
        case .embeddingMultimodal: [.text, .image]
        case .unknown: [.unknown]
        }
    }

    var defaultOutputModalities: Set<Modality> {
        switch self {
        case .chat, .reasoningChat, .agentChat, .visionChat, .videoUnderstanding, .audioUnderstanding, .documentUnderstanding, .structuredOutput, .toolCall, .speechToText, .audioTranslation, .audioCaptioning, .ocr: [.text]
        case .omniChat, .speechToSpeech, .liveTranslate: [.text, .audio]
        case .textToImage, .imageToImage, .imageEdit, .imageVariation, .imageInpaint, .imageOutpaint, .imageProcess: [.image]
        case .textToVideo, .imageToVideo, .videoToVideo, .referenceToVideo, .videoEdit: [.video]
        case .textToAudioVideo, .imageToAudioVideo, .audioToAudioVideo, .videoToAudioVideo, .multimodalToAudioVideo, .lipSync, .audioDrivenVideo: [.audioVideo]
        case .textToSpeech: [.audio]
        case .embeddingText, .embeddingMultimodal: [.embedding]
        case .rerank: [.scores]
        case .musicGeneration: [.music, .audio]
        case .textTo3D, .imageTo3D: [.threeD]
        case .fileUpload: [.file]
        case .unknown: [.unknown]
        }
    }

    var legacyEndpointKind: ModelEndpointKind {
        switch self {
        case .chat, .reasoningChat, .agentChat, .visionChat, .videoUnderstanding, .audioUnderstanding, .documentUnderstanding, .omniChat, .structuredOutput, .toolCall: .chatCompletions
        case .textToImage, .imageVariation: .imageGeneration
        case .imageToImage, .imageEdit, .imageInpaint, .imageOutpaint, .imageProcess, .ocr: .imageEdit
        case .textToVideo, .imageToVideo, .videoToVideo, .referenceToVideo, .videoEdit, .textToAudioVideo, .imageToAudioVideo, .audioToAudioVideo, .videoToAudioVideo, .multimodalToAudioVideo, .lipSync, .audioDrivenVideo: .videoTask
        case .textToSpeech: .audioSpeech
        case .speechToText, .speechToSpeech, .audioTranslation, .audioCaptioning, .liveTranslate: .audioTranscription
        case .embeddingText, .embeddingMultimodal: .embeddings
        case .rerank, .musicGeneration, .textTo3D, .imageTo3D, .fileUpload, .unknown: .custom
        }
    }

    var defaultSchemaId: String {
        switch self {
        case .chat: "generic.chat.v1"
        case .reasoningChat: "generic.reasoning_chat.v1"
        case .agentChat: "generic.chat.v1"
        case .visionChat: "generic.vision_chat.v1"
        case .videoUnderstanding: "generic.video_understanding.v1"
        case .audioUnderstanding: "generic.audio_understanding.v1"
        case .documentUnderstanding: "generic.vision_chat.v1"
        case .omniChat: "generic.omni_chat.v1"
        case .structuredOutput, .toolCall: "generic.chat.v1"
        case .textToImage: "generic.text_to_image.v1"
        case .imageToImage, .imageVariation: "generic.image_to_image.v1"
        case .imageEdit, .imageInpaint, .imageOutpaint, .imageProcess: "generic.image_edit.v1"
        case .ocr: "generic.vision_chat.v1"
        case .textToVideo: "generic.text_to_video.v1"
        case .imageToVideo, .referenceToVideo, .videoToVideo, .videoEdit: "generic.image_to_video.v1"
        case .textToAudioVideo, .imageToAudioVideo, .audioToAudioVideo, .videoToAudioVideo, .multimodalToAudioVideo, .audioDrivenVideo: "generic.multimodal_to_audiovideo.v1"
        case .lipSync: "generic.lip_sync.v1"
        case .textToSpeech: "generic.text_to_speech.v1"
        case .speechToText, .speechToSpeech, .audioTranslation, .audioCaptioning, .liveTranslate: "generic.speech_to_text.v1"
        case .embeddingText: "generic.embedding_text.v1"
        case .embeddingMultimodal: "generic.embedding_multimodal.v1"
        case .rerank: "generic.rerank.v1"
        case .musicGeneration: "generic.music_generation.v1"
        case .textTo3D, .imageTo3D: "generic.text_to_3d.v1"
        case .fileUpload, .unknown: "generic.chat.v1"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = raw == "embedding" ? .embeddingText : (ModelTask(rawValue: raw) ?? .unknown)
    }
}

enum ModelSource: String, Codable, CaseIterable, Identifiable {
    case discovered
    case manual
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ModelCapabilityConfidence: String, Codable, CaseIterable, Identifiable {
    case auto
    case manual
    case imported
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// MARK: - Endpoint Profile & Capability

struct ResponseParserConfig: Codable, Hashable {
    var outputTextPath = ""
    var outputImageUrlPath = ""
    var outputVideoUrlPath = ""
    var outputAudioUrlPath = ""
    var taskIdPath = ""
    var errorMessagePath = ""
    var rawResponseMode = false
}

struct PollingConfig: Codable, Hashable {
    var pollingPath = ""
    var pollingMethod: EndpointHTTPMethod = .get
    var pollIntervalMs = 2_000
    var maxPollAttempts = 150
    var successStatusPath = ""
    var successStatusValues: [String] = ["succeeded", "success", "completed"]
    var failureStatusValues: [String] = ["failed", "failure", "cancelled", "expired"]
}

struct EndpointProfile: Identifiable, Codable, Hashable {
    var id: String
    var providerId: UUID
    var name: String
    var taskGroup: EndpointTaskGroup
    var baseURL: String
    var path: String
    var method: EndpointHTTPMethod = .post
    var mode: EndpointMode = .sync
    var requestContentType: EndpointRequestContentType = .json
    var authType: EndpointAuthType = .inheritFromProvider
    var adapterName: String
    var supportedTasks: Set<ModelTask>
    var supportedInputModalities: Set<Modality>?
    var supportedOutputModalities: Set<Modality>?
    var parameterSchemaIds: [String]?
    var requiredHeaders: [String: String]?
    var responseParser = ResponseParserConfig()
    var polling: PollingConfig?
    var enabled = true
    var isProviderDefault = false
    var lastTestStatus = "Not tested"
    var source: EndpointProfileSource?
    var presetKey: String?
    var presetVersion: String?
    var deletedAt: Date?
    var disabledAt: Date?
    var isDeleted: Bool?
    var isRestorable: Bool?
    var lastModifiedByUser: Bool?
    var docs: EndpointDocsMetadata?
    var regionPolicy: RegionPolicy?

    var effectiveSource: EndpointProfileSource { source ?? .migrated }
    var isActive: Bool { enabled && !(isDeleted ?? false) }
    var fullURLPreview: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + (path.hasPrefix("/") ? path : "/\(path)")
    }
}

struct ModelCapabilityOverrides: Codable, Hashable {
    var baseURL = ""
    var path = ""
    var rawPayloadTemplate = "{}"
    var rawRequestJsonPatch = "{}"
    var hasAnyOverride: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        rawPayloadTemplate.trimmingCharacters(in: .whitespacesAndNewlines) != "{}" ||
        rawRequestJsonPatch.trimmingCharacters(in: .whitespacesAndNewlines) != "{}"
    }
}

struct ModelCapability: Identifiable, Codable, Hashable {
    var id = UUID()
    var modelId: UUID
    var task: ModelTask
    var inputModalities: Set<Modality>
    var optionalInputModalities: Set<Modality>?
    var outputModalities: Set<Modality>
    var endpointProfileId: String
    var parameterSchemaId: String
    var defaultParams = "{}"
    var overrides = ModelCapabilityOverrides()
    var confidence: ModelCapabilityConfidence = .auto
    var docsStatus: DocsStatus?
    var enabled = true
}

// MARK: - Parameter Schema

enum ParameterFieldType: String, Codable, CaseIterable, Identifiable {
    case string
    case number
    case integer
    case boolean
    case array
    case object
    var id: String { rawValue }
}

enum ParameterFieldUI: String, Codable, CaseIterable, Identifiable {
    case input
    case textarea
    case select
    case `switch`
    case slider
    case json
    case assetPicker = "asset_picker"
    var id: String { rawValue }
}

struct ParameterField: Codable, Hashable {
    var type: ParameterFieldType
    var title = ""
    var description = ""
    var defaultValue = ""
    var enumValues: [String] = []
    var minimum: Double?
    var maximum: Double?
    var ui: ParameterFieldUI = .input
}

struct ParameterSchema: Identifiable, Codable, Hashable {
    var id: String
    var providerId: UUID?
    var task: ModelTask
    var version: Int
    var fields: [String: ParameterField]
    var required: [String]
    var uiSchema: [String: String] = [:]
    var rawJsonEnabled = false
    var enabled = true
    var docs: EndpointDocsMetadata?
    var optional: [String]?
    var parameterMappingStrategy: String?

    static let genericDefaults: [ParameterSchema] = [
        ParameterSchema(id: "generic.chat.v1", providerId: nil, task: .chat, version: 1, fields: [
            "messages": ParameterField(type: .array, title: "Messages", description: "Conversation messages.", ui: .json),
            "temperature": ParameterField(type: .number, title: "Temperature", description: "Sampling temperature.", defaultValue: "0.7", minimum: 0, maximum: 2, ui: .slider),
            "maxTokens": ParameterField(type: .integer, title: "Max Tokens", description: "Upper limit for generated tokens.", ui: .input),
            "responseFormat": ParameterField(type: .object, title: "Response Format", description: "Optional structured response format.", ui: .json)
        ], required: ["messages"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.vision_chat.v1", providerId: nil, task: .visionChat, version: 1, fields: [
            "messages": ParameterField(type: .array, title: "Messages", description: "Conversation messages.", ui: .json),
            "images": ParameterField(type: .array, title: "Images", description: "Reference images.", ui: .assetPicker),
            "temperature": ParameterField(type: .number, title: "Temperature", defaultValue: "0.7", minimum: 0, maximum: 2, ui: .slider),
            "maxTokens": ParameterField(type: .integer, title: "Max Tokens", ui: .input)
        ], required: ["messages", "images"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.text_to_image.v1", providerId: nil, task: .textToImage, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", description: "Image prompt.", ui: .textarea),
            "size": ParameterField(type: .string, title: "Size", defaultValue: "1024x1024", ui: .select),
            "n": ParameterField(type: .integer, title: "Count", defaultValue: "1", minimum: 1, maximum: 8, ui: .input),
            "seed": ParameterField(type: .integer, title: "Seed", ui: .input),
            "guidanceScale": ParameterField(type: .number, title: "Guidance Scale", ui: .slider)
        ], required: ["prompt"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.image_to_image.v1", providerId: nil, task: .imageToImage, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "image": ParameterField(type: .string, title: "Image", ui: .assetPicker),
            "size": ParameterField(type: .string, title: "Size", defaultValue: "1024x1024", ui: .select),
            "n": ParameterField(type: .integer, title: "Count", defaultValue: "1", minimum: 1, maximum: 8, ui: .input),
            "seed": ParameterField(type: .integer, title: "Seed", ui: .input),
            "strength": ParameterField(type: .number, title: "Strength", defaultValue: "0.65", minimum: 0, maximum: 1, ui: .slider),
            "guidanceScale": ParameterField(type: .number, title: "Guidance Scale", ui: .slider)
        ], required: ["prompt", "image"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.text_to_video.v1", providerId: nil, task: .textToVideo, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "audioUrl": ParameterField(type: .string, title: "Audio URL", description: "Optional soundtrack or reference audio URL.", ui: .assetPicker),
            "duration": ParameterField(type: .integer, title: "Duration", defaultValue: "5", minimum: 1, maximum: 30, ui: .input),
            "resolution": ParameterField(type: .string, title: "Resolution", defaultValue: "1280x720", ui: .select),
            "aspectRatio": ParameterField(type: .string, title: "Aspect Ratio", defaultValue: "16:9", ui: .select),
            "fps": ParameterField(type: .integer, title: "FPS", defaultValue: "24", minimum: 1, maximum: 60, ui: .input),
            "seed": ParameterField(type: .integer, title: "Seed", ui: .input)
        ], required: ["prompt"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.image_to_video.v1", providerId: nil, task: .imageToVideo, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "image": ParameterField(type: .string, title: "Image", ui: .assetPicker),
            "audioUrl": ParameterField(type: .string, title: "Audio URL", description: "Optional soundtrack or reference audio URL.", ui: .assetPicker),
            "duration": ParameterField(type: .integer, title: "Duration", defaultValue: "5", minimum: 1, maximum: 30, ui: .input),
            "resolution": ParameterField(type: .string, title: "Resolution", defaultValue: "1280x720", ui: .select),
            "aspectRatio": ParameterField(type: .string, title: "Aspect Ratio", defaultValue: "16:9", ui: .select),
            "fps": ParameterField(type: .integer, title: "FPS", defaultValue: "24", minimum: 1, maximum: 60, ui: .input),
            "seed": ParameterField(type: .integer, title: "Seed", ui: .input)
        ], required: ["prompt", "image"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.text_to_speech.v1", providerId: nil, task: .textToSpeech, version: 1, fields: [
            "text": ParameterField(type: .string, title: "Text", ui: .textarea),
            "voice": ParameterField(type: .string, title: "Voice", defaultValue: "alloy", ui: .input),
            "format": ParameterField(type: .string, title: "Format", defaultValue: "mp3", ui: .select),
            "speed": ParameterField(type: .number, title: "Speed", defaultValue: "1.0", minimum: 0.25, maximum: 4, ui: .slider)
        ], required: ["text"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.speech_to_text.v1", providerId: nil, task: .speechToText, version: 1, fields: [
            "audio": ParameterField(type: .string, title: "Audio", ui: .assetPicker),
            "language": ParameterField(type: .string, title: "Language", ui: .input)
        ], required: ["audio"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.embedding.v1", providerId: nil, task: .embeddingText, version: 1, fields: [
            "input": ParameterField(type: .string, title: "Input", ui: .textarea),
            "dimensions": ParameterField(type: .integer, title: "Dimensions", ui: .input)
        ], required: ["input"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.embedding_text.v1", providerId: nil, task: .embeddingText, version: 1, fields: [
            "input": ParameterField(type: .string, title: "Input", ui: .textarea),
            "dimensions": ParameterField(type: .integer, title: "Dimensions", ui: .input),
            "encodingFormat": ParameterField(type: .string, title: "Encoding Format", defaultValue: "float", ui: .select)
        ], required: ["input"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.embedding_multimodal.v1", providerId: nil, task: .embeddingMultimodal, version: 1, fields: [
            "texts": ParameterField(type: .array, title: "Texts", ui: .json),
            "images": ParameterField(type: .array, title: "Images", ui: .assetPicker),
            "videos": ParameterField(type: .array, title: "Videos", ui: .assetPicker),
            "dimensions": ParameterField(type: .integer, title: "Dimensions", ui: .input)
        ], required: ["texts"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.rerank.v1", providerId: nil, task: .rerank, version: 1, fields: [
            "query": ParameterField(type: .string, title: "Query", ui: .textarea),
            "documents": ParameterField(type: .array, title: "Documents", ui: .json),
            "topN": ParameterField(type: .integer, title: "Top N", ui: .input),
            "returnDocuments": ParameterField(type: .boolean, title: "Return Documents", ui: .switch)
        ], required: ["query", "documents"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.reasoning_chat.v1", providerId: nil, task: .reasoningChat, version: 1, fields: [
            "messages": ParameterField(type: .array, title: "Messages", ui: .json),
            "reasoningEffort": ParameterField(type: .string, title: "Reasoning Effort", defaultValue: "medium", ui: .select),
            "temperature": ParameterField(type: .number, title: "Temperature", defaultValue: "0.7", minimum: 0, maximum: 2, ui: .slider),
            "maxTokens": ParameterField(type: .integer, title: "Max Tokens", ui: .input)
        ], required: ["messages"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.video_understanding.v1", providerId: nil, task: .videoUnderstanding, version: 1, fields: [
            "messages": ParameterField(type: .array, title: "Messages", ui: .json),
            "videos": ParameterField(type: .array, title: "Videos", ui: .assetPicker),
            "maxTokens": ParameterField(type: .integer, title: "Max Tokens", ui: .input)
        ], required: ["messages", "videos"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.audio_understanding.v1", providerId: nil, task: .audioUnderstanding, version: 1, fields: [
            "messages": ParameterField(type: .array, title: "Messages", ui: .json),
            "audios": ParameterField(type: .array, title: "Audios", ui: .assetPicker),
            "maxTokens": ParameterField(type: .integer, title: "Max Tokens", ui: .input)
        ], required: ["messages", "audios"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.omni_chat.v1", providerId: nil, task: .omniChat, version: 1, fields: [
            "messages": ParameterField(type: .array, title: "Messages", ui: .json),
            "inputAudio": ParameterField(type: .array, title: "Input Audio", ui: .assetPicker),
            "inputImages": ParameterField(type: .array, title: "Input Images", ui: .assetPicker),
            "inputVideo": ParameterField(type: .array, title: "Input Video", ui: .assetPicker),
            "modalities": ParameterField(type: .array, title: "Output Modalities", ui: .json),
            "voice": ParameterField(type: .string, title: "Voice", ui: .input),
            "stream": ParameterField(type: .boolean, title: "Stream", ui: .switch)
        ], required: ["messages"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.image_edit.v1", providerId: nil, task: .imageEdit, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "image": ParameterField(type: .string, title: "Image", ui: .assetPicker),
            "mask": ParameterField(type: .string, title: "Mask", ui: .assetPicker),
            "bbox": ParameterField(type: .object, title: "Bounding Box", ui: .json),
            "referenceImages": ParameterField(type: .array, title: "Reference Images", ui: .assetPicker),
            "editMode": ParameterField(type: .string, title: "Edit Mode", ui: .select),
            "strength": ParameterField(type: .number, title: "Strength", defaultValue: "0.65", minimum: 0, maximum: 1, ui: .slider),
            "seed": ParameterField(type: .integer, title: "Seed", ui: .input),
            "size": ParameterField(type: .string, title: "Size", ui: .select),
            "n": ParameterField(type: .integer, title: "Count", defaultValue: "1", minimum: 1, maximum: 8, ui: .input)
        ], required: ["prompt", "image"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.multimodal_to_audiovideo.v1", providerId: nil, task: .multimodalToAudioVideo, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "images": ParameterField(type: .array, title: "Images", ui: .assetPicker),
            "audios": ParameterField(type: .array, title: "Audios", ui: .assetPicker),
            "videos": ParameterField(type: .array, title: "Videos", ui: .assetPicker),
            "references": ParameterField(type: .array, title: "References", ui: .assetPicker),
            "duration": ParameterField(type: .integer, title: "Duration", defaultValue: "5", minimum: 1, maximum: 30, ui: .input),
            "resolution": ParameterField(type: .string, title: "Resolution", defaultValue: "1280x720", ui: .select),
            "aspectRatio": ParameterField(type: .string, title: "Aspect Ratio", defaultValue: "16:9", ui: .select),
            "fps": ParameterField(type: .integer, title: "FPS", defaultValue: "24", ui: .input),
            "seed": ParameterField(type: .integer, title: "Seed", ui: .input),
            "audioSyncMode": ParameterField(type: .string, title: "Audio Sync Mode", ui: .select),
            "lipSync": ParameterField(type: .boolean, title: "Lip Sync", ui: .switch),
            "watermark": ParameterField(type: .boolean, title: "Watermark", defaultValue: "false", ui: .switch)
        ], required: ["prompt"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.lip_sync.v1", providerId: nil, task: .lipSync, version: 1, fields: [
            "video": ParameterField(type: .string, title: "Video", ui: .assetPicker),
            "audio": ParameterField(type: .string, title: "Audio", ui: .assetPicker),
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "faceRegion": ParameterField(type: .object, title: "Face Region", ui: .json),
            "syncStrength": ParameterField(type: .number, title: "Sync Strength", minimum: 0, maximum: 1, ui: .slider),
            "outputResolution": ParameterField(type: .string, title: "Output Resolution", ui: .select)
        ], required: ["video", "audio"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.music_generation.v1", providerId: nil, task: .musicGeneration, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "lyrics": ParameterField(type: .string, title: "Lyrics", ui: .textarea),
            "referenceAudio": ParameterField(type: .string, title: "Reference Audio", ui: .assetPicker)
        ], required: ["prompt"], rawJsonEnabled: true),
        ParameterSchema(id: "generic.text_to_3d.v1", providerId: nil, task: .textTo3D, version: 1, fields: [
            "prompt": ParameterField(type: .string, title: "Prompt", ui: .textarea),
            "image": ParameterField(type: .string, title: "Image", ui: .assetPicker),
            "format": ParameterField(type: .string, title: "Format", ui: .select)
        ], required: ["prompt"], rawJsonEnabled: true)
    ]
}

// MARK: - Capability Detection

struct InferredCapability: Identifiable, Codable, Hashable {
    var id = UUID()
    var task: ModelTask
    var inputModalities: Set<Modality>
    var optionalInputModalities: Set<Modality>?
    var outputModalities: Set<Modality>
    var endpointPresetKey: String?
    var parameterSchemaId: String?
}

struct CapabilityDetectionRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var providerPattern = ""
    var modelNameIncludes: [String]
    var modelNameRegex = ""
    var inferredCapabilities: [InferredCapability]
    var confidence: ModelCapabilityConfidence = .auto
    var docsStatus: DocsStatus?
    var enabled = true

    static let defaults: [CapabilityDetectionRule] = [
        CapabilityDetectionRule(name: "Seedance 2 AudioVideo", providerPattern: "volc", modelNameIncludes: ["seedance-2", "seedance-2.0"], modelNameRegex: "seedance.*2", inferredCapabilities: [
            InferredCapability(task: .textToAudioVideo, inputModalities: [.text], outputModalities: [.audioVideo], parameterSchemaId: "generic.multimodal_to_audiovideo.v1"),
            InferredCapability(task: .imageToAudioVideo, inputModalities: [.text, .image], outputModalities: [.audioVideo], parameterSchemaId: "generic.multimodal_to_audiovideo.v1"),
            InferredCapability(task: .audioToAudioVideo, inputModalities: [.text, .audio], outputModalities: [.audioVideo], parameterSchemaId: "generic.multimodal_to_audiovideo.v1"),
            InferredCapability(task: .videoToAudioVideo, inputModalities: [.text, .video], outputModalities: [.audioVideo], parameterSchemaId: "generic.multimodal_to_audiovideo.v1"),
            InferredCapability(task: .multimodalToAudioVideo, inputModalities: [.text, .image, .audio, .video], outputModalities: [.audioVideo], parameterSchemaId: "generic.multimodal_to_audiovideo.v1")
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "OpenAI Images", providerPattern: "openai", modelNameIncludes: ["gpt-image", "dall-e", "chatgpt-image"], modelNameRegex: "^(gpt-image|dall-e|chatgpt-image)", inferredCapabilities: [
            InferredCapability(task: .textToImage, inputModalities: [.text], outputModalities: [.image]),
            InferredCapability(task: .imageToImage, inputModalities: [.text, .image], outputModalities: [.image])
        ], docsStatus: .verified),
        CapabilityDetectionRule(name: "OpenAI Sora Videos", providerPattern: "openai", modelNameIncludes: ["sora"], modelNameRegex: "^sora", inferredCapabilities: [
            InferredCapability(task: .textToVideo, inputModalities: [.text], optionalInputModalities: [.image, .video, .reference], outputModalities: [.video]),
            InferredCapability(task: .imageToVideo, inputModalities: [.text, .image], optionalInputModalities: [.reference], outputModalities: [.video])
        ], docsStatus: .verified),
        CapabilityDetectionRule(name: "Image Generation", modelNameIncludes: ["seedream", "qwen-image", "z-image", "flux", "wanx", "wan-image"], inferredCapabilities: [
            InferredCapability(task: .textToImage, inputModalities: [.text], outputModalities: [.image]),
            InferredCapability(task: .imageToImage, inputModalities: [.text, .image], outputModalities: [.image])
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "Video Generation", modelNameIncludes: ["video", "wan", "veo", "kling", "t2v", "i2v", "hailuo"], inferredCapabilities: [
            InferredCapability(task: .textToVideo, inputModalities: [.text], outputModalities: [.video]),
            InferredCapability(task: .imageToVideo, inputModalities: [.text, .image], outputModalities: [.video])
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "Qwen Omni", providerPattern: "aliyun", modelNameIncludes: ["qwen-omni", "qwen3-omni", "omni-realtime"], inferredCapabilities: [
            InferredCapability(task: .omniChat, inputModalities: [.text], optionalInputModalities: [.image, .audio, .video], outputModalities: [.text, .audio], parameterSchemaId: "generic.omni_chat.v1")
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "Vision Understanding", modelNameIncludes: ["vl", "vision", "qwen3-vl"], inferredCapabilities: [
            InferredCapability(task: .visionChat, inputModalities: [.text, .image], optionalInputModalities: [.video, .file], outputModalities: [.text])
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "TTS", modelNameIncludes: ["tts", "speech"], inferredCapabilities: [
            InferredCapability(task: .textToSpeech, inputModalities: [.text], outputModalities: [.audio])
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "Embedding", modelNameIncludes: ["embedding", "embed"], inferredCapabilities: [
            InferredCapability(task: .embeddingText, inputModalities: [.text], outputModalities: [.embedding])
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "Rerank", modelNameIncludes: ["rerank"], inferredCapabilities: [
            InferredCapability(task: .rerank, inputModalities: [.text, .json], outputModalities: [.scores])
        ], docsStatus: .needsReview),
        CapabilityDetectionRule(name: "Music", modelNameIncludes: ["music"], inferredCapabilities: [
            InferredCapability(task: .musicGeneration, inputModalities: [.text], optionalInputModalities: [.audio], outputModalities: [.music, .audio])
        ], docsStatus: .needsReview)
    ]
}
