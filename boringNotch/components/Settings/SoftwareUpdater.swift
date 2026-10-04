import SwiftUI
import Sparkle

enum ReleaseLinks {
    static let repository = URL(string: "https://github.com/Ownera1/agent-usage-notch")!
    static let downloads = repository.appendingPathComponent("releases")
}

// This integration uses its own releases. The upstream feed could replace it
// with an app that lacks these features, so its Sparkle updater is not started.
struct CheckForUpdatesView: View {
    init(updater: SPUUpdater) {}
    var body: some View {
        Button("下载更新…") { NSWorkspace.shared.open(ReleaseLinks.downloads) }
    }
}

struct UpdaterSettingsView: View {
    init(updater: SPUUpdater) {}
    var body: some View {
        Section("软件更新") {
            Text("此集成版通过自己的 GitHub Release 发布更新。")
            Link("查看安装包与更新说明", destination: ReleaseLinks.downloads)
        }
    }
}
