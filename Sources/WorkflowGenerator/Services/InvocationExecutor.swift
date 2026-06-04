import Foundation

protocol InvocationHTTPClient {
    func send(_ request: URLRequest) async throws -> InvocationHTTPResponse
}

protocol InvocationSleeper {
    func sleep(seconds: Int) async throws
}

enum InvocationProgress: Equatable {
    case submitted(taskId: String)
    case status(taskId: String, value: String)
    case pollRetry(taskId: String, attempt: Int, maximum: Int)

    var message: String {
        switch self {
        case .submitted(let taskId):
            "异步任务已创建：\(taskId)"
        case .status(_, let value):
            "异步任务状态：\(value)"
        case .pollRetry(let taskId, let attempt, let maximum):
            "查询任务状态时网络不稳定，正在重试（\(attempt)/\(maximum)）。任务 ID：\(taskId)"
        }
    }
}

struct CompiledInvocationRequest {
    var url: URL
    var method: EndpointHTTPMethod
    var headers: [String: String]
    var encoding: RequestEncoding
    var payload: [String: Any]
    var files: [InvocationAsset]
    var pollingBaseURL: URL? = nil
    var timeoutInterval: TimeInterval = 90

    func urlRequest() throws -> URLRequest {
        try InvocationRequestFactory().make(self)
    }
}

struct InvocationHTTPResponse {
    var statusCode: Int
    var headers: [String: String]
    var data: Data

    static func json(_ value: [String: Any], statusCode: Int = 200) -> InvocationHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        return InvocationHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            data: data
        )
    }

    var contentType: String {
        headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""
    }

    var normalizedBody: [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

struct InvocationRawResponse {
    var json: [String: Any]
    var binary: Data?
    var contentType: String
}

struct URLSessionInvocationHTTPClient: InvocationHTTPClient {
    func send(_ request: URLRequest) async throws -> InvocationHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw ModelRegistrationError.requestFailed(statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let headers = http?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        } ?? [:]
        return InvocationHTTPResponse(statusCode: statusCode, headers: headers, data: data)
    }
}

struct TaskInvocationSleeper: InvocationSleeper {
    func sleep(seconds: Int) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

struct InvocationRequestFactory {
    func make(_ request: CompiledInvocationRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeoutInterval
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        guard request.method != .get else { return urlRequest }
        switch request.encoding {
        case .json:
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request.payload)
        case .multipart:
            let encoded = try MultipartEncoder().encode(fields: request.payload, files: request.files)
            urlRequest.setValue(encoded.contentType, forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = encoded.body
        case .octetStream:
            urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = request.files.first?.data
        }
        return urlRequest
    }
}

struct MultipartEncoder {
    struct EncodedMultipart {
        var contentType: String
        var body: Data
    }

    func encode(fields: [String: Any], files: [InvocationAsset]) throws -> EncodedMultipart {
        let boundary = "WorkflowGenerator-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.appendMultipartField(name: name, value: stringValue(value), boundary: boundary)
        }
        for file in files {
            let content = InvocationAssetContent(asset: file)
            guard let data = content.data else { continue }
            body.appendMultipartFile(
                name: file.metadata["field"] ?? "file",
                fileName: file.metadata["fileName"] ?? "asset",
                mimeType: content.mimeType,
                data: data,
                boundary: boundary
            )
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return EncodedMultipart(contentType: "multipart/form-data; boundary=\(boundary)", body: body)
    }

    private func stringValue(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return json
    }
}

struct PollingURLBuilder {
    func make(base: URL, path: String, taskId: String) throws -> URL {
        let rendered = path.replacingOccurrences(of: "{task_id}", with: taskId)
        if let absolute = URL(string: rendered), absolute.scheme != nil {
            return absolute
        }
        let normalizedBase = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = rendered.hasPrefix("/") ? rendered : "/\(rendered)"
        guard let url = URL(string: normalizedBase + normalizedPath) else {
            throw ModelRegistrationError.invalidURL(normalizedBase + normalizedPath)
        }
        return url
    }
}

struct InvocationExecutor {
    var client: any InvocationHTTPClient = URLSessionInvocationHTTPClient()
    var sleeper: any InvocationSleeper = TaskInvocationSleeper()

    func execute(
        request: CompiledInvocationRequest,
        polling: ModelRegistrationPolling?,
        onProgress: (InvocationProgress) -> Void = { _ in }
    ) async throws -> InvocationRawResponse {
        let submitted: InvocationHTTPResponse
        do {
            submitted = try await client.send(request.urlRequest())
        } catch {
            guard polling != nil else { throw error }
            throw ModelRegistrationError.asyncSubmitFailed(error.localizedDescription)
        }
        guard let polling else {
            return normalized(submitted)
        }
        let taskId = try JSONPathReader.requiredString(at: polling.taskIdPath, in: submitted.normalizedBody)
        onProgress(.submitted(taskId: taskId))
        return try await poll(taskId: taskId, request: request, rule: polling, onProgress: onProgress)
    }

    private func poll(
        taskId: String,
        request: CompiledInvocationRequest,
        rule: ModelRegistrationPolling,
        onProgress: (InvocationProgress) -> Void
    ) async throws -> InvocationRawResponse {
        let maximumConsecutiveTransportFailures = 3
        var consecutiveTransportFailures = 0
        var previousStatus: String?
        for _ in 0..<rule.maxAttempts {
            try Task.checkCancellation()
            try await sleeper.sleep(seconds: rule.intervalSeconds)
            let url = try PollingURLBuilder().make(
                base: request.pollingBaseURL ?? request.url,
                path: rule.pollingPath,
                taskId: taskId
            )
            let pollRequest = CompiledInvocationRequest(
                url: url,
                method: rule.method,
                headers: request.headers,
                encoding: .json,
                payload: [:],
                files: [],
                pollingBaseURL: request.pollingBaseURL,
                timeoutInterval: 20
            )
            let response: InvocationHTTPResponse
            do {
                response = try await client.send(pollRequest.urlRequest())
                consecutiveTransportFailures = 0
            } catch {
                guard isTransientPollingError(error) else { throw error }
                consecutiveTransportFailures += 1
                guard consecutiveTransportFailures < maximumConsecutiveTransportFailures else {
                    throw ModelRegistrationError.asyncPollingRequestFailed(
                        taskId: taskId,
                        details: error.localizedDescription
                    )
                }
                onProgress(
                    .pollRetry(
                        taskId: taskId,
                        attempt: consecutiveTransportFailures,
                        maximum: maximumConsecutiveTransportFailures
                    )
                )
                continue
            }
            let raw = normalized(response)
            let status = try JSONPathReader.requiredString(at: rule.statusPath, in: raw.json)
            if status != previousStatus {
                onProgress(.status(taskId: taskId, value: status))
                previousStatus = status
            }
            if rule.successValues.contains(where: { $0.caseInsensitiveCompare(status) == .orderedSame }) {
                return raw
            }
            if rule.failureValues.contains(where: { $0.caseInsensitiveCompare(status) == .orderedSame }) {
                throw ModelRegistrationError.asyncTaskFailed(status)
            }
        }
        throw ModelRegistrationError.asyncTaskTimeout(taskId: taskId)
    }

    private func isTransientPollingError(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        let transientCodes: Set<URLError.Code> = [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .resourceUnavailable
        ]
        return transientCodes.contains(code)
    }

    private func normalized(_ response: InvocationHTTPResponse) -> InvocationRawResponse {
        if response.contentType.localizedCaseInsensitiveContains("text/event-stream") {
            return InvocationRawResponse(
                json: SSEAccumulator.accumulate(response.data),
                binary: nil,
                contentType: response.contentType
            )
        }
        if response.contentType.localizedCaseInsensitiveContains("application/json") || !response.normalizedBody.isEmpty {
            return InvocationRawResponse(json: response.normalizedBody, binary: nil, contentType: response.contentType)
        }
        return InvocationRawResponse(json: [:], binary: response.data, contentType: response.contentType)
    }
}

enum SSEAccumulator {
    static func accumulate(_ data: Data) -> [String: Any] {
        guard let body = String(data: data, encoding: .utf8) else { return [:] }
        var text = ""
        var events: [[String: Any]] = []
        for line in body.split(whereSeparator: \.isNewline) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.hasPrefix("data:") else { continue }
            let payload = value.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]",
                  let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
                continue
            }
            events.append(event)
            text += firstString(in: event) ?? ""
        }
        return ["output_text": text, "events": events]
    }

    private static func firstString(in event: [String: Any]) -> String? {
        let paths = [
            "output_text",
            "choices.0.delta.content",
            "choices.0.message.content",
            "delta.text",
            "text"
        ]
        return paths.lazy.compactMap { JSONPathReader.values(at: $0, in: event).first as? String }.first
    }
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(name: String, fileName: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
