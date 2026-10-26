import SwiftUI
import XCTest
@testable import revisr

/// Question typography: how the renderer breaks, scales and lays out mathematics.
@MainActor
final class MathTextLayoutTests: XCTestCase {
    private let longSum = "S_n = 2 + 4 + 10 + 28 + \\cdots + (3^{n-1} + 1) = \\frac{3^n - 1}{2} + n"
    private let proofLine = "(k + 1)^2 + (k + 1) + 41 = (k^2 + k + 41) + 2(k + 1)"

    func testShortExpressionsNeverBreak() {
        for expression in ["x > 0", "S_n > 1000", "mn = 360", "x^2 - 7x + 10 = 0", "h(x) = c\\,g(x)"] {
            XCTAssertEqual(MathWord.breakableChunks(MathMarkup.parse(expression)).count, 1, expression)
        }
    }

    func testLongExpressionsBreakOnlyAfterTopLevelOperators() {
        for expression in [longSum, proofLine] {
            let chunks = MathWord.breakableChunks(MathMarkup.parse(expression))
            XCTAssertGreaterThan(chunks.count, 1, expression)
            for chunk in chunks.dropLast() {
                guard case let .text(tail)? = chunk.last else { return XCTFail("chunk must end in text: \(chunk)") }
                let trimmed = tail.trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(MathWord.breakAfter.contains(trimmed.last ?? " "), "breaks after an operator: \(tail)")
                let flat = chunk.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
                XCTAssertEqual(flat.filter { $0 == "(" }.count, flat.filter { $0 == ")" }.count,
                               "never breaks inside brackets: \(flat)")
            }
            for chunk in chunks {
                XCTAssertGreaterThanOrEqual(MathWord.visibleLength(chunk), MathWord.minimumFragment)
            }
        }
    }

    func testModulusIsNotBroken() {
        let chunks = MathWord.breakableChunks(MathMarkup.parse("|f(x) - f(y)| + |g(x) - g(y)| \\le |x - y| + |x + y|"))
        for chunk in chunks {
            let flat = chunk.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
            XCTAssertEqual(flat.filter { $0 == "|" }.count % 2, 0, "never breaks inside |…|: \(flat)")
        }
    }

    func testDisplayedEquationTakesItsOwnLine() {
        let lines = MathMarkup.lines("Consider the equation\n\\[ \\frac{2x - 1}{x + 3} =\n \\frac{x + 2}{2x - 1} \\]\nwhere \\(x \\ne -3\\).")
        XCTAssertEqual(lines.count, 3)
        guard lines.count == 3, case let .display(nodes) = lines[1].content else { return XCTFail("missing display line") }
        XCTAssertEqual(nodes.filter { if case .fraction = $0 { true } else { false } }.count, 2)
        XCTAssertFalse(MathMarkup.spoken("\\[ \\frac{1}{2} \\]").contains("\\["))
    }

    func testBlankLineStartsParagraphAndNewlineStartsLine() {
        let lines = MathMarkup.lines("First line.\nSecond line.\n\nNew paragraph.")
        XCTAssertEqual(lines.map(\.startsParagraph), [false, false, true])
    }

    func testFunctionNamesAndTextAreUprightAndLettersAreVariables() {
        XCTAssertEqual(MathMarkup.parse("\\sin x"), [.roman("sin\u{2009}"), .text("x")])
        XCTAssertEqual(MathMarkup.parse("\\text{if } n"), [.roman("if "), .text(" n")])
        XCTAssertTrue(MathMarkup.isVariableLetter("x"))
        XCTAssertTrue(MathMarkup.isVariableLetter("θ"))
        XCTAssertFalse(MathMarkup.isVariableLetter("3"))
        XCTAssertFalse(MathMarkup.isVariableLetter("−"))
    }

    func testMetricsScaleWithTextSize() {
        let small = MathMetrics(size: 17, base: 17)
        let large = MathMetrics(size: 34, base: 34)
        XCTAssertEqual(large.superscriptRaise, small.superscriptRaise * 2, accuracy: 0.001)
        XCTAssertEqual(large.subscriptDrop, small.subscriptDrop * 2, accuracy: 0.001)
        XCTAssertEqual(large.axis, small.axis * 2, accuracy: 0.001)
        XCTAssertEqual(large.script.size / large.size, small.script.size / small.size, accuracy: 0.001)
        XCTAssertLessThan(small.script.size, small.size)
        XCTAssertGreaterThanOrEqual(small.rule, 1)
    }

    func testQuestionTextUsesReadingSizeNotHeadingSize() {
        XCTAssertEqual(MathTextRole.question.baseSize, 18)
        XCTAssertEqual(MathTextRole.option.baseSize, 17)
        XCTAssertLessThan(MathTextRole.solution.baseSize, MathTextRole.question.baseSize)
    }

    func testLongQuestionWrapsWithinWidthAndScalesWithDynamicType() {
        let stem = "A student attempts to prove that, for every positive integer \\(n\\), the number \\(n^2 + n + 41\\) is prime.\n(3) Then \\(\(proofLine)\\).\nThe sum is \\(\(longSum)\\)."
        let width: CGFloat = 350
        let regular = measure(MathText(stem, role: .question), width: width, size: .large)
        let accessible = measure(MathText(stem, role: .question), width: width, size: .accessibility3)
        XCTAssertLessThanOrEqual(regular.width, width + 0.5)
        XCTAssertLessThanOrEqual(accessible.width, width + 0.5)
        XCTAssertGreaterThan(accessible.height, regular.height * 1.6, "question text keeps scaling at accessibility sizes")
        // About 22 pt per line at 18 pt; the stem is roughly eight lines at 350 pt wide.
        XCTAssertLessThan(regular.height, 260, "18 pt reading text, not a heading style")
    }

    func testUnbreakableFormulaNeverWidensTheLayout() {
        let formula = "\\(\\frac{1}{1 \\cdot 2}\\frac{1}{2 \\cdot 3}\\frac{1}{3 \\cdot 4}\\frac{1}{4 \\cdot 5}\\frac{1}{5 \\cdot 6}\\frac{1}{6 \\cdot 7}\\frac{1}{7 \\cdot 8}\\frac{1}{8 \\cdot 9}\\)"
        XCTAssertLessThanOrEqual(measure(MathText(formula, role: .question), width: 300, size: .large).width, 300.5)
    }

    private func measure(_ view: some View, width: CGFloat, size: DynamicTypeSize) -> CGSize {
        let controller = UIHostingController(rootView: view.dynamicTypeSize(size).frame(width: width))
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
