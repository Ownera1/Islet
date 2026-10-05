import AppKit
import CodeIslandCore
import Defaults
import NotchIntegrationCore
import SwiftUI

@main
struct AgentLyricsRenderingTests {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "Islet.AgentLyricsTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let monitor = AgentMonitor(preferences: preferences)
        monitor.start()
        defer { monitor.stop() }

        for agent in NotchAgent.allCases {
            monitor.selectedAgent = agent
            precondition(AgentMonitor(preferences: preferences).selectedAgent == agent, "Selection must survive reconstruction")
            precondition(monitor.isServiceReady, "Service readiness is independent of the framework")
            let panel = AgentPanelView(monitor: monitor)
                .frame(width: 556, height: 250)
                .padding(.horizontal, 42).padding(.vertical, 16)
                .background(.black, in: RoundedRectangle(cornerRadius: 24))
                .preferredColorScheme(.dark)
            try saveHosted(panel, size: CGSize(width: 640, height: 282), name: "agent-\(agent.rawValue)", output: output)
        }

        // Exercise the real monitor reducer and its automatic framework selection.
        func event(_ source: NotchAgent, _ name: String) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "_source": source.rawValue, "session_id": "test-\(source.rawValue)",
                "hook_event_name": name, "cwd": "/tmp/example-project", "tool_name": "Bash"
            ])
            IntegrationServiceClient.shared.onEvent?(data, UUID())
        }
        try event(.pi, "SessionStart")
        try event(.codex, "SessionStart")
        monitor.selectedAgent = .pi
        precondition(monitor.sortedSessions.count == 1 && monitor.selected?.snapshot.source == "pi")
        try event(.codex, "PermissionRequest")
        precondition(monitor.selectedAgent == .codex && monitor.selected?.snapshot.source == "codex")
        precondition(monitor.requests.count == 1, "Approval must remain visible across framework filters")
        try saveHosted(AgentPanelView(monitor: monitor).frame(width: 556, height: 250)
            .padding(20).background(.black), size: CGSize(width: 596, height: 290), name: "agent-approval", output: output)
        monitor.selectedAgent = nil
        precondition(AgentMonitor(preferences: preferences).selectedAgent == nil, "All selection must persist")
        precondition(monitor.selected == nil && monitor.connectedAgents.count == 2)
        try event(.claude, "SessionStart")
        try event(.antigravity, "SessionStart")
        try event(.claude, "UserPromptSubmit")
        let styleKey = Defaults.Key<AgentOverviewStyle>("agentOverviewStyle", default: .twoLine, suite: preferences)
        for style in AgentOverviewStyle.allCases {
            Defaults[styleKey] = style
            precondition(Defaults[styleKey] == style)
            let rows = VStack(spacing: 2) {
                ForEach(monitor.connectedAgents) { entry in AgentOverviewRow(entry: entry, style: style, select: {}) }
            }.frame(width: 324).padding(18).background(.black)
            try save(rows, name: "agent-overview-\(style.rawValue)", output: output)
        }
        try saveHosted(AgentPanelView(monitor: monitor).frame(width: 556, height: 250).padding(20).background(.black),
                       size: CGSize(width: 596, height: 290), name: "agent-overview", output: output)
        try saveHosted(AgentPanelView(monitor: monitor, menuOpen: true).frame(width: 556, height: 250).padding(20).background(.black), size: CGSize(width: 596, height: 290), name: "agent-switcher", output: output)
        preferences.set("invalid", forKey: "selectedAgentFramework")
        precondition(AgentMonitor(preferences: preferences).selectedAgent == nil)

        let short = LyricsDocument(lines: Lyrics.parse("[00:00]这里显示正在演唱的这一句歌词\n[00:08]下一句歌词会从下方滑入"))
        let long = LyricsDocument(lines: Lyrics.parse("[00:00]这是一句很长很长的歌词，演唱时会随进度匀速横向滚动，直到这句唱完为止\n[00:10]下一句"))
        let instrumental = LyricsDocument(instrumental: true)
        let samples: [(String, String, LyricsDocument, Double, Bool, Bool)] = [
            ("sing", "正在演唱", short, 3, true, false),
            ("scroll", "长句滚动", long, 5, true, false),
            ("interlude", "间奏 / 纯音乐", instrumental, 3, true, false),
            ("pause", "暂停", short, 3, false, false),
            ("reduced-motion", "减少动态效果", short, 3, true, true)
        ]
        var galleries: [AnyView] = []
        for (name, title, document, time, playing, reduce) in samples {
            let content = CollapsedLyricContent(
                frame: CollapsedLyricFrame(document: document, elapsed: time, duration: 20),
                elapsed: time, date: Date(timeIntervalSinceReferenceDate: 100),
                isPlaying: playing, reduceMotion: reduce
            )
            let capsule = capsule(AnyView(content), width: 440, playing: playing)
            try save(capsule, name: "lyrics-\(name)", output: output)
            galleries.append(AnyView(VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 12)).foregroundStyle(.gray)
                capsule
            }))
        }
        let narrow = capsule(AnyView(Color.clear), width: 230, playing: true)
        try save(narrow, name: "lyrics-unavailable", output: output)
        galleries.append(AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("加载中 / 无歌词").font(.system(size: 12)).foregroundStyle(.gray)
            narrow
        }))
        let strip = VStack(spacing: 0) {
            capsule(AnyView(Color.clear), width: 440, playing: true)
            CollapsedLyricContent(frame: CollapsedLyricFrame(document: short, elapsed: 3, duration: 20),
                                  elapsed: 3, date: Date(timeIntervalSinceReferenceDate: 100),
                                  isPlaying: true, reduceMotion: false, fontSize: 12)
                .frame(width: 272, height: 24).frame(width: 300)
                .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
        try save(strip, name: "lyrics-hardware-notch", output: output)
        galleries.append(AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("内置刘海屏 / 所有显示器").font(.system(size: 12)).foregroundStyle(.gray)
            strip
        }))
        try save(VStack(alignment: .leading, spacing: 20) {
            ForEach(galleries.indices, id: \.self) { galleries[$0] }
        }.padding(24).frame(width: 488).background(Color(white: 0.12)), name: "lyrics-gallery", output: output)

        for mode in CollapsedLyricsMode.allCases {
            try save(CollapsedLyricsSettingsPreview(mode: mode, enabled: true)
                .padding(20).frame(width: 420).background(Color(white: 0.12))
                .preferredColorScheme(.dark), name: "settings-\(mode.rawValue)", output: output)
        }
        print("Passed framework persistence, session filtering and approval selection checks; rendered 21 SwiftUI previews.")
    }

    @MainActor
    private static func capsule(_ content: AnyView, width: CGFloat, playing: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note").foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color(red: 0.54, green: 0.35, blue: 0.35), in: RoundedRectangle(cornerRadius: 4))
            content.frame(maxWidth: .infinity).frame(height: 20)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.75, green: 0.31, blue: 0.3))
                        .frame(width: 3, height: playing ? [8.0, 14.0, 10.0, 16.0][index] : 5)
                }
            }.frame(width: 26)
        }
        .padding(.horizontal, 14).frame(width: width, height: 40)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
    }

    @MainActor
    private static func save<V: View>(_ view: V, name: String, output: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AgentLyricsRenderingTests", code: 1)
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }

    /// ImageRenderer does not draw AppKit-backed controls such as Menu.
    @MainActor
    private static func saveHosted<V: View>(_ view: V, size: CGSize, name: String, output: URL) throws {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "AgentLyricsRenderingTests", code: 2)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AgentLyricsRenderingTests", code: 3)
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
}
