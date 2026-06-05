import SwiftUI

@MainActor
struct NodeChatWorkspaceView: View {
    @Bindable var store: AppStore
    let nodeId: UUID

    private var node: WorkflowNode? {
        store.configuration.workflow.nodes.first { $0.id == nodeId }
    }

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    var body: some View {
        if let node {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    chatHeader(node)
                    Divider()
                    persistentConversationBar(node)
                    Divider()
                    messageTimeline(node)
                    Divider()
                    composer(node)
                }
                .frame(minWidth: 560)

                Divider()

                outputPanel(node)
                    .frame(width: 300)
            }
            .background(.background)
        } else {
            ContentUnavailableView(copy.noNodeSelected, systemImage: "square.dashed")
                .frame(minWidth: 760, minHeight: 520)
        }
    }

    private func chatHeader(_ node: WorkflowNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: node.kind == .agent ? "terminal" : "cpu")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.headline)
                Text(modelOrAgentName(node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if node.kind == .model {
                Button {
                    store.openModelSettingsWindow(for: node)
                } label: {
                    Label("模型参数", systemImage: "slider.horizontal.3")
                }
                .controlSize(.small)
                .disabled(store.modelSettingsTarget(for: node) == nil)
                .quickHelp("打开设置并编辑当前模型的 endpoint、参数和模态能力。")
            }

            HStack(spacing: 6) {
                ForEach(Array(node.outputModalities).sorted { $0.rawValue < $1.rawValue }) { modality in
                    Image(systemName: modality.symbolName)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func persistentConversationBar(_ node: WorkflowNode) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: node.hasStartedPersistentChat ? "link.circle.fill" : "link.circle")
                .foregroundStyle(node.usesPersistentChat ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.persistentChat)
                    .font(.callout.weight(.semibold))
                Text(persistentStatusText(for: node))
                    .font(.caption)
                    .foregroundStyle(hasModelChanged(for: node) ? Color.orange : Color.secondary)
                    .lineLimit(3)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { node.usesPersistentChat },
                set: { store.setPersistentChatEnabled($0, for: node) }
            ))
            .labelsHidden()
            .quickHelp("开启后，模型节点会保留上下文；Agent 节点会维持 ACP 会话。")
            Button {
                store.resetPersistentChat(for: node)
            } label: {
                Label(copy.resetConversation, systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
            .disabled(node.chat.isEmpty && !node.hasStartedPersistentChat)
            .quickHelp("清空这个节点的聊天记录，并关闭当前持久会话。")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hasModelChanged(for: node) ? Color.orange.opacity(0.12) : (node.usesPersistentChat ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06)))
    }

    private func persistentStatusText(for node: WorkflowNode) -> String {
        if hasModelChanged(for: node) {
            return copy.modelChangedWarning
        }
        if node.hasStartedPersistentChat {
            return copy.persistentChatStarted
        }
        return node.kind == .agent ? copy.agentPersistentChatIntro : copy.modelPersistentChatIntro
    }

    private func hasModelChanged(for node: WorkflowNode) -> Bool {
        node.kind == .model &&
        node.hasStartedPersistentChat &&
        node.persistentModelId != nil &&
        node.persistentModelId != node.modelId
    }

    private func messageTimeline(_ node: WorkflowNode) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleMessages(for: node)) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                    if visibleMessages(for: node).isEmpty {
                        ContentUnavailableView(copy.noMessages, systemImage: "bubble.left.and.bubble.right")
                            .padding(.top, 80)
                    }
                }
                .padding(16)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: node.chat) { _, messages in
                guard messages.contains(where: { $0.role != "draft" }) else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func visibleMessages(for node: WorkflowNode) -> [ChatMessage] {
        node.chat.filter { $0.role != "draft" }
    }

    private func composer(_ node: WorkflowNode) -> some View {
        VStack(spacing: 10) {
            if let draft = node.chat.last, draft.role == "draft", !draft.attachments.isEmpty {
                AttachmentStrip(paths: draft.attachments) { path in
                    store.removePendingAttachment(path: path, from: node)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    store.attachFiles(to: node)
                } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 30, height: 30)
                }

                TextField(copy.messageThisNode, text: draftBinding(for: node), axis: .vertical)
                    .lineLimit(2...7)
                    .textFieldStyle(.roundedBorder)

                if store.isExecuting(node) {
                    Button {
                        store.pauseExecution(for: node)
                    } label: {
                        Label(copy.pause, systemImage: "pause.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        store.sendMessage(from: node)
                    } label: {
                        Label(copy.send, systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
    }

    private func outputPanel(_ node: WorkflowNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy.outputs)
                    .font(.headline)
                ForEach(Array(node.outputModalities).sorted { $0.rawValue < $1.rawValue }) { modality in
                    OutputModalityCard(
                        title: outputTitle(for: modality),
                        modality: modality,
                        message: latestOutput(for: node, modality: modality),
                        emptyText: modality == .text ? copy.waitingForOutput : copy.noMediaYet
                    )
                }
            }
            .padding(14)
        }
        .background(.thinMaterial)
    }

    private func draftBinding(for node: WorkflowNode) -> Binding<String> {
        Binding(
            get: {
                store.configuration.workflow.nodes.first(where: { $0.id == node.id })?.draftMessage ?? ""
            },
            set: { newValue in
                guard var updated = store.configuration.workflow.nodes.first(where: { $0.id == node.id }) else { return }
                updated.draftMessage = newValue
                store.updateNode(updated)
            }
        )
    }

    private func latestOutput(for node: WorkflowNode, modality: Modality) -> ChatMessage? {
        let outputs = node.chat.filter { ["assistant", "agent"].contains($0.role) }
        if modality == .text {
            return outputs.last
        }
        return outputs.last { message in
            message.attachments.contains { MediaAsset.inferModality(path: $0) == modality }
        }
    }

    private func outputTitle(for modality: Modality) -> String {
        switch modality {
        case .text: copy.textOutput
        case .image: copy.imageOutput
        case .video: copy.videoOutput
        case .audioVideo: "AudioVideo"
        case .audio: copy.audioOutput
        case .music: "Music"
        case .file: copy.fileOutput
        case .json: "JSON"
        case .embedding: "Embedding"
        case .scores: "Scores"
        case .threeD: "3D"
        case .mask: "Mask"
        case .bbox: "BBox"
        case .reference: "Reference"
        case .unknown: "Unknown"
        }
    }

    private func modelOrAgentName(_ node: WorkflowNode) -> String {
        if node.kind == .agent {
            return node.agentExecutable ?? "Agent"
        }
        guard let modelId = node.modelId,
              let model = store.configuration.models.first(where: { $0.id == modelId }) else {
            return "Model"
        }
        return "\(model.name) · \(model.provider)"
    }
}

@MainActor
private struct ChatBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == "user"
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(message.role.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.text.isEmpty ? " " : message.text)
                    .textSelection(.enabled)
                    .font(.callout)
                if !message.attachments.isEmpty {
                    AttachmentStrip(paths: message.attachments, allowsDelete: false) { _ in }
                }
            }
            .padding(12)
            .background(isUser ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            if !isUser { Spacer(minLength: 80) }
        }
    }
}

@MainActor
private struct AttachmentStrip: View {
    let paths: [String]
    var allowsDelete = true
    let onDelete: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(paths, id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: MediaAsset.inferModality(path: path).symbolName)
                        Text(URL(filePath: path).lastPathComponent)
                            .lineLimit(1)
                        if allowsDelete {
                            Button {
                                onDelete(path)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.10), in: Capsule())
                }
            }
        }
    }
}

@MainActor
private struct OutputModalityCard: View {
    let title: String
    let modality: Modality
    let message: ChatMessage?
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: modality.symbolName)
                .font(.callout.weight(.semibold))

            if modality == .text, let text = message?.text, !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .lineLimit(10)
                    .textSelection(.enabled)
            } else if let attachment = mediaAttachment {
                MediaOutputPreview(path: attachment, modality: modality)
            } else {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }

    private var mediaAttachment: String? {
        message?.attachments.first { MediaAsset.inferModality(path: $0) == modality }
    }
}

@MainActor
private struct MediaOutputPreview: View {
    let path: String
    let modality: Modality

    var body: some View {
        VStack(spacing: 8) {
            if modality == .image, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: modality.symbolName)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(URL(filePath: path).lastPathComponent)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
