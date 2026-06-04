import Foundation

struct InputCardMatcher {
    func match(cards: [ModelRegistrationInputSlot], assets: [InvocationAsset]) throws -> [String: Any] {
        var matched: [String: Any] = [:]
        for card in cards {
            guard let value = try value(for: card, assets: assets) else {
                if card.required {
                    throw ModelRegistrationError.missingSlot(card.label)
                }
                continue
            }
            if card.collectsAsArray {
                var values = matched[card.parameterPath] as? [Any] ?? []
                if let newValues = value as? [Any] {
                    values.append(contentsOf: newValues)
                } else {
                    values.append(value)
                }
                matched[card.parameterPath] = values
            } else {
                matched[card.parameterPath] = value
            }
        }
        return matched
    }

    private func value(for card: ModelRegistrationInputSlot, assets: [InvocationAsset]) throws -> Any? {
        switch card.source {
        case .prompt:
            return assets
                .first(where: { $0.type == .text && !$0.text.isEmpty })
                .map { wrap($0.text, templateJSON: card.valueTemplateJSON) }
        case .fixedValue:
            return card.fixedValue.isEmpty ? nil : wrap(card.fixedValue, templateJSON: card.valueTemplateJSON)
        case .attachment:
            let candidates = assets.filter { $0.type == card.modality }
            let values = candidates
                .compactMap { serialize($0, format: card.valueFormat) }
                .map { wrap($0, templateJSON: card.valueTemplateJSON) }
            if !candidates.isEmpty, values.isEmpty {
                throw ModelRegistrationError.unsupportedAttachmentFormat(card.label, card.valueFormat.rawValue)
            }
            return card.acceptsMultiple ? (values.isEmpty ? nil : values) : values.first
        }
    }

    private func wrap(_ value: Any, templateJSON: String) -> Any {
        let trimmed = templateJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let template = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return value
        }
        return replaceValuePlaceholder(in: template, value: value)
    }

    private func replaceValuePlaceholder(in template: Any, value: Any) -> Any {
        if let string = template as? String {
            return string == "$value" ? value : string
        }
        if let array = template as? [Any] {
            return array.map { replaceValuePlaceholder(in: $0, value: value) }
        }
        if let dictionary = template as? [String: Any] {
            return dictionary.mapValues { replaceValuePlaceholder(in: $0, value: value) }
        }
        return template
    }

    private func serialize(_ asset: InvocationAsset, format: ModelRegistrationValueFormat) -> Any? {
        let content = InvocationAssetContent(asset: asset)
        return switch format {
        case .url:
            content.remoteURL
        case .base64:
            content.base64
        case .dataURL:
            content.dataURL
        case .text:
            content.text
        case .json:
            content.json
        case .automatic:
            content.remoteURL
                ?? content.dataURL
                ?? content.text
                ?? content.json
        }
    }
}
