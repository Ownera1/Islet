import XCTest
@testable import NotchIntegrationCore

final class UpdateSourcePolicyTests: XCTestCase {
    func testOnlyOwnHTTPSReleaseAssetsAreAccepted() {
        XCTAssertTrue(UpdateSourcePolicy.permits(URL(string: "https://github.com/Ownera1/agent-usage-notch/releases/download/v0.1.3/Agent-Usage-Notch.zip")))
        for value in ["https://github.com/TheBoredTeam/boring.notch/releases/download/v2.7.3/app.zip",
                      "http://github.com/Ownera1/agent-usage-notch/releases/download/v0.1.3/app.zip",
                      "https://github.com.evil.example/Ownera1/agent-usage-notch/releases/download/v0.1.3/app.zip",
                      "https://github.com/Ownera1/agent-usage-notch/releases/download/v0.1.3/a%2Fb.zip",
                      "https://github.com/Ownera1/agent-usage-notch/releases/download/v0.1.3/app.zip?redirect=evil",
                      "https://github.com/Ownera1/agent-usage-notch/releases"] {
            XCTAssertFalse(UpdateSourcePolicy.permits(URL(string: value)), value)
        }
        XCTAssertFalse(UpdateSourcePolicy.permits(nil))
    }
}
