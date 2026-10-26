import XCTest

/// End-to-end first-run journeys driven through the real UI on a clean,
/// isolated store with synthetic fixtures.
@MainActor
final class TMUAFirstRunJourneyUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// The full first-run journey: onboarding, Starter diagnostic with
    /// navigation, flagging, pause, termination and resume, both papers,
    /// the report, plan generation, completing a task, and relaunch.
    func testStarterFirstRunJourney() throws {
        var journey = TMUAJourney.launch(store: "starter-journey", reset: true)
        journey.completeOnboarding(length: "starter", restDay: restWeekdayName, testCase: self)

        journey.tap("hub.start.R0.P1")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 1 of 5")
        journey.answer(.correct)
        let first = try XCTUnwrap(journey.selectedOption())
        journey.tap("assessment.next")
        XCTAssertEqual(journey.position, "Question 2 of 5")
        journey.answer(.wrong)
        let second = try XCTUnwrap(journey.selectedOption())
        journey.tap("assessment.flag")
        journey.wait("assessment.flagged")
        journey.tap("assessment.previous")
        XCTAssertEqual(journey.position, "Question 1 of 5")
        XCTAssertEqual(journey.selectedOption(), first, "earlier selection persists")
        journey.tap("assessment.next")
        XCTAssertEqual(journey.selectedOption(), second)
        XCTAssertTrue(journey.element("assessment.flagged").exists)
        journey.attachScreenshot("05-question", to: self)

        journey.tap("assessment.pause")
        journey.wait("paused.title")
        journey.attachScreenshot("06-paused", to: self)
        journey.tap("paused.exit")
        XCTAssertEqual(journey.wait("hub.resume.R0.P1").label, "Resume at question 2")
        XCTAssertTrue(journey.wait("hub.progress.R0.P1").label.hasPrefix("2 of 5 answered"))

        journey = journey.relaunch()
        XCTAssertEqual(journey.wait("hub.resume.R0.P1").label, "Resume at question 2",
                       "resume position survives termination")
        journey.tap("hub.resume.R0.P1")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 2 of 5")
        XCTAssertEqual(journey.selectedOption(), second)
        journey.wait("assessment.flagged")
        journey.tap("assessment.previous")
        XCTAssertEqual(journey.selectedOption(), first)
        journey.tap("assessment.next")
        journey.tap("assessment.next")
        journey.finishSection([.correct, .skip, .correct], expectAnswered: 4, expectFlagged: 1,
                              testCase: self, screenshot: "07-submit-paper-1")
        XCTAssertEqual(journey.submittedLabel(paper: 1), "Submitted · 3 / 5 correct")

        journey.tap("hub.start.R0.P2")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 1 of 5")
        journey.finishSection(Array(repeating: .correct, count: 5), expectAnswered: 5, testCase: self)
        XCTAssertEqual(journey.submittedLabel(paper: 2), "Submitted · 5 / 5 correct")

        journey.tap("hub.results")
        XCTAssertEqual(journey.wait("results.rawScore").label, "8 correct out of 10")
        XCTAssertTrue(journey.element("results.score.P1").label.contains("3 / 5"), journey.element("results.score.P1").label)
        XCTAssertTrue(journey.element("results.score.P2").label.contains("5 / 5"))
        XCTAssertTrue(journey.element("results.confidence").label.contains("Starter"))
        journey.attachScreenshot("08-results", to: self)

        journey.tap("results.generatePlan")
        let summary = journey.wait("today.summary").label
        XCTAssertTrue(summary.hasPrefix("0 of "), summary)
        journey.attachScreenshot("09-today", to: self)
        try completeNextTask(journey)
        XCTAssertTrue(journey.wait("today.summary").label.hasPrefix("1 of "), journey.element("today.summary").label)

        journey.app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(journey.wait("plan.summary").label.hasSuffix("1 complete"), journey.element("plan.summary").label)
        journey.wait("plan.day.today")
        journey.attachScreenshot("10-plan", to: self)

        journey.app.tabBars.buttons["Progress"].tap()
        assertProgress(journey, completed: 1, attempts: 1, diagnostic: "8 / 10")
        journey.attachScreenshot("11-progress", to: self)

        journey = journey.relaunch()
        journey.wait("today.summary")
        XCTAssertTrue(journey.element("today.summary").label.hasPrefix("1 of "), "completed task survives relaunch")
        journey.app.tabBars.buttons["Progress"].tap()
        assertProgress(journey, completed: 1, attempts: 1, diagnostic: "8 / 10")
    }

    func testQuickJourney() throws { try runLength("quick", paperOne: 8, paperTwo: 7) }
    func testBalancedJourney() throws { try runLength("balanced", paperOne: 10, paperTwo: 10) }
    func testComprehensiveJourney() throws { try runLength("comprehensive", paperOne: 20, paperTwo: 20) }

    // MARK: Helpers

    /// Onboarding → both papers (with a mid-paper termination) → report →
    /// plan → one task → relaunch, for one length.
    private func runLength(_ length: String, paperOne: Int, paperTwo: Int) throws {
        var journey = TMUAJourney.launch(store: "\(length)-journey", reset: true)
        journey.completeOnboarding(length: length, restDay: restWeekdayName, testCase: self)
        XCTAssertTrue(journey.app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "Paper 1: \(paperOne), Paper 2: \(paperTwo)")).firstMatch.waitForExistence(timeout: 5))

        // Paper 1: alternate right and wrong, skip the last; terminate halfway.
        let pattern: [TMUAJourney.Answer] = (0..<paperOne).map { $0 == paperOne - 1 ? .skip : $0 % 2 == 0 ? .correct : .wrong }
        let half = paperOne / 2
        journey.tap("hub.start.R0.P1")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 1 of \(paperOne)")
        for answer in pattern.prefix(half) {
            journey.answer(answer)
            journey.tap("assessment.next")
        }
        journey = journey.relaunch()
        XCTAssertEqual(journey.wait("hub.resume.R0.P1").label, "Resume at question \(half + 1)")
        journey.tap("hub.resume.R0.P1")
        journey.finishSection(Array(pattern.dropFirst(half)), expectAnswered: paperOne - 1, testCase: self)
        let correctOne = pattern.filter { $0 == .correct }.count
        XCTAssertEqual(journey.submittedLabel(paper: 1), "Submitted · \(correctOne) / \(paperOne) correct")

        // Paper 2: first one wrong, the rest right.
        journey.tap("hub.start.R0.P2")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 1 of \(paperTwo)")
        journey.finishSection([.wrong] + Array(repeating: .correct, count: paperTwo - 1),
                              expectAnswered: paperTwo, testCase: self)
        XCTAssertEqual(journey.submittedLabel(paper: 2), "Submitted · \(paperTwo - 1) / \(paperTwo) correct")

        journey.tap("hub.results")
        let total = paperOne + paperTwo
        let correct = correctOne + paperTwo - 1
        XCTAssertEqual(journey.wait("results.rawScore").label, "\(correct) correct out of \(total)")
        XCTAssertTrue(journey.element("results.confidence").label.lowercased().contains(length),
                      journey.element("results.confidence").label)
        journey.attachScreenshot("\(length)-results", to: self)
        journey.tap("results.generatePlan")
        journey.wait("today.summary")
        try completeNextTask(journey)
        journey.app.tabBars.buttons["Progress"].tap()
        assertProgress(journey, completed: 1, attempts: 1, diagnostic: "\(correct) / \(total)")

        journey = journey.relaunch()
        journey.app.tabBars.buttons["Progress"].tap()
        assertProgress(journey, completed: 1, attempts: 1, diagnostic: "\(correct) / \(total)")
    }

    /// Opens Today's next task, answers it correctly and returns to Today.
    private func completeNextTask(_ journey: TMUAJourney) throws {
        journey.tap("today.next")
        let key = try XCTUnwrap(journey.stemKey(), "practice question shows a fixture stem")
        let stem = journey.element("question.stem").label
        journey.select("option.\(key)")
        journey.tap("practice.check")
        XCTAssertEqual(journey.wait("practice.result").label, "Correct")
        // Regression: completing the task changes Today's "next" task; the open
        // screen must keep showing the question that was just answered.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(journey.element("question.stem").label, stem, "the answered question stays on screen")
        XCTAssertTrue(journey.element("option.\(key)").isSelected, "the student's answer stays shown")
        journey.attachScreenshot("practice-checked", to: self)
        journey.app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func assertProgress(_ journey: TMUAJourney, completed: Int, attempts: Int, diagnostic: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        func text(_ element: XCUIElement) -> String {
            (element.label + " " + ((element.value as? String) ?? "")).trimmingCharacters(in: .whitespaces)
        }
        let tasks = journey.wait("progress.completedTasks")
        XCTAssertTrue(text(tasks).contains("\(completed) of "), text(tasks), file: file, line: line)
        let attemptsRow = journey.wait("progress.attempts")
        XCTAssertTrue(text(attemptsRow).hasSuffix(" \(attempts)"), text(attemptsRow), file: file, line: line)
        let diagnosticRow = journey.wait("progress.diagnostic")
        XCTAssertTrue(text(diagnosticRow).contains(diagnostic), text(diagnosticRow), file: file, line: line)
    }
}
