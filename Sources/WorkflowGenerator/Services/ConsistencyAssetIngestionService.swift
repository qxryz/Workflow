import Foundation

struct ConsistencyAssetIngestionService {
    func makeAsset(
        path: String,
        node: WorkflowNode,
        runId: UUID,
        sourceNodeId: UUID?,
        sourceRouteId: UUID?,
        config: ConsistencyNodeConfiguration,
        categoryName: (ConsistencyCategoryKind) -> String,
        llmSummary: String?
    ) -> ConsistencyAsset {
        let modality = MediaAsset.inferModality(path: path)
        let categoryKind = config.defaultCategory ?? defaultConsistencyKind(for: modality)
        var asset = ConsistencyAsset(
            category: categoryKind,
            displayCategory: categoryName(categoryKind),
            name: URL(filePath: path).lastPathComponent,
            assetType: modality,
            artifactPath: path,
            sourceNodeId: sourceNodeId,
            sourceRunId: runId,
            sourceRouteId: sourceRouteId,
            description: description(for: path, modality: modality, node: node, config: config, llmSummary: llmSummary),
            locked: config.lockWrittenAssets
        )
        asset.promptSnippets.positive = [asset.description].filter { !$0.isEmpty }
        asset.anchors = anchors(for: asset, config: config)
        if let llmSummary, !llmSummary.isEmpty {
            asset.metadata["llmSummary"] = llmSummary
        }
        return asset
    }

    func defaultConsistencyKind(for modality: Modality) -> ConsistencyCategoryKind {
        switch modality {
        case .image: .visualStyle
        case .video, .audioVideo: .motion
        case .audio: .voice
        case .music: .music
        case .text: .custom
        case .file: .custom
        case .json: .custom
        case .embedding: .custom
        case .scores, .threeD, .mask, .bbox, .reference, .unknown: .custom
        }
    }

    func validationResult(for outputText: String, assetPaths: [String], context: ConsistencyContext, settings: ConsistencyValidationSettings) -> ConsistencyValidationResult? {
        guard settings.enabled else { return nil }
        let hasContext = !context.globalPrompt.isEmpty ||
            !context.referenceArtifacts.isEmpty ||
            !context.lockedConstraints.isEmpty ||
            !context.softConstraints.isEmpty
        guard hasContext else { return nil }

        var score = 0.82
        if assetPaths.isEmpty && !context.referenceArtifacts.isEmpty {
            score -= 0.12
        }
        if outputText.localizedCaseInsensitiveContains("failed") || outputText.localizedCaseInsensitiveContains("error") {
            score -= 0.18
        }
        let passed = score >= settings.threshold
        let issues: [ConsistencyValidationIssue] = passed ? [] : [
            ConsistencyValidationIssue(
                category: .custom,
                severity: .medium,
                message: "生成结果缺少足够的一致性证据，需要人工复核。",
                suggestedFix: "加强节点特殊模板提示词，或补充锁定参考资产后重跑。"
            )
        ]
        return ConsistencyValidationResult(
            score: score,
            categoryScores: [.custom: score],
            passed: passed,
            issues: issues
        )
    }

    private func description(for path: String, modality: Modality, node: WorkflowNode, config: ConsistencyNodeConfiguration, llmSummary: String?) -> String {
        if let llmSummary, !llmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return llmSummary
        }
        let source = URL(filePath: path).lastPathComponent
        let extraction = config.useDefaultLLM ? "已先按文件信息整理，稍后可在一致性窗口补充说明。" : "已按文件信息整理，稍后可在一致性窗口补充说明。"
        return "\(source) imported by \(node.title) as \(modality.title). \(extraction)"
    }

    private func anchors(for asset: ConsistencyAsset, config: ConsistencyNodeConfiguration) -> ConsistencyAnchors {
        guard config.extractAnchors else { return ConsistencyAnchors() }
        var anchors = ConsistencyAnchors()
        switch asset.category {
        case .character:
            anchors.identity = [asset.name]
        case .visualStyle, .scene, .product:
            anchors.style = [asset.displayCategory]
            anchors.composition = [asset.name]
        case .motion:
            anchors.motion = [asset.name]
        case .voice, .music, .sound:
            anchors.voice = [asset.name]
        case .custom:
            anchors.style = [asset.name]
        }
        return anchors
    }
}
