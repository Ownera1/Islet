// Test-only adapters: no XPC process, media controller or external app is started.
import AppKit
import CodeIslandCore
import Combine
import Defaults
import NotchIntegrationCore
import SwiftUI

@MainActor
final class IntegrationServiceClient {
    static let shared = IntegrationServiceClient()
    var onStatus: ((String) -> Void)?
    var onEvent: ((Data, UUID) -> Void)?
    var onDisconnect: ((UUID) -> Void)?
    var onTranscript: ((Data) -> Void)?
    func start() { onStatus?("Agent 服务已就绪") }
    func stop() {}
    func respond(_ data: Data, id: UUID) {}
}

@MainActor
final class BoringViewCoordinator {
    static let shared = BoringViewCoordinator()
    enum Page { case home, agents }
    var currentView: Page = .home
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func showWindow() {}
}

enum AgentTerminal {
    static func open(_ snapshot: SessionSnapshot, id: String) {}
}

@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()
    @Published var isPlaying = false
    @Published var lyricsDocument = LyricsDocument()
    @Published var songDuration: Double = 20
    @Published var songTitle = "测试歌曲"
    @Published var artistName = "测试歌手"
    func estimatedPlaybackPosition(at date: Date) -> Double { 2 }
}

extension Defaults.Keys {
    static let lyricsTimeOffset = Key<Double>("renderLyricsOffset", default: 0)
}
