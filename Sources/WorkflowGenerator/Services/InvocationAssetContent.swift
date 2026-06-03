import Foundation
import UniformTypeIdentifiers

struct InvocationAssetContent {
    let asset: InvocationAsset

    var remoteURL: String? {
        guard let url = URL(string: asset.url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return asset.url
    }

    var base64: String? {
        if !asset.base64.isEmpty {
            return asset.base64
        }
        return data?.base64EncodedString()
    }

    var dataURL: String? {
        if asset.url.lowercased().hasPrefix("data:") {
            return asset.url
        }
        guard let base64 else { return nil }
        return "data:\(mimeType);base64,\(base64)"
    }

    var text: String? {
        if !asset.text.isEmpty {
            return asset.text
        }
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var json: Any? {
        let raw = asset.json.isEmpty ? text : asset.json
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? raw
    }

    var data: Data? {
        if let data = asset.data {
            return data
        }
        guard let localFileURL else { return nil }
        return try? Data(contentsOf: localFileURL)
    }

    var mimeType: String {
        if !asset.mimeType.isEmpty {
            return asset.mimeType
        }
        guard let fileExtension = localFileURL?.pathExtension,
              let type = UTType(filenameExtension: fileExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mimeType
    }

    private var localFileURL: URL? {
        if let url = URL(string: asset.url), url.isFileURL {
            return url
        }
        if FileManager.default.fileExists(atPath: asset.url) {
            return URL(filePath: asset.url)
        }
        if let path = asset.metadata["path"], FileManager.default.fileExists(atPath: path) {
            return URL(filePath: path)
        }
        return nil
    }
}
