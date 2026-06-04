import Foundation

enum InputWrapperProtocol: String, CaseIterable, Identifiable {
    case direct
    case openAIMessage
    case openAIResponses
    case volcengineTask
    case aliyunNative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: "Direct"
        case .openAIMessage: "OpenAI Compatible"
        case .openAIResponses: "OpenAI Responses"
        case .volcengineTask: "Volcengine Task"
        case .aliyunNative: "Aliyun Native"
        }
    }
}

struct InputWrapperTemplate: Identifiable, Hashable {
    var id: String
    var title: String
    var protocolFamily: InputWrapperProtocol
    var modalities: Set<Modality>
    var wrapperJSON: String
    var collectsAsArray: Bool
    var help: String
    var docsURL: String?

    func apply(to slot: inout ModelRegistrationInputSlot) {
        slot.valueTemplateJSON = wrapperJSON
        slot.collectsAsArray = collectsAsArray
    }
}

enum InputWrapperTemplateRegistry {
    static let all: [InputWrapperTemplate] = [
        make(
            "direct.value",
            "Direct value",
            .direct,
            Set(Modality.allCases),
            "",
            false,
            "Pass the serialized value directly without an extra JSON wrapper."
        ),

        make("openai.message.text", "Text block", .openAIMessage, [.text], #"{"type":"text","text":"$value"}"#),
        make("openai.message.image_url", "Image URL block", .openAIMessage, [.image, .reference, .mask], #"{"type":"image_url","image_url":{"url":"$value"}}"#),
        make("openai.message.video_url", "Video URL block", .openAIMessage, [.video, .audioVideo], #"{"type":"video_url","video_url":{"url":"$value"}}"#),
        make("openai.message.audio_url", "Audio URL block", .openAIMessage, [.audio, .music], #"{"type":"audio_url","audio_url":{"url":"$value"}}"#),
        make("openai.message.file_url", "File URL block", .openAIMessage, [.file], #"{"type":"file_url","file_url":{"url":"$value"}}"#),

        make("openai.responses.input_text", "Input text", .openAIResponses, [.text], #"{"type":"input_text","text":"$value"}"#),
        make("openai.responses.input_image", "Input image", .openAIResponses, [.image, .reference, .mask], #"{"type":"input_image","image_url":"$value"}"#),
        make("openai.responses.input_file", "Input file", .openAIResponses, [.file], #"{"type":"input_file","file_url":"$value"}"#),

        make("volc.task.text", "Task text", .volcengineTask, [.text], #"{"type":"text","text":"$value"}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),
        make("volc.task.image_url", "Task image", .volcengineTask, [.image, .reference, .mask], #"{"type":"image_url","image_url":{"url":"$value"}}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),
        make("volc.task.video_url", "Task video", .volcengineTask, [.video, .audioVideo], #"{"type":"video_url","video_url":{"url":"$value"}}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),
        make("volc.task.audio_url", "Task audio", .volcengineTask, [.audio, .music], #"{"type":"audio_url","audio_url":{"url":"$value"}}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),
        make("volc.task.reference_image", "Reference image", .volcengineTask, [.image, .reference], #"{"type":"image_url","image_url":{"url":"$value"},"role":"reference_image"}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),
        make("volc.task.reference_video", "Reference video", .volcengineTask, [.video, .reference], #"{"type":"video_url","video_url":{"url":"$value"},"role":"reference_video"}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),
        make("volc.task.reference_audio", "Reference audio", .volcengineTask, [.audio, .reference], #"{"type":"audio_url","audio_url":{"url":"$value"},"role":"reference_audio"}"#, docsURL: "https://www.volcengine.com/docs/82379/1520757"),

        make("aliyun.native.text", "Native text", .aliyunNative, [.text], #"{"text":"$value"}"#, docsURL: "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api"),
        make("aliyun.native.image", "Native image", .aliyunNative, [.image, .reference, .mask], #"{"image":"$value"}"#, docsURL: "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api"),
        make("aliyun.native.video", "Native video", .aliyunNative, [.video, .audioVideo], #"{"video":"$value"}"#, docsURL: "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api"),
        make("aliyun.native.audio", "Native audio", .aliyunNative, [.audio, .music], #"{"audio":"$value"}"#, docsURL: "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api"),
        make("aliyun.native.file", "Native file", .aliyunNative, [.file], #"{"file":"$value"}"#, docsURL: "https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api")
    ]

    static func template(id: String) -> InputWrapperTemplate? {
        all.first { $0.id == id }
    }

    static func recommended(
        for slot: ModelRegistrationInputSlot,
        interfaceTemplateId: String?
    ) -> [InputWrapperTemplate] {
        let preferred = preferredProtocol(for: interfaceTemplateId)
        let matches = templates(for: slot, protocolFamily: preferred)
        return Array((matches + directTemplates(for: slot)).prefix(4))
    }

    static func additional(
        for slot: ModelRegistrationInputSlot,
        interfaceTemplateId: String?
    ) -> [InputWrapperTemplate] {
        let preferred = preferredProtocol(for: interfaceTemplateId)
        let recommendedIds = Set(recommended(for: slot, interfaceTemplateId: interfaceTemplateId).map(\.id))
        return all.filter { template in
            (template.protocolFamily == preferred || template.protocolFamily == .direct)
                && template.modalities.contains(slot.modality)
                && !recommendedIds.contains(template.id)
        }
    }

    private static func preferredProtocol(for interfaceTemplateId: String?) -> InputWrapperProtocol {
        guard let interfaceTemplateId else { return .openAIMessage }
        if interfaceTemplateId == "openai.responses" {
            return .openAIResponses
        }
        if interfaceTemplateId.hasPrefix("volc.seedance") || interfaceTemplateId == "volc.seed3d" {
            return .volcengineTask
        }
        if interfaceTemplateId.hasPrefix("aliyun.multimodal") || interfaceTemplateId.hasPrefix("aliyun.qwen.image") {
            return .aliyunNative
        }
        return .openAIMessage
    }

    private static func templates(
        for slot: ModelRegistrationInputSlot,
        protocolFamily: InputWrapperProtocol
    ) -> [InputWrapperTemplate] {
        all.filter {
            $0.protocolFamily == protocolFamily && $0.modalities.contains(slot.modality)
        }
    }

    private static func directTemplates(for slot: ModelRegistrationInputSlot) -> [InputWrapperTemplate] {
        all.filter {
            $0.protocolFamily == .direct && $0.modalities.contains(slot.modality)
        }
    }

    private static func make(
        _ id: String,
        _ title: String,
        _ protocolFamily: InputWrapperProtocol,
        _ modalities: Set<Modality>,
        _ wrapperJSON: String,
        _ collectsAsArray: Bool = true,
        _ help: String = "Wrap the serialized value using this provider-compatible JSON shape.",
        docsURL: String? = nil
    ) -> InputWrapperTemplate {
        InputWrapperTemplate(
            id: id,
            title: title,
            protocolFamily: protocolFamily,
            modalities: modalities,
            wrapperJSON: wrapperJSON,
            collectsAsArray: collectsAsArray,
            help: help,
            docsURL: docsURL
        )
    }
}
