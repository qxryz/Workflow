import SwiftUI

@MainActor
struct ContentView: View {
    @Bindable var store: AppStore
    @State private var activeInspectorPanel: InspectorPanel? = .nodeAssets
    @State private var canvasZoomScale: Double = 1
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if store.selectedWorkspace == nil {
                WorkspaceGateView(store: store)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        CanvasView(
                            store: store,
                            inspectorExpanded: activeInspectorPanel != nil,
                            onTapEmptyCanvas: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    activeInspectorPanel = nil
                                }
                            }
                        )

                        AdaptiveInspectorView(store: store, activePanel: $activeInspectorPanel)
                            .frame(height: max(240, proxy.size.height - 16))
                            .padding(.trailing, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    store.refreshWorkbench()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp("刷新整个工作台")

                Button {
                    store.saveWorkflowWithConfirmation()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp(copy.saveWorkflow)

                Button {
                    store.isRunningWorkflow ? store.stopWorkflowRun() : store.startWorkflowRun()
                } label: {
                    Image(systemName: store.isRunningWorkflow ? "stop.circle" : "play.circle")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(store.isRunningWorkflow ? Color.red : Color.primary)
                .quickHelp(store.isRunningWorkflow ? "停止当前工作流运行" : "按逻辑箭头运行工作流")

                if store.isWaitingForNextLevel {
                    Button {
                        store.rerunCurrentLevel()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(Color.orange)
                    .quickHelp("重跑当前层级节点")
                }

                Button {
                    store.addNode(kind: .model)
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp(copy.modelNode)

                Button {
                    store.addNode(kind: .agent)
                } label: {
                    Image(systemName: "terminal")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp(copy.agentNode)

                Button {
                    store.addNode(kind: .consistency)
                } label: {
                    Image(systemName: "archivebox")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp(store.configuration.language == .zhCN ? "在画布放置一致性节点，用来收纳上游资产。" : "Place a consistency node on the canvas to collect upstream assets.")

                Button {
                    activeInspectorPanel = activeInspectorPanel == .nodeAssets ? nil : .nodeAssets
                } label: {
                    Image(systemName: "rectangle.3.group")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(activeInspectorPanel == .nodeAssets ? Color.accentColor : Color.primary)
                .quickHelp(copy.nodeAndAssets)

                Button {
                    activeInspectorPanel = activeInspectorPanel == .consistency ? nil : .consistency
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(activeInspectorPanel == .consistency ? Color.accentColor : Color.primary)
                .quickHelp(copy.consistencyWindow)

                Button {
                    store.setNodeInspectorAutoOpenLocked(!store.configuration.locksNodeInspectorAutoOpen)
                } label: {
                    Image(systemName: store.configuration.locksNodeInspectorAutoOpen ? "lock.fill" : "lock.open")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(store.configuration.locksNodeInspectorAutoOpen ? Color.accentColor : Color.primary)
                .quickHelp(copy.nodeLockHint)

                Menu {
                    Button {
                        store.openSelectedWorkspaceInFinder()
                    } label: {
                        Label("Finder", systemImage: "macwindow")
                    }
                    Button {
                        store.openSelectedWorkspaceInVSCode()
                    } label: {
                        Label("VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button {
                        store.openSelectedWorkspaceInTerminal()
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp(copy.openWith)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .quickHelp(copy.settings)
            }
        }
        .onChange(of: store.configuration.workflow.selectedNodeIds) { _, newValue in
            if !newValue.isEmpty, activeInspectorPanel == nil, !store.configuration.locksNodeInspectorAutoOpen {
                activeInspectorPanel = .nodeAssets
            }
        }
        .alert(copy.workflowSaved, isPresented: $store.showsSaveConfirmation) {
            Button(copy.ok, role: .cancel) { }
        } message: {
            Text(copy.workflowSavedMessage)
        }
    }
}



@MainActor
private struct WorkspaceGateView: View {
    @Bindable var store: AppStore
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(copy.createWorkspaceTitle)
                .font(.title2.bold())
            Text(copy.createWorkspaceDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button {
                store.createWorkspace()
            } label: {
                Label(copy.newWorkspace, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
