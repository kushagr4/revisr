import XCTest

/// Drives the flexible TMUA journey through real XCUITest interactions. The
/// app runs with an isolated store and synthetic fixtures whose stems state
/// their own key ("Fixture answer: C"), so answers can be chosen deliberately.
@MainActor
struct TMUAJourney {
    let app: XCUIApplication
    let store: String
    let timeout: TimeInterval = 15

    static func launch(store: String, reset: Bool, extraArguments: [String] = []) -> TMUAJourney {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", store, "--uitest-fixture-bank"]
            + (reset ? ["--uitest-reset"] : []) + extraArguments
        app.launch()
        return TMUAJourney(app: app, store: store)
    }

    /// Terminates the process (no background transition) and relaunches on the same store.
    func relaunch(extraArguments: [String] = []) -> TMUAJourney {
        app.terminate()
        return Self.launch(store: store, reset: false, extraArguments: extraArguments)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for an element, scrolling down when it is in a lazily loaded
    /// list row that does not exist until it is near the screen.
    @discardableResult
    func wait(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = element(identifier)
        if !element.waitForExistence(timeout: 4) {
            for _ in 0..<10 where !element.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(identifier)", file: file, line: line)
        return element
    }

    func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = wait(identifier, file: file, line: line)
        if !Self.bottomBars.contains(identifier) { scrollIntoView(element) }
        element.tap()
    }

    /// Controls pinned to the bottom of a screen. Content scrolls beneath
    /// them, so a tap aimed at a covered element would land on the bar.
    static let bottomBars = ["onboarding.primary", "assessment.previous", "assessment.flag",
                             "assessment.next", "assessment.review"]

    private func visibleBottom() -> CGFloat {
        var bottom = app.frame.maxY
        for id in Self.bottomBars {
            let bar = element(id)
            if bar.exists, bar.isHittable { bottom = min(bottom, bar.frame.minY - 8) }
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.isHittable { bottom = min(bottom, tabBar.frame.minY - 8) }
        return bottom
    }

    /// Drags content up until the element is clear of any bottom bar, then
    /// lets momentum settle so the following tap is delivered as a tap.
    func scrollIntoView(_ element: XCUIElement) {
        var attempts = 0
        while attempts < 8 && (!element.isHittable || element.frame.maxY > visibleBottom()) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.5)
            attempts += 1
        }
    }

    func attachScreenshot(_ name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    // MARK: Onboarding

    /// Completes onboarding with real controls. Returns the selected exam
    /// date's "days to go" label.
    @discardableResult
    func completeOnboarding(length: String, restDay: String, testCase: XCTestCase) -> String {
        XCTAssertTrue(app.staticTexts["TMUA preparation built around you."].waitForExistence(timeout: timeout))
        testCase.attachScreenshot(app, "01-welcome")
        tap("onboarding.primary")

        // Exam date: move the graphical picker back one month from the default
        // suggestion (two months ahead) and choose the 15th.
        wait("onboarding.examDate")
        let before = element("onboarding.daysToGo").label
        let previous = app.buttons["DatePicker.PreviousMonth"]
        XCTAssertTrue(previous.waitForExistence(timeout: timeout), "graphical date picker month control")
        scrollIntoView(previous)
        previous.tap()
        let day = app.datePickers.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*\\b15\\b.*")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: timeout), "day 15 in the picker")
        scrollIntoView(day)
        day.tap()
        let after = element("onboarding.daysToGo").label
        XCTAssertNotEqual(before, after, "choosing a date updates the countdown")
        XCTAssertFalse(after.hasPrefix("0 "), after)
        testCase.attachScreenshot(app, "02-exam-date")
        tap("onboarding.primary")

        // Weekly time and weekdays.
        select("availability.chip.5 hours")
        let dayButton = wait("availability.day.\(restDay)")
        XCTAssertEqual(dayButton.value as? String, "Study day")
        scrollIntoView(dayButton)
        dayButton.tap()
        if dayButton.value as? String != "Rest day" {
            // A tap absorbed by scrolling momentum is retried once.
            Thread.sleep(forTimeInterval: 0.6)
            scrollIntoView(dayButton)
            dayButton.tap()
        }
        XCTAssertEqual(dayButton.value as? String, "Rest day")
        let summary = wait("availability.summary").label
        XCTAssertTrue(summary.contains("About 50 minutes on each study day"), summary)
        testCase.attachScreenshot(app, "03-availability")
        tap("onboarding.primary")

        // Diagnostic length.
        select("length.\(length)")
        testCase.attachScreenshot(app, "04-length")
        tap("onboarding.primary")
        wait("hub.start.R0.P1")
        return after
    }

    // MARK: Assessment

    var position: String { element("assessment.position").label }

    func stemKey() -> String? {
        let label = wait("question.stem").label
        guard let range = label.range(of: "Fixture answer: ") else { return nil }
        return String(label[range.upperBound...].prefix(1))
    }

    func wrongKey(for key: String) -> String { key == "A" ? "B" : "A" }

    enum Answer { case correct, wrong, skip }

    func answer(_ answer: Answer, file: StaticString = #filePath, line: UInt = #line) {
        guard let key = stemKey() else { return XCTFail("fixture stem without key", file: file, line: line) }
        let option: String
        switch answer {
        case .correct: option = "option.\(key)"
        case .wrong: option = "option.\(wrongKey(for: key))"
        case .skip: return
        }
        select(option, file: file, line: line)
    }

    /// Taps a selectable control and checks it became selected; a tap absorbed
    /// by scrolling momentum is retried once.
    func select(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(identifier, file: file, line: line)
        if !element(identifier).isSelected {
            Thread.sleep(forTimeInterval: 0.6)
            tap(identifier, file: file, line: line)
        }
        XCTAssertTrue(element(identifier).isSelected, "\(identifier) selected", file: file, line: line)
    }

    func selectedOption() -> String? {
        for id in ["A", "B", "C", "D", "E"] where element("option.\(id)").isSelected { return id }
        return nil
    }

    /// Answers from the current position to the end, then submits.
    func finishSection(_ answers: [Answer], expectAnswered: Int? = nil, expectFlagged: Int? = nil,
                       testCase: XCTestCase, screenshot: String? = nil) {
        for (offset, answer) in answers.enumerated() {
            self.answer(answer)
            if offset < answers.count - 1 { tap("assessment.next") }
        }
        tap("assessment.review")
        if let expectAnswered {
            XCTAssertEqual(wait("submit.answered").label.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .joined(), "\(expectAnswered)", "answered count on the submit sheet")
        }
        if let expectFlagged {
            XCTAssertTrue(wait("submit.flagged").label.hasSuffix("\(expectFlagged)") ||
                          (element("submit.flagged").value as? String) == "\(expectFlagged)",
                          element("submit.flagged").label)
        }
        if let screenshot { testCase.attachScreenshot(app, screenshot) }
        tap("submit.confirm")
    }

    func submittedLabel(round: Int = 0, paper: Int) -> String {
        wait("hub.submitted.R\(round).P\(paper)").label
    }
}

extension XCTestCase {
    func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A weekday that is neither today nor tomorrow, so the plan always has
    /// study days at the start of the window.
    var restWeekdayName: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        let restDate = calendar.date(byAdding: .day, value: 3, to: .now) ?? .now
        let weekday = calendar.component(.weekday, from: restDate)
        return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday - 1]
    }
}
