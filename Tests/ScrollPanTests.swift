import AppKit
import XCTest

final class ScrollPanTests: XCTestCase {
    private func scroll(
        _ state: inout ScrollPanState,
        y: CGFloat = -120,
        x: CGFloat = 0,
        inside: Bool = true,
        phase: NSEvent.Phase = .changed,
        momentum: NSEvent.Phase = [],
        precise: Bool = true
    ) -> [ScrollPanUpdate] {
        state.update(
            deltaX: x, deltaY: y, precise: precise,
            phase: phase, momentumPhase: momentum, insideRegion: inside
        )
    }

    @objc func testLongContentScrollNeverRequestsClose() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        XCTAssertTrue(scroll(&state, inside: false, phase: .began).isEmpty)
        for _ in 0..<20 {
            XCTAssertTrue(scroll(&state, inside: false).isEmpty)
        }
        XCTAssertTrue(scroll(&state, inside: false, phase: .ended).isEmpty)
        XCTAssertTrue(scroll(&state, momentum: .began).isEmpty)
        XCTAssertTrue(scroll(&state, momentum: .changed).isEmpty)
        XCTAssertTrue(scroll(&state, momentum: .ended).isEmpty)
    }

    @objc func testContentSequenceCannotBecomeHeaderGesture() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        XCTAssertTrue(scroll(&state, inside: false, phase: .began).isEmpty)
        XCTAssertTrue(scroll(&state, inside: true).isEmpty)
        XCTAssertTrue(scroll(&state, phase: .ended).isEmpty)
        XCTAssertTrue(scroll(&state, momentum: .began).isEmpty)
        XCTAssertTrue(scroll(&state, momentum: .ended).isEmpty)
        let next = scroll(&state, phase: .began)
        XCTAssertEqual(next.first?.phase, .began)
        XCTAssertEqual(next.first?.translation, 120)
    }

    @objc func testHeaderSwipeStillReachesCloseThreshold() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        let begin = scroll(&state, y: -100, phase: .began)
        XCTAssertEqual(begin.first?.phase, .began)
        let change = scroll(&state, y: -120, inside: false)
        XCTAssertEqual(change.first?.translation, 220)
        XCTAssertEqual(change.first?.phase, .changed)
        let end = scroll(&state, y: -500, phase: .ended)
        XCTAssertEqual(end.first?.translation, 0)
        XCTAssertEqual(end.first?.phase, .ended)
    }

    @objc func testInertiaCannotFinishAnIncompleteCloseSwipe() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        _ = scroll(&state, y: -40, phase: .began)
        let end = scroll(&state, y: -500, phase: [], momentum: .began)
        XCTAssertEqual(end.count, 1)
        XCTAssertEqual(end.first?.translation, 0)
        XCTAssertEqual(end.first?.phase, .ended)
        XCTAssertTrue(scroll(&state, y: -500, phase: [], momentum: .changed).isEmpty)
        XCTAssertTrue(scroll(&state, phase: [], momentum: .ended).isEmpty)
    }

    @objc func testMouseWheelOwnershipLastsUntilQuietInterval() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        XCTAssertTrue(scroll(&state, y: -30, inside: false, phase: [], precise: false).isEmpty)
        XCTAssertTrue(scroll(&state, y: -30, inside: true, phase: [], precise: false).isEmpty)
        XCTAssertNil(state.finish())
        let next = scroll(&state, y: -2, phase: [], precise: false)
        XCTAssertEqual(next.first?.translation, 16)
        XCTAssertEqual(next.first?.phase, .began)
        XCTAssertEqual(state.finish()?.translation, 0)
        XCTAssertFalse(state.isTracking)
    }

    @objc func testCancellationResetsProgressAndOwnership() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        _ = scroll(&state, phase: .began)
        let cancel = scroll(&state, y: -500, phase: .cancelled)
        XCTAssertEqual(cancel.first?.translation, 0)
        XCTAssertEqual(cancel.first?.phase, .ended)
        XCTAssertFalse(state.isTracking)
        XCTAssertTrue(scroll(&state, inside: false, phase: .began).isEmpty)
    }

    @objc func testHorizontalMovementAndWrongDirectionDoNotClose() {
        var state = ScrollPanState(direction: .up, threshold: 4)
        XCTAssertTrue(scroll(&state, y: -30, x: 60, phase: .began).isEmpty)
        XCTAssertTrue(scroll(&state, y: 120).isEmpty)
        let next = scroll(&state, y: -20)
        XCTAssertEqual(next.first?.translation, 20)
    }

    @objc func testDownSwipeStillOpensWithoutInertialAccumulation() {
        var state = ScrollPanState(direction: .down, threshold: 4)
        _ = scroll(&state, y: 110, phase: .began)
        XCTAssertEqual(scroll(&state, y: 110).first?.translation, 220)
        XCTAssertEqual(scroll(&state, y: 500, phase: [], momentum: .began).first?.translation, 0)
        XCTAssertTrue(scroll(&state, y: 500, phase: [], momentum: .changed).isEmpty)
    }
}

@main
struct ScrollPanTestRunner {
    static func main() {
        let suite = ScrollPanTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount == 8, result.hasSucceeded else {
            exit(EXIT_FAILURE)
        }
    }
}
