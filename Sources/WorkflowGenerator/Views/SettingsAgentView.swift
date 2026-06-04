import SwiftUI

@MainActor
struct AgentSettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local Agents")
                    .font(.title3.bold())
                Spacer()
                Button {
                    store.scanAgents()
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
            }

            List(store.configuration.agents) { agent in
                AgentSettingsRow(store: store, agent: agent)
            }
        }
    }
}

@MainActor
private struct AgentSettingsRow: View {
    @Bindable var store: AppStore
    @State var agent: AgentConfig
    @State private var showsAdvancedCommands = false
    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: agent.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(agent.isAvailable ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(agent.name)
                    Text(agent.path ?? agent.executable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(agent.isAvailable ? "Available" : "Missing")
                    .foregroundStyle(.secondary)
                Button {
                    store.launchAgentTUI(agent)
                } label: {
                    Label("Launch", systemImage: "play.rectangle")
                }
                .disabled(!agent.isAvailable)
                Button {
                    store.testAgentACP(agent)
                } label: {
                    Label(copy.testACP, systemImage: "checkmark.seal")
                }
                Button(role: .destructive) {
                    store.deleteAgent(agent)
                } label: {
                    Image(systemName: "trash")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showsAdvancedCommands.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showsAdvancedCommands ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "slider.horizontal.3")
                        Text("高级")
                        Text("启动命令与 ACP 配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsAdvancedCommands {
                    commandCard(
                        title: copy.standardLaunchTemplate,
                        badge: "TUI",
                        symbol: "terminal",
                        description: "点右侧 Launch 按钮时使用，用来在当前工作区打开这个 CLI 的交互界面。",
                        tokenHint: "{executable} 会替换成本机 CLI 路径。",
                        text: $agent.invocationTemplate,
                        recommended: defaultAgent?.invocationTemplate
                    )
                    commandCard(
                        title: copy.acpLaunchTemplate,
                        badge: "ACP",
                        symbol: "point.3.connected.trianglepath.dotted",
                        description: "节点聊天优先使用。它必须启动一个会讲 ACP/JSON-RPC 的桥接进程，负责真正的持久 agent 对话。",
                        tokenHint: "Claude/Codex 常用 npx 桥；其他 CLI 通常使用 {executable} acp 或 --acp。",
                        text: $agent.acpInvocationTemplate,
                        recommended: defaultAgent?.acpInvocationTemplate
                    )
                }
            }
            .padding(10)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            if let status = store.agentACPStatuses[agent.id], !status.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: status.hasPrefix("ACP connected") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.hasPrefix("ACP connected") ? .green : .orange)
                    ScrollView {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.hasPrefix("ACP connected") ? .green : .orange)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 92)
                }
                .padding(10)
                .background((status.hasPrefix("ACP connected") ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 4)
        .onChange(of: agent) { _, newValue in
            store.updateAgent(newValue)
        }
    }

    private var defaultAgent: AgentConfig? {
        AgentConfig.candidates.first { $0.executable == agent.executable }
    }

    private func commandCard(title: String, badge: String, symbol: String, description: String, tokenHint: String, text: Binding<String>, recommended: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
                Spacer()
                if let recommended, recommended != text.wrappedValue {
                    Button {
                        text.wrappedValue = recommended
                    } label: {
                        Label("恢复推荐", systemImage: "arrow.counterclockwise")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            Text(tokenHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12))
        }
    }
}

