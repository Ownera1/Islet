import SwiftUI
import Defaults
import CodeIslandCore
import NotchIntegrationCore

extension AgentOverviewStyle: Defaults.Serializable {}
extension Defaults.Keys {
    static let agentOverviewStyle = Key<AgentOverviewStyle>("agentOverviewStyle", default: .twoLine)
    /// Seconds the notch stays open after a completion reveal; 0 keeps it open until the pointer leaves.
    static let agentCompletionCollapseDelay = Key<Double>("agentCompletionCollapseDelay", default: 5)
}

struct AgentPanelView: View {
    @ObservedObject var monitor: AgentMonitor = .shared
    @Default(.agentOverviewStyle) private var overviewStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var menuOpen = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.15)) { menuOpen.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            if let agent = monitor.selectedAgent {
                                Circle().fill(agent.accentColor).frame(width: 8, height: 8)
                            } else {
                                Image(systemName: "square.grid.2x2").foregroundStyle(.gray)
                            }
                            Text(monitor.selectedAgent?.name ?? "全部 Agent")
                                .font(.system(size: 16, weight: .medium)).fixedSize()
                            Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(.gray)
                        }.padding(.vertical, 3).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityLabel("切换 Agent，当前\(monitor.selectedAgent?.name ?? "全部 Agent")")
                    .accessibilityValue(menuOpen ? "已展开" : "已收起")
                    .help("切换 Agent")

                    if let agent = monitor.selectedAgent {
                        singleSummary(agent)
                    } else {
                        overviewSummary
                    }
                    Spacer(minLength: 0)
                }.frame(width: 212, alignment: .topLeading)
                Divider().overlay(.white.opacity(0.12))
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if monitor.selectedAgent == nil {
                            overview
                        } else if let selected = monitor.selected {
                            AgentSessionDetail(id: selected.id, snapshot: selected.snapshot, monitor: monitor)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "terminal").font(.system(size: 24)).foregroundStyle(Color(white: 0.3))
                                Text("连接 Agent 后，任务会显示在这里").font(.caption).foregroundStyle(.gray)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .id(monitor.selectedAgent?.rawValue ?? "all")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 3)))
                    HStack(spacing: 6) {
                        Circle().fill(monitor.isServiceReady ? Color.agentRunning : .gray).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(monitor.serviceStatus).font(.system(size: 11)).foregroundStyle(.gray)
                        if monitor.selectedAgent != nil {
                            Spacer(minLength: 0)
                            Button { monitor.selectedAgent = nil } label: {
                                Label("全部 Agent", systemImage: "chevron.left").font(.system(size: 11))
                            }.buttonStyle(.plain).foregroundStyle(.gray).help("返回全部 Agent")
                        }
                    }.padding(.bottom, 2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if menuOpen {
                Color.clear.contentShape(Rectangle()).onTapGesture { menuOpen = false }
                AgentSwitcher(monitor: monitor) { menuOpen = false }
                    .frame(width: 212).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.25), value: monitor.selectedAgent)
        .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white)
        .onExitCommand { menuOpen = false }
    }

    private var overviewSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryLine(.running, count: monitor.overview.filter { $0.state == .running }.count)
            summaryLine(.idle, count: monitor.overview.filter { $0.state == .idle }.count)
            summaryLine(.offline, count: monitor.overview.filter { $0.state == .offline }.count)
            Text("选择右侧 Agent 查看任务详情").font(.system(size: 11)).foregroundStyle(.gray).padding(.top, 4)
        }
    }
    private func summaryLine(_ state: AgentConnectionState, count: Int) -> some View {
        HStack(spacing: 7) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text("\(count) 个\(state.label)").font(.system(size: 13))
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private func singleSummary(_ agent: NotchAgent) -> some View {
        if let entry = monitor.overview.first(where: { $0.agent == agent }), let snapshot = monitor.selected?.snapshot ?? entry.snapshot {
            HStack(spacing: 6) {
                Circle().fill(entry.state.color).frame(width: 7, height: 7)
                Text(entry.state.label).font(.system(size: 13, weight: .medium))
            }
            Text(AgentOverviewEntry.entries(sessions: ["selected": snapshot]).first(where: { $0.agent == agent })?.subtitle ?? entry.subtitle).font(.caption).foregroundStyle(.gray).lineLimit(2)
            if let selected = monitor.selected, let cwd = selected.snapshot.cwd {
                Text((cwd as NSString).lastPathComponent).font(.caption).foregroundStyle(.gray).lineLimit(1).help(cwd)
            } else if let title = monitor.selected?.snapshot.sessionTitle {
                Text(title).font(.caption).foregroundStyle(.gray).lineLimit(1).help(title)
            }
            if entry.state == .running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(snapshot.startTime)))
                    Text("会话时长 \(seconds / 60)m \(seconds % 60)s")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.gray)
                }
            }
            if monitor.sortedSessions.count > 1 {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(monitor.sortedSessions, id: \.id) { row in
                            Button { monitor.selectedSessionID = row.id } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: statusIcon(row.snapshot.status)).foregroundStyle(statusColor(row.snapshot.status))
                                    Text(row.snapshot.cwd.map { ($0 as NSString).lastPathComponent } ?? row.snapshot.sessionTitle ?? "会话").lineLimit(1)
                                    Spacer(minLength: 0)
                                }.font(.caption).padding(7)
                                .background(monitor.selected?.id == row.id ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        } else {
            AgentFrameworkEmptyState(agent: agent) { SettingsWindowController.shared.showWindow() }
        }
    }
    @ViewBuilder private var overview: some View {
        if monitor.connectedAgents.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "terminal").font(.system(size: 24)).foregroundStyle(Color(white: 0.3))
                Text("还没有已连接的 Agent").font(.caption).foregroundStyle(.gray)
                Button("连接 Agent") { SettingsWindowController.shared.showWindow() }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(monitor.connectedAgents) { entry in
                        AgentOverviewRow(entry: entry, style: overviewStyle) { monitor.selectedAgent = entry.agent }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AgentOverviewRow: View {
    let entry: AgentOverviewEntry
    let style: AgentOverviewStyle
    let select: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                if style == .twoLine {
                    RoundedRectangle(cornerRadius: 2).fill(entry.agent.accentColor).frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.agent.name).font(.system(size: 13, weight: .medium)).fixedSize()
                        Text(entry.subtitle).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Circle().fill(entry.agent.accentColor).frame(width: 7, height: 7)
                    Text(entry.agent.name).font(.system(size: 13, weight: .medium)).fixedSize()
                    Text(entry.subtitle).font(.system(size: 12)).foregroundStyle(.gray)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                }
                Group {
                    if entry.state == .running {
                        AgentActivityIndicator(reduceMotion: reduceMotion)
                    } else { Color.clear }
                }.frame(width: 15, height: 15)
            }.padding(.horizontal, 6).frame(height: style == .twoLine ? 40 : 32)
                .background(hovered ? Color(white: 0.067) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
        .accessibilityLabel("\(entry.agent.name)，\(entry.state.label)，\(entry.subtitle)")
        .help("\(entry.agent.name)：\(entry.subtitle)")
    }
}

private struct AgentActivityIndicator: View {
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Circle().trim(from: 0.05, to: 0.80)
                .stroke(Color.agentRunning, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
        }.accessibilityHidden(true)
    }
}

private struct AgentMenuBottom: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
struct AgentSwitcher: View {
    @ObservedObject var monitor: AgentMonitor
    let close: () -> Void
    @State private var atBottom = false
    var body: some View {
        VStack(spacing: 3) {
            row(nil, state: nil)
            Divider().overlay(.white.opacity(0.12)).padding(.horizontal, 6)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(monitor.overview.enumerated()), id: \.element.id) { index, entry in
                        if index > 0, monitor.overview[index - 1].state != entry.state {
                            Divider().overlay(.white.opacity(0.12)).padding(.horizontal, 6).padding(.vertical, 2)
                        }
                        row(entry.agent, state: entry.state)
                    }
                }.background(GeometryReader { geometry in
                    Color.clear.preference(key: AgentMenuBottom.self, value: geometry.frame(in: .named("agent-menu")).maxY)
                })
            }.coordinateSpace(name: "agent-menu").frame(height: 98)
            .onPreferenceChange(AgentMenuBottom.self) { atBottom = $0 <= 99 }
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.80),
                                       .init(color: atBottom ? .black : .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }.padding(4).background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1))
    }
    private func row(_ agent: NotchAgent?, state: AgentConnectionState?) -> some View {
        AgentMenuRow(name: agent?.name ?? "全部 Agent", color: agent?.accentColor, state: state,
                     selected: monitor.selectedAgent == agent) {
            monitor.selectedAgent = agent
            close()
        }
    }
}
private struct AgentMenuRow: View {
    let name: String
    let color: Color?
    let state: AgentConnectionState?
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                else { Image(systemName: "square.grid.2x2").font(.system(size: 10)).frame(width: 7) }
                Text(name).font(.system(size: 12)).fixedSize()
                Spacer(minLength: 2)
                if let state { Text(state.label).font(.system(size: 10)).foregroundStyle(state.color) }
                Image(systemName: "checkmark").font(.system(size: 10)).opacity(selected ? 1 : 0).frame(width: 10)
            }.padding(.horizontal, 7).frame(height: 26)
                .background(selected || hovered ? .white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
struct AgentFrameworkEmptyState: View {
    let agent: NotchAgent
    let connect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("未连接", systemImage: "circle.fill").foregroundStyle(.gray)
            Text("在设置中连接 \(agent.name) 后，启动一次新会话。")
                .foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
            Button("连接 \(agent.name)", action: connect).buttonStyle(.bordered)
        }.font(.caption)
    }
}
private extension Color {
    static let agentRunning = Color(red: 0.36, green: 0.81, blue: 0.42)
}
private extension AgentConnectionState {
    var color: Color {
        switch self { case .running: return .agentRunning; case .idle: return .init(red: 0.31, green: 0.50, blue: 0.84); case .offline: return .init(white: 0.4) }
    }
}
extension NotchAgent {
    var accentColor: Color {
        switch self {
        case .pi: return Color(red: 0.55, green: 0.49, blue: 0.96)
        case .codex: return Color(red: 0.31, green: 0.50, blue: 0.84)
        case .claude: return Color(red: 0.85, green: 0.45, blue: 0.29)
        case .zcode: return Color(red: 0.18, green: 0.71, blue: 0.59)
        case .antigravity: return Color(red: 0.82, green: 0.40, blue: 0.61)
        }
    }
}
private struct AgentSessionDetail: View {
    let id: String
    let snapshot: SessionSnapshot
    @ObservedObject var monitor: AgentMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(statusLabel(snapshot.status), systemImage: statusIcon(snapshot.status)).foregroundStyle(statusColor(snapshot.status)).font(.caption.weight(.semibold))
                if let branch = snapshot.gitBranch { Text(branch).font(.caption2).foregroundStyle(.gray).lineLimit(1).help(snapshot.cwd ?? "") }
                if let host = ClaudeDesktop.hostLabel(id: id, snapshot: snapshot) {
                    Text(host).font(.caption2).foregroundStyle(.gray).lineLimit(1)
                }
                Spacer()
                Button { AgentTerminal.open(snapshot, id: id) } label: { Image(systemName: "arrow.up.forward.app") }.help("打开来源窗口")
                Button { monitor.dismiss(id) } label: { Image(systemName: "xmark") }.help("移除会话卡片")
            }.buttonStyle(.plain)
            if let request = monitor.requests.first(where: { $0.sessionID == id }) {
                AgentRequestView(request: request, monitor: monitor).id(request.id)
            } else if DisplayOnlyWait.kind(status: snapshot.status, islandHoldsRequest: false) != nil {
                // Blocked on a prompt the island cannot answer (Claude Desktop's own card).
                VStack(alignment: .leading, spacing: 7) {
                    if let tool = snapshot.currentTool { Text(tool).font(.caption.weight(.semibold)) }
                    if let detail = snapshot.toolDescription { Text(detail).font(.caption.monospaced()).foregroundStyle(.gray).lineLimit(4).textSelection(.enabled) }
                    let place = ClaudeDesktop.isDesktopSession(snapshot) ? ClaudeDesktop.displayName : snapshot.terminalName ?? "来源应用"
                    Text(snapshot.status == .waitingQuestion ? "请在\(place)中回答" : "请在\(place)中审批").font(.caption).foregroundStyle(.orange)
                    Button("前往处理") { AgentTerminal.open(snapshot, id: id) }.font(.caption)
                }
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
                        ForEach(snapshot.agentTasks.items) { task in
                            HStack(spacing: 7) {
                                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : task.status == .inProgress ? "circle.dotted" : "circle")
                                    .foregroundStyle(task.status == .completed ? .green : task.status == .inProgress ? .cyan : .gray)
                                Text(task.progressLabel).font(.caption).lineLimit(2)
                                Spacer(minLength: 0)
                            }.accessibilityLabel("\(task.progressLabel)，\(task.status == .completed ? "已完成" : task.status == .inProgress ? "进行中" : "待执行")")
                        }
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
    @ObservedObject var monitor: AgentMonitor
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
