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
