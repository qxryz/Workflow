import Foundation

struct AppCopy {
    let locale: AppLanguage

    var general: String { locale == .zhCN ? "通用" : "General" }
    var appearance: String { locale == .zhCN ? "外观" : "Appearance" }
    var appearanceMode: String { locale == .zhCN ? "显示模式" : "Mode" }
    var lightMode: String { locale == .zhCN ? "日间模式" : "Light" }
    var darkMode: String { locale == .zhCN ? "夜间模式" : "Dark" }
    var themeColors: String { locale == .zhCN ? "主题颜色" : "Theme Colors" }
    var accentColor: String { locale == .zhCN ? "强调色" : "Accent Color" }
    var canvasBackgroundFollowsMode: String { locale == .zhCN ? "画布背景会跟随日间/夜间模式自动切换。" : "Canvas background follows Light/Dark mode automatically." }
    var canvasPattern: String { locale == .zhCN ? "画布图案" : "Canvas Pattern" }
    var canvasPatternHint: String { locale == .zhCN ? "这里控制工作台底纹；网格密度和吸附仍在通用页管理。" : "Controls the workbench pattern. Grid density and snapping stay in General." }
    var gridPattern: String { locale == .zhCN ? "方格" : "Grid" }
    var dotsPattern: String { locale == .zhCN ? "点阵" : "Dots" }
    var blueprintPattern: String { locale == .zhCN ? "蓝图" : "Blueprint" }
    var noPattern: String { locale == .zhCN ? "无图案" : "None" }
    var providers: String { locale == .zhCN ? "提供商" : "Providers" }
    var models: String { locale == .zhCN ? "模型" : "Models" }
    var agents: String { locale == .zhCN ? "代理" : "Agents" }
    var reset: String { locale == .zhCN ? "重置" : "Reset" }
    var resetWorkspaceTitle: String { locale == .zhCN ? "重置当前工作区" : "Reset Current Workspace" }
    var resetWorkspaceDescription: String { locale == .zhCN ? "只重置当前工作区：工作流、运行输入、变量、Secret、日志和工作区内资产记录会回到初始状态；模型、提供商、语言、代理配置都会保留。" : "Resets only the current workspace: workflow, run inputs, variables, secrets, logs, and workspace asset records return to the starter state. Models, providers, language, and agent settings are preserved." }
    var resetWorkspaceUnavailable: String { locale == .zhCN ? "创建或打开工作区后才能重置工作区。" : "Create or open a workspace before resetting it." }
    var resetAppTitle: String { locale == .zhCN ? "重置 App 配置" : "Reset App Configuration" }
    var resetAppDescription: String { locale == .zhCN ? "恢复应用原始配置：模型、提供商、代理、语言和工作区列表都会回到初始状态；不会删除磁盘上的工作区文件。" : "Restores the app defaults for models, providers, agents, language, and workspace list. Workspace files on disk are not deleted." }
    var languageLabel: String { locale == .zhCN ? "语言" : "Language" }
    var appLanguage: String { locale == .zhCN ? "应用语言" : "App Language" }
    var saveAndRefresh: String { locale == .zhCN ? "保存并刷新" : "Save & Refresh" }
    var languageHint: String { locale == .zhCN ? "保存后会刷新设置窗口和工作台主要文案。" : "Saving refreshes the main copy in Settings and the workbench." }
    var helpAndDocs: String { locale == .zhCN ? "帮助与文档" : "Help & Docs" }
    var openDocsHome: String { locale == .zhCN ? "打开使用文档首页" : "Open Docs Home" }
    var docsHomeHint: String { locale == .zhCN ? "打开 workflow.zhouzhou.dev，查看工作区、节点、模型接口和运行工作流的使用教程。" : "Opens workflow.zhouzhou.dev for workspace, node, model endpoint, and workflow run tutorials." }
    var restoreProviders: String { locale == .zhCN ? "恢复预设" : "Restore" }
    var restoreProvidersHint: String { locale == .zhCN ? "只恢复内置提供商。应用不再从界面新增自定义提供商。" : "Restores built-in providers only. The app no longer creates custom providers from the UI." }
    var delete: String { locale == .zhCN ? "删除" : "Delete" }
    var search: String { locale == .zhCN ? "搜索" : "Search" }
    var noProviderSelected: String { locale == .zhCN ? "未选择提供商" : "No Provider Selected" }
    var noProviderDescription: String { locale == .zhCN ? "从左侧选择或新增一个提供商。" : "Select or add a provider from the list." }
    var model: String { locale == .zhCN ? "模型" : "Models" }
    var newModel: String { locale == .zhCN ? "新建" : "New" }
    var testConnection: String { locale == .zhCN ? "测试连接" : "Test" }
    var fetchModels: String { locale == .zhCN ? "获取模型列表" : "Fetch Models" }
    var manageModels: String { locale == .zhCN ? "管理全部模型" : "Manage All Models" }
    var noModels: String { locale == .zhCN ? "未添加模型" : "No models added" }
    var connectionNotes: String { locale == .zhCN ? "连接说明" : "Connection Notes" }
    var selected: String { locale == .zhCN ? "已选择" : "Selected" }
    var availableModels: String { locale == .zhCN ? "可用模型" : "Available Models" }
    var close: String { locale == .zhCN ? "关闭" : "Close" }
    var providerModelHint: String { locale == .zhCN ? "点击模型可加入或取消加入到应用模型列表。" : "Click a model to add or remove it from the app model list." }
    var standardLaunchTemplate: String { locale == .zhCN ? "普通启动命令" : "Standard Launch Command" }
    var acpLaunchTemplate: String { locale == .zhCN ? "ACP 启动命令" : "ACP Launch Command" }
    var testACP: String { locale == .zhCN ? "测试 ACP" : "Test ACP" }

    var saveWorkflow: String { locale == .zhCN ? "保存工作流" : "Save Workflow" }
    var modelNode: String { locale == .zhCN ? "模型节点" : "Model Node" }
    var agentNode: String { locale == .zhCN ? "代理节点" : "Agent Node" }
    var openWith: String { locale == .zhCN ? "打开方式" : "Open With" }
    var settings: String { locale == .zhCN ? "设置" : "Settings" }
    var workflowSaved: String { locale == .zhCN ? "工作流已保存" : "Workflow Saved" }
    var ok: String { locale == .zhCN ? "好" : "OK" }
    var workflowSavedMessage: String { locale == .zhCN ? "当前工作流已写入工作区的 workflow.json。" : "The current workflow has been written to workflow.json in the workspace." }
    var createWorkspaceTitle: String { locale == .zhCN ? "创建工作区后开始" : "Create a workspace to start" }
    var createWorkspaceDescription: String { locale == .zhCN ? "将在项目文件夹里初始化一个 .workflow-名称 文件夹，用来记录这个工作流。" : "A .workflow-name folder will be initialized inside the project folder and will store this workflow's records." }
    var newWorkspace: String { locale == .zhCN ? "新建工作区" : "New Workspace" }
    var openWorkspace: String { locale == .zhCN ? "打开工作区" : "Open Workspace" }
    var workspace: String { locale == .zhCN ? "工作区" : "Workspace" }
    var workflow: String { locale == .zhCN ? "工作流" : "Workflow" }
    var detectedAgents: String { locale == .zhCN ? "检测到的代理" : "Detected Agents" }
    var scanAgents: String { locale == .zhCN ? "扫描代理" : "Scan Agents" }
    var scanning: String { locale == .zhCN ? "扫描中" : "Scanning" }
    var launchTUI: String { locale == .zhCN ? "在工作区启动 TUI" : "Launch TUI in selected workspace" }

    var noNodeSelected: String { locale == .zhCN ? "未选择节点" : "No Node Selected" }
    var node: String { locale == .zhCN ? "节点" : "Node" }
    var title: String { locale == .zhCN ? "标题" : "Title" }
    var description: String { locale == .zhCN ? "描述" : "Description" }
    var kind: String { locale == .zhCN ? "类型" : "Kind" }
    var nodeConfiguration: String { locale == .zhCN ? "节点配置" : "Node Configuration" }
    var nodeStyle: String { locale == .zhCN ? "节点风格" : "Node Style" }
    var nodeLockHint: String { locale == .zhCN ? "锁上后，点击画布节点不会自动弹出节点/资产面板；只能用顶部节点/资产按钮手动打开。" : "When locked, selecting canvas nodes will not auto-open Node / Assets. Use the toolbar button to open it manually." }
    var chat: String { locale == .zhCN ? "聊天" : "Chat" }
    var noMessages: String { locale == .zhCN ? "还没有消息。" : "No messages yet." }
    var pendingAttachments: String { locale == .zhCN ? "待发送附件" : "Pending Attachments" }
    var messageThisNode: String { locale == .zhCN ? "给这个节点发消息" : "Message this node" }
    var attach: String { locale == .zhCN ? "附件" : "Attach" }
    var send: String { locale == .zhCN ? "发送" : "Send" }
    var pause: String { locale == .zhCN ? "暂停" : "Pause" }
    var responsePaused: String { locale == .zhCN ? "\n\n[已暂停]" : "\n\n[Paused]" }
    var persistentChat: String { locale == .zhCN ? "持久对话" : "Persistent Chat" }
    var persistentChatStarted: String { locale == .zhCN ? "此节点的持久对话已开始。" : "Persistent conversation has started for this node." }
    var agentPersistentChatIntro: String { locale == .zhCN ? "第一次发送会绑定这个节点的 Agent 会话；之后只发送新消息，不再重发完整历史。" : "The first send binds this node to an agent session; later sends pass only the new message instead of replaying the whole transcript." }
    var modelPersistentChatIntro: String { locale == .zhCN ? "模型接口通常需要服务端或客户端维护上下文；开始后尽量不要切换模型，否则上下文可能丢失。" : "Model APIs need server-side or client-side context. Avoid switching models after the chat starts or context may be lost." }
    var modelChangedWarning: String { locale == .zhCN ? "当前对话已绑定到第一次使用的模型。切换模型可能导致上下文丢失，建议先重置会话。" : "This conversation is bound to the first model used. Switching models may lose context; reset the conversation first." }
    var resetConversation: String { locale == .zhCN ? "重置会话" : "Reset Conversation" }
    var assets: String { locale == .zhCN ? "资产" : "Assets" }
    var nodeAndAssets: String { locale == .zhCN ? "节点/资产" : "Node / Assets" }
    var noAssets: String { locale == .zhCN ? "还没有资产。" : "No assets attached." }
    var openChat: String { locale == .zhCN ? "展开聊天" : "Open Chat" }
    var outputSummary: String { locale == .zhCN ? "输出概要" : "Output Summary" }
    var outputs: String { locale == .zhCN ? "输出" : "Outputs" }
    var textOutput: String { locale == .zhCN ? "文本输出" : "Text Output" }
    var imageOutput: String { locale == .zhCN ? "图像输出" : "Image Output" }
    var videoOutput: String { locale == .zhCN ? "视频输出" : "Video Output" }
    var audioOutput: String { locale == .zhCN ? "音频输出" : "Audio Output" }
    var fileOutput: String { locale == .zhCN ? "文件输出" : "File Output" }
    var waitingForOutput: String { locale == .zhCN ? "等待模型输出。" : "Waiting for model output." }
    var noMediaYet: String { locale == .zhCN ? "暂未返回这种模态的资产。" : "No returned asset for this modality yet." }
    var consistencyWindow: String { locale == .zhCN ? "一致性窗口" : "Consistency Window" }
    var stylePrompt: String { locale == .zhCN ? "风格提示词" : "Style prompt" }
    var seed: String { locale == .zhCN ? "种子" : "Seed" }
    var addReferenceAsset: String { locale == .zhCN ? "添加参考资产" : "Add Reference Asset" }
    var consistencyCategories: String { locale == .zhCN ? "一致性类别" : "Consistency Categories" }
    var addConsistencyCategory: String { locale == .zhCN ? "新增类别" : "Add Category" }
    var categoryName: String { locale == .zhCN ? "类别名称" : "Category Name" }
    var categoryType: String { locale == .zhCN ? "类别类型" : "Category Type" }
    var categoryDescription: String { locale == .zhCN ? "补充描述" : "Additional Notes" }
    var categoryDescriptionPrompt: String { locale == .zhCN ? "继续写这个类别的具体约束、禁忌或参考资产用途" : "Add concrete constraints, exclusions, or reference usage notes" }
    var noReferenceAssets: String { locale == .zhCN ? "还没有参考资产。" : "No reference assets yet." }

    var importImageToCanvas: String { locale == .zhCN ? "导入图片到画布" : "Import Image to Canvas" }
    var imageAsReference: String { locale == .zhCN ? "作为参考图" : "Use as Reference Image" }
    var importVideoToCanvas: String { locale == .zhCN ? "导入视频到画布" : "Import Video to Canvas" }
    var videoAsReference: String { locale == .zhCN ? "作为参考视频" : "Use as Reference Video" }
    var importAudioToCanvas: String { locale == .zhCN ? "导入音频到画布" : "Import Audio to Canvas" }
    var audioAsReference: String { locale == .zhCN ? "作为参考音频" : "Use as Reference Audio" }
    var saveColor: String { locale == .zhCN ? "保存" : "Save" }
    var shape: String { locale == .zhCN ? "形状" : "Shape" }
    var nodeURL: String { locale == .zhCN ? "网址 URL" : "URL" }
}
