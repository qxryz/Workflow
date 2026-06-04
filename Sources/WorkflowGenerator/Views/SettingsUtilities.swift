import AppKit
import Foundation

func openDocumentation(_ rawURL: String) {
    let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let normalized = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
        ? trimmed
        : "https://\(trimmed)"
    guard let url = URL(string: normalized) else { return }
    NSWorkspace.shared.open(url)
}

