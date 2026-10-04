import SwiftUI
import CodeIslandCore
import NotchIntegrationCore

struct AgentPanelView: View {
    @ObservedObject private var monitor = AgentMonitor.shared
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Agent").font(.headline)
                    Spacer()
                    Menu {
                        Button("全部工具") { monitor.filter = nil }
                        ForEach(NotchAgent.allCases) { agent in Button(agent.name) { monitor.filter = agent } }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .menuStyle(.borderlessButton).frame(width: 20)
                    .help("筛选工具")
                }
                if monitor.sortedSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("等待会话").foregroundStyle(.white)
                        Text("在设置中连接工具后，启动一次新会话。").foregroundStyle(.gray)
                        Button("连接工具") { SettingsWindowController.shared.showWindow() }
                    }.font(.caption)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(monitor.sortedSessions, id: \.id) { row in
                                Button {
                                    monitor.selectedSessionID = row.id
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: statusIcon(row.snapshot.status)).foregroundStyle(statusColor(row.snapshot.status))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(NotchAgent(rawValue: row.snapshot.source)?.name ?? row.snapshot.source).font(.caption.weight(.semibold))
                                            Text(project(row.snapshot)).font(.caption2).foregroundStyle(.gray).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(monitor.selected?.id == row.id ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .accessibilityLabel("\(NotchAgent(rawValue: row.snapshot.source)?.name ?? row.snapshot.source)，\(project(row.snapshot))，\(statusLabel(row.snapshot.status))")
                            }
                        }
                    }
                }
            }.frame(width: 152)
            Divider().overlay(.white.opacity(0.12))
            if let selected = monitor.selected {
                AgentSessionDetail(id: selected.id, snapshot: selected.snapshot)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("让任务进展留在视线里", systemImage: "terminal").font(.headline)
                    Text("Pi · Codex · Claude Code · ZCode · Antigravity").font(.caption).foregroundStyle(.gray)
                    Text(monitor.serviceStatus).font(.caption2).foregroundStyle(.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white)
    }
    private func project(_ snapshot: SessionSnapshot) -> String { snapshot.cwd.map { ($0 as NSString).lastPathComponent } ?? "会话" }
}

private struct AgentSessionDetail: View {
    let id: String
    let snapshot: SessionSnapshot
    @ObservedObject private var monitor = AgentMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(statusLabel(snapshot.status), systemImage: statusIcon(snapshot.status)).foregroundStyle(statusColor(snapshot.status)).font(.caption.weight(.semibold))
                if let branch = snapshot.gitBranch { Text(branch).font(.caption2).foregroundStyle(.gray).lineLimit(1).help(snapshot.cwd ?? "") }
                Spacer()
                Button { AgentTerminal.open(snapshot, id: id) } label: { Image(systemName: "arrow.up.forward.app") }.help("打开来源窗口")
                Button { monitor.dismiss(id) } label: { Image(systemName: "xmark") }.help("移除会话卡片")
            }.buttonStyle(.plain)
            if let request = monitor.requests.first(where: { $0.sessionID == id }) {
                AgentRequestView(request: request).id(request.id)
            } else {
                if !snapshot.agentTasks.isEmpty {
                    HStack {
                        ProgressView(value: Double(snapshot.agentTasks.completedCount), total: Double(snapshot.agentTasks.items.count)).tint(.green)
                        Text("\(snapshot.agentTasks.completedCount)/\(snapshot.agentTasks.items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.gray)
                    }
                    if let task = snapshot.agentTasks.current { Text(task.progressLabel).font(.caption).lineLimit(1) }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let prompt = snapshot.lastUserPrompt { Text(prompt).font(.caption).foregroundStyle(.gray).lineLimit(2) }
                        if let tool = snapshot.currentTool {
                            Label(tool, systemImage: "wrench.and.screwdriver").font(.caption.weight(.medium))
                            if let detail = snapshot.toolDescription { Text(detail).font(.caption.monospaced()).foregroundStyle(.gray).lineLimit(3) }
                        }
                        if let reply = snapshot.lastAssistantMessage, !reply.isEmpty {
                            AgentReplyText(text: reply)
                        } else if snapshot.currentTool == nil { Text("等待下一条事件…").font(.caption).foregroundStyle(.gray) }
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AgentReplyText: View {
    let text: String
    var body: some View {
        AssistantReplyText(text: String(text.suffix(32000)), fontSize: 12, lineLimit: nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct AgentRequestView: View {
    let request: PendingAgentRequest
    @State private var answers: [String: String] = [:]
    @State private var selected: [String: Set<String>] = [:]
    @ObservedObject private var monitor = AgentMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.tool).font(.caption.weight(.semibold))
                    if !request.detail.isEmpty { Text(request.detail).font(.caption.monospaced()).textSelection(.enabled) }
                    ForEach(request.questions) { question in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.text).font(.caption.weight(.medium))
                            ForEach(question.options, id: \.self) { option in
                                Button {
                                    if question.multiple {
                                        var values = selected[question.key] ?? []
                                        if values.contains(option) { values.remove(option) } else { values.insert(option) }
                                        selected[question.key] = values; answers[question.key] = question.options.filter { values.contains($0) }.joined(separator: ", ")
                                    } else { answers[question.key] = option }
                                } label: {
                                    Label(option, systemImage: (question.multiple ? selected[question.key]?.contains(option) == true : answers[question.key] == option) ? "checkmark.circle.fill" : "circle")
                                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                            TextField("输入回答", text: Binding(get: { answers[question.key] ?? "" }, set: { answers[question.key] = $0 })).textFieldStyle(.roundedBorder).font(.caption)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(request.questions.isEmpty ? "拒绝" : "取消") { monitor.decide(request, allow: false) }
                Spacer()
                Button(request.questions.isEmpty ? "允许一次" : "提交回答") {
                    monitor.decide(request, allow: true, answers: request.questions.isEmpty ? nil : answers)
                }.buttonStyle(.borderedProminent).tint(.green)
                .disabled(!request.questions.allSatisfy { !(answers[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }.font(.caption)
        }
    }
}
private func statusLabel(_ status: AgentStatus) -> String {
    switch status { case .idle: return "已完成 / 空闲"; case .processing: return "思考中"; case .running: return "执行中"; case .waitingApproval: return "等待审批"; case .waitingQuestion: return "等待回答" }
}
private func statusIcon(_ status: AgentStatus) -> String {
    switch status { case .idle: return "checkmark.circle"; case .processing: return "ellipsis.circle"; case .running: return "bolt.circle"; case .waitingApproval: return "hand.raised.circle"; case .waitingQuestion: return "questionmark.circle" }
}
private func statusColor(_ status: AgentStatus) -> Color {
    switch status { case .idle: return .green; case .processing, .running: return .cyan; case .waitingApproval, .waitingQuestion: return .orange }
}
