import Foundation

struct ProviderService {
    func fetchModels(provider: ProviderConfig) async -> Result<[String], Error> {
        do {
            let base = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let endpoint = provider.modelListEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/models" : provider.modelListEndpoint
            let urlString = endpoint.lowercased().hasPrefix("http") ? endpoint : "\(base)\(endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)")"
            guard let url = URL(string: urlString) else { return .success([]) }
            var request = URLRequest(url: url)
            if !provider.apiKey.isEmpty {
                switch provider.authType {
                case .bearer, .custom:
                    request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
                case .apiKeyHeader:
                    request.setValue(provider.apiKey, forHTTPHeaderField: "X-API-Key")
                case .queryKey:
                    break
                }
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(NSError(domain: "Provider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
            }
            let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return .success(decoded.data.map(\.id).sorted())
        } catch {
            return .failure(error)
        }
    }
}

private struct ModelListResponse: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let data: [Item]
}
