import XCTest

/// Opens each synthetic layout specimen (`--uitest-typography-bank`) in the real diagnostic
/// question screen, at the default text size and at a large accessibility size, and records
/// a screenshot plus the measured layout of the stem and the first option.
final class TMUAQuestionTypographyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private static let sizes: [(name: String, arguments: [String])] = [
        ("default", []),
        ("ax3", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
    ]

    @MainActor
    func testQuestionLayoutAcrossSpecimens() {
        var lines: [String] = []
        for size in Self.sizes {
            for paper in 1...2 {
                for question in 1...5 {
                    let app = XCUIApplication()
                    app.launchArguments = ["--uitest-store", "typography", "--uitest-reset", "--uitest-typography-bank",
                                           "--tmua-scenario", "layout", "--tmua-length", "starter",
                                           "--tmua-paper", "\(paper)", "--tmua-question", "\(question)",
                                           "--tmua-open", "session"] + size.arguments
                    app.launch()
                    let stem = app.descendants(matching: .any).matching(identifier: "question.stem").firstMatch
                    guard stem.waitForExistence(timeout: 20) else {
                        XCTFail("No question stem for \(size.name) P\(paper) Q\(question)")
                        continue
                    }
                    let window = app.windows.firstMatch.frame
                    let optionA = app.descendants(matching: .any).matching(identifier: "option.A").firstMatch
                    let name = "\(size.name)-P\(paper)-Q\(question)"
                    let attachment = XCTAttachment(screenshot: app.screenshot())
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    let line = String(format: "TYPOGRAPHY %@ stemHeight=%.0f stemWidth=%.0f firstOptionTop=%.0f window=%.0fx%.0f",
                                      name, stem.frame.height, stem.frame.width,
                                      optionA.exists ? optionA.frame.minY : -1, window.width, window.height)
                    lines.append(line)
                    print(line)
                    XCTAssertLessThanOrEqual(stem.frame.maxX, window.maxX + 1, "\(name): stem runs off the screen")
                    XCTAssertLessThanOrEqual(optionA.frame.maxX, window.maxX + 1, "\(name): option runs off the screen")
                    app.terminate()
                }
            }
        }
        let summary = XCTAttachment(string: lines.joined(separator: "\n"))
        summary.name = "typography-measurements"
        summary.lifetime = .keepAlways
        add(summary)
    }

    /// An official past-paper question from the bundled library: shown as printed, answered with
    /// the letter grid, marked, and linked to its official worked solution. Uses the real
    /// development bank (no fixture flag); skipped when the build has no study copies.
    @MainActor
    func testOfficialPaperQuestionPresentation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", "official", "--uitest-reset", "--tmua-scenario", "programme",
                               "--tmua-length", "starter", "--tmua-tab", "questions", "--tmua-open", "practice",
                               "--tmua-item", "tmua-2019-p1-q11"]
        app.launch()
        let stem = app.descendants(matching: .any).matching(identifier: "question.stem").firstMatch
        guard stem.waitForExistence(timeout: 30) else {
            throw XCTSkip("The official question is not in this build's bank")
        }
        XCTAssertEqual(stem.label, "Question shown as printed in the official paper")
        XCTAssertLessThanOrEqual(stem.frame.maxX, app.windows.firstMatch.frame.maxX + 1)
        let source = app.descendants(matching: .any).matching(identifier: "question.source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("UAT-UK"), source.label)
        attach(app, "official-question")
        let letter = app.buttons["option.B"]
        XCTAssertTrue(letter.waitForExistence(timeout: 5))
        letter.tap()
        let check = app.buttons["practice.check"]
        if !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "practice.result").firstMatch.waitForExistence(timeout: 10))
        let official = app.buttons["solution.official"]
        if !official.exists { app.swipeUp() }
        XCTAssertTrue(official.waitForExistence(timeout: 5), "official worked solution is linked")
        attach(app, "official-question-marked")
        if !stem.isHittable { app.swipeDown() }
        stem.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), "tapping the question opens the zoom view")
        attach(app, "official-question-zoom")
        app.buttons["Done"].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
