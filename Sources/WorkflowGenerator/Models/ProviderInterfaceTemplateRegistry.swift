import Foundation

struct DocumentationReference: Codable, Hashable {
    var title: String
    var url: String
    var checkedAt: String
    var status: DocsStatus
    var notes = ""
}

struct ProviderInterfaceTemplate: Identifiable, Codable, Hashable {
    var id: String
    var providerKey: String
    var name: String
    var version: String
    var task: ModelTask
    var family: InterfaceFamily
    var docs: DocumentationReference
    var baseURLSuggestion: String?
    var path: String
    var method: EndpointHTTPMethod
    var requestEncoding: RequestEncoding
    var mode: InvocationMode
    var headers: [String: String]
    var defaultRequestJSON: String
    var inputCards: [ModelRegistrationInputSlot]
    var parameters: [RegistrationParameterDefinition]
    var nodeControls: [NodeControlDefinition]
    var outputSlots: [ModelRegistrationOutputSlot]
    var polling: ModelRegistrationPolling?
}

extension RegisteredModelInterface {
    init(
        template: ProviderInterfaceTemplate,
        model: ModelConfig,
        provider: ProviderConfig,
        status: RegistrationStatus = .draft
    ) {
        let suggestedBaseURL = template.baseURLSuggestion ?? provider.baseURL
        let inheritsProviderBaseURL = suggestedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
            provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.init(
            modelId: model.id,
            providerId: provider.id,
            title: template.name,
            templateId: template.id,
            templateVersion: template.version,
            interfaceFamily: template.family,
            inheritsProviderBaseURL: inheritsProviderBaseURL,
            baseURLOverride: suggestedBaseURL,
            path: template.path,
            method: template.method,
            requestEncoding: template.requestEncoding,
            mode: template.mode,
            headers: template.headers,
            defaultRequestJSON: template.defaultRequestJSON,
            inputCards: template.inputCards,
            parameters: template.parameters,
            nodeControls: template.nodeControls,
            outputSlots: template.outputSlots,
            polling: template.polling,
            status: status,
            task: template.task
        )
    }
}

enum ProviderInterfaceTemplateRegistry {
    static let templateVersion = "2026.06.04.2"
    static let checkedAt = "2026-06-04"

    static let all: [ProviderInterfaceTemplate] =
        agnesAI
        + openAI
        + volcengineArk
        + aliyunBailian
        + deepSeek
        + minimaxChina
        + customOpenAICompatible

    static func template(id: String) -> ProviderInterfaceTemplate? {
        all.first { $0.id == id }
    }

    static func recommended(providerKey: String, modelId: String) -> [ProviderInterfaceTemplate] {
        recommendedIds(providerKey: normalizedProviderKey(providerKey), modelId: modelId.lowercased())
            .compactMap(template(id:))
    }

    private static let agnesAI: [ProviderInterfaceTemplate] = [
        make(
            id: "agnes.chat",
            providerKey: "agnes",
            name: "Agnes AI Chat",
            task: .agentChat,
            docs: docs(
                "Agnes AI Chat Completions",
                "https://agnes-ai.com/doc/agnes-20-flash",
                .verified,
                notes: "OpenAI-compatible chat endpoint for agnes-2.0-flash. Supports temperature, top_p, max_tokens, stream, tools, tool_choice, chat_template_kwargs.enable_thinking, and thinking budget fields."
            ),
            baseURL: "https://apihub.agnes-ai.com/v1",
            path: "/chat/completions",
            defaultRequestJSON: #"{"messages":[{"role":"user"}],"temperature":0.7,"max_tokens":1024}"#,
            inputCards: [
                prompt("messages.0.content")
            ],
            nodeControls: [
                slider("temperature", "Temperature", "0.7", minimum: 0, maximum: 2),
                slider("top_p", "Top P", "1", minimum: 0, maximum: 1),
                number("max_tokens", "Max Tokens", "1024", minimum: 1),
                toggle("stream", "Stream", "false"),
                text("tools", "Tools JSON", "[]"),
                text("tool_choice", "Tool Choice JSON", #""auto""#),
                toggle("chat_template_kwargs.enable_thinking", "Enable Thinking", "false"),
                picker("thinking.type", "Thinking", "disabled", ["disabled", "enabled"]),
                number("thinking.budget_tokens", "Thinking Budget", "2048", minimum: 1)
            ],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "agnes.chat.streaming",
            providerKey: "agnes",
            name: "Agnes AI Streaming Chat",
            task: .agentChat,
            docs: docs(
                "Agnes AI Chat Streaming",
                "https://agnes-ai.com/doc/agnes-20-flash",
                .verified,
                notes: "Server-sent events chat template for agnes-2.0-flash with stream enabled by default."
            ),
            baseURL: "https://apihub.agnes-ai.com/v1",
            path: "/chat/completions",
            mode: .sse,
            defaultRequestJSON: #"{"stream":true,"messages":[{"role":"user"}],"temperature":0.7,"max_tokens":1024}"#,
            inputCards: [
                prompt("messages.0.content")
            ],
            nodeControls: [
                slider("temperature", "Temperature", "0.7", minimum: 0, maximum: 2),
                slider("top_p", "Top P", "1", minimum: 0, maximum: 1),
                number("max_tokens", "Max Tokens", "1024", minimum: 1),
                text("tools", "Tools JSON", "[]"),
                text("tool_choice", "Tool Choice JSON", #""auto""#),
                toggle("chat_template_kwargs.enable_thinking", "Enable Thinking", "false"),
                picker("thinking.type", "Thinking", "disabled", ["disabled", "enabled"]),
                number("thinking.budget_tokens", "Thinking Budget", "2048", minimum: 1)
            ],
            outputSlots: [textOutput("choices.0.delta.content")]
        ),
        make(
            id: "agnes.image.21",
            providerKey: "agnes",
            name: "Agnes AI Image 2.1 Flash",
            task: .textToImage,
            family: .special,
            docs: docs(
                "Agnes AI Image 2.1 Flash",
                "https://agnes-ai.com/doc/agnes-image-21-flash",
                .verified,
                notes: "Most advanced Agnes image model. Supports text-to-image and image-to-image with size, extra_body.image, and extra_body.response_format."
            ),
            baseURL: "https://apihub.agnes-ai.com/v1",
            path: "/images/generations",
            defaultRequestJSON: #"{"size":"1024x768","extra_body":{"response_format":"url"}}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Image", "extra_body.image", .image, acceptsMultiple: true)
            ],
            nodeControls: [
                picker("size", "Size", "1024x768", ["1024x768", "1024x1024", "768x1024", "1152x768", "768x1152"]),
                picker("extra_body.response_format", "Response Format", "url", ["url"])
            ],
            outputSlots: [assetOutput("Images", .image, "data.*.url")]
        ),
        make(
            id: "agnes.image.20",
            providerKey: "agnes",
            name: "Agnes AI Image 2.0 Flash",
            task: .imageToImage,
            family: .special,
            docs: docs(
                "Agnes AI Image 2.0 Flash",
                "https://agnes-ai.com/doc/agnes-image-20-flash",
                .verified,
                notes: "Image-to-image and multi-image composition template. Uses tags [\"img2img\"], size, seed, extra_body.image, and extra_body.response_format."
            ),
            baseURL: "https://apihub.agnes-ai.com/v1",
            path: "/images/generations",
            defaultRequestJSON: #"{"tags":["img2img"],"size":"1024x768","extra_body":{"response_format":"url"}}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Input Images", "extra_body.image", .image, acceptsMultiple: true)
            ],
            nodeControls: [
                picker("size", "Size", "1024x768", ["1024x768", "1024x1024", "768x1024", "1152x768", "768x1152"]),
                number("seed", "Seed", "-1"),
                text("tags", "Tags JSON", #"["img2img"]"#),
                picker("extra_body.response_format", "Response Format", "url", ["url"])
            ],
            outputSlots: [assetOutput("Images", .image, "data.*.url")]
        ),
        make(
            id: "agnes.video",
            providerKey: "agnes",
            name: "Agnes AI Video",
            task: .textToVideo,
            family: .special,
            docs: docs(
                "Agnes AI Video Task",
                "https://agnes-ai.com/doc/agnes-video-v20",
                .verified,
                notes: "Most advanced Agnes video model. Async task with prompt, image, keyframes, width, height, num_frames, frame_rate, seed, negative_prompt, mode, and extra_body fields."
            ),
            baseURL: "https://apihub.agnes-ai.com/v1",
            path: "/videos",
            mode: .async,
            defaultRequestJSON: #"{"height":768,"width":1152,"num_frames":121,"frame_rate":24}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Image", "image", .image),
                attachment("Reference Images", "extra_body.image", .reference, acceptsMultiple: true)
            ],
            nodeControls: [
                picker("mode", "Mode", "ti2vid", ["ti2vid", "keyframes"]),
                picker("extra_body.mode", "Extra Mode", "keyframes", ["keyframes"]),
                number("height", "Height", "768", minimum: 1),
                number("width", "Width", "1152", minimum: 1),
                picker("num_frames", "Frames", "121", ["81", "121", "161", "241", "441"]),
                slider("frame_rate", "FPS", "24", minimum: 1, maximum: 60),
                number("seed", "Seed", "-1"),
                text("negative_prompt", "Negative Prompt")
            ],
            outputSlots: [
                taskOutput("id"),
                assetOutput("Video", .video, "video_url"),
                assetOutput("Completed Video", .video, "remixed_from_video_id")
            ],
            polling: polling(taskIdPath: "id", path: "/videos/{task_id}", statusPath: "status")
        )
    ]

    private static let openAI: [ProviderInterfaceTemplate] = [
        make(
            id: "openai.responses",
            providerKey: "openai",
            name: "OpenAI Responses",
            docs: docs("OpenAI Responses API", "https://platform.openai.com/docs/api-reference/responses", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/responses",
            defaultRequestJSON: #"{"input":[{"role":"user"}]}"#,
            inputCards: [
                contentBlock("Prompt", "input.0.content", .prompt, .text, #"{"type":"input_text","text":"$value"}"#, required: true),
                contentBlock("Image", "input.0.content", .attachment, .image, #"{"type":"input_image","image_url":"$value"}"#),
                contentBlock("File", "input.0.content", .attachment, .file, #"{"type":"input_file","file_url":"$value"}"#)
            ],
            outputSlots: [textOutput("output_text")]
        ),
        make(
            id: "openai.chat",
            providerKey: "openai",
            name: "OpenAI Chat Completions",
            docs: docs("OpenAI Chat Completions API", "https://platform.openai.com/docs/api-reference/chat/create", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/chat/completions",
            defaultRequestJSON: #"{"messages":[{"role":"user"}]}"#,
            inputCards: [
                messagePrompt(),
                messageAttachment("Image", .image)
            ],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "openai.images",
            providerKey: "openai",
            name: "OpenAI Images",
            task: .textToImage,
            family: .special,
            docs: docs("OpenAI Images API", "https://platform.openai.com/docs/api-reference/images", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/images/generations",
            defaultRequestJSON: #"{"size":"1024x1024","n":1}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Image", "image", .image),
                attachment("Mask", "mask", .mask)
            ],
            nodeControls: [
                picker("size", "Size", "1024x1024", ["1024x1024", "1536x1024", "1024x1536"]),
                number("n", "Count", "1", minimum: 1, maximum: 10)
            ],
            outputSlots: [assetOutput("Images", .image, "data.*.url")]
        ),
        make(
            id: "openai.videos",
            providerKey: "openai",
            name: "OpenAI Videos",
            task: .textToVideo,
            family: .special,
            docs: docs("OpenAI Videos API", "https://platform.openai.com/docs/api-reference/videos/content", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/videos",
            requestEncoding: .multipart,
            mode: .async,
            defaultRequestJSON: #"{"seconds":"4","size":"720x1280"}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Input Reference", "input_reference", .image)
            ],
            nodeControls: [
                picker("seconds", "Seconds", "4", ["4", "8", "12"]),
                picker("size", "Size", "720x1280", ["720x1280", "1280x720", "1024x1792", "1792x1024"])
            ],
            outputSlots: [
                taskOutput("id"),
                assetOutput("Video", .video, "id")
            ],
            polling: polling(taskIdPath: "id", path: "/videos/{task_id}", statusPath: "status")
        ),
        make(
            id: "openai.audio.speech",
            providerKey: "openai",
            name: "OpenAI Audio Speech",
            task: .textToSpeech,
            family: .special,
            docs: docs("OpenAI Audio Speech API", "https://platform.openai.com/docs/api-reference/audio", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/audio/speech",
            defaultRequestJSON: #"{"voice":"alloy","response_format":"mp3","speed":1}"#,
            inputCards: [prompt("input")],
            nodeControls: [
                text("voice", "Voice", "alloy"),
                picker("response_format", "Format", "mp3", ["mp3", "opus", "aac", "flac", "wav", "pcm"]),
                slider("speed", "Speed", "1", minimum: 0.25, maximum: 4)
            ],
            outputSlots: [assetOutput("Audio", .audio, "$binary")]
        ),
        make(
            id: "openai.audio.transcriptions",
            providerKey: "openai",
            name: "OpenAI Audio Transcriptions",
            task: .speechToText,
            family: .special,
            docs: docs("OpenAI Audio Transcriptions API", "https://platform.openai.com/docs/api-reference/audio", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/audio/transcriptions",
            requestEncoding: .multipart,
            inputCards: [attachment("Audio File", "file", .audio, required: true)],
            outputSlots: [textOutput("text")]
        ),
        make(
            id: "openai.embeddings",
            providerKey: "openai",
            name: "OpenAI Embeddings",
            task: .embeddingText,
            family: .special,
            docs: docs("OpenAI Embeddings API", "https://platform.openai.com/docs/api-reference/embeddings/create", .verified),
            baseURL: "https://api.openai.com/v1",
            path: "/embeddings",
            inputCards: [prompt("input")],
            outputSlots: [assetOutput("Embedding", .embedding, "data.0.embedding")]
        )
    ]

    private static let volcengineArk: [ProviderInterfaceTemplate] = [
        make(
            id: "volc.chat",
            providerKey: "volc",
            name: "Volcengine Ark Chat",
            docs: docs("Volcengine Ark Chat API", "https://www.volcengine.com/docs/82379/1302009", .verified),
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            path: "/chat/completions",
            defaultRequestJSON: #"{"messages":[{"role":"user"}]}"#,
            inputCards: [
                messagePrompt(),
                messageAttachment("Image", .image),
                messageAttachment("Video", .video),
                messageAttachment("Audio", .audio),
                messageAttachment("File", .file)
            ],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "volc.seedream.image",
            providerKey: "volc",
            name: "Volcengine Ark Seedream Image",
            task: .textToImage,
            family: .special,
            docs: docs("Seedream Image Generation", "https://www.volcengine.com/docs/82379/1541523", .needsReview),
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            path: "/images/generations",
            defaultRequestJSON: #"{"size":"2K","n":1,"seed":-1}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Image", "image", .image),
                attachment("Reference", "image", .reference)
            ],
            nodeControls: [
                picker("size", "Size", "2K", ["1K", "2K", "4K"]),
                number("n", "Count", "1", minimum: 1, maximum: 10),
                number("seed", "Seed", "-1")
            ],
            outputSlots: [assetOutput("Images", .image, "data.*.url")]
        ),
        make(
            id: "volc.seedance.audiovideo",
            providerKey: "volc",
            name: "Volcengine Ark Seedance AudioVideo",
            task: .multimodalToAudioVideo,
            family: .special,
            docs: docs(
                "Seedance AudioVideo Task API",
                "https://www.volcengine.com/docs/82379/1520757",
                .needsReview,
                notes: "Review model-specific audio-video fields before promoting this template."
            ),
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            path: "/contents/generations/tasks",
            mode: .async,
            defaultRequestJSON: #"{"duration":5,"ratio":"adaptive","resolution":"720p","generate_audio":true,"seed":-1}"#,
            inputCards: [
                taskContentPrompt(),
                taskContentAttachment("Image", .image),
                taskContentAttachment("Audio", .audio),
                taskContentAttachment("Video", .video)
            ],
            nodeControls: [
                picker("duration", "Duration", "5", ["5", "10"]),
                picker("ratio", "Aspect Ratio", "adaptive", ["adaptive", "16:9", "4:3", "1:1", "3:4", "9:16", "21:9"]),
                picker("resolution", "Resolution", "720p", ["720p", "1080p"]),
                toggle("generate_audio", "Generate Audio", "true"),
                number("seed", "Seed", "-1")
            ],
            outputSlots: [
                taskOutput("id"),
                assetOutput("AudioVideo", .audioVideo, "content.video_url")
            ],
            polling: polling(taskIdPath: "id", path: "/contents/generations/tasks/{task_id}", statusPath: "status")
        ),
        make(
            id: "volc.seed3d",
            providerKey: "volc",
            name: "Volcengine Ark Seed3D",
            task: .imageTo3D,
            family: .special,
            docs: docs("Seed3D API", "https://www.volcengine.com/docs/82379/1856293", .needsReview),
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            path: "/contents/generations/tasks",
            mode: .async,
            inputCards: [
                taskContentPrompt(required: false),
                taskContentAttachment("Image", .image, required: true)
            ],
            outputSlots: [
                taskOutput("id"),
                assetOutput("3D Asset", .threeD, "content.file_url")
            ],
            polling: polling(taskIdPath: "id", path: "/contents/generations/tasks/{task_id}", statusPath: "status")
        )
    ]

    private static let aliyunBailian: [ProviderInterfaceTemplate] = [
        make(
            id: "aliyun.compatible.chat",
            providerKey: "aliyun",
            name: "Aliyun Bailian Compatible Chat",
            docs: docs("Bailian OpenAI-Compatible Chat", "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api", .verified),
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            path: "/chat/completions",
            defaultRequestJSON: #"{"messages":[{"role":"user"}]}"#,
            inputCards: [
                messagePrompt(),
                messageAttachment("Image", .image),
                messageAttachment("File", .file)
            ],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "aliyun.multimodal",
            providerKey: "aliyun",
            name: "Aliyun Bailian Native Multimodal",
            task: .visionChat,
            docs: docs("DashScope Multimodal Generation", "https://help.aliyun.com/zh/dashscope/developer-reference/api-details", .needsReview),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/aigc/multimodal-generation/generation",
            defaultRequestJSON: #"{"input":{"messages":[{"role":"user"}]}}"#,
            inputCards: [
                nativeContentPrompt("input.messages.0.content"),
                nativeContentAttachment("Image", "input.messages.0.content", .image),
                nativeContentAttachment("Video", "input.messages.0.content", .video),
                nativeContentAttachment("Audio", "input.messages.0.content", .audio),
                nativeContentAttachment("File", "input.messages.0.content", .file)
            ],
            outputSlots: [textOutput("output.choices.0.message.content")]
        ),
        make(
            id: "aliyun.qwen.omni",
            providerKey: "aliyun",
            name: "Aliyun Bailian Qwen Omni",
            task: .omniChat,
            docs: docs("Qwen Omni", "https://help.aliyun.com/zh/model-studio/user-guide/qwen-omni", .verified),
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            path: "/chat/completions",
            mode: .sse,
            defaultRequestJSON: #"{"stream":true,"messages":[{"role":"user"}]}"#,
            inputCards: [
                messagePrompt(),
                messageAttachment("Image", .image),
                messageAttachment("Audio", .audio),
                messageAttachment("Video", .video)
            ],
            outputSlots: [
                textOutput("choices.0.delta.content"),
                assetOutput("Audio", .audio, "choices.0.delta.audio.data")
            ]
        ),
        make(
            id: "aliyun.qwen.image",
            providerKey: "aliyun",
            name: "Aliyun Bailian Qwen Image",
            task: .textToImage,
            family: .special,
            docs: docs(
                "Qwen Image API",
                "https://help.aliyun.com/zh/model-studio/qwen-image-api",
                .verified,
                notes: "Synchronous Qwen Image route. Available sizes and image counts vary by selected model generation."
            ),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/aigc/multimodal-generation/generation",
            defaultRequestJSON: #"{"input":{"messages":[{"role":"user"}]},"parameters":{"size":"1328*1328","n":1,"seed":-1}}"#,
            inputCards: [
                nativeContentPrompt("input.messages.0.content"),
                nativeContentAttachment("Image", "input.messages.0.content", .image)
            ],
            nodeControls: [
                text("parameters.size", "Size", "1328*1328"),
                number("parameters.n", "Count", "1", minimum: 1, maximum: 6),
                toggle("parameters.prompt_extend", "Prompt Extend", "true"),
                toggle("parameters.watermark", "Watermark", "false"),
                number("parameters.seed", "Seed", "-1")
            ],
            outputSlots: [assetOutput("Images", .image, "output.choices.*.message.content.*.image")]
        ),
        make(
            id: "aliyun.wan.image",
            providerKey: "aliyun",
            name: "Aliyun Bailian Wan Image",
            task: .textToImage,
            family: .special,
            docs: docs("Wan Image Generation", "https://help.aliyun.com/zh/model-studio/text-to-image-api-reference", .needsReview),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/aigc/text2image/image-synthesis",
            mode: .async,
            headers: ["X-DashScope-Async": "enable"],
            defaultRequestJSON: #"{"parameters":{"size":"1024*1024","n":1,"seed":-1}}"#,
            inputCards: [prompt("input.prompt")],
            nodeControls: [
                text("parameters.size", "Size", "1024*1024"),
                number("parameters.n", "Count", "1", minimum: 1, maximum: 4),
                number("parameters.seed", "Seed", "-1")
            ],
            outputSlots: [
                taskOutput("output.task_id"),
                assetOutput("Images", .image, "output.results.*.url")
            ],
            polling: polling()
        ),
        make(
            id: "aliyun.wan.video",
            providerKey: "aliyun",
            name: "Aliyun Bailian Wan Video",
            task: .textToVideo,
            family: .special,
            docs: docs(
                "Wan Video Generation",
                "https://help.aliyun.com/zh/model-studio/text-to-video-api-reference",
                .verified,
                notes: "Wan 2.7 text-to-video route. Keep model, endpoint region, and API Key in the same region."
            ),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/aigc/video-generation/video-synthesis",
            mode: .async,
            headers: ["X-DashScope-Async": "enable"],
            defaultRequestJSON: #"{"parameters":{"duration":5,"ratio":"16:9","resolution":"720P","prompt_extend":true,"watermark":false}}"#,
            inputCards: [
                prompt("input.prompt"),
                attachment("Image", "input.img_url", .image),
                attachment("Video", "input.video_url", .video),
                attachment("Audio", "input.audio_url", .audio),
                attachment("Reference", "input.reference_url", .reference)
            ],
            nodeControls: [
                number("parameters.duration", "Duration", "5", minimum: 2, maximum: 15),
                picker("parameters.ratio", "Aspect Ratio", "16:9", ["16:9", "9:16", "1:1", "4:3", "3:4"]),
                picker("parameters.resolution", "Resolution", "720P", ["720P", "1080P"]),
                toggle("parameters.prompt_extend", "Prompt Extend", "true"),
                toggle("parameters.watermark", "Watermark", "false"),
                number("parameters.seed", "Seed", "-1", minimum: -1, maximum: 2_147_483_647)
            ],
            outputSlots: [
                taskOutput("output.task_id"),
                assetOutput("Video", .video, "output.video_url")
            ],
            polling: polling(intervalSeconds: 15)
        ),
        make(
            id: "aliyun.tts",
            providerKey: "aliyun",
            name: "Aliyun Bailian TTS",
            task: .textToSpeech,
            family: .special,
            docs: docs("Bailian Text to Speech", "https://help.aliyun.com/zh/model-studio/text-to-speech", .needsReview),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/audio/tts/generation",
            defaultRequestJSON: #"{"voice":"","format":"mp3","speed":1}"#,
            inputCards: [prompt("input.text")],
            nodeControls: [
                text("voice", "Voice"),
                picker("format", "Format", "mp3", ["mp3", "wav", "pcm"]),
                slider("speed", "Speed", "1", minimum: 0.5, maximum: 2)
            ],
            outputSlots: [assetOutput("Audio", .audio, "output.audio.url")]
        ),
        make(
            id: "aliyun.asr",
            providerKey: "aliyun",
            name: "Aliyun Bailian ASR",
            task: .speechToText,
            family: .special,
            docs: docs("Bailian Speech Recognition", "https://help.aliyun.com/zh/model-studio/speech-to-text", .needsReview),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/audio/asr/transcription",
            inputCards: [attachment("Audio", "input.audio_url", .audio, required: true)],
            outputSlots: [textOutput("output.text")]
        ),
        make(
            id: "aliyun.embeddings",
            providerKey: "aliyun",
            name: "Aliyun Bailian Embeddings",
            task: .embeddingText,
            family: .special,
            docs: docs("Bailian Embeddings", "https://help.aliyun.com/zh/model-studio/embedding-and-rerank/", .needsReview),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/embeddings/text-embedding/text-embedding",
            inputCards: [prompt("input.texts")],
            outputSlots: [assetOutput("Embedding", .embedding, "output.embeddings.0.embedding")]
        ),
        make(
            id: "aliyun.rerank",
            providerKey: "aliyun",
            name: "Aliyun Bailian Rerank",
            task: .rerank,
            family: .special,
            docs: docs("Bailian Text Rerank", "https://help.aliyun.com/zh/model-studio/text-rerank-api", .needsReview),
            baseURL: "https://dashscope.aliyuncs.com",
            path: "/api/v1/services/rerank/text-rerank/text-rerank",
            inputCards: [
                prompt("input.query"),
                attachment("Documents", "input.documents", .json, required: true, acceptsMultiple: true)
            ],
            outputSlots: [assetOutput("Scores", .scores, "output.results")]
        )
    ]

    private static let deepSeek: [ProviderInterfaceTemplate] = [
        make(
            id: "deepseek.chat",
            providerKey: "deepseek",
            name: "DeepSeek Chat",
            docs: docs("DeepSeek Chat Completion", "https://api-docs.deepseek.com/api/create-chat-completion", .verified),
            baseURL: "https://api.deepseek.com",
            path: "/chat/completions",
            inputCards: [prompt("messages.0.content")],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "deepseek.reasoning",
            providerKey: "deepseek",
            name: "DeepSeek Reasoning",
            task: .reasoningChat,
            docs: docs("DeepSeek Chat Completion", "https://api-docs.deepseek.com/api/create-chat-completion", .verified),
            baseURL: "https://api.deepseek.com",
            path: "/chat/completions",
            defaultRequestJSON: #"{"thinking":{"type":"enabled"}}"#,
            inputCards: [prompt("messages.0.content")],
            outputSlots: [
                textOutput("choices.0.message.content"),
                ModelRegistrationOutputSlot(label: "Reasoning", kind: .text, modality: .text, jsonPath: "choices.0.message.reasoning_content")
            ]
        )
    ]

    private static let minimaxChina: [ProviderInterfaceTemplate] = [
        make(
            id: "minimax.chat",
            providerKey: "minimax",
            name: "MiniMax China OpenAI-Compatible Chat",
            docs: docs(
                "MiniMax OpenAI-Compatible Text API",
                "https://platform.minimaxi.com/docs/api-reference/text-openai-api",
                .verified
            ),
            baseURL: "https://api.minimaxi.com/v1",
            path: "/chat/completions",
            inputCards: [prompt("messages.0.content")],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "minimax.chat.multimodal",
            providerKey: "minimax",
            name: "MiniMax China M3 Multimodal Chat",
            docs: docs(
                "MiniMax OpenAI-Compatible Text API",
                "https://platform.minimaxi.com/docs/api-reference/text-openai-api",
                .verified,
                notes: "MiniMax-M3 accepts text, image, and video content blocks through Chat Completions."
            ),
            baseURL: "https://api.minimaxi.com/v1",
            path: "/chat/completions",
            defaultRequestJSON: #"{"messages":[{"role":"user"}]}"#,
            inputCards: [
                messagePrompt(),
                messageAttachment("Image", .image),
                messageAttachment("Video", .video)
            ],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "minimax.image",
            providerKey: "minimax",
            name: "MiniMax China Image",
            task: .textToImage,
            family: .special,
            docs: docs("MiniMax Image Generation", "https://platform.minimaxi.com/docs/api-reference/image-generation", .verified),
            baseURL: "https://api.minimaxi.com/v1",
            path: "/image_generation",
            defaultRequestJSON: #"{"aspect_ratio":"1:1","n":1}"#,
            inputCards: [
                prompt("prompt"),
                attachment("Subject Reference", "subject_reference", .image)
            ],
            nodeControls: [
                picker("aspect_ratio", "Aspect Ratio", "1:1", ["1:1", "16:9", "9:16", "4:3", "3:4"]),
                number("n", "Count", "1", minimum: 1, maximum: 4)
            ],
            outputSlots: [assetOutput("Images", .image, "data.image_urls")]
        ),
        make(
            id: "minimax.video",
            providerKey: "minimax",
            name: "MiniMax China Video",
            task: .textToVideo,
            family: .special,
            docs: docs("MiniMax Video Generation", "https://platform.minimaxi.com/docs/api-reference/video-generation-t2v", .verified),
            baseURL: "https://api.minimaxi.com/v1",
            path: "/video_generation",
            mode: .async,
            defaultRequestJSON: #"{"duration":6,"resolution":"1080P"}"#,
            inputCards: [
                prompt("prompt"),
                attachment("First Frame", "first_frame_image", .image),
                attachment("Subject Reference", "subject_reference", .reference)
            ],
            nodeControls: [
                picker("duration", "Duration", "6", ["6", "10"]),
                picker("resolution", "Resolution", "1080P", ["720P", "1080P"])
            ],
            outputSlots: [
                taskOutput("task_id"),
                assetOutput("Video", .video, "file_id")
            ],
            polling: polling(
                taskIdPath: "task_id",
                path: "/query/video_generation?task_id={task_id}",
                statusPath: "status",
                failureValues: ["Fail", "Failed", "failed"],
                intervalSeconds: 10
            )
        ),
        make(
            id: "minimax.tts",
            providerKey: "minimax",
            name: "MiniMax China TTS",
            task: .textToSpeech,
            family: .special,
            docs: docs("MiniMax Synchronous Speech", "https://platform.minimaxi.com/docs/api-reference/speech-t2a-http", .verified),
            baseURL: "https://api.minimaxi.com/v1",
            path: "/t2a_v2",
            defaultRequestJSON: #"{"voice_setting":{"voice_id":"","speed":1},"audio_setting":{"format":"mp3"}}"#,
            inputCards: [prompt("text")],
            nodeControls: [
                text("voice_setting.voice_id", "Voice"),
                picker("audio_setting.format", "Format", "mp3", ["mp3", "wav", "pcm", "flac"]),
                slider("voice_setting.speed", "Speed", "1", minimum: 0.5, maximum: 2)
            ],
            outputSlots: [assetOutput("Audio", .audio, "data.audio")]
        ),
        make(
            id: "minimax.music",
            providerKey: "minimax",
            name: "MiniMax China Music",
            task: .musicGeneration,
            family: .special,
            docs: docs("MiniMax Music Generation", "https://platform.minimaxi.com/docs/api-reference/music-generation", .verified),
            baseURL: "https://api.minimaxi.com/v1",
            path: "/music_generation",
            inputCards: [
                prompt("prompt"),
                attachment("Reference Audio", "reference_audio", .audio)
            ],
            outputSlots: [assetOutput("Music", .music, "data.audio")]
        )
    ]

    private static let customOpenAICompatible: [ProviderInterfaceTemplate] = [
        make(
            id: "custom.chat",
            providerKey: "custom",
            name: "Custom OpenAI-Compatible Chat",
            docs: docs(
                "OpenAI Chat Completions Reference",
                "https://platform.openai.com/docs/api-reference/chat/create",
                .needsReview,
                notes: "Confirm compatibility against the custom provider before use."
            ),
            baseURL: nil,
            path: "/chat/completions",
            inputCards: [prompt("messages.0.content")],
            outputSlots: [textOutput("choices.0.message.content")]
        ),
        make(
            id: "custom.special.sync",
            providerKey: "custom",
            name: "Custom Special Interface",
            task: .unknown,
            family: .special,
            docs: docs("Custom Provider Starting Point", "https://platform.openai.com/docs/api-reference/introduction", .needsReview),
            baseURL: nil,
            path: "",
            inputCards: [],
            outputSlots: []
        ),
        make(
            id: "custom.special.sse",
            providerKey: "custom",
            name: "Custom Streaming Special Interface",
            task: .unknown,
            family: .special,
            docs: docs("Custom Provider Starting Point", "https://platform.openai.com/docs/api-reference/introduction", .needsReview),
            baseURL: nil,
            path: "",
            mode: .sse,
            inputCards: [],
            outputSlots: []
        ),
        make(
            id: "custom.special.websocket",
            providerKey: "custom",
            name: "Custom WebSocket Special Interface",
            task: .unknown,
            family: .special,
            docs: docs("Custom Provider Starting Point", "https://platform.openai.com/docs/api-reference/introduction", .needsReview),
            baseURL: nil,
            path: "",
            mode: .websocket,
            inputCards: [],
            outputSlots: []
        )
    ]

    private static func recommendedIds(providerKey: String, modelId: String) -> [String] {
        switch providerKey {
        case "agnes":
            if modelId.contains("image-2.1") { return ["agnes.image.21"] }
            if modelId.contains("image-2.0") { return ["agnes.image.20"] }
            if modelId.contains("image") { return ["agnes.image.21", "agnes.image.20"] }
            if modelId.contains("video") { return ["agnes.video"] }
            return ["agnes.chat", "agnes.chat.streaming"]
        case "openai":
            if containsAny(modelId, ["gpt-image", "dall-e"]) { return ["openai.images"] }
            if modelId.contains("sora") { return ["openai.videos"] }
            if containsAny(modelId, ["transcribe", "whisper"]) { return ["openai.audio.transcriptions"] }
            if containsAny(modelId, ["tts", "speech"]) { return ["openai.audio.speech"] }
            if modelId.contains("embedding") { return ["openai.embeddings"] }
            return ["openai.responses", "openai.chat"]
        case "volc":
            if modelId.contains("seedream") { return ["volc.seedream.image"] }
            if modelId.contains("seedance-2") { return ["volc.seedance.audiovideo"] }
            if containsAny(modelId, ["seed3d", "3d"]) { return ["volc.seed3d"] }
            return ["volc.chat"]
        case "aliyun":
            if modelId.contains("wan"), containsAny(modelId, ["t2v", "i2v", "r2v", "video"]) {
                return ["aliyun.wan.video"]
            }
            if containsAny(modelId, ["qwen-image", "z-image"]) { return ["aliyun.qwen.image"] }
            if modelId.contains("wan"), modelId.contains("image") { return ["aliyun.wan.image"] }
            if modelId.contains("omni") { return ["aliyun.qwen.omni"] }
            if containsAny(modelId, ["tts", "cosyvoice", "sambert"]) { return ["aliyun.tts"] }
            if containsAny(modelId, ["asr", "paraformer"]) { return ["aliyun.asr"] }
            if modelId.contains("embedding") { return ["aliyun.embeddings"] }
            if modelId.contains("rerank") { return ["aliyun.rerank"] }
            if modelId.contains("vl") { return ["aliyun.multimodal"] }
            return ["aliyun.compatible.chat"]
        case "deepseek":
            return modelId.contains("reason") ? ["deepseek.reasoning"] : ["deepseek.chat"]
        case "minimax":
            if modelId.contains("speech") { return ["minimax.tts"] }
            if containsAny(modelId, ["hailuo", "video"]) { return ["minimax.video"] }
            if modelId.contains("image") { return ["minimax.image"] }
            if modelId.contains("music") { return ["minimax.music"] }
            if modelId.contains("minimax-m3") { return ["minimax.chat.multimodal"] }
            return ["minimax.chat"]
        default:
            return ["custom.chat"]
        }
    }

    private static func normalizedProviderKey(_ providerKey: String) -> String {
        let key = providerKey.lowercased()
        if containsAny(key, ["agnes", "sapiens"]) { return "agnes" }
        if containsAny(key, ["openai"]) { return "openai" }
        if containsAny(key, ["volc", "ark", "火山"]) { return "volc" }
        if containsAny(key, ["aliyun", "dashscope", "bailian", "百炼", "阿里"]) { return "aliyun" }
        if key.contains("deepseek") { return "deepseek" }
        if key.contains("minimax") { return "minimax" }
        return "custom"
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains { value.contains($0) }
    }

    private static func make(
        id: String,
        providerKey: String,
        name: String,
        task: ModelTask = .chat,
        family: InterfaceFamily = .conversation,
        docs: DocumentationReference,
        baseURL: String?,
        path: String,
        method: EndpointHTTPMethod = .post,
        requestEncoding: RequestEncoding = .json,
        mode: InvocationMode = .sync,
        headers: [String: String] = [:],
        defaultRequestJSON: String = "{}",
        inputCards: [ModelRegistrationInputSlot],
        parameters: [RegistrationParameterDefinition] = [],
        nodeControls: [NodeControlDefinition] = [],
        outputSlots: [ModelRegistrationOutputSlot],
        polling: ModelRegistrationPolling? = nil
    ) -> ProviderInterfaceTemplate {
        ProviderInterfaceTemplate(
            id: id,
            providerKey: providerKey,
            name: name,
            version: templateVersion,
            task: task,
            family: family,
            docs: docs,
            baseURLSuggestion: baseURL,
            path: path,
            method: method,
            requestEncoding: requestEncoding,
            mode: mode,
            headers: headers,
            defaultRequestJSON: defaultRequestJSON,
            inputCards: inputCards,
            parameters: parameters.isEmpty ? nodeControls.map(parameter(for:)) : parameters,
            nodeControls: nodeControls,
            outputSlots: outputSlots,
            polling: polling
        )
    }

    private static func docs(
        _ title: String,
        _ url: String,
        _ status: DocsStatus,
        notes: String = ""
    ) -> DocumentationReference {
        DocumentationReference(title: title, url: url, checkedAt: checkedAt, status: status, notes: notes)
    }

    private static func prompt(_ path: String, required: Bool = true) -> ModelRegistrationInputSlot {
        ModelRegistrationInputSlot(label: "Prompt", parameterPath: path, source: .prompt, modality: .text, required: required)
    }

    private static func messagePrompt(_ path: String = "messages.0.content") -> ModelRegistrationInputSlot {
        contentBlock("Prompt", path, .prompt, .text, #"{"type":"text","text":"$value"}"#, required: true)
    }

    private static func messageAttachment(
        _ label: String,
        _ modality: Modality,
        path: String = "messages.0.content"
    ) -> ModelRegistrationInputSlot {
        let wrapper: String
        switch modality {
        case .image, .reference, .mask:
            wrapper = #"{"type":"image_url","image_url":{"url":"$value"}}"#
        case .video, .audioVideo:
            wrapper = #"{"type":"video_url","video_url":{"url":"$value"}}"#
        case .audio, .music:
            wrapper = #"{"type":"audio_url","audio_url":{"url":"$value"}}"#
        case .file:
            wrapper = #"{"type":"file_url","file_url":{"url":"$value"}}"#
        default:
            wrapper = #"{"type":"text","text":"$value"}"#
        }
        return contentBlock(label, path, .attachment, modality, wrapper)
    }

    private static func nativeContentPrompt(_ path: String) -> ModelRegistrationInputSlot {
        contentBlock("Prompt", path, .prompt, .text, #"{"text":"$value"}"#, required: true)
    }

    private static func taskContentPrompt(required: Bool = true) -> ModelRegistrationInputSlot {
        contentBlock("Prompt", "content", .prompt, .text, #"{"type":"text","text":"$value"}"#, required: required)
    }

    private static func taskContentAttachment(
        _ label: String,
        _ modality: Modality,
        required: Bool = false
    ) -> ModelRegistrationInputSlot {
        let wrapper: String
        switch modality {
        case .image, .reference, .mask:
            wrapper = #"{"type":"image_url","image_url":{"url":"$value"}}"#
        case .video, .audioVideo:
            wrapper = #"{"type":"video_url","video_url":{"url":"$value"}}"#
        case .audio, .music:
            wrapper = #"{"type":"audio_url","audio_url":{"url":"$value"}}"#
        default:
            wrapper = #"{"type":"text","text":"$value"}"#
        }
        return contentBlock(label, "content", .attachment, modality, wrapper, required: required)
    }

    private static func nativeContentAttachment(_ label: String, _ path: String, _ modality: Modality) -> ModelRegistrationInputSlot {
        let key: String
        switch modality {
        case .image, .reference, .mask: key = "image"
        case .video, .audioVideo: key = "video"
        case .audio, .music: key = "audio"
        case .file: key = "file"
        default: key = "text"
        }
        return contentBlock(label, path, .attachment, modality, #"{"\#(key)":"$value"}"#)
    }

    private static func contentBlock(
        _ label: String,
        _ path: String,
        _ source: ModelRegistrationSlotSource,
        _ modality: Modality,
        _ wrapper: String,
        required: Bool = false
    ) -> ModelRegistrationInputSlot {
        ModelRegistrationInputSlot(
            label: label,
            parameterPath: path,
            source: source,
            modality: modality,
            required: required,
            collectsAsArray: true,
            valueTemplateJSON: wrapper
        )
    }

    private static func attachment(
        _ label: String,
        _ path: String,
        _ modality: Modality,
        required: Bool = false,
        acceptsMultiple: Bool = false
    ) -> ModelRegistrationInputSlot {
        ModelRegistrationInputSlot(
            label: label,
            parameterPath: path,
            source: .attachment,
            modality: modality,
            required: required,
            acceptsMultiple: acceptsMultiple
        )
    }

    private static func textOutput(_ path: String) -> ModelRegistrationOutputSlot {
        ModelRegistrationOutputSlot(label: "Text", kind: .text, modality: .text, jsonPath: path)
    }

    private static func assetOutput(_ label: String, _ modality: Modality, _ path: String) -> ModelRegistrationOutputSlot {
        ModelRegistrationOutputSlot(label: label, kind: .asset, modality: modality, jsonPath: path)
    }

    private static func taskOutput(_ path: String) -> ModelRegistrationOutputSlot {
        ModelRegistrationOutputSlot(label: "Task ID", kind: .taskId, modality: .json, jsonPath: path)
    }

    private static func polling(
        taskIdPath: String = "output.task_id",
        path: String = "/api/v1/tasks/{task_id}",
        statusPath: String = "output.task_status",
        successValues: [String] = ["SUCCEEDED", "succeeded", "success", "completed"],
        failureValues: [String] = ["FAILED", "failed", "cancelled", "expired"],
        intervalSeconds: Int = 10
    ) -> ModelRegistrationPolling {
        var config = ModelRegistrationPolling()
        config.taskIdPath = taskIdPath
        config.pollingPath = path
        config.statusPath = statusPath
        config.successValues = successValues
        config.failureValues = failureValues
        config.intervalSeconds = intervalSeconds
        return config
    }

    private static func parameter(for control: NodeControlDefinition) -> RegistrationParameterDefinition {
        RegistrationParameterDefinition(
            parameterPath: control.parameterPath,
            title: control.title,
            valueType: control.kind == .toggle ? "boolean" : control.kind == .slider || control.kind == .number ? "number" : "string",
            defaultValue: control.defaultValue,
            help: control.help
        )
    }

    private static func text(_ path: String, _ title: String, _ defaultValue: String = "") -> NodeControlDefinition {
        NodeControlDefinition(parameterPath: path, title: title, kind: .text, defaultValue: defaultValue)
    }

    private static func number(
        _ path: String,
        _ title: String,
        _ defaultValue: String,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> NodeControlDefinition {
        NodeControlDefinition(
            parameterPath: path,
            title: title,
            kind: .number,
            defaultValue: defaultValue,
            minimum: minimum,
            maximum: maximum
        )
    }

    private static func slider(
        _ path: String,
        _ title: String,
        _ defaultValue: String,
        minimum: Double,
        maximum: Double
    ) -> NodeControlDefinition {
        NodeControlDefinition(
            parameterPath: path,
            title: title,
            kind: .slider,
            defaultValue: defaultValue,
            minimum: minimum,
            maximum: maximum
        )
    }

    private static func toggle(_ path: String, _ title: String, _ defaultValue: String) -> NodeControlDefinition {
        NodeControlDefinition(parameterPath: path, title: title, kind: .toggle, defaultValue: defaultValue)
    }

    private static func picker(_ path: String, _ title: String, _ defaultValue: String, _ choices: [String]) -> NodeControlDefinition {
        NodeControlDefinition(parameterPath: path, title: title, kind: .picker, defaultValue: defaultValue, choices: choices)
    }
}
