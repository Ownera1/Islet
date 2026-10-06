import Foundation
import Defaults
import AppKit

@main struct HUDLifecycleTests {
    @MainActor static func main() async {
        let interceptor = MediaKeyInterceptor.shared
        let client = XPCHelperClient.shared
        defer { interceptor.stop(); Defaults.reset(.hudReplacement, .optionKeyAction) }
        Defaults[.hudReplacement] = true
        client.result = (false, "permission denied")
        await interceptor.start()
        precondition(!Defaults[.hudReplacement] && !interceptor.isRunning && interceptor.errorMessage == "permission denied")

        Defaults[.hudReplacement] = true
        client.result = (true, nil)
        await interceptor.start()
        precondition(interceptor.isRunning && interceptor.errorMessage == nil)
        client.onMediaKeyDown?(0, NSEvent.ModifierFlags([.option, .shift]).rawValue)
        await Task.yield()
        precondition(VolumeManager.shared.increases == [4], "Forwarded modifiers must preserve quarter steps")
        client.onMediaDisconnect?()
        precondition(!Defaults[.hudReplacement] && !interceptor.isRunning && interceptor.errorMessage != nil)
        interceptor.stop()

        // Disable while XPC start is suspended: a late reply must not re-enable the tap.
        Defaults[.hudReplacement] = true
        client.deferred = true
        let start = Task { await interceptor.start() }
        while client.pending.isEmpty { await Task.yield() }
        Defaults[.hudReplacement] = false
        interceptor.stop()
        let stops = client.stopCount
        client.pending.removeFirst().resume(returning: (true, nil))
        await start.value
        precondition(!interceptor.isRunning && client.stopCount == stops + 1)

        // A newer enable owns the tap; an older reply cannot stop or mark it running.
        Defaults[.hudReplacement] = true
        let old = Task { await interceptor.start() }
        while client.pending.isEmpty { await Task.yield() }
        Defaults[.hudReplacement] = false
        interceptor.stop()
        Defaults[.hudReplacement] = true
        let new = Task { await interceptor.start() }
        while client.pending.count < 2 { await Task.yield() }
        let before = client.stopCount
        client.pending.removeFirst().resume(returning: (true, nil))
        await old.value
        precondition(!interceptor.isRunning && client.stopCount == before)
        client.pending.removeFirst().resume(returning: (true, nil))
        await new.value
        precondition(interceptor.isRunning)

        // A cancelled caller no longer abandons the start halfway with the switch left on.
        interceptor.stop()
        client.deferred = false
        let cancelled = Task { await interceptor.start() }
        cancelled.cancel()
        await cancelled.value
        precondition(interceptor.isRunning && Defaults[.hudReplacement])

        // The helper loses its tap without telling the app: supervision restarts it.
        let starts = client.startCount
        client.tapActive = false
        try? await Task.sleep(for: .seconds(3.5))
        precondition(client.startCount > starts && interceptor.isRunning, "Supervisor must restart a dead tap")
        client.tapActive = true
        print("Passed HUD failure, retry, modifiers, disconnect, delayed XPC, cancellation and supervision checks.")
    }
}
