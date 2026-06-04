import Foundation

struct ProviderMigrationService {
    func migrate(_ configuration: inout AppConfiguration) -> Bool {
        var didChange = false
        let removedProviderIds = Set(configuration.providers.filter { provider in
            isRetiredProviderName(provider.name)
        }.map(\.id))
        let removedModelIds = Set(configuration.models.filter { model in
            if let providerId = model.providerId, removedProviderIds.contains(providerId) {
                return true
            }
            return isRetiredProviderName(model.provider)
        }.map(\.id))
        let providerCount = configuration.providers.count
        configuration.providers.removeAll { provider in
            isRetiredProviderName(provider.name)
        }
        if configuration.providers.count != providerCount {
            didChange = true
        }
        if !removedModelIds.isEmpty {
            configuration.models.removeAll { removedModelIds.contains($0.id) }
            configuration.modelRegistrations.removeAll { removedModelIds.contains($0.modelId) }
            configuration.modelCapabilities.removeAll { removedModelIds.contains($0.modelId) }
            if configuration.defaultModelId.map(removedModelIds.contains) == true {
                configuration.defaultModelId = configuration.models.first?.id
            }
            didChange = true
        }
        let endpointCount = configuration.endpointProfiles.count
        configuration.endpointProfiles.removeAll { endpoint in
            removedProviderIds.contains(endpoint.providerId) ||
            endpoint.presetKey?.lowercased().hasPrefix("kimi.") == true
        }
        if configuration.endpointProfiles.count != endpointCount {
            didChange = true
        }
        let registrationCount = configuration.modelRegistrations.count
        configuration.modelRegistrations.removeAll { registration in
            registration.templateId?.lowercased().hasPrefix("kimi.") == true
        }
        if configuration.modelRegistrations.count != registrationCount {
            didChange = true
        }
        for index in configuration.capabilityDetectionRules.indices {
            let previous = configuration.capabilityDetectionRules[index].modelNameIncludes
            configuration.capabilityDetectionRules[index].modelNameIncludes.removeAll { keyword in
                let normalized = keyword.lowercased()
                return normalized.contains("kimi") || normalized.contains("moonshot")
            }
            if previous != configuration.capabilityDetectionRules[index].modelNameIncludes {
                didChange = true
            }
        }
        for preset in ProviderConfig.defaults where !configuration.providers.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
            configuration.providers.append(preset)
            didChange = true
        }
        for index in configuration.providers.indices {
            guard let preset = ProviderConfig.defaults.first(where: { $0.name.caseInsensitiveCompare(configuration.providers[index].name) == .orderedSame }) else { continue }
            if configuration.providers[index].symbolName == "network" {
                configuration.providers[index].symbolName = preset.symbolName
                didChange = true
            }
            if configuration.providers[index].defaultModelIds.isEmpty {
                configuration.providers[index].defaultModelIds = preset.defaultModelIds
                didChange = true
            }
            if preset.name == "Agnes AI" {
                let defaultKeys = Set(preset.defaultModelIds.map { $0.lowercased() })
                let extras = configuration.providers[index].defaultModelIds.filter { !defaultKeys.contains($0.lowercased()) }
                let merged = preset.defaultModelIds + extras
                if configuration.providers[index].defaultModelIds != merged {
                    configuration.providers[index].defaultModelIds = merged
                    didChange = true
                }
            }
            if configuration.providers[index].notes.isEmpty {
                configuration.providers[index].notes = preset.notes
                didChange = true
            }
            if preset.name == "Agnes AI",
               configuration.providers[index].notes == "Agnes AI by Sapiens AI. Default catalog keeps the most advanced model per modality: text, image, and video." {
                configuration.providers[index].notes = preset.notes
                didChange = true
            }
            if configuration.providers[index].documentationURL.isEmpty {
                configuration.providers[index].documentationURL = preset.documentationURL
                didChange = true
            }
            if preset.name == "MiniMax Coding Plan",
               configuration.providers[index].baseURL.contains("api.minimax.io") {
                configuration.providers[index].baseURL = preset.baseURL
                didChange = true
            }
        }
        for index in configuration.models.indices
            where ProviderEndpointCatalog.normalizedProviderName(configuration.models[index].provider) == "minimax"
            && configuration.models[index].baseURL.contains("api.minimax.io") {
            configuration.models[index].baseURL = "https://api.minimaxi.com/v1"
            didChange = true
        }
        for index in configuration.models.indices
            where ProviderEndpointCatalog.normalizedProviderName(configuration.models[index].provider) == "aliyun" {
            if configuration.models[index].endpointPath == "https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis" ||
                configuration.models[index].endpointPath == "/api/v1/services/aigc/text2image/image-synthesis" ||
                configuration.models[index].endpointPath == "/api/v1" {
                configuration.models[index].endpointPath = "/api/v1/services/aigc/image-generation/generation"
                didChange = true
            }
            if configuration.models[index].requestParametersJSON.contains("\"size\": \"1024*1024\""),
               configuration.models[index].modelId.localizedCaseInsensitiveContains("wan") {
                configuration.models[index].requestParametersJSON = ProviderEndpointCatalog.requestParametersJSON(providerName: configuration.models[index].provider, endpointKind: configuration.models[index].endpointKind)
                didChange = true
            }
            if configuration.models[index].endpointPath == "/audio/speech" {
                configuration.models[index].endpointPath = ProviderEndpointCatalog.endpointPath(providerName: configuration.models[index].provider, endpointKind: .audioSpeech)
                didChange = true
            }
            if configuration.models[index].endpointPath == "/audio/transcriptions" {
                configuration.models[index].endpointPath = ProviderEndpointCatalog.endpointPath(providerName: configuration.models[index].provider, endpointKind: .audioTranscription)
                didChange = true
            }
        }
        for index in configuration.models.indices {
            guard let providerId = configuration.models[index].providerId,
                  let provider = configuration.providers.first(where: { $0.id == providerId }) else { continue }
            let shouldOverride = ProviderEndpointCatalog.shouldOverrideBaseURL(providerName: provider.name, endpointKind: configuration.models[index].endpointKind)
            let preferredBase = ProviderEndpointCatalog.preferredBaseURL(providerName: provider.name, providerBaseURL: provider.baseURL, endpointKind: configuration.models[index].endpointKind)
            if shouldOverride {
                if !configuration.models[index].overridesProviderBaseURL {
                    configuration.models[index].overridesProviderBaseURL = true
                    didChange = true
                }
                let modelURL = configuration.models[index].baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let providerURL = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if modelURL.isEmpty || modelURL == providerURL {
                    configuration.models[index].baseURL = preferredBase
                    didChange = true
                }
            } else if configuration.models[index].overridesProviderBaseURL {
                let modelURL = configuration.models[index].baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let providerURL = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if modelURL == providerURL {
                    configuration.models[index].overridesProviderBaseURL = false
                    configuration.models[index].baseURL = provider.baseURL
                    didChange = true
                }
            }
        }
        for defaultRule in ModelInferenceRule.defaults {
            guard let index = configuration.modelInferenceRules.firstIndex(where: { $0.name == defaultRule.name }) else { continue }
            let existing = Set(configuration.modelInferenceRules[index].keywords.map { $0.lowercased() })
            let missing = defaultRule.keywords.filter { !existing.contains($0.lowercased()) }
            if !missing.isEmpty {
                configuration.modelInferenceRules[index].keywords.append(contentsOf: missing)
                didChange = true
            }
        }
        for model in configuration.models where !configuration.modelRegistrations.contains(where: { $0.modelId == model.id }) {
            let provider = model.providerId.flatMap { id in configuration.providers.first { $0.id == id } }
            if let registrations = ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: model, provider: provider) {
                configuration.modelRegistrations.append(contentsOf: registrations)
            } else {
                var draft = ModelRegistrationPresetRegistry.draft(for: model, provider: provider)
                draft.status = .draft
                draft.lastTestSummary = "Migrated from legacy model settings"
                configuration.modelRegistrations.append(draft)
            }
            didChange = true
        }
        for index in configuration.modelRegistrations.indices {
            let registration = configuration.modelRegistrations[index]
            guard let model = configuration.models.first(where: { $0.id == registration.modelId }),
                  let providerId = model.providerId,
                  let provider = configuration.providers.first(where: { $0.id == providerId }),
                  let template = ProviderInterfaceTemplateRegistry
                    .recommended(providerKey: provider.name, modelId: model.modelId)
                    .first else {
                continue
            }
            if refreshSystemTemplateRegistration(
                &configuration.modelRegistrations[index],
                model: model,
                provider: provider,
                template: template
            ) {
                didChange = true
            }
        }
        if reconcileAgnesModelRegistrations(&configuration) {
            didChange = true
        }
        let taskContentNormalizer = TaskContentBlockNormalizer()
        for index in configuration.modelRegistrations.indices {
            if taskContentNormalizer.normalize(&configuration.modelRegistrations[index]) {
                didChange = true
            }
        }
        return didChange
    }

    private func isRetiredProviderName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "火山引擎 coding plan" ||
            normalized.contains("opencode zen") ||
            normalized.contains("opencode go") ||
            normalized.contains("kimi") ||
            normalized.contains("moonshot")
    }

    private func refreshSystemTemplateRegistration(
        _ registration: inout ModelRegistration,
        model: ModelConfig,
        provider: ProviderConfig,
        template: ProviderInterfaceTemplate
    ) -> Bool {
        guard !registration.lastModifiedByUser else {
            return false
        }
        let isMigratedDraft = registration.templateId?.hasPrefix("migrated.") == true
        let isOutdatedSystemTemplate = registration.templateId == template.id &&
            registration.templateVersion != template.version
        guard isMigratedDraft || isOutdatedSystemTemplate else {
            return false
        }

        let previous = registration
        var refreshed = RegisteredModelInterface(template: template, model: model, provider: provider)
        refreshed.id = previous.id
        refreshed.status = ProviderEndpointCatalog.normalizedProviderName(provider.name) == "agnes" ? .unverified : previous.status
        refreshed.lastTestSummary = previous.lastTestSummary
        refreshed.lastTestedAt = previous.lastTestedAt
        refreshed.lastModifiedByUser = false
        registration = refreshed
        return true
    }

    private func reconcileAgnesModelRegistrations(_ configuration: inout AppConfiguration) -> Bool {
        var didChange = false
        for model in configuration.models {
            guard let providerId = model.providerId,
                  let provider = configuration.providers.first(where: { $0.id == providerId }),
                  ProviderEndpointCatalog.normalizedProviderName(provider.name) == "agnes",
                  let desired = ModelRegistrationPresetRegistry.providerSpecificRegistrations(for: model, provider: provider) else {
                continue
            }
            let existingForModel = configuration.modelRegistrations.filter { $0.modelId == model.id }
            guard !existingForModel.contains(where: \.lastModifiedByUser) else {
                continue
            }
            let desiredTemplateIds = Set(desired.compactMap(\.templateId))
            for index in configuration.modelRegistrations.indices
                where configuration.modelRegistrations[index].modelId == model.id
                && configuration.modelRegistrations[index].status == .draft
                && desiredTemplateIds.contains(configuration.modelRegistrations[index].templateId ?? "") {
                configuration.modelRegistrations[index].status = .unverified
                configuration.modelRegistrations[index].lastTestSummary = "Ready from Agnes AI model template"
                didChange = true
            }
            let userModifiedTemplateIds = Set(existingForModel.filter(\.lastModifiedByUser).compactMap(\.templateId))
            for desiredRegistration in desired where !existingForModel.contains(where: { $0.templateId == desiredRegistration.templateId }) {
                guard !userModifiedTemplateIds.contains(desiredRegistration.templateId ?? "") else { continue }
                configuration.modelRegistrations.append(desiredRegistration)
                didChange = true
            }
        }
        return didChange
    }

    func normalizeAgents(_ configuration: inout AppConfiguration) -> Bool {
        var didChange = false
        for index in configuration.agents.indices {
            guard let candidate = AgentConfig.candidates.first(where: { $0.executable == configuration.agents[index].executable }) else { continue }
            if configuration.agents[index].acpInvocationTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.agents[index].acpInvocationTemplate = candidate.acpInvocationTemplate
                didChange = true
            }
            let knownOldACPTemplates: Set<String> = [
                "npx -y @agentclientprotocol/claude-agent-acp@0.29.2",
                "npx -y @zed-industries/codex-acp@0.9.5"
            ]
            if knownOldACPTemplates.contains(configuration.agents[index].acpInvocationTemplate) {
                configuration.agents[index].acpInvocationTemplate = candidate.acpInvocationTemplate
                didChange = true
            }
        }
        return didChange
    }
}
