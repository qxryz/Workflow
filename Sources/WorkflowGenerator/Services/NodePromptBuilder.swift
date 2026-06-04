struct NodePromptBuilder {
    func prompt(text: String, attachments: [String], nodeKind: NodeKind) -> String {
        guard nodeKind == .agent, !attachments.isEmpty else { return text }
        let attachmentBlock = attachments.map { "- \($0)" }.joined(separator: "\n")
        return "\(text)\n\nAttached files:\n\(attachmentBlock)"
    }
}
