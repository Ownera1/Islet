import XCTest
@testable import CodeIslandCore

final class MarkdownMathTests: XCTestCase {
    func testSplitsInlineAndDisplayMath() {
        XCTAssertEqual(MarkdownMath.segments("Energy $E = mc^2$, so\n$$\n\\frac{a_i}{b}\n$$ done"), [
            .text("Energy "), .inline("E = mc^2"), .text(", so\n"), .display("\\frac{a_i}{b}"), .text(" done"),
        ])
    }

    func testLeavesPricesCodeEscapesAndUnclosedMathAsText() {
        for text in ["costs $5 and $10", "run `echo $HOME $PATH`", "a \\$x\\$ b", "streaming $$x^2", "$ x$", "x$"] {
            XCTAssertEqual(MarkdownMath.segments(text), [.text(text)], text)
        }
    }
}
