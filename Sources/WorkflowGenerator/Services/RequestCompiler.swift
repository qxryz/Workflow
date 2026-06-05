import Foundation

struct RequestCompiler {
    func compile(
        baseJSON: String,
        modelPath: String,
        modelId: String,
        matchedValues: [String: Any],
        nodeOverrides: [String: String]
    ) throws -> [String: Any] {
        var payload = try decodeObject(baseJSON)
        set(modelId, at: modelPath, in: &payload)
        for (path, value) in matchedValues {
            set(value, at: path, in: &payload)
        }
        for (path, value) in nodeOverrides {
            set(coerce(value), at: path, in: &payload)
        }
        return payload
    }

    func injectingConversationHistory(
        _ messages: [ChatCompletionMessage],
        into payload: [String: Any],
        inputCards: [ModelRegistrationInputSlot]
    ) -> [String: Any] {
        guard let messagesPath = messagesPath(from: inputCards),
              !messages.isEmpty else {
            return payload
        }
        var updated = payload
        let currentMessages = value(at: messagesPath, in: payload) as? [[String: Any]] ?? []
        let history = messages.dropLast().map { message in
            ["role": message.role, "content": message.content]
        }
        let current = currentMessages.last ?? [
            "role": messages.last?.role ?? "user",
            "content": messages.last?.content ?? ""
        ]
        set(history + [current], at: messagesPath, in: &updated)
        return updated
    }

    private func decodeObject(_ json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}" else { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelRegistrationError.invalidDefaultJSON
        }
        return payload
    }

    private func coerce(_ rawValue: String) -> Any {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return value
        }
        return rawValue
    }

    private func set(_ value: Any, at path: String, in dictionary: inout [String: Any]) {
        let parts = path.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return }
        dictionary = insert(value, parts: parts, current: dictionary) as? [String: Any] ?? dictionary
    }

    private func value(at path: String, in dictionary: [String: Any]) -> Any? {
        path.split(separator: ".").reduce(dictionary as Any?) { current, component in
            guard let current else { return nil }
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                return array[index]
            }
            return (current as? [String: Any])?[String(component)]
        }
    }

    private func messagesPath(from cards: [ModelRegistrationInputSlot]) -> String? {
        for card in cards {
            let components = card.parameterPath.split(separator: ".").map(String.init)
            guard let index = components.firstIndex(of: "messages") else { continue }
            return components[...index].joined(separator: ".")
        }
        return nil
    }

    private func insert(_ value: Any, parts: [String], current: Any) -> Any {
        guard let head = parts.first else { return value }
        let tail = Array(parts.dropFirst())
        if let index = Int(head) {
            var array = current as? [Any] ?? []
            while array.count <= index {
                array.append([String: Any]())
            }
            array[index] = insert(value, parts: tail, current: array[index])
            return array
        }
        var dictionary = current as? [String: Any] ?? [:]
        dictionary[head] = insert(value, parts: tail, current: dictionary[head] ?? [:])
        return dictionary
    }
}
