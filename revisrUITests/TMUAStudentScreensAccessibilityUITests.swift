import XCTest

/// R5: accessibility of the new and changed student screens (Practice filters, Today, a worksheet,
/// a worksheet question, Saved) at the default and the largest text size. Element descriptions,
/// hit regions and traits fail the test; Dynamic Type and clipped-text advisories are counted and
/// attached. Filter screenshots are kept for visual inspection; they show filter controls and
/// question references only, never a question page.
final class TMUAStudentScreensAccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testStudentScreensAtDefaultText() throws { try runScreens(size: nil, name: "default") }

    @MainActor
    func testStudentScreensAtLargestText() throws {
        try runScreens(size: "UICTContentSizeCategoryAccessibilityXXXL", name: "ax5")
    }

    @MainActor
    private func runScreens(size: String?, name: String) throws {
        let journey = TMUAJourney.launch(store: "ax-r5-\(name)", reset: true, extraArguments: [
            "--tmua-scenario", "worksheet", "--tmua-length", "starter", "--tmua-tab", "questions"]
            + (size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []))
        let app = journey.app
        journey.wait("questions.library")

        // Practice filters: every filter names itself and its value; the marking value is readable.
        for id in ["filter.topic", "filter.marking", "filter.source", "filter.difficulty", "filter.status"] {
            let filter = reveal(journey, id)
            XCTAssertTrue(filter.exists, id)
            XCTAssertFalse((filter.value as? String ?? "").isEmpty, "\(id) reads its value")
        }
        let marking = reveal(journey, "filter.marking")
        marking.tap()
        app.buttons["Self-marked with solution"].firstMatch.tap()
        let chosen = reveal(journey, "filter.marking")
        XCTAssertEqual(chosen.value as? String, "Self-marked with solution")
        XCTAssertTrue(chosen.isHittable)
        shot(app, "filters-\(name)")
        audit(app, screen: "practice-\(name)")

        // Saved.
        for _ in 0..<6 where !app.buttons["Saved"].isHittable { app.swipeDown() }
        app.buttons["Saved"].tap()
        audit(app, screen: "saved-\(name)")

        // Today and the worksheet.
        app.tabBars.buttons["Today"].tap()
        journey.wait("today.summary")
        audit(app, screen: "today-\(name)")
        let row = app.descendants(matching: .any).matching(identifier: "task.row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Topic worksheet")).firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let start = journey.wait("worksheet.continue")
        journey.scrollIntoView(start)
        XCTAssertTrue(start.isHittable, "the worksheet can be started at this text size")
        audit(app, screen: "worksheet-\(name)")
        start.tap()
        journey.wait("catalogue.credit")
        let correct = app.buttons["selfmark.correct"]
        for _ in 0..<6 where !(correct.exists && correct.isHittable) { app.swipeUp() }
        XCTAssertTrue(correct.isHittable, "self-marking is reachable at this text size")
        correct.tap()
        audit(app, screen: "worksheet-question-\(name)")
    }

    /// Brings a lazily loaded list row on screen: down the list first, then back up.
    @MainActor
    private func reveal(_ journey: TMUAJourney, _ id: String) -> XCUIElement {
        let element = journey.element(id)
        for _ in 0..<8 where !(element.exists && element.isHittable) { journey.app.swipeUp() }
        for _ in 0..<10 where !(element.exists && element.isHittable) { journey.app.swipeDown() }
        return element
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
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
        print("A11Y \(screen) issues=\(lines.count)")
        for line in lines { print("A11Y-ISSUE \(line)") }
        let attachment = XCTAttachment(string: lines.isEmpty ? "\(screen): no issues" : lines.joined(separator: "\n"))
        attachment.name = "audit-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
