import XCTest
@testable import revisr

final class ProgressAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    func testThisWeekUsesMondayToExclusiveNextMonday() {
        let date = makeDate(2026, 8, 19, hour: 14)
        let interval = ProgressRange.thisWeek.interval(endingOn: date, calendar: calendar)

        XCTAssertEqual(interval.start, makeDate(2026, 8, 17))
        XCTAssertEqual(interval.end, makeDate(2026, 8, 24))
    }

    func testLastThirtyDaysIncludesTodayAndTwentyNinePriorCalendarDays() {
        let interval = ProgressRange.lastThirtyDays.interval(
            endingOn: makeDate(2026, 8, 15, hour: 20),
            calendar: calendar
        )

        XCTAssertEqual(interval.start, makeDate(2026, 7, 17))
        XCTAssertEqual(interval.end, makeDate(2026, 8, 16))
    }

    func testRangeTotalsFilterDatesAndActualComesOnlyFromSessions() {
        let interval = DateInterval(start: makeDate(2026, 8, 10), end: makeDate(2026, 8, 17))
        let insideSession = session(date: makeDate(2026, 8, 12), minutes: 75, snapshot: "TMUA")
        let outsideSession = session(date: makeDate(2026, 8, 9), minutes: 500, snapshot: "TMUA")
        let block = PlannedStudyBlock(day: makeDate(2026, 8, 12), duration: 90 * 60, activity: .revision)

        XCTAssertEqual(StudyAnalytics.actualDuration(in: interval, sessions: [insideSession, outsideSession]), 75 * 60)
        XCTAssertEqual(StudyAnalytics.plannedDuration(in: interval, blocks: [block]), 90 * 60)
        XCTAssertEqual(StudyAnalytics.completionFraction(planned: 60, actual: 90), 1)
    }

    func testAllocationUsesSessionDurationsAndSettingsTargets() throws {
        let settings = AppSettings(tmuaTarget: 0.50, furtherMathematicsTarget: 0.30, mathematicsTarget: 0.20)
        let sessions = [
            session(date: .now, minutes: 60, snapshot: "TMUA"),
            session(date: .now, minutes: 30, snapshot: "Further Mathematics"),
            session(date: .now, minutes: 10, snapshot: "Mathematics")
        ]

        let allocations = ProgressAnalytics.allocations(sessions: sessions, settings: settings)
        XCTAssertEqual(try XCTUnwrap(allocations.first(where: { $0.category == .tmua })?.fraction), 0.6, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(allocations.first(where: { $0.category == .furtherMathematics })?.fraction), 0.3, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(allocations.first(where: { $0.category == .mathematics })?.targetFraction), 0.2, accuracy: 0.000_001)
    }

    func testAllocationFallsBackToHistoricalSubjectSnapshot() {
        let historical = session(date: .now, minutes: 45, snapshot: "Further Mathematics")
        historical.subject = nil

        let allocations = ProgressAnalytics.allocations(sessions: [historical], settings: nil)

        XCTAssertEqual(allocations.first(where: { $0.category == .furtherMathematics })?.duration, 45 * 60)
        XCTAssertEqual(allocations.first(where: { $0.category == .furtherMathematics })?.fraction, 1)
    }

    func testTMUAPrefersScaledWhenAtLeastTwoAndNeverMixesUnits() {
        let results = [
            result(date: makeDate(2026, 8, 1), label: "Paper 1", raw: 12, maximum: 20, scaled: 6.2, subject: "TMUA"),
            result(date: makeDate(2026, 8, 2), label: "Paper 2", raw: 14, maximum: 20, scaled: 6.8, subject: "TMUA"),
            result(date: makeDate(2026, 8, 3), label: "Paper 1", raw: 16, maximum: 20, scaled: nil, subject: "TMUA")
        ]

        XCTAssertEqual(ProgressAnalytics.tmuaMetric(for: results), .scaled)
        let points = ProgressAnalytics.tmuaPoints(from: results, metric: .scaled)
        XCTAssertEqual(points.map(\.value), [6.2, 6.8])
    }

    func testTMUAUsesPercentageWhenScaledHistoryIsInsufficient() {
        let results = [
            result(date: makeDate(2026, 8, 1), label: "Paper 1", raw: 10, maximum: 20, scaled: 6.0, subject: "TMUA"),
            result(date: makeDate(2026, 8, 2), label: "Paper 2", raw: 15, maximum: 20, scaled: nil, subject: "TMUA")
        ]

        XCTAssertEqual(ProgressAnalytics.tmuaMetric(for: results), .percentage)
        XCTAssertEqual(ProgressAnalytics.tmuaPoints(from: results, metric: .percentage).map(\.value), [50, 75])
    }

    func testScaledOnlySingleResultRemainsVisible() {
        let result = result(date: .now, label: "Paper 1", raw: nil, maximum: nil, scaled: 7.1, subject: "TMUA")

        XCTAssertEqual(ProgressAnalytics.tmuaMetric(for: [result]), .scaled)
        XCTAssertEqual(ProgressAnalytics.tmuaPoints(from: [result], metric: .scaled).first?.value, 7.1)
    }

    func testPaperAveragesStayWithinChosenMetric() {
        let points = [
            ComparableResultPoint(id: UUID(), date: makeDate(2026, 8, 1), label: "Paper 1", subjectName: "TMUA", value: 6),
            ComparableResultPoint(id: UUID(), date: makeDate(2026, 8, 2), label: "Paper 2", subjectName: "TMUA", value: 7),
            ComparableResultPoint(id: UUID(), date: makeDate(2026, 8, 3), label: "Paper 1", subjectName: "TMUA", value: 8)
        ]
        let averages = ProgressAnalytics.averages(for: points)

        XCTAssertEqual(averages.first(where: { $0.label == "Paper 1" })?.value, 7)
        XCTAssertEqual(averages.first(where: { $0.label == "Paper 2" })?.value, 7)
    }

    func testTrendRequiresThreeAndUsesDeterministicWindows() {
        let points = (1...5).map { index in
            ComparableResultPoint(
                id: UUID(),
                date: makeDate(2026, 8, index),
                label: "Paper 1",
                subjectName: "TMUA",
                value: Double(index)
            )
        }

        XCTAssertNil(ProgressAnalytics.trend(for: Array(points.prefix(2))))
        XCTAssertEqual(ProgressAnalytics.trend(for: Array(points.prefix(3))), .recentAverage(2))
        XCTAssertEqual(ProgressAnalytics.trend(for: points), .change(2))
    }

    func testALevelGroupingAndFilteringExcludeTMUA() {
        let results = [
            result(date: .now, label: "Pure", raw: 60, maximum: 75, scaled: nil, subject: "Mathematics"),
            result(date: .now, label: "CP1", raw: 50, maximum: 75, scaled: nil, subject: "Further Mathematics"),
            result(date: .now, label: "Paper 1", raw: 15, maximum: 20, scaled: nil, subject: "TMUA")
        ]

        XCTAssertEqual(ProgressAnalytics.aLevelResults(from: results).count, 2)
        XCTAssertEqual(ProgressAnalytics.aLevelResults(from: results, category: .mathematics).map(\.paperOrModuleLabel), ["Pure"])
        XCTAssertEqual(ProgressAnalytics.aLevelPoints(from: results).count, 2)
    }

    private func session(date: Date, minutes: Int, snapshot: String) -> StudySession {
        StudySession(
            date: date,
            duration: TimeInterval(minutes * 60),
            activity: .revision,
            subjectNameSnapshot: snapshot
        )
    }

    private func result(
        date: Date,
        label: String,
        raw: Double?,
        maximum: Double?,
        scaled: Double?,
        subject: String
    ) -> StudyResult {
        StudyResult(
            date: date,
            paperOrModuleLabel: label,
            rawScore: raw,
            maximumScore: maximum,
            scaledScore: scaled,
            subjectNameSnapshot: subject
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
