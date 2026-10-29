import XCTest

/// R3: the journey exactly as a public build shows it today, with the bundled bank judged by
/// the public gate (`--tmua-public-content`) and no question approved. A new student must be
/// able to finish setup, see an honest reason the diagnostic is unavailable, and still reach
/// the external library with its credits and publisher links.
@MainActor
final class TMUAPublicContentUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPublicBuildWithoutApprovedQuestionsStaysHonestAndUseful() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", "r3-public-content", "--uitest-reset", "--tmua-public-content"]
        app.launch()
        let journey = TMUAJourney(app: app, store: "r3-public-content")

        XCTAssertTrue(app.staticTexts["TMUA preparation built around you."].waitForExistence(timeout: journey.timeout))
        journey.tap("onboarding.primary")
        journey.wait("onboarding.examDate")
        journey.tap("onboarding.primary")
        journey.select("availability.chip.5 hours")
        journey.tap("onboarding.primary")

        // Every length is unavailable, with the reason on the card, and setup can still finish.
        journey.wait("length.unavailableNotice")
        XCTAssertTrue(textExists("independent review", in: app), "the reason is shown once above the cards")
        for length in ["starter", "quick", "balanced", "comprehensive"] {
            let card = app.buttons.matching(identifier: "length.\(length)").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: journey.timeout), length)
            XCTAssertFalse(card.isEnabled, "\(length) cannot be chosen without approved questions")
        }
        let primary = journey.wait("onboarding.primary")
        XCTAssertTrue(primary.isEnabled, "the student is not held on a step with no enabled choice")
        XCTAssertEqual(primary.label, "Save and browse papers")
        journey.attachScreenshot("r3-public-length", to: self)
        primary.tap()

        // The hub explains the gap and offers the library; nothing can be started.
        journey.wait("hub.unavailable")
        XCTAssertTrue(textExists("independent review", in: app), "the hub gives the same reason")
        XCTAssertFalse(journey.element("hub.start.R0.P1").exists, "no diagnostic without approved questions")
        XCTAssertFalse(app.buttons["Choose a different length"].exists, "no pointless length picker")
        journey.attachScreenshot("r3-public-hub", to: self)
        audit(app, screen: "public-hub")
        journey.tap("hub.library")

        // Sources are credited and open on the publisher's site; nothing is reproduced.
        let source = journey.wait("library.source")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "Revisr does not reproduce them")).firstMatch.waitForExistence(timeout: journey.timeout))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "personal study copy")).firstMatch.exists, "no study copies in a public build")
        journey.attachScreenshot("r3-public-library", to: self)
        audit(app, screen: "public-library")
        source.tap()
        let credit = journey.wait("library.credit")
        XCTAssertTrue(credit.label.contains("Source: "), credit.label)
        XCTAssertTrue(journey.wait("library.providerLink").isHittable, "a publisher link is offered")
        XCTAssertFalse(journey.element("library.openPaper").exists, "no bundled paper in a public build")
        journey.attachScreenshot("r3-public-source", to: self)
        audit(app, screen: "public-source")

        // A self-recorded study session can be saved and is labelled as self-marked.
        journey.tap("library.recordPaper")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "not used as evidence of topic mastery")).firstMatch.waitForExistence(timeout: journey.timeout))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@",
            "last whole-paper result")).firstMatch.waitForExistence(timeout: journey.timeout))
        journey.attachScreenshot("r3-public-recorded", to: self)
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

    /// A `Label`'s identifier can resolve to its icon, so text is matched on any element.
    private func textExists(_ text: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            .waitForExistence(timeout: 10)
    }
}
