import Foundation

enum ProviderEndpointPresetRegistry {
    static let presetVersion = "2026.06.04"
    static let checkedAt = "2026-06-04"

    static func profiles(for provider: ProviderConfig) -> [EndpointProfile] {
        switch ProviderEndpointCatalog.normalizedProviderName(provider.name) {
        case "agnes": agnesAI(provider)
        case "openai": openAI(provider)
        case "volc": volcengine(provider)
        case "aliyun": aliyun(provider)
        case "deepseek": deepSeek(provider)
        case "minimax": minimaxChina(provider)
        default: customOpenAICompatible(provider)
        }
    }

    static func profile(provider: ProviderConfig, presetKey: String) -> EndpointProfile? {
        profiles(for: provider).first { $0.presetKey == presetKey || $0.id == presetKey }
    }

    private static func agnesAI(_ provider: ProviderConfig) -> [EndpointProfile] {
        [
            endpoint(provider, "agnes.chat", "Agnes 2.0 Flash Chat Completions", .chat, "https://apihub.agnes-ai.com/v1", "/chat/completions", "GenericOpenAICompatibleChatAdapter", [.chat, .agentChat, .reasoningChat, .structuredOutput, .toolCall], input: [.text], output: [.text, .json], docs: docs("Agnes 2.0 Flash Chat Completions", "https://agnes-ai.com/doc/agnes-20-flash", .verified, notes: "OpenAI-compatible chat endpoint. Supports stream, tools, tool_choice, chat_template_kwargs, and thinking controls.")),
            endpoint(provider, "agnes.image.21", "Agnes Image 2.1 Flash", .image, "https://apihub.agnes-ai.com/v1", "/images/generations", "OpenAIImagesAdapter", [.textToImage, .imageToImage], input: [.text, .image, .reference], output: [.image], docs: docs("Agnes Image 2.1 Flash", "https://agnes-ai.com/doc/agnes-image-21-flash", .verified, notes: "Text-to-image and image-to-image with extra_body.image and URL response format.")),
            endpoint(provider, "agnes.image.20", "Agnes Image 2.0 Flash", .image, "https://apihub.agnes-ai.com/v1", "/images/generations", "OpenAIImagesAdapter", [.imageToImage, .imageEdit], input: [.text, .image, .reference], output: [.image], docs: docs("Agnes Image 2.0 Flash", "https://agnes-ai.com/doc/agnes-image-20-flash", .verified, notes: "Image-to-image and multi-image composition. Use tags [\"img2img\"] with extra_body.image.")),
            endpoint(provider, "agnes.video", "Agnes Video V2.0 Task", .video, "https://apihub.agnes-ai.com/v1", "/videos", "OpenAIVideosAdapter", [.textToVideo, .imageToVideo, .referenceToVideo], input: [.text, .image, .reference], output: [.video], mode: .async, docs: docs("Agnes Video V2.0 Task", "https://agnes-ai.com/doc/agnes-video-v20", .verified, notes: "Asynchronous video task with text, image, multi-image, and keyframe modes."), polling: PollingConfig(pollingPath: "/videos/{task_id}", pollingMethod: .get, successStatusPath: "status", successStatusValues: ["completed", "succeeded"], failureStatusValues: ["failed", "cancelled"]))
        ]
    }

    private static func openAI(_ provider: ProviderConfig) -> [EndpointProfile] {
        [
            endpoint(provider, "openai.responses", "OpenAI Responses", .chat, "https://api.openai.com/v1", "/responses", "OpenAIResponsesAdapter", [.chat, .reasoningChat, .agentChat, .visionChat, .structuredOutput, .toolCall], input: [.text, .image, .file], output: [.text, .json], docs: docs("OpenAI Responses API", "https://platform.openai.com/docs/api-reference/responses/create", .verified)),
            endpoint(provider, "openai.chat", "OpenAI Chat Completions", .chat, "https://api.openai.com/v1", "/chat/completions", "GenericOpenAICompatibleChatAdapter", [.chat, .visionChat, .structuredOutput, .toolCall], input: [.text, .image], output: [.text, .json], docs: docs("OpenAI Chat Completions API", "https://platform.openai.com/docs/api-reference/chat/create", .verified)),
            endpoint(provider, "openai.images", "OpenAI Images", .image, "https://api.openai.com/v1", "/images/generations", "OpenAIImagesAdapter", [.textToImage, .imageToImage, .imageEdit, .imageVariation, .imageInpaint, .imageOutpaint], input: [.text, .image, .mask, .reference], output: [.image], docs: docs("OpenAI Images API", "https://platform.openai.com/docs/api-reference/images", .verified)),
            endpoint(provider, "openai.videos", "OpenAI Videos", .video, "https://api.openai.com/v1", "/videos", "OpenAIVideosAdapter", [.textToVideo, .imageToVideo, .videoEdit, .referenceToVideo], input: [.text, .image, .video, .reference], output: [.video], mode: .async, requestContentType: .multipart, docs: docs("OpenAI Videos API", "https://platform.openai.com/docs/api-reference/videos/create", .verified), polling: PollingConfig(pollingPath: "/videos/{task_id}", pollingMethod: .get, successStatusPath: "status", successStatusValues: ["completed", "succeeded"], failureStatusValues: ["failed", "cancelled"])),
            endpoint(provider, "openai.audio.speech", "OpenAI Audio Speech", .audio, "https://api.openai.com/v1", "/audio/speech", "OpenAIAudioSpeechAdapter", [.textToSpeech], input: [.text], output: [.audio], mode: .streaming, docs: docs("OpenAI Audio Speech API", "https://platform.openai.com/docs/api-reference/audio/createSpeech", .verified)),
            endpoint(provider, "openai.audio.transcriptions", "OpenAI Audio Transcriptions", .audio, "https://api.openai.com/v1", "/audio/transcriptions", "OpenAIAudioTranscriptionAdapter", [.speechToText], input: [.audio], output: [.text], requestContentType: .multipart, docs: docs("OpenAI Audio Transcriptions API", "https://platform.openai.com/docs/api-reference/audio/createTranscription", .verified)),
            endpoint(provider, "openai.embeddings", "OpenAI Embeddings", .embedding, "https://api.openai.com/v1", "/embeddings", "OpenAIEmbeddingsAdapter", [.embeddingText], input: [.text], output: [.embedding], docs: docs("OpenAI Embeddings API", "https://platform.openai.com/docs/api-reference/embeddings/create", .verified))
        ]
    }

    private static func volcengine(_ provider: ProviderConfig) -> [EndpointProfile] {
        [
            endpoint(provider, "volc.chat", "Ark Chat Completions", .chat, "https://ark.cn-beijing.volces.com/api/v3", "/chat/completions", "VolcengineChatAdapter", [.chat, .reasoningChat, .visionChat, .videoUnderstanding, .audioUnderstanding, .documentUnderstanding, .toolCall, .structuredOutput], input: [.text, .image, .video, .audio, .file], output: [.text, .json], docs: docs("火山方舟 Chat API", "https://www.volcengine.com/docs/82379/1302009", .verified)),
            endpoint(provider, "volc.responses", "Ark Responses", .chat, "https://ark.cn-beijing.volces.com/api/v3", "/responses", "VolcengineResponsesAdapter", [.chat, .reasoningChat, .visionChat, .toolCall, .imageProcess], input: [.text, .image, .file], output: [.text, .json, .image], enabled: false, docs: docs("火山方舟 Responses API", "https://www.volcengine.com/docs/82379", .needsReview)),
            endpoint(provider, "volc.seedream.image", "Ark Seedream Image Generation", .image, "https://ark.cn-beijing.volces.com/api/v3", "/images/generations", "VolcengineImageAdapter", [.textToImage, .imageToImage, .imageEdit, .imageVariation], input: [.text, .image, .reference], output: [.image], docs: docs("Seedream Image Generation", "https://www.volcengine.com/docs/82379/1541523", .needsReview)),
            endpoint(provider, "volc.seedance.audiovideo", "Ark Seedance AudioVideo Task", .audioVideo, "https://ark.cn-beijing.volces.com/api/v3", "/contents/generations/tasks", "VolcengineAudioVideoAdapter", [.textToVideo, .imageToVideo, .videoToVideo, .referenceToVideo, .textToAudioVideo, .imageToAudioVideo, .audioToAudioVideo, .videoToAudioVideo, .multimodalToAudioVideo, .lipSync, .audioDrivenVideo], input: [.text, .image, .audio, .video, .reference], output: [.video, .audioVideo], mode: .async, docs: docs("Seedance Video / AudioVideo Task API", "https://www.volcengine.com/docs/82379/1520757", .needsReview), polling: PollingConfig(pollingPath: "/contents/generations/tasks/{task_id}", pollingMethod: .get, successStatusPath: "status", successStatusValues: ["succeeded", "success", "completed"], failureStatusValues: ["failed", "cancelled"])),
            endpoint(provider, "volc.embeddings", "Ark Embedding", .embedding, "https://ark.cn-beijing.volces.com/api/v3", "/embeddings", "VolcengineEmbeddingAdapter", [.embeddingText, .embeddingMultimodal], input: [.text, .image, .video], output: [.embedding], docs: docs("火山方舟 Embedding API", "https://www.volcengine.com/docs/82379", .needsReview)),
            endpoint(provider, "volc.threed", "Ark 3D Generation", .threeD, "https://ark.cn-beijing.volces.com/api/v3", "/contents/generations/tasks", "Volcengine3DAdapter", [.textTo3D, .imageTo3D], input: [.text, .image], output: [.threeD], mode: .async, enabled: false, docs: docs("火山方舟 3D Generation", "https://www.volcengine.com/docs/82379", .needsReview))
        ]
    }

    private static func aliyun(_ provider: ProviderConfig) -> [EndpointProfile] {
        let regions = RegionPolicy(requiresSameRegionApiKey: true, supportedRegions: [
            EndpointRegion(regionId: "cn-beijing", label: "中国站", baseURL: "https://dashscope.aliyuncs.com"),
            EndpointRegion(regionId: "singapore", label: "Singapore", baseURL: "https://dashscope-intl.aliyuncs.com"),
            EndpointRegion(regionId: "us-virginia", label: "US Virginia", baseURL: "https://dashscope-us.aliyuncs.com", notes: "Use official workspace endpoint when required.")
        ])
        var profiles = [
            endpoint(provider, "aliyun.openai.chat", "DashScope OpenAI Compatible Chat", .chat, "https://dashscope.aliyuncs.com/compatible-mode/v1", "/chat/completions", "DashScopeOpenAICompatibleChatAdapter", [.chat, .reasoningChat, .visionChat, .videoUnderstanding, .audioUnderstanding, .omniChat, .structuredOutput, .toolCall], input: [.text, .image, .video, .audio, .file], output: [.text, .json, .audio], docs: docs("百炼 OpenAI 兼容 Chat", "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api", .needsReview)),
            endpoint(provider, "aliyun.responses", "DashScope Responses", .chat, "https://dashscope.aliyuncs.com/compatible-mode/v1", "/responses", "DashScopeResponsesAdapter", [.chat, .reasoningChat, .visionChat, .toolCall, .structuredOutput], input: [.text, .image, .file], output: [.text, .json], enabled: false, docs: docs("百炼 Responses 兼容接口", "https://help.aliyun.com/zh/model-studio", .needsReview)),
            endpoint(provider, "aliyun.text_generation", "DashScope Text Generation", .chat, "https://dashscope.aliyuncs.com", "/api/v1/services/aigc/text-generation/generation", "DashScopeTextGenerationAdapter", [.chat, .reasoningChat], input: [.text], output: [.text, .json], docs: docs("DashScope Text Generation", "https://help.aliyun.com/zh/dashscope/developer-reference/api-details", .needsReview)),
            endpoint(provider, "aliyun.multimodal_generation", "DashScope Multimodal Generation", .chat, "https://dashscope.aliyuncs.com", "/api/v1/services/aigc/multimodal-generation/generation", "DashScopeMultimodalGenerationAdapter", [.visionChat, .videoUnderstanding, .audioUnderstanding, .documentUnderstanding, .ocr], input: [.text, .image, .video, .audio, .file], output: [.text, .json], docs: docs("DashScope Multimodal Generation", "https://help.aliyun.com/zh/dashscope/developer-reference/api-details", .needsReview)),
            endpoint(provider, "aliyun.qwen_omni", "Qwen Omni", .chat, "https://dashscope.aliyuncs.com/compatible-mode/v1", "/chat/completions", "DashScopeQwenOmniAdapter", [.omniChat, .audioUnderstanding, .videoUnderstanding, .speechToSpeech], input: [.text, .image, .audio, .video], output: [.text, .audio], mode: .streaming, docs: docs("Qwen-Omni API", "https://help.aliyun.com/zh/model-studio/qwen-omni", .needsReview)),
            endpoint(provider, "aliyun.image_generation", "DashScope Image Generation", .image, "https://dashscope.aliyuncs.com", "/api/v1/services/aigc/image-generation/generation", "DashScopeImageAdapter", [.textToImage, .imageToImage, .imageEdit, .imageVariation, .imageInpaint], input: [.text, .image, .reference, .mask, .bbox], output: [.image], docs: docs("DashScope Image Generation", "https://help.aliyun.com/zh/model-studio/text-to-image", .needsReview)),
            endpoint(provider, "aliyun.video_task", "DashScope Video Task", .video, "https://dashscope.aliyuncs.com", "/api/v1/services/aigc/video-generation/video-synthesis", "DashScopeVideoTaskAdapter", [.textToVideo, .imageToVideo, .videoToVideo, .referenceToVideo, .videoEdit, .textToAudioVideo, .imageToAudioVideo], input: [.text, .image, .video, .audio, .reference], output: [.video, .audioVideo], mode: .async, requiredHeaders: ["X-DashScope-Async": "enable"], docs: docs("DashScope Video Task", "https://help.aliyun.com/zh/model-studio/video-generation", .needsReview), polling: PollingConfig(pollingPath: "/api/v1/tasks/{task_id}", pollingMethod: .get, pollIntervalMs: 15_000, successStatusPath: "output.task_status", successStatusValues: ["SUCCEEDED", "succeeded"], failureStatusValues: ["FAILED", "CANCELED", "failed"])),
            endpoint(provider, "aliyun.tts", "DashScope TTS", .audio, "https://dashscope.aliyuncs.com", "/api/v1/services/audio/tts/generation", "DashScopeTTSAdapter", [.textToSpeech], input: [.text], output: [.audio], enabled: false, docs: docs("DashScope TTS", "https://help.aliyun.com/zh/model-studio/text-to-speech", .needsReview)),
            endpoint(provider, "aliyun.asr", "DashScope ASR", .audio, "https://dashscope.aliyuncs.com", "/api/v1/services/audio/asr/transcription", "DashScopeASRAdapter", [.speechToText], input: [.audio], output: [.text], enabled: false, docs: docs("DashScope ASR", "https://help.aliyun.com/zh/model-studio/speech-to-text", .needsReview)),
            endpoint(provider, "aliyun.embedding", "DashScope Embedding", .embedding, "https://dashscope.aliyuncs.com", "/api/v1/services/embeddings/text-embedding/text-embedding", "DashScopeEmbeddingAdapter", [.embeddingText, .embeddingMultimodal], input: [.text, .image, .video], output: [.embedding], docs: docs("DashScope Embedding", "https://help.aliyun.com/zh/model-studio/embeddings", .needsReview)),
            endpoint(provider, "aliyun.rerank", "DashScope Rerank", .rerank, "https://dashscope.aliyuncs.com", "/api/v1/services/rerank/text-rerank/text-rerank", "DashScopeRerankAdapter", [.rerank], input: [.text, .json], output: [.scores], docs: docs("DashScope Rerank", "https://help.aliyun.com/zh/model-studio/rerank", .needsReview))
        ]
        profiles = profiles.map { profile in
            var copy = profile
            copy.regionPolicy = regions
            return copy
        }
        return profiles
    }

    private static func deepSeek(_ provider: ProviderConfig) -> [EndpointProfile] {
        [
            endpoint(provider, "deepseek.chat", "DeepSeek OpenAI Compatible Chat", .chat, "https://api.deepseek.com", "/chat/completions", "DeepSeekOpenAIChatAdapter", [.chat, .reasoningChat, .agentChat, .structuredOutput, .toolCall], input: [.text], output: [.text, .json], docs: docs("DeepSeek Chat API", "https://api-docs.deepseek.com/api/create-chat-completion", .verified)),
            endpoint(provider, "deepseek.anthropic", "DeepSeek Anthropic Compatible", .chat, "https://api.deepseek.com/anthropic", "/messages", "DeepSeekAnthropicAdapter", [.chat, .reasoningChat, .agentChat, .toolCall], input: [.text], output: [.text, .json], enabled: false, docs: docs("DeepSeek Anthropic Compatible API", "https://api-docs.deepseek.com", .needsReview))
        ]
    }

    private static func minimaxChina(_ provider: ProviderConfig) -> [EndpointProfile] {
        [
            endpoint(provider, "minimax.chat", "MiniMax Language", .chat, "https://api.minimaxi.com/v1", "/chat/completions", "MiniMaxChatAdapter", [.chat, .agentChat, .toolCall, .structuredOutput], input: [.text], output: [.text, .json], docs: docs("MiniMax OpenAI-Compatible Text API", "https://platform.minimaxi.com/docs/api-reference/text-openai-api", .verified)),
            endpoint(provider, "minimax.tts", "MiniMax TTS", .audio, "https://api.minimaxi.com/v1", "/t2a_v2", "MiniMaxTTSAdapter", [.textToSpeech], input: [.text], output: [.audio], docs: docs("MiniMax T2A", "https://platform.minimaxi.com/docs/api-reference/speech-t2a-http", .verified)),
            endpoint(provider, "minimax.video", "MiniMax Video Generation", .video, "https://api.minimaxi.com/v1", "/video_generation", "MiniMaxVideoAdapter", [.textToVideo, .imageToVideo, .referenceToVideo], input: [.text, .image, .reference], output: [.video], mode: .async, docs: docs("MiniMax Video Generation", "https://platform.minimaxi.com/docs/api-reference/video-generation-t2v", .verified), polling: PollingConfig(pollingPath: "/query/video_generation?task_id={task_id}", pollingMethod: .get, pollIntervalMs: 10_000, successStatusPath: "status", successStatusValues: ["Success", "success"], failureStatusValues: ["Fail", "Failed", "failed"])),
            endpoint(provider, "minimax.image", "MiniMax Image Generation", .image, "https://api.minimaxi.com/v1", "/image_generation", "MiniMaxImageAdapter", [.textToImage, .imageToImage], input: [.text, .image], output: [.image], docs: docs("MiniMax Image Generation", "https://platform.minimaxi.com/docs/api-reference/image-generation", .verified)),
            endpoint(provider, "minimax.music", "MiniMax Music Generation", .music, "https://api.minimaxi.com/v1", "/music_generation", "MiniMaxMusicAdapter", [.musicGeneration], input: [.text, .audio], output: [.music, .audio], mode: .async, docs: docs("MiniMax Music Generation", "https://platform.minimaxi.com/docs/api-reference/music-generation", .verified))
        ]
    }

    private static func customOpenAICompatible(_ provider: ProviderConfig) -> [EndpointProfile] {
        [
            endpoint(provider, "custom.chat", "Chat Completions", .chat, provider.baseURL, "/chat/completions", "GenericOpenAICompatibleChatAdapter", [.chat, .visionChat], input: [.text, .image], output: [.text, .json], docs: docs("Custom OpenAI-Compatible Chat", provider.documentationURL, .unknown)),
            endpoint(provider, "custom.responses", "Responses", .chat, provider.baseURL, "/responses", "OpenAIResponsesAdapter", [.chat, .visionChat, .structuredOutput, .toolCall], input: [.text, .image, .file], output: [.text, .json], enabled: false, docs: docs("Custom Responses", provider.documentationURL, .unknown)),
            endpoint(provider, "custom.embeddings", "Embeddings", .embedding, provider.baseURL, "/embeddings", "GenericOpenAICompatibleEmbeddingAdapter", [.embeddingText], input: [.text], output: [.embedding], enabled: false, docs: docs("Custom Embeddings", provider.documentationURL, .unknown)),
            endpoint(provider, "custom.images", "Images", .image, provider.baseURL, "/images/generations", "OpenAIImagesAdapter", [.textToImage, .imageToImage, .imageEdit], input: [.text, .image, .mask], output: [.image], enabled: false, docs: docs("Custom Images", provider.documentationURL, .unknown)),
            endpoint(provider, "custom.videos", "Videos", .video, provider.baseURL, "/videos", "OpenAIVideosAdapter", [.textToVideo, .imageToVideo], input: [.text, .image, .video], output: [.video], mode: .async, enabled: false, docs: docs("Custom Videos", provider.documentationURL, .unknown)),
            endpoint(provider, "custom.rerank", "Rerank", .rerank, provider.baseURL, "/rerank", "GenericJsonAdapter", [.rerank], input: [.text, .json], output: [.scores], enabled: false, docs: docs("Custom Rerank", provider.documentationURL, .unknown))
        ]
    }

    private static func endpoint(
        _ provider: ProviderConfig,
        _ presetKey: String,
        _ name: String,
        _ taskGroup: EndpointTaskGroup,
        _ baseURL: String,
        _ path: String,
        _ adapterName: String,
        _ tasks: Set<ModelTask>,
        input: Set<Modality>,
        output: Set<Modality>,
        method: EndpointHTTPMethod = .post,
        mode: EndpointMode = .sync,
        requestContentType: EndpointRequestContentType = .json,
        authType: EndpointAuthType = .inheritFromProvider,
        enabled: Bool = true,
        requiredHeaders: [String: String] = [:],
        docs: EndpointDocsMetadata,
        polling: PollingConfig? = nil
    ) -> EndpointProfile {
        var profile = EndpointProfile(
            id: "\(provider.id.uuidString.lowercased()).\(presetKey)",
            providerId: provider.id,
            name: name,
            taskGroup: taskGroup,
            baseURL: baseURL,
            path: path,
            method: method,
            mode: mode,
            requestContentType: requestContentType,
            authType: authType,
            adapterName: adapterName,
            supportedTasks: tasks,
            supportedInputModalities: input,
            supportedOutputModalities: output,
            parameterSchemaIds: Array(Set(tasks.map(\.defaultSchemaId))).sorted(),
            requiredHeaders: requiredHeaders.isEmpty ? nil : requiredHeaders,
            responseParser: ResponseParserConfig(),
            polling: polling,
            enabled: enabled,
            isProviderDefault: enabled,
            lastTestStatus: "Not tested",
            source: .systemPreset,
            presetKey: presetKey,
            presetVersion: presetVersion,
            deletedAt: nil,
            disabledAt: nil,
            isDeleted: !enabled,
            isRestorable: true,
            lastModifiedByUser: false,
            docs: docs,
            regionPolicy: nil
        )
        if mode == .async, profile.polling == nil {
            profile.polling = PollingConfig(pollingPath: "\(path)/{task_id}")
        }
        return profile
    }

    private static func docs(_ title: String, _ url: String, _ status: DocsStatus, notes: String = "") -> EndpointDocsMetadata {
        EndpointDocsMetadata(title: title, url: url, checkedAt: checkedAt, status: status, notes: notes)
    }
}
