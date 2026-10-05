import XCTest
@testable import NotchIntegrationCore

final class CollapsedLyricsTests: XCTestCase {
    func testPlacementOnBothScreenTypes() {
        XCTAssertEqual(collapsedLyricsPlacement(mode: .off, hasHardwareNotch: false), .hidden)
        XCTAssertEqual(collapsedLyricsPlacement(mode: .off, hasHardwareNotch: true), .hidden)
        XCTAssertEqual(collapsedLyricsPlacement(mode: .externalDisplays, hasHardwareNotch: false), .inline)
        XCTAssertEqual(collapsedLyricsPlacement(mode: .externalDisplays, hasHardwareNotch: true), .hidden)
        XCTAssertEqual(collapsedLyricsPlacement(mode: .allDisplays, hasHardwareNotch: false), .inline)
        XCTAssertEqual(collapsedLyricsPlacement(mode: .allDisplays, hasHardwareNotch: true), .belowNotch)
    }

    func testScrollUsesFullLineIntervalWithEndpointPauses() {
        let document = LyricsDocument(lines: Lyrics.parse("[00:10]first\n[00:30]second"))
        func frame(_ time: Double) -> CollapsedLyricFrame {
            CollapsedLyricFrame(document: document, elapsed: time, duration: 40)
        }
        XCTAssertNil(frame(9).line)
        XCTAssertEqual(frame(10).line?.text, "first")
        XCTAssertEqual(frame(12).scrollProgress, 0)
        XCTAssertEqual(frame(20).scrollProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(frame(28).scrollProgress, 1)
        XCTAssertEqual(frame(30).line?.text, "second")
        XCTAssertEqual(frame(11).scrollProgress, 0, "Seeking backwards restores the line start")
        XCTAssertEqual(frame(39).scrollProgress, 1)
        XCTAssertNil(frame(40).line, "The last line ends at the track duration")
    }

    func testInterludesAndContentAvailability() {
        let document = LyricsDocument(lines: [
            LyricLine(time: 1, text: "sing", duration: 2),
            LyricLine(time: 8, text: ""),
            LyricLine(time: 12, text: "again")
        ])
        XCTAssertNotNil(CollapsedLyricFrame(document: document, elapsed: 2, duration: 20).line)
        XCTAssertNil(CollapsedLyricFrame(document: document, elapsed: 3, duration: 20).line)
        XCTAssertNil(CollapsedLyricFrame(document: document, elapsed: 9, duration: 20).line)
        XCTAssertTrue(CollapsedLyricFrame.hasContent(document: document, availability: .available))
        XCTAssertFalse(CollapsedLyricFrame.hasContent(document: document, availability: .loading))
        XCTAssertFalse(CollapsedLyricFrame.hasContent(document: document, availability: .unavailable))
        XCTAssertFalse(CollapsedLyricFrame.hasContent(document: LyricsDocument(plain: "untimed"), availability: .available))
        XCTAssertTrue(CollapsedLyricFrame.hasContent(document: LyricsDocument(instrumental: true), availability: .instrumental))
    }
}
