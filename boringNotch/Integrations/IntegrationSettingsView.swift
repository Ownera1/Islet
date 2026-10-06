import SwiftUI
import Defaults
import NotchIntegrationCore

struct IntegrationSettingsView: View {
    @ObservedObject private var installer = AgentInstaller.shared
    @Default(.agentOverviewStyle) private var overviewStyle
    @Default(.agentCompletionCollapseDelay) private var collapseDelay
    @AppStorage("agentRevealOnCompletion") private var revealOnCompletion = true
    @ObservedObject private var monitor = AgentMonitor.shared
    @AppStorage("subscriptionSyncEnabled") private var syncEnabled = true
    @AppStorage("integrationClaudeHome") private var claudeHome = HomePaths.userHome + "/.claude"
    @AppStorage("integrationCodexHome") private var codexHome = HomePaths.userHome + "/.codex"
    var body: some View {
        Form {
            Section("Agent 显示") {
                Toggle("对话结束后展开 Agent 状态页", isOn: $revealOnCompletion)
                Text("对话完成时自动展开刘海，并选中对应会话。等待审批或回答时优先显示待处理请求。").font(.caption).foregroundStyle(.secondary)
                Stepper(value: $collapseDelay, in: 0...30, step: 1) {
                    HStack {
                        Text("自动收起")
                        Spacer()
                        Text(collapseDelay > 0 ? "\(Int(collapseDelay)) 秒后" : "不自动收起").foregroundStyle(.secondary)
                    }
                }.disabled(!revealOnCompletion)
                Text("完成提示展开后到时自动收起；指针停在刘海上时保持展开，移开后收起。等待审批或回答时不会自动收起。").font(.caption).foregroundStyle(.secondary)
                Picker("Agent 总览样式", selection: $overviewStyle) {
                    Text("单行").tag(AgentOverviewStyle.singleLine)
                    Text("双行").tag(AgentOverviewStyle.twoLine)
                }.pickerStyle(.segmented)
                Text("名称始终完整显示；任务描述超长时省略。切换样式会立即生效。").font(.caption).foregroundStyle(.secondary)
            }
            Section("Agent 连接") {
                ForEach(NotchAgent.allCases) { agent in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.name)
                            Text(installer.path(for: agent)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Button(installer.installed.contains(agent) ? "移除连接" : "安装连接") {
                            installer.setInstalled(agent, enabled: !installer.installed.contains(agent))
                        }.disabled(installer.busy)
                    }
                }
                Text(installer.message).font(.caption).foregroundStyle(.secondary)
                Text("安装前备份现有配置，并保留其他 Hook。Codex 安装后需要在 /hooks 中审核；ZCode、Antigravity 和 Pi 需要重启。Antigravity 审批在原应用处理。").font(.caption).foregroundStyle(.secondary)
                Text(monitor.serviceStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("登录目录") {
                TextField("Claude 配置目录", text: $claudeHome)
                TextField("Codex 配置目录", text: $codexHome)
                Text("自定义目录同时用于 Hook 安装和用量读取。请填写完整路径；更改前先移除原目录的连接。").font(.caption).foregroundStyle(.secondary)
            }
            Section("订阅用量") {
                Toggle("自动同步订阅用量", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, enabled in if enabled { SubscriptionMonitor.shared.refresh() } }
                Text("每 5 分钟同步。OpenAI 显示 Codex 配额；Google AI 只显示一张 Antigravity / agy 共享额度卡片，优先检测 agy CLI，失败后读取已运行的 Antigravity 应用。Gemini CLI 不参与此额度页面。两种来源均不可用时只显示文字提醒，请手动登录后刷新；不会打开网页。").font(.caption).foregroundStyle(.secondary)
                Button("立即同步") { SubscriptionMonitor.shared.refresh() }.disabled(!syncEnabled)
            }
            Section("刘海中的订阅可见性") {
                ForEach(SubscriptionProvider.monitoredProviders) { provider in
                    SubscriptionVisibilityToggle(provider: provider)
                }
                Text("控制用量页面中各张订阅卡片的显示，重启后保留选择。隐藏卡片不影响自动同步。").font(.caption).foregroundStyle(.secondary)
            }
            Section("音乐") {
                Toggle("显示同步歌词", isOn: Binding(get: { Defaults[.enableLyrics] }, set: { Defaults[.enableLyrics] = $0; MusicManager.shared.refreshLyrics() }))
                Text("优先读取 Apple Music 歌词；其余播放器按歌曲和歌手查询 LRCLIB。有时间戳时跟随播放进度。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Agent 与订阅").onAppear { installer.refresh() }
    }
}

private struct SubscriptionVisibilityToggle: View {
    let provider: SubscriptionProvider
    @AppStorage private var visible: Bool
    init(provider: SubscriptionProvider) {
        self.provider = provider
        _visible = AppStorage(wrappedValue: true, provider.visibilityKey)
    }
    var body: some View { Toggle("显示 \(provider.name) 剩余量", isOn: $visible) }
}
