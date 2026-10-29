import XCTest

/// R5 student journeys through the real views and persistence: daily practice from Today (B), a
/// planned worksheet left and resumed across a relaunch (C), library filters, flags and Saved (D),
/// and a plan refresh after changing availability (E). Journey A, the fresh student, is
/// `TMUAFirstRunJourneyUITests.testStarterFirstRunJourney`. Synthetic bank questions; worksheet
/// questions come from the development library, so no screenshots of question screens are kept.
final class TMUAStudentJourneyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ store: String, scenario: String, tab: String = "today") -> TMUAJourney {
        TMUAJourney.launch(store: store, reset: true,
                           extraArguments: ["--tmua-scenario", scenario, "--tmua-length", "starter", "--tmua-tab", tab])
    }

    @MainActor
    private func completedToday(_ journey: TMUAJourney) -> Int {
        Int(journey.wait("today.summary").label.components(separatedBy: " of ").first ?? "") ?? -1
    }

    // MARK: B · Daily practice

    @MainActor
    func testDailyPracticeFromToday() throws {
        let journey = launch("journey-daily", scenario: "programme")
        let before = completedToday(journey)
        XCTAssertTrue(journey.wait("today.remaining").label.contains("minutes left"))
        journey.tap("today.next")
        let key = try XCTUnwrap(journey.stemKey(), "Today's first task is a question Revisr marks")
        journey.select("option.\(key)")
        journey.tap("practice.check")
        XCTAssertEqual(journey.wait("practice.result").label, "Correct")
        journey.tap("practice.done")
        XCTAssertEqual(completedToday(journey), before + 1, "Today counts the finished task")
        journey.app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(journey.wait("progress.attempts").label.contains("Question attempts"))
    }

    // MARK: C · Worksheet: record, leave, relaunch, resume, finish, review

    @MainActor
    func testWorksheetResumesAcrossRelaunchAndFinishesFromItsResults() throws {
        var journey = launch("journey-worksheet", scenario: "worksheet")
        openWorksheet(journey)
        // The header is one VoiceOver element: kind, size, sources, then the state.
        XCTAssertTrue(journey.wait("worksheet.state").label.contains("Not started"), journey.element("worksheet.state").label)
        audit(journey.app, screen: "worksheet")
        journey.tap("worksheet.continue")
        XCTAssertTrue(journey.wait("catalogue.credit").label.hasPrefix("Question 1 of "), journey.element("catalogue.credit").label)
        audit(journey.app, screen: "worksheet-question")
        journey.tap("selfmark.correct")
        journey.tap("worksheet.nextUnrecorded")
        XCTAssertTrue(journey.wait("catalogue.credit").label.hasPrefix("Question 2 of "))
        journey.tap("selfmark.incorrect")
        journey.app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(journey.wait("worksheet.state").label.contains("In progress · 2 of "), journey.element("worksheet.state").label)

        // Leave the app entirely; the worksheet resumes where the student stopped.
        journey = journey.relaunch(extraArguments: ["--tmua-tab", "today"])
        openWorksheet(journey)
        XCTAssertTrue(journey.wait("worksheet.state").label.contains("In progress · 2 of "), journey.element("worksheet.state").label)
        XCTAssertEqual(journey.wait("worksheet.continue").label, "Continue with question 3")
        journey.tap("worksheet.continue")
        XCTAssertTrue(journey.wait("catalogue.credit").label.hasPrefix("Question 3 of "))
        // The overview lists every question with its result.
        journey.tap("worksheet.overview")
        XCTAssertTrue(journey.wait("worksheet.question").label.contains("Correct"))
        journey.app.buttons["Done"].tap()
        // Record the rest except the last question, which stays unrecorded, then finish from the worksheet.
        for _ in 0..<10 {
            let position = journey.wait("catalogue.credit").label
            let numbers = position.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            guard numbers.count >= 2, numbers[0] < numbers[1] else { break }
            journey.tap("selfmark.attempted")
            guard journey.element("worksheet.nextUnrecorded").waitForExistence(timeout: 5) else { break }
            journey.tap("worksheet.nextUnrecorded")
        }
        journey.app.navigationBars.buttons.element(boundBy: 0).tap()
        journey.tap("worksheet.finish")
        // One question has no result, so finishing asks first; it stays unrecorded, never counted correct.
        let confirm = journey.app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
                                                               "Finish the worksheet", "worksheet.finish")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "finishing with a gap asks first")
        confirm.tap()
        let done = journey.app.staticTexts["worksheet.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(done.label.contains("Self-marked") && done.label.contains("1 not recorded"), done.label)
        XCTAssertTrue(journey.element("worksheet.state").label.contains("Completed with gaps"), journey.element("worksheet.state").label)
        XCTAssertTrue(journey.element("worksheet.state").label.contains("1 not recorded"), journey.element("worksheet.state").label)

        // Review mistakes: the incorrect question is under Saved.
        journey.app.tabBars.buttons["Questions"].tap()
        scrollToTop(journey)
        journey.app.buttons["Saved"].tap()
        journey.wait("saved.incorrect")
    }

    /// The segmented control is in a lazily loaded list section: bring it back on screen first.
    @MainActor
    private func scrollToTop(_ journey: TMUAJourney) {
        let picker = journey.element("questions.library")
        for _ in 0..<6 where !(picker.exists && picker.isHittable) { journey.app.swipeDown() }
    }

    @MainActor
    private func openWorksheet(_ journey: TMUAJourney) {
        let row = journey.app.descendants(matching: .any).matching(identifier: "task.row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Topic worksheet")).firstMatch
        if !row.waitForExistence(timeout: 10) { journey.app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 15), "today has a worksheet")
        journey.scrollIntoView(row)
        row.tap()
    }

    // MARK: D · Library: topic and strand filters, flag, Saved, filters kept

    @MainActor
    func testLibraryFiltersFlagAndSavedKeepTheirState() throws {
        let journey = launch("journey-library", scenario: "programme", tab: "questions")
        journey.wait("questions.library")
        let topic = journey.wait("filter.topic")
        topic.tap()
        journey.app.buttons["Algebra"].firstMatch.tap()
        XCTAssertEqual(journey.element("filter.topic").value as? String, "Algebra")
        journey.tap("filter.strand")
        let strand = journey.app.buttons.matching(NSPredicate(format: "label != %@ AND label != %@", "All strands", "Strand"))
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "polynomial")).firstMatch
        XCTAssertTrue(strand.waitForExistence(timeout: 5))
        let strandName = strand.label
        strand.tap()
        XCTAssertEqual(journey.element("filter.strand").value as? String, strandName)
        audit(journey.app, screen: "practice-filtered")

        let row = journey.wait("catalogue.question")
        journey.scrollIntoView(row)
        row.tap()
        let flag = journey.wait("practice.flag")
        journey.scrollIntoView(flag)
        flag.tap()
        XCTAssertEqual(flag.value as? String, "1")
        journey.app.navigationBars.buttons.element(boundBy: 0).tap()

        scrollToTop(journey)
        journey.app.buttons["Saved"].tap()
        journey.wait("saved.flagged")
        scrollToTop(journey)
        journey.app.buttons["Practice"].tap()
        XCTAssertEqual(journey.wait("filter.topic").value as? String, "Algebra", "filters survive switching views")
        XCTAssertEqual(journey.element("filter.strand").value as? String, strandName)
    }

    // MARK: E · Refresh after changing availability

    @MainActor
    func testRefreshAfterChangingAvailabilityKeepsCompletedWork() throws {
        let journey = launch("journey-refresh", scenario: "programme")
        journey.tap("today.next")
        let key = try XCTUnwrap(journey.stemKey())
        journey.select("option.\(key)")
        journey.tap("practice.check")
        journey.tap("practice.done")
        let completed = completedToday(journey)
        journey.app.tabBars.buttons["Plan"].tap()
        let planBefore = journey.wait("plan.summary").label

        journey.tap("settings.open")
        journey.app.buttons["Change preparation details"].tap()
        let saturday = journey.wait("availability.day.Saturday")
        let wasStudy = saturday.value as? String == "Study day"
        journey.scrollIntoView(saturday)
        saturday.tap()
        XCTAssertNotEqual(saturday.value as? String == "Study day", wasStudy, "Saturday changed")
        journey.app.buttons["Save"].tap()
        let alert = journey.app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.label.contains("kept") || alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "kept")).firstMatch.exists,
                      "the refresh says completed work was kept")
        alert.buttons["OK"].tap()
        journey.tap("settings.done")

        let planAfter = journey.wait("plan.summary").label
        XCTAssertEqual(planAfter.components(separatedBy: " · ").last, planBefore.components(separatedBy: " · ").last,
                       "the number of completed tasks is unchanged: \(planBefore) → \(planAfter)")
        journey.app.tabBars.buttons["Today"].tap()
        XCTAssertEqual(completedToday(journey), completed, "today's finished task is still finished")
    }

    /// Same audit policy as the other suites: element descriptions, hit regions and traits fail the
    /// test; other advisories are recorded.
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
