import Foundation

struct HTTPClient {
    func postJSON(url: URL, key: String, body: [String: Any], extraHeaders: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "No response body"
            throw NSError(domain: "ModelEndpoint", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"])
        }
        return data
    }

    func getJSON(url: URL, key: String, extraHeaders: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "No response body"
            throw NSError(domain: "ModelEndpoint", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"])
        }
        return data
    }

    func streamSSE(url: URL, key: String, body: [String: Any]) async throws -> URLSession.AsyncBytes {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw NSError(domain: "ModelEndpoint", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(errorBody.isEmpty ? "No response body" : errorBody)"])
        }
        return bytes
    }

    func postMultipart(url: URL, key: String, fields: [String: String], fileFieldName: String, filePath: String) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        let fileURL = URL(filePath: filePath)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "No response body"
            throw NSError(domain: "ModelEndpoint", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"])
        }
        return data
    }

    func apiKey(for model: ModelConfig, configuration: AppConfiguration) -> String? {
        let providerKey = model.providerId.flatMap { id in configuration.providers.first { $0.id == id }?.apiKey }
        let key = providerKey?.isEmpty == false ? providerKey : ProcessInfo.processInfo.environment[model.apiKeyReference]
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    func endpointURL(for model: ModelConfig, fallback: ModelEndpointKind) -> URL? {
        let base = model.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rawPath = model.endpointPath.isEmpty ? fallback.defaultPath : model.endpointPath
        let path = normalizedProviderEndpointPath(rawPath, model: model, fallback: fallback)
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return URL(string: path)
        }
        if ProviderEndpointCatalog.normalizedProviderName(model.provider) == "aliyun",
           path.hasPrefix("/api/v1/services/") || path.hasPrefix("/api/v1/tasks/") {
            return aliyunDashScopeURL(model: model, path: path)
        }
        return URL(string: base + normalizedEndpointPath(path))
    }

    func requestParameters(for model: ModelConfig, fallback: [String: Any] = [:]) throws -> [String: Any] {
        let trimmed = model.requestParametersJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}" else { return fallback }
        guard let data = trimmed.data(using: .utf8) else {
            throw NSError(domain: "ModelRequestParameters", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default request parameters for \(model.name) are not valid UTF-8."])
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let parameters = object as? [String: Any] else {
            throw NSError(domain: "ModelRequestParameters", code: 2, userInfo: [NSLocalizedDescriptionKey: "Default request parameters for \(model.name) must be a JSON object."])
        }
        var merged = fallback
        merged.merge(parameters) { _, custom in custom }
        return merged
    }

    func normalizedProviderEndpointPath(_ path: String, model: ModelConfig, fallback: ModelEndpointKind) -> String {
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") { return path }
        guard ProviderEndpointCatalog.normalizedProviderName(model.provider) == "aliyun" else { return path }
        let normalized = normalizedEndpointPath(path)
        switch normalized {
        case "/api/v1/services/aigc/text2image/image-synthesis":
            return "/api/v1/services/aigc/image-generation/generation"
        case "/api/v1":
            return fallback == .imageGeneration
                ? "/api/v1/services/aigc/image-generation/generation"
                : normalized
        case "/audio/speech":
            return normalizedAliyunAudioSpeechPath(model: model)
        case "/audio/transcriptions":
            return normalizedAliyunAudioTranscriptionPath(model: model)
        default:
            if fallback == .imageGeneration, isAliyunQwenImage2Model(model) {
                return "/api/v1/services/aigc/multimodal-generation/generation"
            }
            if fallback == .audioSpeech, normalized == fallback.defaultPath {
                return normalizedAliyunAudioSpeechPath(model: model)
            }
            if fallback == .audioTranscription, normalized == fallback.defaultPath {
                return normalizedAliyunAudioTranscriptionPath(model: model)
            }
            return normalized
        }
    }

    func aliyunDashScopeURL(model: ModelConfig, path: String) -> URL? {
        guard var components = URLComponents(string: model.baseURL) else { return nil }
        components.scheme = components.scheme ?? "https"
        if components.host?.contains("dashscope-us") == true {
            components.host = "dashscope-us.aliyuncs.com"
        } else if components.host?.contains("dashscope-intl") == true {
            components.host = "dashscope-intl.aliyuncs.com"
        } else {
            components.host = "dashscope.aliyuncs.com"
        }
        components.path = normalizedEndpointPath(path)
        components.queryItems = nil
        return components.url
    }

    func requestHeaders(for model: ModelConfig, endpointKind: ModelEndpointKind) -> [String: String] {
        let providerKey = ProviderEndpointCatalog.normalizedProviderName(model.provider)
        if providerKey == "aliyun", [.imageGeneration, .imageEdit, .videoTask].contains(endpointKind) {
            guard model.usesAsyncTask else { return ["Accept": "application/json"] }
            return ["X-DashScope-Async": "enable", "Accept": "application/json"]
        }
        return ["Accept": "application/json"]
    }

    func pollIntervalNanoseconds(model: ModelConfig, kind: GeneratedMediaKind) -> UInt64 {
        let providerKey = ProviderEndpointCatalog.normalizedProviderName(model.provider)
        if providerKey == "minimax" { return 10_000_000_000 }
        if kind == .video { return 5_000_000_000 }
        return 2_000_000_000
    }

    func taskPollURL(taskId: String, taskURL: URL, model: ModelConfig, kind: GeneratedMediaKind) -> URL? {
        switch ProviderEndpointCatalog.normalizedProviderName(model.provider) {
        case "aliyun":
            return aliyunDashScopeURL(model: model, path: "/api/v1/tasks/\(taskId)")
        case "minimax":
            let path = kind == .video ? "/query/video_generation" : "/query/image_generation"
            return providerURL(model: model, absolutePath: path, queryItems: [URLQueryItem(name: "task_id", value: taskId)])
        default:
            return taskURL.appending(path: taskId)
        }
    }

    func providerURL(model: ModelConfig, absolutePath: String, queryItems: [URLQueryItem] = []) -> URL? {
        let baseURL = ProviderEndpointCatalog.normalizedProviderName(model.provider) == "minimax"
            ? model.baseURL.replacingOccurrences(of: "api.minimax.io", with: "api.minimaxi.com")
            : model.baseURL
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if components.path.isEmpty {
            components.path = absolutePath
        } else {
            components.path = "/" + components.path + normalizedEndpointPath(absolutePath)
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func normalizedEndpointPath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }

    private func normalizedAliyunAudioSpeechPath(model: ModelConfig) -> String {
        model.modelId.localizedCaseInsensitiveContains("cosyvoice")
            ? "/api/v1/services/audio/tts/SpeechSynthesizer"
            : "/api/v1/services/aigc/multimodal-generation/generation"
    }

    private func normalizedAliyunAudioTranscriptionPath(model: ModelConfig) -> String {
        let id = model.modelId.lowercased()
        if id.contains("filetrans") || id.contains("sensevoice") {
            return "/api/v1/services/audio/asr/transcription"
        }
        return "/api/v1/services/aigc/multimodal-generation/generation"
    }

    private func isAliyunQwenImage2Model(_ model: ModelConfig) -> Bool {
        guard ProviderEndpointCatalog.normalizedProviderName(model.provider) == "aliyun" else { return false }
        let id = model.modelId.lowercased()
        return id.contains("qwen-image-2.0") || id.contains("qwen-image-2")
    }
}

enum GeneratedMediaKind {
    case image
    case video

    var label: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        }
    }

    var preferredExtension: String {
        switch self {
        case .image: "png"
        case .video: "mp4"
        }
    }

    var endpointKind: ModelEndpointKind {
        switch self {
        case .image: .imageGeneration
        case .video: .videoTask
        }
    }
}
