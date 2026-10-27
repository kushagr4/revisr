import XCTest

/// Xcode's accessibility audit on the diagnostic question screen alone, for every synthetic
/// layout specimen (`--uitest-typography-bank`): Dynamic Type support and clipped text, which the
/// journey audit records only as advisories.
///
/// - The progress header is capped at accessibility size 1 on purpose, so the question keeps the
///   screen at the largest sizes; its two elements may report partial Dynamic Type support.
/// - Before R2 the renderer drew every word at a bare point size and the audit flagged 1,120
///   elements here. Fonts now come from `UIFontMetrics`, and no word of prose may be flagged.
/// - A few formula fragments (fraction parts, unbreakable formulas) and nodes the audit cannot
///   name are still reported, although they resize with the text size (checked live and by
///   `MathTextLayoutTests`). They are held to a budget so any regression shows.
final class TMUAQuestionAccessibilityAuditUITests: XCTestCase {
    private static let intentionallyCapped: Set<String> = ["assessment.position", "assessment.progress"]
    /// Measured on 27 October 2026 across the ten specimens: 5 named formula fragments (3 unbreakable
    /// formulas, a full stop and a space) in light and dark mode, and 17 to 19 nodes the audit
    /// cannot name, which varies between runs.
    private static let formulaFragmentBudget = 6
    private static let unnamedNodeBudget = 25

    @MainActor
    func testQuestionScreenSupportsDynamicType() throws {
        var lines: [String] = []
        var unexpected = 0
        var unnamed = 0
        for paper in 1...2 {
            for question in 1...5 {
                let app = XCUIApplication()
                app.launchArguments = ["--uitest-store", "a11y-question", "--uitest-reset", "--uitest-typography-bank",
                                       "--tmua-scenario", "layout", "--tmua-length", "starter",
                                       "--tmua-paper", "\(paper)", "--tmua-question", "\(question)",
                                       "--tmua-open", "session"]
                app.launch()
                let stem = app.descendants(matching: .any).matching(identifier: "question.stem").firstMatch
                guard stem.waitForExistence(timeout: 20) else {
                    XCTFail("No question stem for P\(paper) Q\(question)")
                    continue
                }
                var issues: [String] = []
                var prose: [String] = []
                try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
                    let identifier = issue.element?.identifier ?? ""
                    let label = issue.element.map { String($0.label.prefix(40)) } ?? "—"
                    let kind = issue.auditType == .dynamicType ? "dynamicType" : "textClipped"
                    let allowed = issue.auditType == .dynamicType && Self.intentionallyCapped.contains(identifier)
                    let frame = issue.element.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "-"
                    issues.append("\(kind) \(allowed ? "allowed" : "UNEXPECTED") [\(identifier)] '\(label)' at \(frame): \(issue.detailedDescription)")
                    if !allowed && issue.element == nil {
                        unnamed += 1
                    } else if !allowed {
                        unexpected += 1
                        if label.range(of: "[A-Za-z]{3,}", options: .regularExpression) != nil { prose.append(label) }
                    }
                    return true
                }
                let line = "A11Y P\(paper)-Q\(question): \(issues.count) issue(s)"
                    + (issues.isEmpty ? "" : "\n  " + issues.joined(separator: "\n  "))
                lines.append(line)
                print(line)
                XCTAssertTrue(prose.isEmpty, "P\(paper) Q\(question): prose without Dynamic Type support: \(prose)")
                app.terminate()
            }
        }
        let report = XCTAttachment(string: lines.joined(separator: "\n"))
        report.name = "question-dynamic-type-audit"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertLessThanOrEqual(unexpected, Self.formulaFragmentBudget,
                                 "more Dynamic Type or clipping issues on the question screen than the known fragments")
        XCTAssertLessThanOrEqual(unnamed, Self.unnamedNodeBudget, "more unnamed nodes than measured")
        print("A11Y named fragments \(unexpected) (budget \(Self.formulaFragmentBudget)), unnamed \(unnamed) (budget \(Self.unnamedNodeBudget))")
    }

    /// On the first question "Previous" is disabled: it must keep the enabled button's shape and
    /// size (so it stays recognisable and the bar does not jump) and report itself as not enabled.
    @MainActor
    func testDisabledPreviousButtonStaysRecognisable() {
        var frames: [CGRect] = []
        for question in 1...2 {
            let app = XCUIApplication()
            // The fixture bank: question N is position N (the typography bank maps N to a specimen).
            app.launchArguments = ["--uitest-store", "a11y-question", "--uitest-reset", "--uitest-fixture-bank",
                                   "--tmua-scenario", "layout", "--tmua-length", "starter",
                                   "--tmua-paper", "1", "--tmua-question", "\(question)", "--tmua-open", "session"]
            app.launch()
            let previous = app.buttons["assessment.previous"]
            XCTAssertTrue(previous.waitForExistence(timeout: 20))
            XCTAssertEqual(previous.isEnabled, question > 1, "question \(question)")
            XCTAssertEqual(previous.label, "Previous question")
            frames.append(previous.frame)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "previous-q\(question)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
        XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 1, "same width enabled and disabled")
        XCTAssertEqual(frames[0].height, frames[1].height, accuracy: 1, "same height enabled and disabled")
        print("PREVIOUS disabled \(frames[0]) enabled \(frames[1])")
    }
}
