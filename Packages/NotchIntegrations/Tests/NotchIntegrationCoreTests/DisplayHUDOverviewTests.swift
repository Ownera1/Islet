import XCTest
import CodeIslandCore
@testable import NotchIntegrationCore

final class DisplayHUDOverviewTests: XCTestCase {
    func testDisplayDisconnectToggleAndReconnect() {
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: ["built-in", "external"], main: "built-in", automaticallySwitch: true), "external")
        XCTAssertNil(DisplaySelection.resolve(preferred: "external", available: ["built-in"], main: "built-in", automaticallySwitch: false))
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: ["built-in"], main: "built-in", automaticallySwitch: true), "built-in")
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: ["built-in", "external"], main: "built-in", automaticallySwitch: true), "external")
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: ["built-in"], main: nil, automaticallySwitch: true), "built-in")
        XCTAssertNil(DisplaySelection.resolve(preferred: "external", available: [], main: nil, automaticallySwitch: true))
    }

    func testAutomaticSwitchFollowsActiveDisplay() {
        let both = ["built-in", "external"]
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: both, main: "external", automaticallySwitch: true, active: "built-in"), "built-in")
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: both, main: "built-in", automaticallySwitch: false, active: "built-in"), "external")
        // An active display that has since disconnected falls back to the preference.
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: both, main: "built-in", automaticallySwitch: true, active: "gone"), "external")
        XCTAssertEqual(DisplaySelection.resolve(preferred: "external", available: ["built-in"], main: nil, automaticallySwitch: true, active: "external"), "built-in")
    }

    func testActiveDisplayTrackerDebouncesAndHolds() {
        let t0 = Date(timeIntervalSince1970: 0)
        var tracker = ActiveDisplayTracker(active: "external", dwell: 0.3)
        XCTAssertNil(tracker.observe("external", at: t0, canSwitch: true))
        XCTAssertNil(tracker.observe("built-in", at: t0, canSwitch: true))
        XCTAssertNil(tracker.observe("built-in", at: t0.addingTimeInterval(0.2), canSwitch: true))
        XCTAssertEqual(tracker.observe("built-in", at: t0.addingTimeInterval(0.35), canSwitch: true), "built-in")
        XCTAssertEqual(tracker.active, "built-in")

        // Brief crossing restarts the dwell.
        XCTAssertNil(tracker.observe("external", at: t0.addingTimeInterval(1), canSwitch: true))
        XCTAssertNil(tracker.observe("built-in", at: t0.addingTimeInterval(1.1), canSwitch: true))
        XCTAssertNil(tracker.observe("external", at: t0.addingTimeInterval(1.2), canSwitch: true))
        XCTAssertNil(tracker.observe("external", at: t0.addingTimeInterval(1.4), canSwitch: true))

        // Held while the notch is busy, and the dwell starts over once it is free.
        XCTAssertNil(tracker.observe("external", at: t0.addingTimeInterval(2), canSwitch: false))
        XCTAssertNil(tracker.observe("external", at: t0.addingTimeInterval(2.1), canSwitch: true))
        XCTAssertEqual(tracker.observe("external", at: t0.addingTimeInterval(2.5), canSwitch: true), "external")
        XCTAssertNil(tracker.observe(nil, at: t0.addingTimeInterval(3), canSwitch: true))
        XCTAssertEqual(tracker.active, "external")
    }

    func testOnlyHUDMediaKeysAreIntercepted() {
        for key in [0, 1, 2, 3, 7, 21, 22] {
            XCTAssertEqual(MediaKeyEvent(data1: (key << 16) | 0xA00, subtype: 8)?.isKeyDown, true)
            XCTAssertEqual(MediaKeyEvent(data1: (key << 16) | 0xB00, subtype: 8)?.isKeyDown, false)
        }
        XCTAssertNil(MediaKeyEvent(data1: (16 << 16) | 0xA00, subtype: 8)) // Play/pause passes through.
        XCTAssertNil(MediaKeyEvent(data1: 0xA00, subtype: 0))
        XCTAssertNil(MediaKeyEvent(data1: 0xC00, subtype: 8))

        // Brightness keys pass through when Islet cannot drive the display under the pointer.
        let brightnessUp = MediaKeyEvent(data1: (2 << 16) | 0xA00, subtype: 8)!
        XCTAssertTrue(brightnessUp.shouldIntercept(commandHeld: false, pointerDisplayBrightnessControllable: true))
        XCTAssertFalse(brightnessUp.shouldIntercept(commandHeld: false, pointerDisplayBrightnessControllable: false))
        XCTAssertTrue(brightnessUp.shouldIntercept(commandHeld: true, pointerDisplayBrightnessControllable: false)) // ⌘ = keyboard backlight
        let volumeUp = MediaKeyEvent(data1: 0xA00, subtype: 8)!
        XCTAssertTrue(volumeUp.shouldIntercept(commandHeld: false, pointerDisplayBrightnessControllable: false))
        let backlightUp = MediaKeyEvent(data1: (21 << 16) | 0xA00, subtype: 8)!
        XCTAssertTrue(backlightUp.shouldIntercept(commandHeld: false, pointerDisplayBrightnessControllable: false))
    }

    func testOverviewUsesLiveSessionsAndStableStateOrdering() {
        var pi = SessionSnapshot(); pi.source = "pi"; pi.status = .idle
        var codex = SessionSnapshot(); codex.source = "codex"; codex.status = .running; codex.currentTool = "Bash"
        var approval = codex; approval.status = .waitingApproval
        let entries = AgentOverviewEntry.entries(sessions: ["pi": pi, "codex": codex, "approval": approval])
        XCTAssertEqual(entries.map(\.agent), [.codex, .pi, .claude, .zcode, .antigravity])
        XCTAssertEqual(entries.first?.sessionCount, 2)
        XCTAssertEqual(entries.first?.subtitle, "等待审批")
        XCTAssertEqual(entries.filter { $0.state != .offline }.count, 2)
        XCTAssertTrue(AgentOverviewEntry.entries(sessions: [:]).allSatisfy { $0.state == .offline })
    }
}
