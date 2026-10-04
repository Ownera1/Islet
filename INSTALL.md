# Agent Usage Notch 安装说明

系统要求：macOS 15 或更新版本。通用安装包同时包含 Apple Silicon 和 Intel 二进制；本次实际运行验证使用 Apple Silicon Mac。

1. 打开 `Agent-Usage-Notch-0.1.0-universal.dmg`。
2. 将 `Agent Usage Notch.app` 拖到 `Applications`。
3. 从“应用程序”启动。此版本使用本地签名，尚未经过 Apple 公证。如被系统阻止，请到“系统设置 → 隐私与安全性”查看并允许打开你刚下载的应用。
4. 完成首次引导。需要 Agent 连接时，进入“设置 → Agent 与订阅”，安装对应连接；Codex 还需运行 `/hooks` 审核。
5. 在“刘海中的订阅可见性”分别选择 Claude、OpenAI、Gemini、Antigravity 的剩余量是否显示。

应用使用独立标识 `com.ownera1.agentusagenotch`，与原版 boring.notch 设置隔离。不要同时运行原版/旧开发构建与本集成版，以免两个刘海窗口重叠或争用同一个 Agent socket。更新通过本仓库的 GitHub Release 下载。

源码及安装包：https://github.com/Ownera1/agent-usage-notch/releases

本仓库为私有，下载需要登录有访问权限的 GitHub 账号。签名、公证、验证和功能范围见仓库 README 与 INTEGRATION.md。
