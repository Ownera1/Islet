# boring.notch + Agent 与订阅

这是基于 boring.notch 的原生 SwiftUI 集成版本。顶部四个小按钮依次切换主页、暂存器/隔空投送、Agent、订阅剩余量。原项目功能继续保留。

## 使用

本机开发构建位于 `build/DerivedData/Build/Products/Debug/Islet.app`。打开应用，在刘海右上角点设置，选择 **Agent 与订阅**。

- **Agent 连接**：只提供 Pi、Codex、Claude Code、ZCode、Antigravity 五种连接。点对应工具的“安装连接”，然后重启该工具。Codex 还需要运行 `/hooks` 审核并启用新 Hook。安装前会在配置文件旁保存 `.boringnotch-backup-时间戳`；安装和移除都会保留其他 Hook。
- **刘海中的订阅可见性**：Claude、OpenAI、Google AI 各自有“显示剩余量”开关。Google AI 将 Antigravity 应用与 agy CLI 的共享额度显示在唯一一张卡片中，沿用原 Antigravity 的显示设置。默认全部显示，立即生效，重启后保留；隐藏卡片不影响后台同步。全部隐藏时显示设置提示。Gemini CLI 不展示、不参与自动同步。
- **自动同步订阅用量**：默认每 5 分钟刷新，也可以手动刷新。显示各窗口的剩余百分比、重置时间和上次更新时间。失败时保留上次成功数据并标记错误；没有额度数据时显示原因。无论卡片是否显示，后台检测均不打开登录页面；请手动到对应工具完成登录。
- **音乐**：打开“显示同步歌词”。优先读取 Apple Music 当前歌曲歌词，其他播放器按歌曲、歌手、专辑和时长查询 LRCLIB。同步歌词跟随进度，普通歌词显示首行；找不到时显示提示。切歌会取消旧请求并清空旧歌词。

Agent 页面提供多会话列表、工具筛选、运行/思考/完成状态、当前工具、项目/分支、任务清单进度、最近提问与原生 Markdown 回复。可以回到来源窗口，处理一次性工具审批和问题回答。Antigravity 当前为观察模式，权限仍在其原应用处理；不会从刘海静默授权。Terminal / iTerm 会尽量定位来源标签，其他终端回到应用窗口。

## 配额来源与范围

| 卡片 | 读取来源 | 显示范围 |
| --- | --- | --- |
| Claude | Claude Code 已有 OAuth 登录：所配置目录自己的钥匙串条目或凭据文件，没有时用默认 `~/.claude` 的登录 | Claude 返回的会话、每周和模型额度 |
| OpenAI | Codex 已有登录，优先 wham 用量接口，失败时调用 Codex app-server `account/rateLimits/read` | Codex 订阅窗口及模型额度 |
| Google AI | 优先自动查找 `~/.local/bin/agy`、CLI 安装目录、绝对 PATH 目录及常用安装目录，并静默读取 `/usage`；失败后只查询已运行的同一用户 Antigravity 应用本地服务 | Antigravity / agy 的共享模型额度及实际返回的窗口，标明当前使用的来源 |

Google AI 每轮只返回第一份成功读取的额度快照：CLI 成功时不再查询应用；CLI 安装、版本、登录、超时或解析失败时，才尝试应用。同一额度池不相加、不取平均，也不在 Gemini 模型池和第三方模型池之间混用窗口。两种来源都失败时显示各自原因和手动登录提醒；Google AI 卡片没有网页跳转按钮。来源切换不改变卡片或可见性开关，失败时仍保留上次成功快照。

Gemini CLI 的旧数据解析保留兼容，但不进入当前额度页面或后台轮询。网页聊天的所有模型额度目前没有统一可读取接口，本版本不会用 CLI 配额冒充它们。`agy` 要求 1.1.11 或更新的稳定版本，先检查版本，再执行 `-p /usage --output-format json`，不提交模型提示。版本检查和配额命令均在禁止执行 `open`、AppleScript、应用主程序及访问 LaunchServices / Apple Events 的系统沙箱内运行，限制继承到子进程；同时使用无终端输入和禁止浏览器的环境。沙箱不可用时不启动 CLI，不回退到无限制执行。

登录凭据只在辅助进程及 CLI 内读取和使用，不复制进本应用、不写入本应用设置、不打印凭据。Antigravity 本地 HTTPS 只允许连接同一用户进程拥有的 `127.0.0.1` 端口，使用其 CSRF token，拒绝重定向；网络订阅请求保持正常 TLS 校验。

主应用保留 App Sandbox。文件和 CLI 操作在 boring.notch 原有的 XPC Helper 内执行。Helper 设置 `XPCService.JoinExistingSession = true`，加入调用者的登录安全会话，让其启动的 agy 能读取已有钥匙串凭据；不修改钥匙串权限，也不复制 token。钥匙串访问失败单独提示，不误报为未登录。禁止网页跳转的 CLI 子进程沙箱继续生效。Agent 通过权限为 0600 的 `/tmp/boringnotch-用户ID/agent.sock` 通信；桥接程序安装到 `~/.boringnotch/notch-agent-bridge`，Pi 扩展安装到 `~/.pi/agent/extensions/boringnotch.ts`。

## Claude 桌面版

详细说明和实测步骤见 [docs/claude-desktop-support.md](docs/claude-desktop-support.md)。

- **Code 标签页**：通过与命令行版相同的 Hook 显示，卡片标注「Claude 桌面版」，点击回到桌面版。审批由桌面版自己的卡片处理：刘海只显示等待状态并提示到桌面版处理，不提供批准或拒绝按钮。
- **Cowork**：Cowork 在虚拟机里运行，不触发 Hook。Helper 每 2 秒只读扫描 `~/Library/Application Support/Claude/local-agent-mode-sessions`，显示运行中、等待审批 / 回答（仅展示）和完成；点击打开桌面版中的该任务。归档、隐藏（Dispatch、radar 等）和 10 分钟内没有活动的旧会话不显示。同一会话已有 Hook 卡片时以 Hook 卡片为准。
- **额度**：只来自命令行版 Claude Code 的登录。Islet 不解密桌面版的登录凭据，不读取 "Claude Safe Storage"，不刷新 token，也不为取额度调用模型。只用桌面版时卡片会提示在终端运行一次 `claude` 登录。
- **调试**：bridge 只在设置 `BORINGNOTCH_DEBUG=1` 时写 `/tmp/notch-agent-bridge.log`（权限 0600），不记录 Hook 内容。

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

### 订阅修复

139 项 Swift Package 测试通过，覆盖 CLI 优先且成功后不再访问应用、CLI 各类失败后按顺序回退、空配额不伪造零用量、双来源失败文字提醒、取消不回退，以及 agy 检测、版本门槛、XPC 新旧数据兼容、浏览器和子进程应用启动拦截、OAuth 提前停止、网络超时与登录失败区分。新增回归检查钥匙串访问失败不会被误报为未登录，也不会阻断成功的凭据回退。另通过 8 项滚动手势测试、12 项表面渲染检查和 3 项更新源策略测试。

0.1.4 的 Debug 应用和 Helper 已编译通过。Apple Silicon 实机验证：修复前终端沙箱查询成功，而真实 XPC 查询因钥匙串 `exit status 36` 失败；Helper 加入用户登录安全会话并重启后，真实应用通过 XPC 成功读取 agy 1.2.16 的 2 组、4 个额度窗口，界面显示“来源：agy CLI”、剩余百分比和重置时间。只显示一张 Google AI 卡片，没有 Google 网页跳转按钮。此前已验证双来源失败时完整显示文字提醒，agy 登录回退的 `open` 调用被系统沙箱拒绝。发布包校验额外要求 Helper 的 `JoinExistingSession` 为 true，避免该配置在打包时遗漏。

### 此前的集成验证

- Swift Package：117 项测试通过，覆盖 Hook 配置保留/幂等安装、五种来源生命周期、审批回答格式、任务进度、JSONL 增量/文件替换、歌词时间戳、四种配额解析和独立可见性。
- 本机 Debug 构建已通过；发布构建按 arm64 与 x86_64 两个架构打包应用、Helper 和 bridge。Intel 实机运行尚未验证。主应用 App Sandbox 保留。
- 当前 Mac：五种合成会话到达刘海，原生 Markdown 显示正常，Claude 一次审批/回答在真实 bridge 通道返回，设置开关即时改变卡片并在重启后保留。
- 当前登录：OpenAI、Antigravity 用量成功读取；Claude、Gemini 显示未登录提示。未改动本机五种 Agent 的真实 Hook 配置；各工具的真实新会话需要在设置中安装连接后验证。
- 歌词解析已测试；当前网易云歌曲没有找到 LRCLIB 歌词，未验证该播放器上有歌词歌曲的实播同步。歌词库的覆盖率会影响结果。

上游版本及改动位置见 [UPSTREAM_REVISIONS.md](UPSTREAM_REVISIONS.md)，许可证保留在根目录和 `Packages/NotchIntegrations/LICENSE-*`。
