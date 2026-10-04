import SwiftUI
import NotchIntegrationCore

struct SubscriptionPanelView: View {
    @ObservedObject private var monitor = SubscriptionMonitor.shared
    @AppStorage("subscriptionVisible.claude") private var claudeVisible = true
    @AppStorage("subscriptionVisible.openai") private var openaiVisible = true
    @AppStorage("subscriptionVisible.gemini") private var geminiVisible = true
    @AppStorage("subscriptionVisible.antigravity") private var antigravityVisible = true
    @AppStorage("subscriptionSyncEnabled") private var syncEnabled = true
    private var providers: [SubscriptionProvider] {
        SubscriptionProvider.allCases.filter {
            switch $0 {
            case .claude: return claudeVisible
            case .openai: return openaiVisible
            case .gemini: return geminiVisible
            case .antigravity: return antigravityVisible
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("订阅剩余量").font(.headline)
                Spacer()
                Text(syncEnabled ? "每 5 分钟同步" : "自动同步已关闭").font(.caption2).foregroundStyle(.gray)
                Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(monitor.refreshing || !syncEnabled).help("刷新用量")
            }
            if providers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash").font(.title2)
                    Text("所有订阅卡片已隐藏").font(.callout)
                    Text("在设置 → Agent 与订阅中选择要显示的剩余量。").font(.caption).foregroundStyle(.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(providers) { provider in
                        SubscriptionTile(provider: provider, usage: monitor.usage[provider], error: monitor.errors[provider], refreshing: monitor.refreshing, enabled: syncEnabled)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.foregroundStyle(.white)
    }
}
private struct SubscriptionTile: View {
    let provider: SubscriptionProvider
    let usage: SubscriptionUsage?
    let error: String?
    let refreshing: Bool
    let enabled: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.name).font(.caption.weight(.semibold))
                Spacer(minLength: 2)
                Button { NSWorkspace.shared.open(provider.dashboard) } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.plain).help("打开 \(provider.name) 用量页面")
            }
            Text(provider.scope).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    if let usage {
                        ForEach(usage.windows) { window in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(window.label).font(.system(size: 10)).lineLimit(2).help(window.label)
                                HStack(spacing: 6) {
                                    ProgressView(value: window.remainingPercent, total: 100).tint(window.remainingPercent <= 10 ? .orange : .green)
                                        .accessibilityLabel("\(provider.name) \(window.label) 剩余 \(Int(window.remainingPercent.rounded()))%")
                                    Text("剩余 \(Int(window.remainingPercent.rounded()))%").font(.system(size: 10).weight(.medium)).monospacedDigit().fixedSize()
                                }
                                if let reset = window.resetsAt {
                                    Text("重置 \(reset.formatted(.dateTime.month().day().hour().minute()))").font(.system(size: 9)).foregroundStyle(.gray)
                                }
                            }
                        }
                        HStack(spacing: 3) {
                            if let plan = usage.plan { Text(plan).lineLimit(1) }
                            Text(usage.fetchedAt, style: .time)
                        }.font(.system(size: 9)).foregroundStyle(.gray)
                        if let error { Text("上次数据 · \(error)").font(.system(size: 9)).foregroundStyle(.orange) }
                    } else {
                        Text(!enabled ? "同步已关闭" : error ?? (refreshing ? "正在读取用量…" : "等待同步"))
                            .font(.caption2).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
