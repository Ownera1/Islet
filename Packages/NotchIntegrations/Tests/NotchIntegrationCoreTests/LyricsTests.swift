import XCTest
@testable import NotchIntegrationCore

final class LyricsTests: XCTestCase {
    func testYRCWordTimingAndTrailingSpaces() {
        let lines = Lyrics.parseYRC("{\"t\":0}\n[1000,2000](1000,800,0)Hello (1800,1200,0)world\nmalformed")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Hello world")
        XCTAssertEqual(lines[0].words[0].text, "Hello ")
        XCTAssertEqual(lines[0].words[0].progress(at: 0), 0)
        XCTAssertEqual(lines[0].words[0].progress(at: 1.4), 0.5, accuracy: 0.0001)
        XCTAssertEqual(lines[0].words[1].progress(at: 3), 1)
    }

    func testEnhancedLRCUsesWordEndTagsAndGlobalOffset() {
        let lines = Lyrics.parseEnhancedLRC("[offset:200]\n[00:01.00]<00:01.00>Hello <00:01.50>world<00:02.00>\n[00:03.00]plain")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].time, 1.2, accuracy: 0.0001)
        XCTAssertEqual(lines[0].text, "Hello world")
        XCTAssertEqual(lines[0].words[0].text, "Hello ")
        XCTAssertEqual(lines[0].words[0].duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(lines[0].words[1].time, 1.7, accuracy: 0.0001)
        XCTAssertEqual(lines[1].time, 3.2, accuracy: 0.0001)
    }

    func testLineSweepLeadInCapAndSeek() {
        let lines = Lyrics.parse("[00:10.00]first\n[00:30.00]second\n[00:30.00]duplicate")
        XCTAssertNil(Lyrics.index(at: 9.9, in: lines))
        XCTAssertEqual(Lyrics.index(at: 30, in: lines), 2)
        XCTAssertEqual(Lyrics.index(at: 12, in: lines), 0)
        XCTAssertEqual(Lyrics.progress(at: 10, index: 0, in: lines, duration: 45), 0)
        XCTAssertEqual(Lyrics.progress(at: 17.2, index: 0, in: lines, duration: 45), 1, accuracy: 0.0001)
        XCTAssertEqual(Lyrics.progress(at: 100, index: 2, in: lines, duration: 45), 1)
        XCTAssertEqual(Lyrics.progress(at: 0, index: 99, in: lines, duration: 45), 0)
    }

    func testPayloadQualityFallbackAndInstrumentalStates() {
        let row: [String: Any] = ["yrc": ["lyric": "[1000,1000](1000,1000,0)word"],
                                  "lrc": ["lyric": "[00:01.00]line"]]
        XCTAssertFalse(LyricsDocument.netease(row).lines[0].words.isEmpty)
        XCTAssertTrue(LyricsDocument.netease(["yrc": ["lyric": "invalid"], "lrc": ["lyric": "[00:01.00]line"]]).lines[0].words.isEmpty)
        for payload: [String: Any] in [["nolyric": true], ["pureMusic": true], ["lrc": ["lyric": "[00:05.00]纯音乐，请欣赏"]]] {
            XCTAssertEqual(LyricsDocument.netease(payload).availability, .instrumental)
        }
        XCTAssertEqual(LyricsDocument.netease(["uncollected": true]).availability, .unavailable)
        XCTAssertEqual(LyricsDocument.lrclib(["instrumental": true]).availability, .instrumental)
        XCTAssertEqual(LyricsDocument(plain: "words").availability, .available)
        XCTAssertFalse(LyricsAvailability.loading.canFocus)
        XCTAssertTrue(LyricsAvailability.instrumental.canFocus)
        XCTAssertFalse(LyricsAvailability.unavailable.canFocus)
    }
}
