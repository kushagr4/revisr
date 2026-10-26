import XCTest

/// App lifecycle, timer, duplicate-submission, expansion and large-text
/// checks driven through the real UI.
@MainActor
final class TMUALifecycleAndExpansionUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testBackgroundingPausesClockAndTerminationKeepsAnswers() throws {
        var journey = TMUAJourney.launch(store: "lifecycle", reset: true)
        journey.completeOnboarding(length: "quick", restDay: restWeekdayName, testCase: self)
        journey.tap("hub.start.R0.P1")
        journey.answer(.correct)
        let chosen = try XCTUnwrap(journey.selectedOption())

        // Leaving the app pauses the section; returning asks to resume.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        journey.app.activate()
        journey.wait("paused.title")
        journey.attachScreenshot("paused-after-background", to: self)
        journey.tap("paused.resume")
        XCTAssertEqual(journey.selectedOption(), chosen, "answer kept across background and resume")

        // An explicit pause stops the clock: across a 20-second pause the
        // timer may advance only by the running time around it.
        let wallStart = Date()
        let before = try seconds(journey.wait("assessment.timer"))
        journey.tap("assessment.pause")
        journey.wait("paused.title")
        Thread.sleep(forTimeInterval: 20)
        journey.tap("paused.resume")
        let after = try seconds(journey.wait("assessment.timer"))
        let wall = Date().timeIntervalSince(wallStart)
        XCTAssertLessThanOrEqual(Double(after - before), wall - 20 + 2,
            "paused time must not be counted (timer \(before)s → \(after)s over \(Int(wall))s)")

        // Terminate while the clock runs: answers and position survive.
        journey.tap("assessment.next")
        journey.answer(.wrong)
        let second = try XCTUnwrap(journey.selectedOption())
        journey = journey.relaunch()
        XCTAssertEqual(journey.wait("hub.resume.R0.P1").label, "Resume at question 2")
        journey.tap("hub.resume.R0.P1")
        XCTAssertEqual(journey.selectedOption(), second)
        journey.tap("assessment.previous")
        XCTAssertEqual(journey.selectedOption(), chosen)

        // A double tap on the confirmation submits once and shows no error.
        journey.tap("assessment.next")
        for answer in Array(repeating: TMUAJourney.Answer.correct, count: 6) {
            journey.tap("assessment.next")
            journey.answer(answer)
        }
        journey.tap("assessment.review")
        journey.wait("submit.confirm").doubleTap()
        XCTAssertEqual(journey.submittedLabel(paper: 1), "Submitted · 7 / 8 correct")
        XCTAssertEqual(journey.app.alerts.count, 0, "no error after a repeated submit tap")
    }

    func testExpansionFromStarterKeepsEarlierAnswersAndScores() throws {
        let journey = TMUAJourney.launch(store: "expansion", reset: true)
        journey.completeOnboarding(length: "starter", restDay: restWeekdayName, testCase: self)
        journey.tap("hub.start.R0.P1")
        journey.finishSection([.correct, .wrong, .correct, .wrong, .skip], testCase: self)
        journey.tap("hub.start.R0.P2")
        journey.finishSection(Array(repeating: .correct, count: 5), testCase: self)
        journey.tap("hub.results")
        journey.tap("results.generatePlan")
        journey.wait("today.summary")

        journey.tap("settings.open")
        journey.tap("settings.diagnostic")
        journey.tap("hub.improve")
        journey.tap("expansion.quick")
        journey.attachScreenshot("expansion-choice", to: self)
        journey.tap("expansion.confirm")
        journey.tap("hub.start.R1.P1")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 1 of 3")
        journey.finishSection(Array(repeating: .correct, count: 3), testCase: self)
        journey.tap("hub.start.R1.P2")
        XCTAssertEqual(journey.wait("assessment.position").label, "Question 1 of 2")
        journey.finishSection([.wrong, .correct], testCase: self)

        XCTAssertEqual(journey.submittedLabel(round: 0, paper: 1), "Submitted · 2 / 5 correct", "earlier round unchanged")
        XCTAssertEqual(journey.submittedLabel(round: 0, paper: 2), "Submitted · 5 / 5 correct")
        XCTAssertEqual(journey.submittedLabel(round: 1, paper: 1), "Submitted · 3 / 3 correct")
        XCTAssertEqual(journey.submittedLabel(round: 1, paper: 2), "Submitted · 1 / 2 correct")
        journey.tap("hub.results")
        XCTAssertEqual(journey.wait("results.rawScore").label, "11 correct out of 15")
        XCTAssertTrue(journey.element("results.confidence").label.contains("Quick"))
        journey.attachScreenshot("expanded-results", to: self)
    }

    func testLargestAccessibilityTextKeepsJourneyOperable() throws {
        let journey = TMUAJourney.launch(store: "ax-text", reset: true, extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        journey.completeOnboarding(length: "starter", restDay: restWeekdayName, testCase: self)
        journey.tap("hub.start.R0.P1")
        journey.answer(.correct)
        XCTAssertTrue(journey.element("assessment.next").isHittable)
        XCTAssertTrue(journey.element("assessment.flag").isHittable)
        journey.attachScreenshot("ax-question", to: self)
        journey.tap("assessment.overview")
        journey.wait("overview.cell.1")
        journey.attachScreenshot("ax-overview", to: self)
        journey.tap("overview.done")
        journey.tap("assessment.next")
        journey.finishSection([.correct, .correct, .correct, .correct], testCase: self, screenshot: "ax-submit")
        XCTAssertEqual(journey.submittedLabel(paper: 1), "Submitted · 5 / 5 correct")
    }

    private func seconds(_ timer: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(timer.value as? String, "timer value")
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
