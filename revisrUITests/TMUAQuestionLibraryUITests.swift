import XCTest

/// R4: the Questions tab as the unified library. Practice, Papers, Sources and Saved are reachable;
/// a question Revisr cannot mark opens at its page in the paper, is self-recorded, and then appears
/// under Saved; a source shows its credit. Uses the development bank; no screenshots are attached,
/// because these screens show third-party papers.
final class TMUAQuestionLibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLibrarySegmentsAndASelfMarkedQuestion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", "library", "--uitest-reset", "--tmua-scenario", "programme",
                               "--tmua-length", "starter", "--tmua-tab", "questions"]
        app.launch()
        let picker = app.descendants(matching: .any).matching(identifier: "questions.library").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 30))
        for segment in ["Practice", "Papers", "Sources", "Saved"] {
            XCTAssertTrue(app.buttons[segment].exists, "\(segment) segment")
        }

        // Practice: narrow to self-marked questions and open the first one. A menu picker in a list is
        // one button labelled with its title and current value ("Marking, Any marking").
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Marking")).firstMatch.tap()
        let selfMarked = app.buttons["Self-marked with solution"].firstMatch
        XCTAssertTrue(selfMarked.waitForExistence(timeout: 10))
        selfMarked.tap()
        let row = app.descendants(matching: .any).matching(identifier: "catalogue.question").firstMatch
        if !row.waitForExistence(timeout: 10) || !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        audit(app, screen: "practice-list")
        row.tap()

        let credit = app.descendants(matching: .any).matching(identifier: "catalogue.credit").firstMatch
        XCTAssertTrue(credit.waitForExistence(timeout: 10))
        // The header is one combined VoiceOver element: question, paper, credit, then details.
        XCTAssertTrue(credit.label.contains("Source: "), credit.label)
        XCTAssertTrue(app.buttons["catalogue.openSolution"].exists, "a self-marked question links its solution")
        audit(app, screen: "document-question")
        app.buttons["catalogue.openQuestion"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), "the paper opens at the question's page")
        app.buttons["Done"].tap()
        app.buttons["catalogue.next"].tap()
        XCTAssertTrue(credit.waitForExistence(timeout: 5), "moving to the next question keeps the screen")

        // R5: one tap records the student's own result; the footer says it is never evidence of mastery.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "never used as evidence of topic mastery")).firstMatch.waitForExistence(timeout: 10))
        let notChecked = app.buttons["selfmark.attempted"]
        if !notChecked.isHittable { app.swipeUp() }
        notChecked.tap()
        let chosen = expectation(for: NSPredicate(format: "value == %@", "Recorded"), evaluatedWith: notChecked)
        wait(for: [chosen], timeout: 10)
        // The history section is at the foot of a lazily loaded list.
        let history = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Your results for this question")).firstMatch
        for _ in 0..<4 where !history.exists { app.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Saved lists it; Sources credits providers. The segmented control is in a lazy list section.
        for _ in 0..<6 where !app.buttons["Saved"].isHittable { app.swipeDown() }
        app.buttons["Saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "catalogue.question").firstMatch
            .waitForExistence(timeout: 10), "the recorded question appears under Saved")
        app.buttons["Sources"].tap()
        let provider = app.descendants(matching: .any).matching(identifier: "sources.provider").firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        audit(app, screen: "sources")
        provider.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sources.credit").firstMatch
            .waitForExistence(timeout: 10))
    }

    /// The same policy as `TMUAAccessibilityAuditUITests`: element descriptions, hit regions and
    /// traits fail the test; other advisories are recorded in an attachment.
    private func audit(_ app: XCUIApplication, screen: String) {
        let enforced: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .trait]
        var lines: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "'\($0.identifier)' '\($0.label.prefix(60))'" } ?? "—"
                lines.append("\(screen) | \(issue.auditType.rawValue) | \(issue.compactDescription) | \(element)")
                if enforced.contains(issue.auditType) { XCTFail(lines.last ?? screen) }
                return true
            }
        } catch {
            XCTFail("\(screen): audit could not run: \(error)")
        }
        let attachment = XCTAttachment(string: lines.isEmpty ? "\(screen): no issues" : lines.joined(separator: "\n"))
        attachment.name = "audit-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
