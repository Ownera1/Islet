<img src="boringNotch/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" height="96" alt="Islet 图标">

# Islet

原名 Agent Usage Notch。应用名称、安装包和仓库现统一为 Islet，保留原有设置和 Agent 连接。

基于 [boring.notch](https://github.com/TheBoredTeam/boring.notch) 的原生 macOS 刘海应用，集成 [CodeIsland](https://github.com/wxtsky/CodeIsland) 的 Agent 会话监控、订阅剩余量和音乐歌词，并支持 Claude 桌面版的 Code 标签页与 Cowork 任务。

顶部小按钮切换四个页面：**主页 · 暂存器/隔空投送 · Agent · 订阅剩余量**。

当前版本：**0.1.12**（build 14）。

## 安装

从 [最新 GitHub Release](https://github.com/Ownera1/Islet/releases/latest) 下载 DMG，将其中的 `Islet.app` 拖入“应用程序”。本仓库已公开，源码和安装包均可直接访问，无需 GitHub 登录。

- macOS **15 或更新版本**。
- 通用二进制包含 **Apple Silicon / Intel**。实机运行验证使用 Apple Silicon；外接显示器 DDC/CI 亮度调节仅支持 Apple 芯片。
- 当前发行包使用本地签名，**尚未经过 Apple 公证**。首次打开可能需要在“系统设置 → 隐私与安全性”允许。
- 0.1.3 起通过 Sparkle 在应用内检查、下载、验证并安装 GitHub Release 更新。0.1.2 及更早版本需要先手动安装一次新版本。
- 升级到 0.1.10 后如果 HUD 开关被自动关闭，请到“系统设置 → 隐私与安全性 → 辅助功能”删除旧的 Islet 条目，再在 Islet 设置中重新开启 HUD 并授权。

具体步骤见 [INSTALL.md](INSTALL.md)，签名、发布和首次升级说明见 [UPDATES.md](UPDATES.md)。

## 功能

### Agent

- 支持 Pi、Codex、Claude Code、ZCode、Antigravity 五种连接，以及 Claude 桌面版。显示多会话状态、工具调用、任务进度、最近提问、Markdown 回复，可跳回来源窗口。
- 一次性工具审批和问题回答直接在刘海中处理。Antigravity 当前为观察模式，审批仍由原应用处理。
- Agent 页支持全部总览与各框架切换，单行／双行样式可持久保存；名称始终完整显示，按实时状态分组，审批到达时自动切到对应框架。
- 对话结束后自动展开 Agent 状态页并选中对应会话（可在“设置 → Agent 与订阅 → Agent 显示”中关闭）；按设置的秒数自动收起（默认 5 秒），指针停在刘海上或等待审批／回答时保持展开。
- **Claude 桌面版**：Code 标签页的会话卡片标注「Claude 桌面版」，审批可在刘海中允许或拒绝，在桌面版自己的卡片中处理后刘海的审批卡会在工具运行结束时自动移除。Cowork 任务只读显示运行、等待和完成状态，审批需在桌面版中处理，点击打开对应任务。详见 [docs/claude-desktop-support.md](docs/claude-desktop-support.md)。

### 订阅剩余量

- Claude、OpenAI、Google AI 三张额度卡片，每 5 分钟同步，显示剩余百分比、重置时间、读取来源和数据更新时间；设置中各有独立的显示开关，隐藏卡片不影响后台同步。
- Claude 读取命令行版 Claude Code 的登录，优先使用所配置 Claude 目录（`CLAUDE_CONFIG_DIR`）自己的登录，没有时回退到默认 `~/.claude`。只用桌面版时，卡片会提示在终端运行一次 `claude` 登录后即可显示实时额度；不解密桌面版凭据，也不刷新 token。
- OpenAI 读取 Codex 配额，不代表网页聊天中所有模型的限制。
- Google AI 将 agy CLI 与 Antigravity 作为同一个共享额度池：优先静默读取 agy CLI，失败后读取已运行的 Antigravity 应用，不相加或平均。Gemini CLI 不参与额度页面或后台轮询。两种来源均不可用时只显示文字提醒，不提供网页跳转。

### 显示器与 HUD

- 开启“刘海跟随指针切换显示器”后，刘海移到指针停留的显示器；刘海展开、拖放文件或显示提示时不切换。关闭后固定在首选显示器，首选屏断开时回退，重连后恢复。
- HUD 权限与媒体键拦截统一由 Helper 处理，开启时定时检查按键拦截，丢失后自动恢复，无法恢复时关闭开关并提示原因。
- 亮度键调节指针所在的显示器：内置屏和 Apple 显示器用系统接口，其他外接显示器通过 DDC/CI 调节，不支持的显示器交给系统处理。若 BetterDisplay 等工具也接管了亮度键，建议在其中关闭。

### 音乐与歌词

- Apple Music 自带歌词优先，缺失时严格匹配网易云歌曲并回退到 LRCLIB。支持 YRC／增强 LRC 逐字时间与普通 LRC 行级扫光，切歌取消旧查询。
- Home 显示当前歌词和下一句预告；引号按钮切换歌词专注模式。专注歌词可点击跳转，手动滚动后 4 秒恢复跟随，设置中可微调时间偏移。自动专注只在每次展开 Home 时判断一次，手动退出后不会被重新拉回。
- 收起态可选关闭、仅外接显示器或所有显示器显示歌词；无硬件刘海屏显示单句；内置刘海屏由刘海本身向下延伸出等宽歌词条，演唱时常驻，间奏和暂停时收回，指针靠近时自动让开。支持长句滚动。默认仅在无硬件刘海屏显示。
- 退出 Islet 时，读取播放信息的后台进程随之结束，不再残留。

### 其他

- 设置界面全部为中文。
- 保留 boring.notch 的原生主页、媒体控制、日历、暂存器和隔空投送等功能。

首次使用 Agent 请到 **设置 → Agent 与订阅** 安装对应连接；配置会先备份并保留其他 Hook。详细来源、范围和验证边界见 [INTEGRATION.md](INTEGRATION.md)。

## 版本记录

| 版本 | 主要变化 |
| --- | --- |
| 0.1.12 | 内置刘海屏收起态歌词改为刘海等宽向下延伸，演唱时常驻、指针靠近自动让开 |
| 0.1.11 | Agent 页跳转到 Codex 桌面版对话；Codex hook 超时改为 3 秒 |
| 0.1.10 | 刘海跟随指针切换显示器；外接显示器 DDC/CI 亮度；HUD 拦截丢失自动恢复；完成状态页自动收起；设置全面汉化；修复播放信息进程残留 |
| 0.1.9 | Claude 桌面版 Code 标签页会话与审批、Cowork 任务状态；Claude 额度按配置目录查找登录；bridge 调试日志默认关闭 |
| 0.1.8 | 对话结束后自动展开 Agent 状态页；修复日历操作误入歌词专注模式 |
| 0.1.5–0.1.7 | 显示器回退与恢复；HUD 统一由 Helper 处理；Agent 全部总览与单行／双行样式；收起态歌词；移除主应用和 Helper 的调试权限 |
| 0.1.4 | agy CLI 与 Antigravity 合并为一张 Google AI 卡片；修复 XPC 后台钥匙串访问误报未登录 |
| 0.1.3 | Sparkle 应用内更新；两种音乐布局 |
| 0.1.2 | 修复内容滚动误收起刘海 |
| 0.1.1 | “极简终端”应用图标 |

每个版本的完整说明见 [updater/release-notes](updater/release-notes)。

## 开发与打包

需要完整 Xcode、Swift 工具链和 Python 3。Swift 依赖版本保留在工程的 `Package.resolved` 中。

```sh
# 本机 Debug 构建（存在 Apple Development 证书时自动重签，避免每次重建后丢失辅助功能授权；
# 可用 ISLET_SIGN_IDENTITY 指定证书，设为 "-" 保持 ad-hoc）
./scripts/build-app.sh
# 集成测试
swift test --package-path Packages/NotchIntegrations --scratch-path build/IntegrationPackage
# 滚动与收起手势回归测试
./scripts/test-pan-gesture.sh
# 展开背景、顶部贴合和圆角裁剪渲染回归
./scripts/test-notch-surface.sh
# 更新源策略测试
python3 scripts/test-update-pipeline.py
# Agent 框架状态与歌词组件渲染（先完成 Debug 构建和集成测试）
./scripts/test-agent-lyrics.sh
# 通用 Release 构建
./scripts/build-app.sh Release 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
# 以下回归测试使用 Release 构建产物
./scripts/test-hud-lifecycle.sh Release      # HUD 失败、重试、修饰键与异步开关生命周期
./scripts/test-calendar-focus.sh Release     # 日历与歌词自动专注
./scripts/test-agent-completion.sh Release   # 对话完成后展开与自动收起
# 在已提交且干净的源码树上打包、验签、生成 SHA-256 和发布清单
./scripts/package-release.sh
# 使用本应用钥匙串中的 Ed25519 密钥生成签名 feed（仅生成文件，不发布）
./scripts/generate-appcast.sh
# 发布成功后清理本地编译缓存（可先加 --dry-run）
./scripts/clean-build-cache.sh
```

应用运行时可用 `python3 scripts/smoke-agents.py` 以合成数据检查 bridge → socket → XPC → 刘海的完整流程，用法见 [INTEGRATION.md](INTEGRATION.md)。bridge 只在设置 `BORINGNOTCH_DEBUG=1` 时写调试日志（`/tmp/notch-agent-bridge.log`，权限 0600），不记录 Hook 内容。

Debug/Release 应用输出到 `build/DerivedData/Build/Products/`，安装包和校验文件输出到 `dist/`。构建产物、研究参考仓库和本机配置均不提交到 Git。GitHub Actions 对 `main` 和 PR 执行上述测试及通用 Release 编译；推送与工程版本一致的 `v*` 标签后执行签名发布工作流。

打包脚本专用于没有 Developer ID 证书的本地签名构建，因此不启用 Hardened Runtime 的 Team ID 框架校验；工程本身保留正式签名时的 Hardened Runtime 配置。打包保留主应用 App Sandbox，并移除主应用与 Helper 的调试器访问权限。正式签名和 Apple 公证需要另行提供 Developer ID。

## 上游与许可证

本项目是修改后的 boring.notch 发行版本，保留 **GPL-3.0** 许可证。CodeIsland 以及参考的 CodexBar 集成部分为 MIT，MediaRemoteAdapter 等第三方许可证保留在 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) 中，亦随安装包提供。

上游版本与改动说明：[UPSTREAM_REVISIONS.md](UPSTREAM_REVISIONS.md)。上游原版介绍：[docs/upstream-boring.notch.md](docs/upstream-boring.notch.md)。
