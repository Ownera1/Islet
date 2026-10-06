# Claude 桌面版支持

目标：在 Claude 桌面版里使用 Claude（Code 标签页、Cowork）时，刘海也能显示 Agent 状态和订阅额度。Islet 只读取桌面版的文件，不写入；不解密桌面版的登录凭据，不读取钥匙串里的 "Claude Safe Storage"；不用 refresh token 刷新 OAuth；不为了取额度调用模型。

## 第 0 步：本机实测

实测需要在装有 Claude 桌面版的 Mac 上进行，所有命令都不输出 token、提问内容或对话内容。

### 0.1 Code 标签页是否触发 Hook

调试构建的 bridge 在 `BORINGNOTCH_DEBUG=1` 时，每个事件额外写一行 `probe`（临时代码，记录完后回退）：

```
probe _source=claude _term_bundle=<bundle id 或 empty> hook_event_name=<事件> cwd=set|empty transcript_path=set|empty transcript_store=claude-projects|claude-desktop-sessions|other|empty
```

只记录字段是否为空、来源标签和 bundle id；`cwd` 只记有没有，transcript 只记所在的存储位置。日志位于 `/tmp/notch-agent-bridge.log`（权限 0600）。

1. 让桌面版启动的 Hook 进程拿到环境变量。先试：

   ```sh
   launchctl setenv BORINGNOTCH_DEBUG 1
   ```

   然后完全退出并重新打开 Claude 桌面版。如果之后日志里没有 `probe` 行，改为临时在 Claude 配置目录 `settings.json` 中 Islet 的每条 bridge 命令前加 `BORINGNOTCH_DEBUG=1 `，测完恢复。
2. 在桌面版 Code 标签页新开一个会话，发一条消息，再触发一次需要审批的工具调用（例如让它运行一条命令）。
3. 查看结果：

   ```sh
   ./scripts/probe-claude-desktop.sh hook-log
   ```

4. 测完恢复：`launchctl unsetenv BORINGNOTCH_DEBUG`，或去掉 `settings.json` 中加的前缀。

记录：收到了哪些事件；`_term_bundle` 是否为 `com.anthropic.claudefordesktop`；`transcript_store` 是哪一种。

### 0.2 Code 标签页审批时的行为

在 0.1 第 2 步触发审批时观察：Islet 显示审批卡片期间，桌面版是在等待（界面上没有自己的审批卡片），还是同时弹出了自己的卡片？

日志中 `probe blocking wait start` 之后没有对应的 `wait end`，说明桌面版在 Islet 回复前结束了 Hook 进程。

### 0.3–0.5 会话存储、额度记录、钥匙串

```sh
./scripts/probe-claude-desktop.sh
```

- **0.3** 统计 `local-agent-mode-sessions/*/*/` 下的 `local_<id>.json` 和 `local_<id>/audit.jsonl`，只输出数量、最新一个元数据文件的字段名，以及该会话审计记录的类型计数。
- **0.4** 在 Cowork 的 `audit.jsonl` 和 Claude Code 的 `projects/**/*.jsonl` 中查找 `rate_limit_event` / `rate_limit_info`，只输出记录的字段名和值的形态：字符串只在像枚举值（如 `five_hour`）时原样显示，否则显示 `<str>` 或 `<iso8601>`；数字显示为 `<0..1>`、`<0..100>`、`<epoch_s>`、`<epoch_ms>` 等范围类别。
- **0.5** 运行 `security dump-keychain`（不带 `-d`，不输出密码数据），只列出服务名含 claude 的条目。

### 实测结果

> 待在本机完成第 0 步后填写。下列各项决定第 5 项审批方式和第 7 项第 2 条是否实现。

| 项目 | 结果 |
| --- | --- |
| 0.1 Code 标签页收到的事件 | 待实测 |
| 0.1 `_term_bundle` | 待实测 |
| 0.1 transcript 所在位置 | 待实测 |
| 0.2 审批时桌面版是否同时显示自己的卡片 | 待实测 |
| 0.3 Cowork 会话文件 | 待实测 |
| 0.4 额度记录（5 小时 / 7 天使用率、重置时间） | 待实测 |
| 0.5 只用桌面版时可读的钥匙串条目 | 待实测 |

## 第 5 项：Code 标签页会话（Hook 路径）

依据：上游 CodeIsland（#211）记录桌面版 Code 标签页和命令行版运行同一引擎，会触发同一份 `settings.json` 中的 Hook，Hook 子进程继承桌面版的 `__CFBundleIdentifier`。本机是否如此以 0.1 的结果为准；如果 Hook 没有到达，在此记录，并评估改为用 `JSONLTailer` 监听 transcript 目录，先和用户确认再实现。

已实现：

- 识别：`_term_bundle == com.anthropic.claudefordesktop`（bridge 已有字段，写入 `SessionSnapshot.termBundleId`）。
- 卡片在状态旁标注「Claude 桌面版」。
- 点击"打开来源窗口"或"前往处理"时，按 bundle id 用 `NSWorkspace` 打开桌面版。
- 审批：`ClaudeDesktop.codeTabPermissionHandling` 默认为 `.displayOnly`。Islet 收到桌面版会话的 `PermissionRequest` 后立即回复 `{}`，只把会话设为等待审批 / 等待回答，并展开刘海；不显示批准、拒绝按钮，卡片提示"请在 Claude 桌面版中审批"。工具的 `PostToolUse` / `PostToolUseFailure` 到达后，等待状态结束。

  选择默认值的理由：回复 `{}` 表示 Hook 不做决定，Claude Code 随后走桌面版自己的审批流程，无论 0.2 的结果如何都不会让桌面版卡住；而挂住 Hook 时，如果桌面版同时弹出自己的卡片，刘海会留下一张已经失效的审批卡。**如果 0.2 显示桌面版在 Hook 挂起期间完全等待、没有自己的卡片**，把该常量改为 `.island`，即恢复现有的刘海审批流程。

终端里的 Claude Code 会话不受影响，仍由刘海审批。

## 第 6 项：Cowork 会话（读取桌面版自己的会话文件）

Cowork 在虚拟机里运行，`~/.claude/settings.json` 的 Hook 不会触发，因此由 Helper 读取桌面版的会话存储（只读）：

- `CoworkWatcher`（Helper）随 `IntegrationHost.start` 启动、`stop` 停止，每 2 秒扫描一次 `CoworkPaths.defaultRoot(home: HomePaths.userHome)`。
- `CoworkStoreScanner`（CodeIslandCore）只跟踪满足 `isTrackable` 和 `shouldSurfaceOnLaunch` 的会话；按偏移量增量读取 `audit.jsonl`，未写完的最后一行保留为 `trailingFragment`；文件变小或被替换（inode 变化）时从头重读。事件叠加进 `CoworkAuditState`。首次看到的历史和重读的文件不算新完成，避免重启后重复展开。会话被归档、隐藏或删除时发送移除。
- XPC 回调 `agentCoworkUpdate(_ data: Data)`，Helper 与主应用两处声明一致。内容为 `CoworkSessionUpdate` 的 JSON：sessionId、title、cwd、phase、currentTool、toolDetail、lastPrompt、lastResultText、lastActivity、cliSessionId 以及本次是否结束了一轮。
- 主应用 `AgentMonitor` 用 `ClaudeDesktop.apply` 映射为 `SessionSnapshot`：`source = "claude"`，id 为 `local_<id>`；`idle` / `processing` / `waitingApproval` / `waitingQuestion` 对应同名状态，等待状态为仅展示；同一 CLI 会话已有 Hook 卡片时跳过并移除 Cowork 卡片；一轮正常结束时走 `revealCompletedSession`，用户中止的不算完成。点击打开 `claude://claude.ai/cowork/<id>`。

## 第 7 项：订阅额度

1. **命令行版凭据 + `/api/oauth/usage`**：使用 `ClaudeCredentialStore.resolve`。先找所配置 Claude 目录自己的登录（`Claude Code-credentials-<目录 SHA-256 前 8 位>` 钥匙串条目和该目录的 `.credentials.json`），没有时才用默认 `~/.claude` 的登录。不刷新 token。
2. **桌面版落盘的额度记录**：取决于 0.4 的结果，尚未实现。确认有记录后：在 `SubscriptionUsageSource` 中新增 `claudeDesktop`（卡片显示「来源：Claude 桌面版最近一次对话」），`fetchedAt` 取记录时间，只在第 1 条失败时使用或两者都有时取较新的一份，窗口不完整时只显示实际有的窗口；解析器测试使用 0.4 输出的真实结构并去掉身份信息。
3. **两者都没有**：安装了桌面版时，卡片显示「Claude 桌面版不提供可读取的额度。在终端运行一次 `claude` 登录后，Islet 可显示实时额度。」；未安装时仍显示「请先登录 Claude Code。」

## 测完之后

- 把结果填入上面的表格。
- 回退 bridge 里标为 `TEMPORARY (step-0 probe)` 的两段代码（提交 "Add the Claude Desktop step-0 probe" 中 `main.swift` 的部分）；`scripts/probe-claude-desktop.sh` 可以保留。
- 按 0.2 决定 `ClaudeDesktop.codeTabPermissionHandling`；按 0.4 决定是否实现第 7 项第 2 条。
