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

    func testOnlyHUDMediaKeysAreIntercepted() {
        for key in [0, 1, 2, 3, 7, 21, 22] {
            XCTAssertEqual(MediaKeyEvent(data1: (key << 16) | 0xA00, subtype: 8)?.isKeyDown, true)
            XCTAssertEqual(MediaKeyEvent(data1: (key << 16) | 0xB00, subtype: 8)?.isKeyDown, false)
        }
        XCTAssertNil(MediaKeyEvent(data1: (16 << 16) | 0xA00, subtype: 8)) // Play/pause passes through.
        XCTAssertNil(MediaKeyEvent(data1: 0xA00, subtype: 0))
        XCTAssertNil(MediaKeyEvent(data1: 0xC00, subtype: 8))
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
