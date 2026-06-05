import SwiftUI

@MainActor
struct SidebarView: View {
    @Bindable var store: AppStore
    @State private var confirmDelete: WorkspaceLocation?
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        List {
            Section {
                ForEach(store.configuration.workspaces) { workspace in
                    WorkspaceRow(store: store, workspace: workspace, onRequestDelete: { confirmDelete = $0 })
                }
            } header: {
                HStack {
                    Text(copy.workspace)
                    Spacer()
                    Button {
                        store.openExistingWorkspace()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .quickHelp(copy.openWorkspace)
                    Button {
                        store.createWorkspace()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if store.selectedWorkspace != nil {
                Section(copy.workflow) {
                    ForEach(store.configuration.workflow.nodes) { node in
                        Label(node.title, systemImage: sidebarNodeIcon(node.kind))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                store.configuration.workflow.selectedNodeIds.contains(node.id) ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectNode(node.id)
                            }
                    }
                }
            }

            Section(copy.detectedAgents) {
                ForEach(store.configuration.agents) { agent in
                    HStack {
                        Image(systemName: agent.isAvailable ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(agent.isAvailable ? .green : .secondary)
                        Text(agent.name)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            store.launchAgentTUI(agent)
                        } label: {
                            Image(systemName: "play.rectangle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!agent.isAvailable)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("删除工作区", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("取消", role: .cancel) { confirmDelete = nil }
            Button("删除", role: .destructive) {
                if let ws = confirmDelete { store.deleteWorkspace(ws) }
                confirmDelete = nil
            }
        } message: {
            if let ws = confirmDelete {
                Text("确定要删除「\(ws.name)」吗？此操作无法撤销。")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                ActiveAgentSessionsMenu(store: store)

                Button {
                    store.scanAgents()
                } label: {
                    Label(store.isScanningAgents ? copy.scanning : copy.scanAgents, systemImage: "magnifyingglass")
                }
                .disabled(store.isScanningAgents)
                .buttonStyle(.borderless)
            }
            .padding(12)
        }
    }

    private func sidebarNodeIcon(_ kind: NodeKind) -> String {
        switch kind {
        case .model: "cpu"
        case .agent: "terminal"
        case .consistency: "scope"
        }
    }
}

@MainActor
private struct ActiveAgentSessionsMenu: View {
    @Bindable var store: AppStore

    var body: some View {
        Menu {
            if store.activeAgentSessionNodes.isEmpty {
                Text("暂无活跃代理会话")
            } else {
                ForEach(store.activeAgentSessionNodes) { node in
                    Button(role: .destructive) {
                        store.resetPersistentChat(for: node)
                    } label: {
                        Label("\(node.title) · \(node.agentExecutable ?? "Agent")", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Label("活跃代理 \(store.activeAgentSessionNodes.count)", systemImage: "bolt.horizontal.circle")
                .frame(maxWidth: .infinity)
        }
        .disabled(store.activeAgentSessionNodes.isEmpty)
        .quickHelp("查看并关闭已启动的持久 Agent 会话。")
    }
}

@MainActor
private struct WorkspaceRow: View {
    @Bindable var store: AppStore
    let workspace: WorkspaceLocation
    var onRequestDelete: (WorkspaceLocation) -> Void = { _ in }
    @State private var draftName: String
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    init(store: AppStore, workspace: WorkspaceLocation, onRequestDelete: @escaping (WorkspaceLocation) -> Void = { _ in }) {
        self.store = store
        self.workspace = workspace
        self.onRequestDelete = onRequestDelete
        _draftName = State(initialValue: workspace.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            let isSelected = workspace.id == store.selectedWorkspace?.id
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                TextField(copy.workspace, text: $draftName)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .onSubmit {
                        store.updateWorkspaceName(workspace, name: draftName)
                    }
                Text(workspace.displayPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.selectWorkspace(workspace)
            }
            Spacer()
            Button(role: .destructive) {
                onRequestDelete(workspace)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .quickHelp("从列表中移除这个工作区记录。")
        }
        .padding(.vertical, 4)
        .onChange(of: workspace.name) { _, newValue in
            draftName = newValue
        }
    }
}
