import Foundation

struct RegisteredModelAsset {
    var modality: Modality
    var url = ""
    var data: Data?
}

struct RegisteredModelResponse {
    var text = ""
    var assets: [RegisteredModelAsset] = []
    var assetURLs: [String] = []
    var base64Assets: [String] = []
    var binaryAssets: [Data] = []
    var raw: [String: Any] = [:]
}

struct ResponseNormalizer {
    func normalize(raw: InvocationRawResponse, slots: [ModelRegistrationOutputSlot]) throws -> RegisteredModelResponse {
        var response = try normalize(raw: raw.json, slots: slots)
        if let binary = raw.binary,
           let slot = slots.first(where: { $0.kind == .asset && $0.jsonPath == "$binary" }) {
            response.assets.append(RegisteredModelAsset(modality: slot.modality, data: binary))
            response.binaryAssets.append(binary)
        }
        return response
    }

    func normalize(raw: [String: Any], slots: [ModelRegistrationOutputSlot]) throws -> RegisteredModelResponse {
        var response = RegisteredModelResponse(raw: raw)
        for slot in slots {
            guard slot.jsonPath != "$binary" else { continue }
            let values = JSONPathReader.values(at: slot.jsonPath, in: raw)
            switch slot.kind {
            case .text:
                response.text += values.compactMap { $0 as? String }.joined(separator: "\n")
            case .asset:
                let urls = values.compactMap { $0 as? String }
                response.assetURLs += urls
                response.assets += urls.map { RegisteredModelAsset(modality: slot.modality, url: $0) }
            case .taskId, .raw:
                break
            }
        }
        if response.text.isEmpty, response.assets.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted]),
           let string = String(data: data, encoding: .utf8) {
            response.text = string
        }
        return response
    }
}

enum JSONPathReader {
    static func values(at path: String, in object: Any) -> [Any] {
        read(parts: path.split(separator: ".").map(String.init), object: object)
    }

    static func requiredString(at path: String, in object: Any) throws -> String {
        guard let value = values(at: path, in: object).first as? String else {
            throw ModelRegistrationError.responseParseFailed(path)
        }
        return value
    }

    private static func read(parts: [String], object: Any) -> [Any] {
        guard let head = parts.first else { return [object] }
        let tail = Array(parts.dropFirst())
        if head == "*", let array = object as? [Any] {
            return array.flatMap { read(parts: tail, object: $0) }
        }
        if let index = Int(head), let array = object as? [Any], array.indices.contains(index) {
            return read(parts: tail, object: array[index])
        }
        if let dictionary = object as? [String: Any], let next = dictionary[head] {
            return read(parts: tail, object: next)
        }
        return []
    }
}
