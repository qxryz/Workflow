# AppStore 拆分方案（草案）

> 状态：调研稿 v0.1
> 目标文件：`Sources/WorkflowGenerator/Stores/AppStore.swift`（3,271 行 / 222 个方法 / 38 个属性）

## 动机

`AppStore` 已经演化成单文件"小型 UIApplicationDelegate"：它管理持久化、撤销 / 重做、节点 CRUD、画布选择、模型注册迁移、Agent 会话、空间路由缓存、工作流运行生命周期、一致性资料、设置导航。所有 222 个方法都能直接 mutate `configuration.workflow`，因此测试只能跑到 `XCTest` 之外就难以断言不变量。

进一步后果：

- 阅读时无法在 5 分钟内回答"撤销栈和持久化之间谁先发生"；
- 任何模型注册 / 工作流运行的 bug 修复都要进同一个文件，git blame 已经收敛成单点；
- `@Observable` 让 SwiftUI 视图可以"读 AppStore 任何一个属性"，等于隐式建立了一个超级依赖。

## 方法聚类（基于 `grep -n "^    func"`）

| 集群 | 行数范围 | 方法数 | 职责 |
| --- | --- | --- | --- |
| 1. 撤销 / 重做 | 95–137 | 5 | undoStack / redoStack 维护 |
| 2. 节点 CRUD | 139–371 | 13 | addNode / updateNode / 位置 / 选择 |
| 3. 节点聊天执行 | 373–470 | 6 | sendMessage / pauseExecution / openChatWindow |
| 4. 工作流运行生命周期 | 472–665 | 7 | startWorkflowRun / stopWorkflowRun / rerunCurrentLevel |
| 5. 工作流执行协调 | 663–960 | 12 | runWorkflow / executeWorkflowNode / 状态机 |
| 6. 模板与映射（纯函数） | 982–1199 | 11 | workflowPrompt / mappedPayload / edgeAllowsFlow |
| 7. 一致性上下文 | 1221–1383 | 9 | compileConsistencyContext / executeConsistencyNode |
| 8. 运行输入校验 | 1385–1448 | 5 | validateWorkflowRunInputs / syncWorkflowRunInputDefinitions |
| 9. 持久聊天 | 1451–1479 | 3 | setPersistentChatEnabled / resetPersistentChat |
| 10. 模型注册编辑 | 1481–1636 | 13 | beginRegistration / saveRegistration / validateModelRegistration |
| 11. 模型推断规则 | 1617–1636 | 4 | updateModelInferenceRule / add / delete / reset |
| 12. 提供商 + 模型拉取 | 1650–1760 | 12 | addProvider / fetchProviderModels / addFetchedModel / inferredModelProfile |
| 13. Agent | 1762–1804 | 4 | scanAgents / updateAgent / testAgentACP / deleteAgent |
| 14. 工作区 | 1806–1888 | 13 | createWorkspace / selectWorkspace / openSelectedWorkspaceInX |
| 15. 资产挂载 / 拖拽 | 1890–1998 | 8 | attachFiles / addDroppedFilesToCanvas / absorbingNodeId |
| 16. 一致性资产 | 2010–2164 | 12 | addConsistencyAssets / toggleConsistencyAssetLock |
| 17. 其它（私有 helpers） | 散落 | ~50 | 私有纯函数 / 索引查找 |

## 推荐拆分策略

不是把 `AppStore` 直接拆成 17 个 `@Observable` 组件，而是**先抽出两个层次的纯结构体 / 协调器**：

### 层次 1：纯结构 / 纯函数（`struct`，无 `@MainActor`）

- `UndoRedoCoordinator`（集群 1 + 6 中的 `dependenciesAreSatisfied` / `edgeAllowsFlow`）
- `WorkflowRunInputValidator`（集群 8）
- `WorkflowPromptResolver`（集群 6 的 workflowPrompt / resolveWorkflowTemplate / mappedPayload / mappedSpatialPayload / mappedArtifacts）
- `ModelInferenceRuleApplier`（集群 12 的 `inferredModelProfile`）

这些方法已经是纯函数：输入参数 + `configuration.workflow` 子集，输出新值或写回引用。它们可以独立测试，不需要 mock。

### 层次 2：协调器（`@MainActor @Observable` 子 store）

- `CanvasSelectionStore`（集群 2 的选择部分 + `setNodePosition` + `moveSelectedItems` + `snapSelectedItemsToGrid`）
- `ExecutionCoordinator`（集群 3 + 5 + 7）—— 唯一保留 `Task<Void, Never>` 和 async 流
- `RegistrationStore`（集群 10 + 11）—— 写时校验，单独 view 测
- `WorkspaceCoordinator`（集群 14）—— 与 `WorkspaceService` 串接
- `AssetHub`（集群 15 + 16）—— 拖拽、附件、一致性资产吸收

### 层次 3：`AppStore` 留作组合根

`AppStore` 仅保留：

- `configuration: AppConfiguration` 单一可观察源
- 对上面协调器的引用
- 一组 `save()` / `flushPendingSave()` 入口
- 初始化时的迁移 / 协调

视图层（`ContentView` / `SidebarView` 等）通过 `@Bindable` / `@Environment` 拿到 `AppStore`，但具体操作通过 `store.canvasSelection.moveSelectedItems(...)` 这样的路径走。

## 最小可行落地（已部分实施）

为了证明路径可行，本次提交做了两个**最小化**提取：

1. **`KeyboardPanController`**（在 `Views/CanvasKeyboardPan.swift`）—— 把 `CanvasView` 里 7 个 `@State` + 8 个 helper 方法组成的 WASD 平移逻辑抽到独立结构。`CanvasView` 只保留 `keyboardPan.bind(...)` 一行调用。
2. **（计划中）`UndoRedoCoordinator`**——纯结构体，仅 `recordSnapshot(current:) / undo(from:) / redo(from:)` 三个方法，外加 `canUndo` / `canRedo`。`AppStore` 持有 `private let undoCoordinator = UndoRedoCoordinator()`，所有 snapshot 调用转给它。

## 不拆的部分（明示）

- 工作流运行生命周期（集群 4 + 5 + 7）暂不动。它依赖 `configuration.workflow.runState.records` 这种复杂共享可变状态，做 `@Observable` 拆分需要先在 `WorkflowDocument` 里建更细粒度的 sub-store（`runState` 已经是嵌套结构，可以先尝试切分）。
- 私有 helpers 暂时留在 `AppStore` 内作为 private 方法；它们还没成为测试目标，且拆出后会让调用链变长。
- `SettingsSelection` 已经在自己的 `var settingsSelection = SettingsSelection()`，未来适合提到 `SettingsCoordinator`。

## 风险与回滚

- `@Observable` 在 SwiftUI 中通过 getter 注入，所以"读 `store.configuration.workflow.nodes.first?.title`"和"读 `store.canvasSelection.selectedNodeId`"在观测行为上不同——视图需要重写访问路径。这是 PR diff 的主要来源。
- 每次合并都应跑 `swift test` + `./script/build_and_run.sh --verify`。
- 一旦发现性能或观测问题，把协调器的 `@Observable` 改回 `AppStore` 内的 `var` 是 1–2 行的回滚。

## 后续

- 在 v0.2 里把 `ExecutionCoordinator` 和 `RegistrationStore` 拆出去，预期 `AppStore` 降到 1500 行左右。
- v0.3 给拆出的协调器补 XCTest，目标是把 92 个测试扩到 150+，并覆盖 `AppStore` 现有 0% 覆盖的执行路径。
