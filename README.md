<img src="boringNotch/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" height="96" alt="Agent Usage Notch 图标">

# Agent Usage Notch

基于 [boring.notch](https://github.com/TheBoredTeam/boring.notch) 的原生 macOS 刘海应用，集成 [CodeIsland](https://github.com/wxtsky/CodeIsland) 的 Agent 会话监控、订阅剩余量和音乐歌词。

顶部小按钮切换四个页面：**主页 · 暂存器/隔空投送 · Agent · 订阅剩余量**。

## 安装

从 [最新 GitHub Release](https://github.com/Ownera1/agent-usage-notch/releases/latest) 下载 DMG，将 `Agent Usage Notch.app` 拖入“应用程序”。本仓库已公开，源码和安装包均可直接访问，无需 GitHub 登录。

- macOS **15 或更新版本**。
- 通用二进制包含 **Apple Silicon / Intel**。实机运行验证使用 Apple Silicon。
- 当前发行包使用本地签名，**尚未经过 Apple 公证**。首次打开可能需要在“系统设置 → 隐私与安全性”允许。
- 此集成版有独立应用标识和设置，更新通过本仓库 Release 下载。

`v0.1.1` 使用新的“极简终端”应用图标：暖白底色、黑色刘海、终端符号和珊瑚红状态点。Dock、首次引导和设置中的图标预览保持一致。

`v0.1.2` 修复内容滚动误收起刘海的问题：在订阅卡片、Agent 回复等内容区域上下滑动可正常浏览；上滑收起手势仅在顶部导航区域开始时生效，滚动惯性不会触发收起。

具体步骤见 [INSTALL.md](INSTALL.md)。

## 功能

- Agent：Pi、Codex、Claude Code、ZCode、Antigravity。多会话状态、工具调用、任务进度、最近提问、Markdown 回复、来源窗口跳转。
- 一次性工具审批和问题回答。Antigravity 当前为观察模式，审批仍由原应用处理。
- Claude、OpenAI、Gemini、Antigravity 四种配额来源。每 5 分钟同步，显示剩余百分比、重置时间和数据更新时间。
- 设置中的四个独立可见性开关，立即生效并持久保存；隐藏卡片不影响后台同步。
- Apple Music 歌词优先，其余播放器使用 LRCLIB。存在 LRC 时跟随播放进度，切歌取消旧查询。
- 保留 boring.notch 的原生主页、媒体控制、日历、暂存器和隔空投送等功能。

Gemini 当前读取 CLI / Code Assist 配额，OpenAI 当前读取 Codex 配额；不代表网页聊天中所有模型的限制。Gemini 与 Antigravity 独立读取。未登录、过期和服务错误均显示明确状态。

首次使用 Agent 请到 **设置 → Agent 与订阅** 安装对应连接；配置会先备份并保留其他 Hook。详细来源、范围和验证边界见 [INTEGRATION.md](INTEGRATION.md)。

## 开发与打包

需要完整 Xcode、Swift 工具链和 Python 3。Swift 依赖版本保留在工程的 `Package.resolved` 中。

```sh
# 本机 Debug 构建
./scripts/build-app.sh
# 集成测试
swift test --package-path Packages/NotchIntegrations --scratch-path build/IntegrationPackage
# 滚动与收起手势回归测试
./scripts/test-pan-gesture.sh
# 通用 Release 构建
./scripts/build-app.sh Release 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
# 在已提交且干净的源码树上打包、验签、生成 SHA-256 和发布清单
./scripts/package-release.sh
```

Debug/Release 应用输出到 `build/DerivedData/Build/Products/`，安装包和校验文件输出到 `dist/`。构建产物、研究参考仓库和本机配置均不提交到 Git。GitHub Actions 对 `main` 和 PR 执行测试及通用 Release 编译。

此脚本专用于没有 Developer ID 证书的本地签名构建，因此不启用 Hardened Runtime 的 Team ID 框架校验；工程本身保留正式签名时的 Hardened Runtime 配置。打包保留主应用 App Sandbox，并移除调试器访问权限。正式签名和 Apple 公证需要另行提供 Developer ID。

## 上游与许可证

本项目是修改后的 boring.notch 发行版本，保留 **GPL-3.0** 许可证。CodeIsland 以及参考的 CodexBar 集成部分为 MIT，MediaRemoteAdapter 等第三方许可证保留在 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) 中，亦随安装包提供。

上游版本与改动说明：[UPSTREAM_REVISIONS.md](UPSTREAM_REVISIONS.md)。上游原版介绍：[docs/upstream-boring.notch.md](docs/upstream-boring.notch.md)。
