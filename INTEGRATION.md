# boring.notch + Agent 与订阅

这是基于 boring.notch 的原生 SwiftUI 集成版本。顶部四个小按钮依次切换主页、暂存器/隔空投送、Agent、订阅剩余量。原项目功能继续保留。

## 使用

本机开发构建位于 `build/DerivedData/Build/Products/Debug/Islet.app`。打开应用，在刘海右上角点设置，选择 **Agent 与订阅**。

- **Agent 连接**：只提供 Pi、Codex、Claude Code、ZCode、Antigravity 五种连接。点对应工具的“安装连接”，然后重启该工具。Codex 还需要运行 `/hooks` 审核并启用新 Hook。安装前会在配置文件旁保存 `.boringnotch-backup-时间戳`；安装和移除都会保留其他 Hook。
- **刘海中的订阅可见性**：Claude、OpenAI、Gemini、Antigravity 各自有“显示剩余量”开关。默认全部显示，立即生效，重启后保留；隐藏卡片不影响后台同步。全部隐藏时显示设置提示。
- **自动同步订阅用量**：默认每 5 分钟刷新，也可以手动刷新。显示各窗口的剩余百分比、重置时间和上次更新时间。失败时保留上次成功数据并标记错误；没有额度数据时显示原因。
- **音乐**：打开“显示同步歌词”。优先读取 Apple Music 当前歌曲歌词，其他播放器按歌曲、歌手、专辑和时长查询 LRCLIB。同步歌词跟随进度，普通歌词显示首行；找不到时显示提示。切歌会取消旧请求并清空旧歌词。

Agent 页面提供多会话列表、工具筛选、运行/思考/完成状态、当前工具、项目/分支、任务清单进度、最近提问与原生 Markdown 回复。可以回到来源窗口，处理一次性工具审批和问题回答。Antigravity 当前为观察模式，权限仍在其原应用处理；不会从刘海静默授权。Terminal / iTerm 会尽量定位来源标签，其他终端回到应用窗口。

## 配额来源与范围

| 卡片 | 读取来源 | 显示范围 |
| --- | --- | --- |
| Claude | Claude Code 已有 OAuth 登录：自定义目录文件，或 Keychain / 默认凭据文件 | Claude 返回的会话、每周和模型额度 |
| OpenAI | Codex 已有登录，优先 wham 用量接口，失败时调用 Codex app-server `account/rateLimits/read` | Codex 订阅窗口及模型额度 |
| Gemini | Gemini CLI `.gemini/oauth_creds.json`，Code Assist quota API | CLI / Code Assist 的模型配额 |
| Antigravity | 已运行的同一用户 Antigravity 本地服务；不可用时调用已安装、已登录的 `agy` 的内置 `/usage` 报告 | Antigravity 自己的 Gemini、Claude/GPT 等模型额度及实际返回的窗口 |

Gemini 网页聊天额度、OpenAI 网页聊天的所有模型额度目前没有统一可读取接口，本版本不会用 CLI 配额冒充它们。Gemini 和 Antigravity 使用独立来源，互不借用登录凭据。`agy` 回退要求 1.1.11 或更新版本，先检查版本，再执行 `-p /usage --output-format json`，不提交模型提示。

登录凭据只在辅助进程内读取和使用，不复制进本应用、不写入本应用设置、不打印日志。Gemini 过期 token 在已安装 CLI 的 OAuth client 可用时仅在内存刷新。Antigravity 本地 HTTPS 只允许连接同一用户进程拥有的 `127.0.0.1` 端口，使用其 CSRF token，拒绝重定向；网络订阅请求保持正常 TLS 校验。

主应用保留 App Sandbox。文件和 CLI 操作在 boring.notch 原有的 XPC Helper 内执行。Agent 通过权限为 0600 的 `/tmp/boringnotch-用户ID/agent.sock` 通信；桥接程序安装到 `~/.boringnotch/notch-agent-bridge`，Pi 扩展安装到 `~/.pi/agent/extensions/boringnotch.ts`。

## 构建与测试

需要完整 Xcode 和其 Swift 工具链。依赖版本沿用上游的 Package.resolved。构建脚本生成本机开发签名应用，Xcode 工程也可直接打开；工程会自动编译并打包 Agent bridge 和 Pi 扩展。

```sh
./scripts/build-app.sh
swift test --package-path Packages/NotchIntegrations --scratch-path build/IntegrationPackage
```

发行版最低版本设为 macOS 15，与上游预编译 MediaRemoteAdapter 匹配。应用名称为 Islet，使用独立 Bundle ID；不会启动上游 Sparkle 更新源。安装方式见 [INSTALL.md](INSTALL.md)。

可在应用运行时用合成数据检查真实 bridge → socket → XPC → 刘海流程，不需要安装用户 Hook，不会调用模型或执行请求展示的工具：

```sh
# 默认检查全部五种 Agent；脚本会创建临时 JSONL 文件
python3 scripts/smoke-agents.py
# Claude 审批或问题回答，需要在刘海点击完成
python3 scripts/smoke-agents.py --source claude --permission
python3 scripts/smoke-agents.py --source claude --question
# 移除合成会话及其临时文件
python3 scripts/smoke-agents.py --cleanup
```

## 本次验证

- Swift Package：117 项测试通过，覆盖 Hook 配置保留/幂等安装、五种来源生命周期、审批回答格式、任务进度、JSONL 增量/文件替换、歌词时间戳、四种配额解析和独立可见性。
- 本机 Debug 构建已通过；发布构建按 arm64 与 x86_64 两个架构打包应用、Helper 和 bridge。Intel 实机运行尚未验证。主应用 App Sandbox 保留。
- 当前 Mac：五种合成会话到达刘海，原生 Markdown 显示正常，Claude 一次审批/回答在真实 bridge 通道返回，设置开关即时改变卡片并在重启后保留。
- 当前登录：OpenAI、Antigravity 用量成功读取；Claude、Gemini 显示未登录提示。未改动本机五种 Agent 的真实 Hook 配置；各工具的真实新会话需要在设置中安装连接后验证。
- 歌词解析已测试；当前网易云歌曲没有找到 LRCLIB 歌词，未验证该播放器上有歌词歌曲的实播同步。歌词库的覆盖率会影响结果。

上游版本及改动位置见 [UPSTREAM_REVISIONS.md](UPSTREAM_REVISIONS.md)，许可证保留在根目录和 `Packages/NotchIntegrations/LICENSE-*`。
