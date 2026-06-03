import Foundation

enum ModelRegistrationError: LocalizedError, Equatable {
    case modelNotFound
    case registrationNotFound
    case providerNotFound
    case missingCredential
    case missingSlot(String)
    case unsupportedAttachmentFormat(String, String)
    case invalidURL(String)
    case invalidDefaultJSON
    case requestFailed(Int, String)
    case responseParseFailed(String)
    case asyncTaskFailed(String)
    case asyncSubmitFailed(String)
    case asyncPollingRequestFailed(taskId: String, details: String)
    case asyncTaskTimeout(taskId: String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound: "没有找到可用模型。"
        case .registrationNotFound: "这个模型还没有适合当前材料的注册配方。请在设置 > 模型中完成注册。"
        case .providerNotFound: "模型没有关联可用供应商。"
        case .missingCredential: "供应商 API Key 未填写。"
        case .missingSlot(let label): "缺少必填输入：\(label)。请向节点添加对应附件。"
        case .unsupportedAttachmentFormat(let label, let format): "附件“\(label)”无法转换为 \(format)。本地文件不能直接作为公网 URL 发送；请改用 base64、data_url，或提供供应商可访问的远程 URL。"
        case .invalidURL(let value): "请求地址无效：\(value)"
        case .invalidDefaultJSON: "默认请求 JSON 不是合法对象。"
        case .requestFailed(let status, let body): "模型请求失败：HTTP \(status)\n\(body)"
        case .responseParseFailed(let path): "响应中没有找到输出字段：\(path)"
        case .asyncTaskFailed(let status): "异步任务失败：\(status)"
        case .asyncSubmitFailed(let details): "异步任务提交失败：\(details)"
        case .asyncPollingRequestFailed(let taskId, let details): "异步任务仍保留在供应商侧，但暂时无法继续查询。任务 ID：\(taskId)\n\(details)"
        case .asyncTaskTimeout(let taskId): "异步任务等待超时。任务 ID：\(taskId)"
        }
    }
}

struct ResolvedModelRegistration {
    var model: ModelConfig
    var provider: ProviderConfig
    var registration: ModelRegistration
}

struct ModelRegistrationRouter {
    private let matcher = InputCardMatcher()
    private let compiler = RequestCompiler()
    private let executor = InvocationExecutor()
    private let normalizer = ResponseNormalizer()

    func resolve(
        interfaceId: UUID,
        configuration: AppConfiguration
    ) throws -> ResolvedModelRegistration {
        guard let registration = configuration.modelRegistrations.first(where: {
            $0.id == interfaceId && $0.status.isNodeSelectable
        }) else {
            throw ModelRegistrationError.registrationNotFound
        }
        guard let model = configuration.models.first(where: {
            $0.id == registration.modelId && $0.enabled
        }) else {
            throw ModelRegistrationError.modelNotFound
        }
        guard registration.hasResolvedProvider,
              let provider = configuration.providers.first(where: {
                  $0.id == registration.providerId && $0.enabled
              }) else {
            throw ModelRegistrationError.providerNotFound
        }
        return ResolvedModelRegistration(model: model, provider: provider, registration: registration)
    }

    func resolve(
        modelId: UUID,
        desiredOutputModalities: Set<Modality>,
        inputs: [InvocationAsset],
        configuration: AppConfiguration
    ) throws -> ResolvedModelRegistration {
        guard let model = configuration.models.first(where: { $0.id == modelId && $0.enabled }) else {
            throw ModelRegistrationError.modelNotFound
        }
        guard let providerId = model.providerId,
              let provider = configuration.providers.first(where: { $0.id == providerId && $0.enabled }) else {
            throw ModelRegistrationError.providerNotFound
        }
        let modalities = Set(inputs.map(\.type))
        let candidates = configuration.modelRegistrations
            .filter { registration in
                registration.modelId == model.id &&
                registration.status.isNodeSelectable &&
                desiredOutputModalities.isSubset(of: registration.outputModalities)
            }
            .sorted { score($0, modalities: modalities) > score($1, modalities: modalities) }
        guard let registration = candidates.first(where: { canSatisfy($0, inputs: inputs) }) else {
            throw ModelRegistrationError.registrationNotFound
        }
        return ResolvedModelRegistration(model: model, provider: provider, registration: registration)
    }

    func compiledPayload(
        interfaceId: UUID,
        inputs: [InvocationAsset],
        nodeOverrides: [String: String] = [:],
        configuration: AppConfiguration
    ) throws -> [String: Any] {
        try buildPayload(
            context: resolve(interfaceId: interfaceId, configuration: configuration),
            inputs: inputs,
            nodeOverrides: nodeOverrides
        )
    }

    func buildPayload(
        context: ResolvedModelRegistration,
        inputs: [InvocationAsset],
        nodeOverrides: [String: String] = [:],
        conversationMessages: [ChatCompletionMessage] = []
    ) throws -> [String: Any] {
        let taskContentNormalizer = TaskContentBlockNormalizer()
        let registration = taskContentNormalizer.normalized(context.registration)
        let matched = try matcher.match(cards: registration.inputCards, assets: inputs)
        let payload = try compiler.compile(
            baseJSON: registration.defaultRequestJSON,
            modelPath: registration.modelParameterPath,
            modelId: context.model.modelId,
            matchedValues: matched,
            nodeOverrides: taskContentNormalizer.normalizedOverrides(nodeOverrides, registration: registration)
        )
        guard registration.interfaceFamily == .conversation else {
            return payload
        }
        return compiler.injectingConversationHistory(
            conversationMessages,
            into: payload,
            inputCards: registration.inputCards
        )
    }

    func requestURL(context: ResolvedModelRegistration, pollingTaskId: String? = nil) throws -> URL {
        let registration = context.registration
        let rawPath: String
        if let pollingTaskId, let polling = registration.polling {
            rawPath = polling.pollingPath.replacingOccurrences(of: "{task_id}", with: pollingTaskId)
        } else {
            rawPath = registration.path
        }
        if let absolute = URL(string: rawPath), absolute.scheme != nil { return absolute }
        let base = registration.resolvedBaseURL(provider: context.provider).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        guard let url = URL(string: base + path) else {
            throw ModelRegistrationError.invalidURL(base + path)
        }
        return url
    }

    func invoke(
        context: ResolvedModelRegistration,
        inputs: [InvocationAsset],
        nodeOverrides: [String: String] = [:],
        conversationMessages: [ChatCompletionMessage] = [],
        onProgress: (InvocationProgress) -> Void = { _ in }
    ) async throws -> RegisteredModelResponse {
        let payload = try buildPayload(
            context: context,
            inputs: inputs,
            nodeOverrides: nodeOverrides,
            conversationMessages: conversationMessages
        )
        let request = try compiledRequest(context: context, payload: payload, inputs: inputs)
        let polling = context.registration.mode == .async ? context.registration.polling : nil
        let raw = try await executor.execute(request: request, polling: polling, onProgress: onProgress)
        return try normalizer.normalize(raw: raw, slots: context.registration.outputSlots)
    }

    func invoke(
        interfaceId: UUID,
        inputs: [InvocationAsset],
        nodeOverrides: [String: String] = [:],
        configuration: AppConfiguration
    ) async throws -> RegisteredModelResponse {
        try await invoke(
            context: resolve(interfaceId: interfaceId, configuration: configuration),
            inputs: inputs,
            nodeOverrides: nodeOverrides
        )
    }

    func normalize(_ raw: [String: Any], registration: ModelRegistration) throws -> RegisteredModelResponse {
        try normalizer.normalize(raw: raw, slots: registration.outputSlots)
    }

    private func score(_ registration: ModelRegistration, modalities: Set<Modality>) -> Int {
        registration.inputSlots.filter { $0.required && modalities.contains($0.modality) }.count * 100 +
        registration.inputSlots.filter { modalities.contains($0.modality) }.count
    }

    private func canSatisfy(_ registration: ModelRegistration, inputs: [InvocationAsset]) -> Bool {
        (try? matcher.match(cards: registration.inputCards, assets: inputs)) != nil
    }

    private func compiledRequest(
        context: ResolvedModelRegistration,
        payload: [String: Any],
        inputs: [InvocationAsset]
    ) throws -> CompiledInvocationRequest {
        guard !context.provider.apiKey.isEmpty else { throw ModelRegistrationError.missingCredential }
        let resolvedBaseURL = context.registration.resolvedBaseURL(provider: context.provider)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let pollingBaseURL = URL(string: resolvedBaseURL) else {
            throw ModelRegistrationError.invalidURL(resolvedBaseURL)
        }
        var headers = [
            "Authorization": "Bearer \(context.provider.apiKey)",
            "Accept": "application/json"
        ]
        headers.merge(context.registration.headers) { _, registered in registered }
        return CompiledInvocationRequest(
            url: try requestURL(context: context),
            method: context.registration.method,
            headers: headers,
            encoding: context.registration.requestEncoding,
            payload: payload,
            files: inputs,
            pollingBaseURL: pollingBaseURL
        )
    }
}
