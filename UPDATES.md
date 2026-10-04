# Sparkle 与 GitHub Releases

客户端只使用 `Ownera1/agent-usage-notch` 的更新源：

- Feed：`https://raw.githubusercontent.com/Ownera1/agent-usage-notch/main/updater/appcast.xml`
- 安装包：该仓库 `releases/download/v<version>/` 下的 ZIP／delta。
- Sparkle 2.9.1 使用 `SUPublicEDKey` 校验 Ed25519 签名，在解压前验证；客户端拒绝其他仓库的安装地址。
- 默认自动检查，用户选择安装。设置中的“后台下载更新”对应 Sparkle 的自动下载选项。安装完成会重启应用。

0.1.2 和更早版本没有启动 Sparkle，也没有这把公钥，因此必须手动安装一次 0.1.3 或更新版本。源码中的初始 feed 为空，首次签名 Release 发布后工作流才加入有效条目，不会将未签名的旧 DMG 宣称为可自动更新的版本。

## 签名密钥

本项目使用独立钥匙串 account `com.ownera1.agentusagenotch`。私钥不进入仓库；`boringNotch/Info.plist` 只保存公钥。CI 从本仓库的 Actions secret `SPARKLE_PRIVATE_KEY` 读取私钥，通过标准输入交给 Sparkle，避免出现在命令参数或日志中。

本机可以查询公钥或生成新应用的密钥：

```sh
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account com.ownera1.agentusagenotch
```

发布后应备份钥匙串中的签名密钥。此应用目前仍使用 ad-hoc 代码签名，未经过 Apple 公证；Ed25519 保护更新包完整性，不替代 Developer ID 或公证。没有 Developer ID 时不要直接更换 Ed25519 公钥，否则已有安装无法认证新的更新。

## 发布新版本

1. 同时提高工程内主应用与 XPC Helper 的 `MARKETING_VERSION` 和整数 `CURRENT_PROJECT_VERSION`，保持 build 单调递增。
2. 添加 `updater/release-notes/v<version>.md`，提交到 `main`。
3. 为该提交推送匹配的标签，例如 `v0.1.3`。

`.github/workflows/release.yml` 校验标签、secret 和源码来源，执行测试、Universal Release 编译、DMG／ZIP 打包、Ed25519 签名和独立的公钥验签。存在上一个 ZIP 时，Sparkle 自动尝试生成 delta；没有可用 delta 时客户端使用完整 ZIP。

发布先创建草稿并上传所有产物，再公开 Release，最后将签名 appcast 提交到 `main`。避免 feed 指向尚不可下载的文件。工作流串行执行且只正常推送，不强制覆盖分支。Release 失败时应检查 Actions 日志；若 Release 已公开但 feed 推送失败，可将该 Release 的 `appcast.xml` 验证后提交至 `main`，不要重新签名或修改已上传的 ZIP。

每个 Release 包含 DMG、用于更新的 ZIP、appcast、SHA256SUMS 和 sourceCommit 发布清单，有效时还包含 delta。当前工作流使用本地签名；引入 Developer ID／公证时需要同时调整构建、打包和发布清单校验，不能只更改清单中的标签。

## 本机验证

```sh
python3 scripts/test-update-pipeline.py
swift test --package-path Packages/NotchIntegrations --scratch-path build/IntegrationPackage
./scripts/test-pan-gesture.sh
./scripts/build-app.sh Release 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
# 以下要求源码已提交且干净
./scripts/package-release.sh
./scripts/generate-appcast.sh
```

`generate-appcast.sh` 只写入 `dist/` 和 `build/`。它使用本机专用钥匙串密钥，也可使用 CI 的 `SPARKLE_PRIVATE_KEY`；通过 CryptoKit 使用源码公钥再次校验真实 ZIP／delta。没有旧 ZIP 时不生成增量包。

验证签名、feed 和编译并不等同于实机完整更新验收。首次公开支持 Sparkle 的版本后，还需从该版本升级至下一版本，检查下载、替换、重启和 XPC／Agent 连接恢复。
