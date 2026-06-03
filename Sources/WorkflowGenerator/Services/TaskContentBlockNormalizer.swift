import Foundation

struct TaskContentBlockNormalizer {
    func normalized(_ registration: RegisteredModelInterface) -> RegisteredModelInterface {
        var normalized = registration
        _ = normalize(&normalized)
        return normalized
    }

    func normalize(_ registration: inout RegisteredModelInterface) -> Bool {
        guard registration.path == "/contents/generations/tasks" else { return false }
        var didChange = false

        for index in registration.inputCards.indices {
            guard let field = legacyContentField(registration.inputCards[index].parameterPath) else { continue }
            registration.inputCards[index].parameterPath = "content"
            registration.inputCards[index].collectsAsArray = true
            if registration.inputCards[index].valueTemplateJSON.isEmpty {
                registration.inputCards[index].valueTemplateJSON = contentWrapper(
                    for: field,
                    modality: registration.inputCards[index].modality
                )
            }
            didChange = true
        }

        if let rewritten = replacingAspectRatio(in: registration.defaultRequestJSON),
           rewritten != registration.defaultRequestJSON {
            registration.defaultRequestJSON = rewritten
            didChange = true
        }
        for index in registration.parameters.indices where registration.parameters[index].parameterPath == "aspect_ratio" {
            registration.parameters[index].parameterPath = "ratio"
            didChange = true
        }
        for index in registration.nodeControls.indices where registration.nodeControls[index].parameterPath == "aspect_ratio" {
            registration.nodeControls[index].parameterPath = "ratio"
            didChange = true
        }
        return didChange
    }

    func normalizedOverrides(_ overrides: [String: String], registration: RegisteredModelInterface) -> [String: String] {
        guard registration.path == "/contents/generations/tasks",
              let value = overrides["aspect_ratio"] else {
            return overrides
        }
        var normalized = overrides
        normalized.removeValue(forKey: "aspect_ratio")
        normalized["ratio"] = value
        return normalized
    }

    private func legacyContentField(_ path: String) -> String? {
        let components = path.split(separator: ".").map(String.init)
        guard components.count == 3,
              components[0] == "content",
              components[1] == "0" else {
            return nil
        }
        return components[2]
    }

    private func contentWrapper(for field: String, modality: Modality) -> String {
        switch field {
        case "text":
            #"{"type":"text","text":"$value"}"#
        case "image_url", "reference_url":
            #"{"type":"image_url","image_url":{"url":"$value"}}"#
        case "audio_url":
            #"{"type":"audio_url","audio_url":{"url":"$value"}}"#
        case "video_url":
            #"{"type":"video_url","video_url":{"url":"$value"}}"#
        default:
            modality == .text
                ? #"{"type":"text","text":"$value"}"#
                : #"{"type":"\#(field)","\#(field)":{"url":"$value"}}"#
        }
    }

    private func replacingAspectRatio(in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let aspectRatio = object.removeValue(forKey: "aspect_ratio") else {
            return nil
        }
        object["ratio"] = aspectRatio
        guard let updated = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: updated, encoding: .utf8)
    }
}
