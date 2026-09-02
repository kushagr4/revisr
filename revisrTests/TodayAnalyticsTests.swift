import XCTest
@testable import revisr

final class TodayAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    func testPlannedDurationIncludesCompletedAndSkippedBlocks() {
        let day = makeDate(hour: 0)
        let blocks = [
            block(day: day, startMinute: 9 * 60, duration: 60, status: .completed),
            block(day: day, startMinute: 11 * 60, duration: 90, status: .skipped),
            block(day: day, startMinute: nil, duration: 30),
            block(day: calendar.date(byAdding: .day, value: 1, to: day)!, startMinute: nil, duration: 120)
        ]

        XCTAssertEqual(
            StudyAnalytics.plannedDuration(on: day, blocks: blocks, calendar: calendar),
            180 * 60
        )
    }

    func testActualDurationUsesSessionsWithoutDoubleCountingLinkedBlock() {
        let day = makeDate(hour: 0)
        let linkedBlock = block(day: day, startMinute: 9 * 60, duration: 90, status: .completed)
        let linkedSession = session(day: day, duration: 75, block: linkedBlock)
        linkedBlock.linkedSession = linkedSession

        XCTAssertEqual(
            StudyAnalytics.actualDuration(on: day, sessions: [linkedSession], calendar: calendar),
            75 * 60
        )
    }

    func testSkippedBlockDoesNotCreateActualDuration() {
        let day = makeDate(hour: 0)
        let skipped = block(day: day, startMinute: 10 * 60, duration: 60, status: .skipped)

        XCTAssertEqual(
            StudyAnalytics.actualDuration(on: day, sessions: [], calendar: calendar),
            0
        )
        XCTAssertEqual(skipped.status, .skipped)
    }

    func testManualSessionContributesToActualDuration() {
        let day = makeDate(hour: 0)
        let manual = session(day: day, duration: 45)

        XCTAssertEqual(
            StudyAnalytics.actualDuration(on: day, sessions: [manual], calendar: calendar),
            45 * 60
        )
        XCTAssertEqual(
            StudyAnalytics.manualSessions(on: day, sessions: [manual], calendar: calendar).count,
            1
        )
    }

    func testNextBlockPrioritisesCurrentThenUpcoming() {
        let day = makeDate(hour: 0)
        let past = block(day: day, startMinute: 8 * 60, duration: 30)
        let current = block(day: day, startMinute: 10 * 60, duration: 90)
        let upcoming = block(day: day, startMinute: 13 * 60, duration: 60)

        XCTAssertEqual(
            StudyAnalytics.nextBlock(
                from: [upcoming, past, current],
                now: makeDate(hour: 10, minute: 30),
                calendar: calendar
            )?.id,
            current.id
        )

        current.status = .completed
        XCTAssertEqual(
            StudyAnalytics.nextBlock(
                from: [upcoming, past, current],
                now: makeDate(hour: 10, minute: 30),
                calendar: calendar
            )?.id,
            upcoming.id
        )
    }

    func testScheduledAndUnscheduledOrderingStaySeparateAndStable() {
        let day = makeDate(hour: 0)
        let late = block(day: day, startMinute: 14 * 60, duration: 60)
        let early = block(day: day, startMinute: 9 * 60, duration: 60)
        let firstAnyTime = block(day: day, startMinute: nil, duration: 45, createdOffset: 1)
        let secondAnyTime = block(day: day, startMinute: nil, duration: 45, createdOffset: 2)

        XCTAssertEqual(StudyAnalytics.scheduledBlocks(from: [late, early]).map(\.id), [early.id, late.id])
        XCTAssertEqual(
            StudyAnalytics.unscheduledBlocks(from: [secondAnyTime, firstAnyTime]).map(\.id),
            [firstAnyTime.id, secondAnyTime.id]
        )
    }

    func testCompletionFractionCapsVisualProgressAndHandlesNoPlan() {
        XCTAssertEqual(StudyAnalytics.completionFraction(planned: 120, actual: 60), 0.5)
        XCTAssertEqual(StudyAnalytics.completionFraction(planned: 0, actual: 60), 0)
        XCTAssertEqual(StudyAnalytics.completionFraction(planned: 60, actual: 90), 1)
    }

    private func block(
        day: Date,
        startMinute: Int?,
        duration: Int,
        status: PlannedBlockStatus = .planned,
        createdOffset: TimeInterval = 0
    ) -> PlannedStudyBlock {
        PlannedStudyBlock(
            day: day,
            startMinute: startMinute,
            duration: TimeInterval(duration * 60),
            activity: .revision,
            status: status,
            createdAt: day.addingTimeInterval(createdOffset),
            calendar: calendar
        )
    }

    private func session(
        day: Date,
        duration: Int,
        block: PlannedStudyBlock? = nil
    ) -> StudySession {
        StudySession(
            date: day.addingTimeInterval(12 * 60 * 60),
            duration: TimeInterval(duration * 60),
            activity: .revision,
            plannedBlock: block,
            subjectNameSnapshot: "TMUA"
        )
    }

    private func makeDate(hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: 15,
                hour: hour,
                minute: minute
            )
        )!
    }
}
