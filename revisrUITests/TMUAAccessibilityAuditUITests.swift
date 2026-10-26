import XCTest

/// Runs Xcode's automated accessibility audit (contrast, element
/// descriptions, hit regions, Dynamic Type, clipped text, traits) on each
/// main screen of the journey. Issues are collected into an attachment and
/// the test fails only on audit types listed in `enforced`.
@MainActor
final class TMUAAccessibilityAuditUITests: XCTestCase {
    private var issues: [String] = []

    /// Audit types that must be clean. Contrast and Dynamic Type findings are
    /// reviewed by hand (see docs/R1_END_TO_END_VALIDATION.md) because the
    /// audit also flags system controls and decorative symbols.
    private let enforced: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .trait]

    override func setUp() async throws {
        continueAfterFailure = true
    }

    func testAccessibilityAuditAcrossJourney() throws {
        let journey = TMUAJourney.launch(store: "a11y-audit", reset: true)
        audit(journey, "welcome")
        journey.tap("onboarding.primary")
        journey.wait("onboarding.examDate")
        audit(journey, "exam-date")
        journey.tap("onboarding.primary")
        journey.select("availability.chip.5 hours")
        audit(journey, "availability")
        journey.tap("onboarding.primary")
        journey.select("length.starter")
        audit(journey, "length")
        journey.tap("onboarding.primary")
        journey.wait("hub.start.R0.P1")
        audit(journey, "diagnostic-hub")

        journey.tap("hub.start.R0.P1")
        journey.answer(.correct)
        audit(journey, "question")
        journey.tap("assessment.overview")
        journey.wait("overview.cell.1")
        audit(journey, "overview")
        journey.tap("overview.done")
        journey.tap("assessment.pause")
        journey.wait("paused.title")
        audit(journey, "paused")
        journey.tap("paused.resume")
        journey.tap("assessment.next")
        journey.finishSection([.correct, .wrong, .correct, .skip], testCase: self)
        journey.tap("hub.start.R0.P2")
        journey.finishSection(Array(repeating: .correct, count: 5), testCase: self)
        journey.tap("hub.results")
        journey.wait("results.rawScore")
        audit(journey, "results")
        journey.tap("results.generatePlan")
        journey.wait("today.summary")
        audit(journey, "today")
        for tab in ["Plan", "Progress", "Topics", "Questions"] {
            journey.app.tabBars.buttons[tab].tap()
            Thread.sleep(forTimeInterval: 1)
            audit(journey, tab.lowercased())
        }
        journey.tap("settings.open")
        journey.wait("settings.done")
        audit(journey, "settings")

        let report = XCTAttachment(string: issues.isEmpty ? "No issues" : issues.joined(separator: "\n"))
        report.name = "accessibility-audit-issues"
        report.lifetime = .keepAlways
        add(report)
    }

    private func audit(_ journey: TMUAJourney, _ screen: String) {
        journey.attachScreenshot("a11y-\(screen)", to: self)
        do {
            try journey.app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label.prefix(60))'" } ?? "—"
                let line = "\(screen) | \(Self.name(issue.auditType)) | \(issue.compactDescription) | \(element)"
                self.issues.append(line)
                // Returning true marks the issue as handled; enforced types still fail below.
                if self.enforced.contains(issue.auditType) {
                    XCTFail(line)
                }
                return true
            }
        } catch {
            XCTFail("\(screen): audit could not run: \(error)")
        }
    }

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "description"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "other(\(type.rawValue))"
        }
    }
}
