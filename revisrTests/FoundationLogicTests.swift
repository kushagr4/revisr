import XCTest
@testable import revisr

final class FoundationLogicTests: XCTestCase {
    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    func testSubjectAllocationIsValid() {
        XCTAssertTrue(DomainValidation.isValidPercentageGroup([0.55, 0.27, 0.18]))
    }

    func testTMUAPaperAllocationIsValid() {
        XCTAssertTrue(DomainValidation.isValidPercentageGroup([0.40, 0.60]))
    }

    func testResultPercentage() {
        let result = StudyResult(
            date: makeDate(year: 2026, month: 8, day: 15),
            paperOrModuleLabel: "FM1",
            rawScore: 62,
            maximumScore: 75,
            subjectNameSnapshot: "Further Mathematics"
        )

        XCTAssertEqual(result.percentage, 62.0 / 75.0, accuracy: 0.000_001)
    }

    func testStartOfWeekUsesMondayBoundary() {
        let wednesday = makeDate(year: 2026, month: 8, day: 19, hour: 15)
        let expectedMonday = makeDate(year: 2026, month: 8, day: 17)

        XCTAssertEqual(
            DateUtilities.startOfWeek(for: wednesday, calendar: calendar),
            expectedMonday
        )
    }

    func testTMUACountdownUsesSuppliedDates() {
        let source = makeDate(year: 2026, month: 8, day: 15, hour: 16)
        let exam = makeDate(year: 2026, month: 10, day: 16)

        XCTAssertEqual(DateUtilities.daysUntil(exam, from: source, calendar: calendar), 62)
    }

    func testCountdownHandlesTodayTomorrowAndYesterday() {
        let source = makeDate(year: 2026, month: 8, day: 15, hour: 23)

        XCTAssertEqual(
            DateUtilities.daysUntil(
                makeDate(year: 2026, month: 8, day: 15),
                from: source,
                calendar: calendar
            ),
            0
        )
        XCTAssertEqual(
            DateUtilities.daysUntil(
                makeDate(year: 2026, month: 8, day: 16),
                from: source,
                calendar: calendar
            ),
            1
        )
        XCTAssertEqual(
            DateUtilities.daysUntil(
                makeDate(year: 2026, month: 8, day: 14),
                from: source,
                calendar: calendar
            ),
            -1
        )
    }

    func testLeapDayAndMidnightBoundariesUseCalendarDays() {
        let leapDay = makeDate(year: 2028, month: 2, day: 29, hour: 23, minute: 59)
        let marchFirst = makeDate(year: 2028, month: 3, day: 1)
        let week = DateUtilities.daysInWeek(containing: leapDay, calendar: calendar)

        XCTAssertEqual(DateUtilities.daysUntil(marchFirst, from: leapDay, calendar: calendar), 1)
        XCTAssertEqual(week.count, 7)
        XCTAssertTrue(week.contains(where: { calendar.isDate($0, inSameDayAs: leapDay) }))
    }

    func testTimerElapsedTimeDerivesFromDates() {
        let state = StudyTimerState()
        let start = makeDate(year: 2026, month: 8, day: 15, hour: 9)
        state.start(at: start)

        let later = calendar.date(byAdding: .minute, value: 47, to: start)!
        XCTAssertEqual(state.elapsed(at: later), 47 * 60, accuracy: 0.001)
    }

    func testTimerDoesNotLoseAccumulatedTimeWhenClockMovesBackward() {
        let state = StudyTimerState()
        let start = makeDate(year: 2026, month: 8, day: 15, hour: 9)
        state.start(at: start)
        state.pause(at: start.addingTimeInterval(30 * 60))
        state.resume(at: start.addingTimeInterval(60 * 60))

        XCTAssertEqual(
            state.elapsed(at: start.addingTimeInterval(45 * 60)),
            30 * 60,
            accuracy: 0.001
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
