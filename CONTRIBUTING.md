# 贡献指南

感谢对 Workflow Generator 的关注。本仓库目前以个人维护为主，欢迎小而具体的修改；重大改动请先提 issue 讨论。

## 提交前必做

1. `swift build` 通过。
2. `swift test` 全绿（109 个测试，覆盖路由、模型注册和工作流图）。
3. 提交信息遵循仓库已有格式：`type: short summary`，例如 `refactor: split AppStore undo/redo coordinator`。
4. 单个 commit 保持单一目的；不要把"顺手清理"和主线改动混在同一个 commit 里。

## 提交信息约定

参考已有 `git log` 的风格：

| 前缀 | 用途 |
| --- | --- |
| `feat:` | 新功能 |
| `fix:` | bug 修复 |
| `refactor:` | 不改行为的结构调整 |
| `perf:` | 性能优化 |
| `test:` | 单独补测试 |
| `docs:` | 文档（README、CONTRIBUTING） |
| `build:` / `ci:` | 构建或持续集成 |
| `chore:` | 其他杂项 |

## 风格约束

- Swift 代码遵循 `.swiftformat` 与 `.swiftlint.yml` 仓库根配置。
- 缩进 4 空格，行尾 LF。
- 不要新增 `try!` / `as!` 形式的强制解包。
- 测试用 XCTest 写在 `Tests/WorkflowGeneratorTests/` 下；新功能尽量带测试，纯函数逻辑可独立测。
- 中文注释可以保留；用户可见字符串跟随 `AppCopy` 或 `configuration.language` 走，不要硬编码。

## Pull Request

- PR 标题用一句话说清动机（"为什么"），正文用要点列"改了什么 / 怎么验"。
- 涉及持久化数据结构变更时，说明向后兼容策略（迁移 vs. 强制用户重置）。
- UI 改动附运行截图或一段 10 秒内的录屏（录屏可放仓库外的临时位置再删除）。

## 安全

- API Key、Secret、个人 Token 不允许进仓库。`.workflow-*` 工作区目录已经在 `.gitignore`，提交前 `git status --ignored` 自检。
- 不要提交 `dist/WorkflowGenerator.app`；它已经在 `.gitignore`。文档站代码已迁出至独立仓库，与本仓无关。

## 提问渠道

直接在 GitHub issue 提。
