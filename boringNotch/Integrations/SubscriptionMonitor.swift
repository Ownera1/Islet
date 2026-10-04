import Foundation
import Combine
import CodeIslandCore
import NotchIntegrationCore

@MainActor
final class SubscriptionMonitor: ObservableObject {
    static let shared = SubscriptionMonitor()
    @Published private(set) var usage: [SubscriptionProvider: SubscriptionUsage] = [:]
    @Published private(set) var errors: [SubscriptionProvider: String] = [:]
    @Published private(set) var refreshing = false
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    var enabled: Bool { UserDefaults.standard.object(forKey: "subscriptionSyncEnabled") as? Bool ?? true }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() { timer?.invalidate(); refreshTask?.cancel(); refreshTask = nil }
    func refresh() {
        guard enabled, !refreshing else { return }
        refreshing = true
        let claudeHome = AgentInstaller.shared.claudeHome
        let codexHome = AgentInstaller.shared.codexHome
        refreshTask = Task { [weak self] in
            await withTaskGroup(of: (SubscriptionProvider, SubscriptionUsage?, String?).self) { group in
                for provider in SubscriptionProvider.allCases {
                    group.addTask {
                        let result = await IntegrationServiceClient.shared.fetchUsage(provider, claudeHome: claudeHome, codexHome: codexHome)
                        return (provider, result.0, result.1)
                    }
                }
                for await (provider, value, error) in group {
                    guard !Task.isCancelled else { continue }
                    if let value { self?.usage[provider] = value }
                    self?.errors[provider] = error
                }
            }
            self?.refreshing = false
        }
    }
}
