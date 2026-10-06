import Foundation
import CodeIslandCore
import NotchIntegrationCore

/// Follows Claude Desktop's Cowork sessions. Cowork runs the Claude Code
/// engine inside a VM, so `~/.claude/settings.json` hooks never fire for it;
/// its own session store is the only signal. Polls every 2 s on a private
/// queue and only reads (see `CoworkStoreScanner`).
final class CoworkWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ownera1.agentusagenotch.cowork", qos: .utility)
    private let onUpdate: @Sendable (Data) -> Void
    // Touched only on `queue`.
    private var timer: DispatchSourceTimer?
    private var scanner: CoworkStoreScanner?

    init(onUpdate: @escaping @Sendable (Data) -> Void) {
        self.onUpdate = onUpdate
    }

    func start(root: String = CoworkPaths.defaultRoot(home: HomePaths.userHome), interval: TimeInterval = 2) {
        queue.async { [self] in
            stopOnQueue()
            scanner = CoworkStoreScanner(root: root)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        scanner = nil
    }

    private func tick() {
        guard let scanner else { return }
        let encoder = JSONEncoder()
        for update in scanner.scan() {
            if let data = try? encoder.encode(update) { onUpdate(data) }
        }
    }
}
