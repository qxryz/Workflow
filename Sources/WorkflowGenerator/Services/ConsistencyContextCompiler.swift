import Foundation

struct ConsistencyContextCompiler {
    func compile(
        profile: MediaConsistencyProfile,
        snapshot: [ConsistencyAsset],
        delta: [ConsistencyAsset],
        node: WorkflowNode
    ) -> ConsistencyContext {
        guard profile.enabled else { return ConsistencyContext() }
        let assets = mergedAssets(snapshot: snapshot, delta: delta, profileAssets: profile.assets)
        let relevantKinds = consistencyKinds(for: node)
        let selectedAssets = assets
            .filter { relevantKinds.contains($0.category) }
            .sorted { first, second in
                if first.locked != second.locked { return first.locked }
                if first.canonical != second.canonical { return first.canonical }
                return first.strength > second.strength
            }
            .prefix(24)

        var context = ConsistencyContext()
        context.globalPrompt = profile.stylePrompt
        if !profile.seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.lockedConstraints.append("Seed: \(profile.seed)")
        }

        for category in profile.categories where relevantKinds.contains(category.kind) {
            let categoryAssets = selectedAssets.filter { $0.category == category.kind }
            var lines: [String] = []
            if !category.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(category.description)
            }
            lines.append(contentsOf: categoryAssets.compactMap { asset in
                let body = asset.description.isEmpty ? asset.name : asset.description
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "- \(asset.name): \(body)"
            })
            if !lines.isEmpty {
                context.categoryPrompts[category.kind] = lines.joined(separator: "\n")
            }
        }

        for asset in selectedAssets {
            context.positivePromptSnippets.append(contentsOf: asset.promptSnippets.positive)
            context.negativePromptSnippets.append(contentsOf: asset.promptSnippets.negative)
            context.referenceArtifacts.append(asset.artifactPath)
            let constraint = asset.description.isEmpty ? asset.name : asset.description
            if asset.locked {
                context.lockedConstraints.append(constraint)
            } else {
                context.softConstraints.append(constraint)
            }
            if profile.validation.enabled {
                context.validationRules.append("Keep \(asset.displayCategory) consistent with \(asset.name).")
            }
        }
        return context
    }

    func render(_ context: ConsistencyContext) -> String {
        var sections: [String] = []
        if !context.globalPrompt.isEmpty {
            sections.append("Global: \(context.globalPrompt)")
        }
        if !context.categoryPrompts.isEmpty {
            sections.append("Categories:\n" + context.categoryPrompts
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.title):\n\($0.value)" }
                .joined(separator: "\n"))
        }
        if !context.positivePromptSnippets.isEmpty {
            sections.append("Positive snippets: \(context.positivePromptSnippets.joined(separator: ", "))")
        }
        if !context.negativePromptSnippets.isEmpty {
            sections.append("Negative snippets: \(context.negativePromptSnippets.joined(separator: ", "))")
        }
        if !context.referenceArtifacts.isEmpty {
            sections.append("Reference artifacts:\n" + context.referenceArtifacts.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !context.lockedConstraints.isEmpty {
            sections.append("Locked constraints:\n" + context.lockedConstraints.map { "- \($0)" }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private func mergedAssets(snapshot: [ConsistencyAsset], delta: [ConsistencyAsset], profileAssets: [ConsistencyAsset]) -> [ConsistencyAsset] {
        (snapshot + delta + profileAssets)
            .reduce(into: [UUID: ConsistencyAsset]()) { result, asset in
                result[asset.id] = asset
            }
            .values
            .map { $0 }
    }

    private func consistencyKinds(for node: WorkflowNode) -> Set<ConsistencyCategoryKind> {
        if node.outputModalities.contains(.image) {
            return [.character, .visualStyle, .scene, .product]
        }
        if node.outputModalities.contains(.video) {
            return [.character, .visualStyle, .scene, .motion, .product]
        }
        if node.outputModalities.contains(.audio) {
            return [.voice, .music, .sound]
        }
        if node.outputModalities.contains(.text) || node.inputModalities.contains(.text) {
            return [.character, .visualStyle, .scene, .product, .custom]
        }
        return Set(ConsistencyCategoryKind.allCases)
    }
}
