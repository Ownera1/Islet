# Agent Usage Notch 安装说明

系统要求：macOS 15 或更新版本。通用安装包同时包含 Apple Silicon 和 Intel 二进制；本次实际运行验证使用 Apple Silicon Mac。

1. 打开下载的 `Agent-Usage-Notch-0.1.3-universal.dmg`。
2. 将 `Agent Usage Notch.app` 拖到 `Applications`。
3. 从“应用程序”启动。此版本使用本地签名，尚未经过 Apple 公证。如被系统阻止，请到“系统设置 → 隐私与安全性”查看并允许打开你刚下载的应用。
4. 完成首次引导。需要 Agent 连接时，进入“设置 → Agent 与订阅”，安装对应连接；Codex 还需运行 `/hooks` 审核。
5. 在“刘海中的订阅可见性”分别选择 Claude、OpenAI、Gemini、Antigravity 的剩余量是否显示。

设置也可从应用菜单或菜单栏图标打开，快捷键为 `⌘,`。

应用使用独立标识 `com.ownera1.agentusagenotch`，与原版 boring.notch 设置隔离。不要同时运行原版/旧开发构建与本集成版，以免两个刘海窗口重叠或争用同一个 Agent socket。0.1.3 起可从菜单或设置中的“检查更新…”在应用内下载、验证并安装更新。安装后会重新启动；默认自动检查，后台下载可在设置中开启。0.1.2 及更早版本需要先手动安装一次支持 Sparkle 的版本。

源码及安装包：https://github.com/Ownera1/agent-usage-notch/releases

本仓库已公开，源码和 Release 安装包均可直接访问，无需 GitHub 登录。签名、公证、验证和功能范围见仓库 README 与 INTEGRATION.md。
