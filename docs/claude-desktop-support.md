# Claude 桌面版支持

目标：在 Claude 桌面版里使用 Claude（Code 标签页、Cowork）时，刘海也能显示 Agent 状态和订阅额度。Islet 只读取桌面版的文件，不写入；不解密桌面版的登录凭据，不读取钥匙串里的 "Claude Safe Storage"；不用 refresh token 刷新 OAuth（命令行版登录过期时交给 Claude Code 自己刷新，见第 7 项）；不为了取额度调用模型。

## 第 0 步：本机实测

2026-10-06 已在本机完成，结果见下方「实测结果」。bridge 里的临时 probe 已在提交 "Remove the Claude Desktop step-0 probe from the bridge" 中移除；需要重新测 0.1 / 0.2 时，先 revert 该提交再按下面的步骤操作。`scripts/probe-claude-desktop.sh` 保留，0.3–0.5 随时可以重跑。

实测需要在装有 Claude 桌面版的 Mac 上进行，所有命令都不输出 token、提问内容或对话内容。注意 bridge 在 Islet 的 socket（`/tmp/boringnotch-<uid>/agent.sock`）不存在时直接退出、不写日志，所以测试期间 Islet 必须在运行。

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

2026-10-06，本机实测。

| 项目 | 结果 |
| --- | --- |
| 0.1 Code 标签页收到的事件 | `UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`Notification`、`Stop`、`SubagentStop`（会话在 Islet 启动前已开着，所以没观察到 `SessionStart`；测试中没有工具失败，所以没观察到 `PostToolUseFailure`）。和命令行版走同一份 `~/.claude/settings.json`；`cwd`、`transcript_path` 都有值 |
| 0.1 `_term_bundle` | `com.anthropic.claudefordesktop` |
| 0.1 transcript 所在位置 | `~/.claude/projects/`（与命令行版相同） |
| 0.2 审批时桌面版是否同时显示自己的卡片 | 是。Hook 挂起期间桌面版同时显示自己的卡片。在刘海中允许 / 拒绝，桌面版按 Hook 的决定执行；在桌面版卡片中决定，Hook **不会**被结束，一直挂到本轮 `Stop`，期间该工具的 `PostToolUse` 照常到达 |
| 0.3 Cowork 会话文件 | 存储目录存在，0 个会话（本机未使用过 Cowork） |
| 0.4 额度记录（5 小时 / 7 天使用率、重置时间） | Claude Code `projects/**/*.jsonl` 中没有 `rate_limit_event` / `rate_limit_info`；Cowork 一侧因没有会话未能验证 |
| 0.5 只用桌面版时可读的钥匙串条目 | `Claude Code-credentials`（命令行版登录）和 `Claude Safe Storage`（桌面版，按设计不读取） |

## 第 5 项：Code 标签页会话（Hook 路径）

依据：上游 CodeIsland（#211）记录桌面版 Code 标签页和命令行版运行同一引擎，会触发同一份 `settings.json` 中的 Hook，Hook 子进程继承桌面版的 `__CFBundleIdentifier`。本机是否如此以 0.1 的结果为准；如果 Hook 没有到达，在此记录，并评估改为用 `JSONLTailer` 监听 transcript 目录，先和用户确认再实现。

已实现：

- 识别：`_term_bundle == com.anthropic.claudefordesktop`（bridge 已有字段，写入 `SessionSnapshot.termBundleId`）。
- 卡片在状态旁标注「Claude 桌面版」。
- 点击"打开来源窗口"或"前往处理"时，用卡片的 CLI 会话 id 在 `claude-code-sessions/<a>/<b>/local_<id>.json` 中匹配 `cliSessionId`，打开 `claude://claude.ai/epitaxy/local_<id>`，直接切到该会话（已实测；`claude://claude.ai/code/local_<id>` 无效）。找不到时按 bundle id 打开桌面版。主 App 沙盒对该目录只有只读例外。
- 审批：`ClaudeDesktop.codeTabPermissionHandling` 为 `.island`，与终端会话一样在刘海中显示允许、拒绝按钮，Hook 挂起直到用户在刘海中决定。桌面版同时显示自己的卡片（0.2），两边都可以处理：
  - 在刘海中决定：桌面版按 Hook 的决定执行（允许、拒绝均已实测）。
  - 在桌面版中决定：桌面版不会结束挂起的 Hook。被审批的工具的 `PostToolUse` / `PostToolUseFailure` 到达时（同一会话、工具名和 `tool_input` 都相同；`AskUserQuestion` 回答后输入会多出 `answers`，比较时忽略，见 `ClaudeDesktop.isAnsweredInApp`），Islet 回复 `{}` 并移除刘海中的审批卡，会话回到处理中。并行完成的其他工具不影响审批卡。在桌面版中允许已实测；在桌面版中拒绝未实测，预计工具不运行、没有 `PostToolUse`，审批卡在本轮 `Stop` 时移除。

  `.displayOnly`（立即回复 `{}`，刘海只显示等待状态并提示到桌面版处理）保留为备选。

终端里的 Claude Code 会话不受影响，仍由刘海审批。

## 第 6 项：Cowork 会话（读取桌面版自己的会话文件）

Cowork 在虚拟机里运行，`~/.claude/settings.json` 的 Hook 不会触发，因此由 Helper 读取桌面版的会话存储（只读）：

- `CoworkWatcher`（Helper）随 `IntegrationHost.start` 启动、`stop` 停止，每 2 秒扫描一次 `CoworkPaths.defaultRoot(home: HomePaths.userHome)`。
- `CoworkStoreScanner`（CodeIslandCore）只跟踪满足 `isTrackable` 和 `shouldSurfaceOnLaunch` 的会话；按偏移量增量读取 `audit.jsonl`，未写完的最后一行保留为 `trailingFragment`；文件变小或被替换（inode 变化）时从头重读。事件叠加进 `CoworkAuditState`。首次看到的历史和重读的文件不算新完成，避免重启后重复展开。会话被归档、隐藏或删除时发送移除。
- XPC 回调 `agentCoworkUpdate(_ data: Data)`，Helper 与主应用两处声明一致。内容为 `CoworkSessionUpdate` 的 JSON：sessionId、title、cwd、phase、currentTool、toolDetail、lastPrompt、lastResultText、lastActivity、cliSessionId 以及本次是否结束了一轮。
- 主应用 `AgentMonitor` 用 `ClaudeDesktop.apply` 映射为 `SessionSnapshot`：`source = "claude"`，id 为 `local_<id>`；`idle` / `processing` / `waitingApproval` / `waitingQuestion` 对应同名状态，等待状态为仅展示；同一 CLI 会话已有 Hook 卡片时跳过并移除 Cowork 卡片；一轮正常结束时走 `revealCompletedSession`，用户中止的不算完成。点击打开 `claude://claude.ai/cowork/<id>`。

## 第 7 项：订阅额度

1. **命令行版凭据 + `/api/oauth/usage`**：使用 `ClaudeCredentialStore.resolve`。先找所配置 Claude 目录自己的登录（`Claude Code-credentials-<目录 SHA-256 前 8 位>` 钥匙串条目和该目录的 `.credentials.json`），没有时才用默认 `~/.claude` 的登录。Islet 自己不刷新 token。access token 只有 8 小时有效期，而桌面版用自己的登录（Code 标签页带 `CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH`），不会刷新命令行版的钥匙串条目；所以过期（或 401）时 `ClaudeCLIRefresh` 运行一次 `claude -p /status --no-session-persistence --strict-mcp-config --settings '{"disableAllHooks":true}'`，由 Claude Code 自己刷新并写回钥匙串，然后重读凭据再请求一次。实测（2.1.295）：0 个 turn、费用 $0、约 5 秒，不留会话记录、不触发 hook。每个配置目录 10 分钟内最多尝试一次；找不到 `claude` 时不尝试。
2. **桌面版落盘的额度记录**：0.4 在 Claude Code 的记录中没有找到额度信息，因此不实现；Cowork 的 `audit.jsonl` 尚未验证。以后如果在 Cowork 中确认有记录：在 `SubscriptionUsageSource` 中新增 `claudeDesktop`（卡片显示「来源：Claude 桌面版最近一次对话」），`fetchedAt` 取记录时间，只在第 1 条失败时使用或两者都有时取较新的一份，窗口不完整时只显示实际有的窗口；解析器测试使用 0.4 输出的真实结构并去掉身份信息。
3. **两者都没有**：安装了桌面版时，卡片显示「Claude 桌面版不提供可读取的额度。在终端运行一次 `claude` 登录后，Islet 可显示实时额度。」；未安装时仍显示「请先登录 Claude Code。」

## 后续

- 本机使用过 Cowork 后，重跑 `./scripts/probe-claude-desktop.sh`，补测 0.3 和 0.4 的 Cowork 部分，再决定是否实现第 7 项第 2 条。
