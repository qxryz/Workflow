import Foundation

struct WorkspaceAssetImporter {
    func destinationURL(fileName: String, workspace: WorkspaceLocation?) -> URL {
        generatedDirectory(workspace: workspace)
            .appending(path: sanitizedFileName(fileName))
    }

    func importResponse(
        _ response: RegisteredModelResponse,
        model: ModelConfig,
        workspace: WorkspaceLocation?
    ) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        if !response.assets.isEmpty {
            for (index, asset) in response.assets.enumerated() {
                if let data = asset.data {
                    assets.append(try write(
                        data: data,
                        suggestedFileName: generatedFileName(model: model, index: index, extension: preferredExtension(for: asset.modality)),
                        workspace: workspace,
                        modality: asset.modality
                    ))
                } else if let imported = try await importURLAsset(asset, model: model, index: index, workspace: workspace) {
                    assets.append(imported)
                }
            }
            return assets
        }
        for (index, value) in response.assetURLs.enumerated() {
            if let decoded = decodeDataURL(value) {
                assets.append(try write(
                    data: decoded.data,
                    suggestedFileName: generatedFileName(model: model, index: index, extension: decoded.fileExtension),
                    workspace: workspace
                ))
            } else if let remoteURL = URL(string: value), ["http", "https"].contains(remoteURL.scheme?.lowercased()) {
                let (data, _) = try await URLSession.shared.data(from: remoteURL)
                let fileExtension = remoteURL.pathExtension.isEmpty ? "bin" : remoteURL.pathExtension
                assets.append(try write(
                    data: data,
                    suggestedFileName: generatedFileName(model: model, index: index, extension: fileExtension),
                    workspace: workspace
                ))
            } else if FileManager.default.fileExists(atPath: value) {
                assets.append(MediaAsset(
                    name: URL(filePath: value).lastPathComponent,
                    path: value,
                    modality: MediaAsset.inferModality(path: value)
                ))
            }
        }
        for (index, encoded) in response.base64Assets.enumerated() {
            guard let data = Data(base64Encoded: encoded) else { continue }
            assets.append(try write(
                data: data,
                suggestedFileName: generatedFileName(model: model, index: assets.count + index, extension: "bin"),
                workspace: workspace
            ))
        }
        for (index, data) in response.binaryAssets.enumerated() {
            assets.append(try write(
                data: data,
                suggestedFileName: generatedFileName(model: model, index: assets.count + index, extension: "bin"),
                workspace: workspace
            ))
        }
        return assets
    }

    func write(
        data: Data,
        suggestedFileName: String,
        workspace: WorkspaceLocation?,
        modality: Modality? = nil
    ) throws -> MediaAsset {
        let destination = destinationURL(fileName: suggestedFileName, workspace: workspace)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: [.atomic])
        return MediaAsset(
            name: destination.lastPathComponent,
            path: destination.path,
            modality: modality ?? MediaAsset.inferModality(path: destination.path)
        )
    }

    private func importURLAsset(
        _ asset: RegisteredModelAsset,
        model: ModelConfig,
        index: Int,
        workspace: WorkspaceLocation?
    ) async throws -> MediaAsset? {
        if let decoded = decodeDataURL(asset.url) {
            return try write(
                data: decoded.data,
                suggestedFileName: generatedFileName(model: model, index: index, extension: decoded.fileExtension),
                workspace: workspace,
                modality: asset.modality
            )
        }
        if let remoteURL = URL(string: asset.url), ["http", "https"].contains(remoteURL.scheme?.lowercased()) {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let fileExtension = remoteURL.pathExtension.isEmpty ? preferredExtension(for: asset.modality) : remoteURL.pathExtension
            return try write(
                data: data,
                suggestedFileName: generatedFileName(model: model, index: index, extension: fileExtension),
                workspace: workspace,
                modality: asset.modality
            )
        }
        if FileManager.default.fileExists(atPath: asset.url) {
            return MediaAsset(
                name: URL(filePath: asset.url).lastPathComponent,
                path: asset.url,
                modality: asset.modality
            )
        }
        return nil
    }

    private func generatedDirectory(workspace: WorkspaceLocation?) -> URL {
        guard let workspace else {
            return FileManager.default.temporaryDirectory
                .appending(path: "WorkflowGenerator", directoryHint: .isDirectory)
                .appending(path: ".workflow-assets", directoryHint: .isDirectory)
                .appending(path: "generated", directoryHint: .isDirectory)
        }
        return URL(filePath: workspace.path, directoryHint: .isDirectory)
            .appending(path: ".workflow-assets", directoryHint: .isDirectory)
            .appending(path: sanitizedComponent(workspace.name), directoryHint: .isDirectory)
            .appending(path: "generated", directoryHint: .isDirectory)
    }

    private func generatedFileName(model: ModelConfig, index: Int, extension fileExtension: String) -> String {
        let modelName = sanitizedComponent(model.modelId)
        let timestamp = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.lowercased().prefix(8)
        return "\(modelName)-\(timestamp)-\(index)-\(suffix).\(sanitizedExtension(fileExtension))"
    }

    private func sanitizedFileName(_ value: String) -> String {
        let url = URL(filePath: value)
        let stem = sanitizedComponent(url.deletingPathExtension().lastPathComponent)
        let fileExtension = sanitizedExtension(url.pathExtension)
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    private func sanitizedComponent(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        return sanitized.isEmpty ? "asset" : sanitized
    }

    private func sanitizedExtension(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func decodeDataURL(_ value: String) -> (data: Data, fileExtension: String)? {
        guard value.hasPrefix("data:"),
              let comma = value.firstIndex(of: ",") else {
            return nil
        }
        let metadata = String(value[value.index(value.startIndex, offsetBy: 5)..<comma])
        let payload = String(value[value.index(after: comma)...])
        let data = metadata.contains(";base64")
            ? Data(base64Encoded: payload)
            : payload.removingPercentEncoding?.data(using: .utf8)
        guard let data else { return nil }
        return (data, fileExtension(for: metadata))
    }

    private func fileExtension(for mimeMetadata: String) -> String {
        if mimeMetadata.contains("image/png") { return "png" }
        if mimeMetadata.contains("image/jpeg") { return "jpg" }
        if mimeMetadata.contains("video/mp4") { return "mp4" }
        if mimeMetadata.contains("audio/mpeg") { return "mp3" }
        if mimeMetadata.contains("audio/wav") { return "wav" }
        if mimeMetadata.contains("application/json") { return "json" }
        return "bin"
    }

    private func preferredExtension(for modality: Modality) -> String {
        switch modality {
        case .image, .mask: "png"
        case .video, .audioVideo: "mp4"
        case .audio, .music: "mp3"
        case .json, .bbox, .scores: "json"
        case .text: "txt"
        default: "bin"
        }
    }
}
