import XCTest
@testable import CodeIslandCore

final class BridgeDebugLogTests: XCTestCase {
    func testDebugLoggingIsOffUnlessExplicitlyEnabled() {
        XCTAssertFalse(BridgeDebugLog.isEnabled(environment: [:]))
        for value in ["", " ", "0", "false", "FALSE", "no", "off"] {
            XCTAssertFalse(BridgeDebugLog.isEnabled(environment: ["BORINGNOTCH_DEBUG": value]), value)
        }
        for value in ["1", "true", "yes", "on"] {
            XCTAssertTrue(BridgeDebugLog.isEnabled(environment: ["BORINGNOTCH_DEBUG": value]), value)
        }
    }

    func testLogPathCanBeRedirected() {
        XCTAssertEqual(BridgeDebugLog.path(environment: [:]), "/tmp/notch-agent-bridge.log")
        XCTAssertEqual(BridgeDebugLog.path(environment: ["BORINGNOTCH_BRIDGE_LOG": " "]), "/tmp/notch-agent-bridge.log")
        XCTAssertEqual(BridgeDebugLog.path(environment: ["BORINGNOTCH_BRIDGE_LOG": "/tmp/x.log"]), "/tmp/x.log")
    }
}
