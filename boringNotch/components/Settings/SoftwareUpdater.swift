import SwiftUI
import Sparkle
import Combine
import NotchIntegrationCore

enum ReleaseLinks {
    static let repository = URL(string: "https://github.com/Ownera1/agent-usage-notch")!
    static let downloads = repository.appendingPathComponent("releases")
    static let feed = URL(string: "https://raw.githubusercontent.com/Ownera1/agent-usage-notch/main/updater/appcast.xml")!
}

// Pin the feed even if a local preference was left over from an upstream build.
final class AppUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { ReleaseLinks.feed.absoluteString }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard UpdateSourcePolicy.permits(item.fileURL) else {
            throw NSError(domain: "AgentUsageNotch.UpdateSource", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "更新源暂不可用：安装包必须来自 Agent Usage Notch 的 GitHub Release。"])
        }
    }
}

@MainActor
final class UpdaterPreferences: ObservableObject {
    private let updater: SPUUpdater
    @Published var canCheck = false
    @Published var automaticallyChecks = true {
        didSet { if updater.automaticallyChecksForUpdates != automaticallyChecks { updater.automaticallyChecksForUpdates = automaticallyChecks } }
    }
    @Published var automaticallyDownloads = false {
        didSet { if updater.automaticallyDownloadsUpdates != automaticallyDownloads { updater.automaticallyDownloadsUpdates = automaticallyDownloads } }
    }

    init(updater: SPUUpdater) {
        self.updater = updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).assign(to: &$automaticallyChecks)
        updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main).assign(to: &$automaticallyDownloads)
    }
}

struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    @StateObject private var preferences: UpdaterPreferences

    init(updater: SPUUpdater) {
        self.updater = updater
        _preferences = StateObject(wrappedValue: UpdaterPreferences(updater: updater))
    }

    var body: some View {
        Button("检查更新…") { updater.checkForUpdates() }
            .disabled(!preferences.canCheck)
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater
    @StateObject private var preferences: UpdaterPreferences

    init(updater: SPUUpdater) {
        self.updater = updater
        _preferences = StateObject(wrappedValue: UpdaterPreferences(updater: updater))
    }

    var body: some View {
        Section("软件更新") {
            Toggle("自动检查更新", isOn: $preferences.automaticallyChecks)
            Toggle("后台下载更新", isOn: $preferences.automaticallyDownloads)
            CheckForUpdatesView(updater: updater)
            Text("更新会在应用内下载、验证并安装，安装完成后重新启动应用。")
                .font(.caption).foregroundStyle(.secondary)
            Link("查看版本说明", destination: ReleaseLinks.downloads)
        }
    }
}
