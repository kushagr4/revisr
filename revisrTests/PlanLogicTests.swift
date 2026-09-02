import SwiftData
import XCTest
@testable import revisr

@MainActor
final class PlanLogicTests: XCTestCase {
    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    func testWeekRangeUsesMondayThroughSundayAcrossMonthBoundary() throws {
        let wednesday = makeDate(year: 2026, month: 9, day: 2)
        let days = DateUtilities.daysInWeek(containing: wednesday, calendar: calendar)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(days.first)), Weekday.monday.rawValue)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(days.last)), Weekday.sunday.rawValue)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(days.first)), 8)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(days.last)), 9)
    }

    func testWeekRangeCrossesYearCorrectly() throws {
        let date = makeDate(year: 2026, month: 12, day: 31)
        let days = DateUtilities.daysInWeek(containing: date, calendar: calendar)

        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(days.first)), 2026)
        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(days.last)), 2027)
    }

    func testWeeklyAndSelectedDayTotalsIncludeEveryStatus() {
        let monday = DateUtilities.startOfWeek(
            for: makeDate(year: 2026, month: 8, day: 12),
            calendar: calendar
        )
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: monday)!
        let blocks = [
            block(day: monday, durationMinutes: 60, status: .completed),
            block(day: monday, durationMinutes: 90, status: .skipped),
            block(day: tuesday, durationMinutes: 120),
            block(day: nextWeek, durationMinutes: 300)
        ]

        XCTAssertEqual(
            StudyAnalytics.weeklyPlannedDuration(containing: monday, blocks: blocks, calendar: calendar),
            270 * 60
        )
        XCTAssertEqual(
            StudyAnalytics.plannedDuration(on: monday, blocks: blocks, calendar: calendar),
            150 * 60
        )
    }

    func testPlanSortingKeepsScheduledChronologicalAndAnyTimeStable() {
        let monday = makeDate(year: 2026, month: 8, day: 10)
        let late = block(day: monday, startMinute: 15 * 60, durationMinutes: 60, createdOffset: 4)
        let early = block(day: monday, startMinute: 9 * 60, durationMinutes: 60, createdOffset: 3)
        let firstAny = block(day: monday, durationMinutes: 60, createdOffset: 1)
        let secondAny = block(day: monday, durationMinutes: 60, createdOffset: 2)

        XCTAssertEqual(StudyAnalytics.scheduledBlocks(from: [late, early]).map(\.id), [early.id, late.id])
        XCTAssertEqual(StudyAnalytics.unscheduledBlocks(from: [secondAny, firstAny]).map(\.id), [firstAny.id, secondAny.id])
    }

    func testMoveChangesDayAndTimeThenCanReturnToAnyTime() throws {
        let fixture = try makeFixture()
        let target = calendar.date(byAdding: .day, value: 2, to: fixture.block.day)!

        try StudySessionService.move(
            block: fixture.block,
            to: target,
            startMinute: 14 * 60 + 30,
            calendar: calendar,
            in: fixture.context
        )
        XCTAssertTrue(calendar.isDate(fixture.block.day, inSameDayAs: target))
        XCTAssertEqual(fixture.block.startMinute, 14 * 60 + 30)

        try StudySessionService.move(
            block: fixture.block,
            to: target,
            startMinute: nil,
            calendar: calendar,
            in: fixture.context
        )
        XCTAssertNil(fixture.block.startMinute)
    }

    func testDuplicateDoesNotInheritHistoricalStateOrSession() throws {
        let fixture = try makeFixture()
        let session = StudySession(
            date: fixture.block.day,
            duration: fixture.block.duration,
            activity: fixture.block.activity,
            subject: fixture.subject,
            module: fixture.module,
            plannedBlock: fixture.block,
            subjectNameSnapshot: fixture.subject.name,
            moduleNameSnapshot: fixture.module.name
        )
        fixture.context.insert(session)
        fixture.block.status = .completed
        fixture.block.linkedSession = session
        try fixture.context.save()

        let duplicate = try StudySessionService.duplicate(block: fixture.block, in: fixture.context)

        XCTAssertEqual(duplicate.status, .planned)
        XCTAssertNil(duplicate.linkedSession)
        XCTAssertEqual(duplicate.subject?.id, fixture.subject.id)
        XCTAssertEqual(duplicate.module?.id, fixture.module.id)
        XCTAssertEqual(duplicate.duration, fixture.block.duration)
    }

    func testDeleteNullifiesPlanLinkButKeepsHistoricalSession() throws {
        let fixture = try makeFixture()
        let session = StudySession(
            date: fixture.block.day,
            duration: fixture.block.duration,
            activity: fixture.block.activity,
            subject: fixture.subject,
            module: fixture.module,
            plannedBlock: fixture.block,
            subjectNameSnapshot: fixture.subject.name,
            moduleNameSnapshot: fixture.module.name
        )
        fixture.context.insert(session)
        fixture.block.linkedSession = session
        try fixture.context.save()

        try StudySessionService.delete(block: fixture.block, in: fixture.context)

        let sessions = try fixture.context.fetch(FetchDescriptor<StudySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions.first?.plannedBlock)
        XCTAssertEqual(sessions.first?.subjectNameSnapshot, "TMUA")
    }

    func testUnavailableThursdayAndSundayAreAdvisoryConflicts() {
        let thursday = makeDate(year: 2026, month: 8, day: 13)
        let sunday = makeDate(year: 2026, month: 8, day: 16)

        for day in [thursday, sunday] {
            XCTAssertEqual(
                PlanningService.conflicts(
                    day: day,
                    startMinute: nil,
                    duration: 60 * 60,
                    among: [],
                    availability: AppSettings.defaultAvailability,
                    calendar: calendar
                ),
                [.unavailableDay]
            )
        }
    }

    func testTuesdayBeforeFourteenHundredConflictsButLaterDoesNot() {
        let tuesday = makeDate(year: 2026, month: 8, day: 11)
        let early = PlanningService.conflicts(
            day: tuesday,
            startMinute: 11 * 60,
            duration: 60 * 60,
            among: [],
            availability: AppSettings.defaultAvailability,
            calendar: calendar
        )
        let valid = PlanningService.conflicts(
            day: tuesday,
            startMinute: 14 * 60,
            duration: 60 * 60,
            among: [],
            availability: AppSettings.defaultAvailability,
            calendar: calendar
        )

        XCTAssertEqual(early, [.beforeAvailableStart(14 * 60)])
        XCTAssertTrue(valid.isEmpty)
    }

    func testOverlapUsesHalfOpenIntervalsSoAdjacentBlocksAreValid() {
        XCTAssertTrue(
            PlanningService.overlaps(
                startMinute: 9 * 60,
                duration: 90 * 60,
                otherStartMinute: 10 * 60,
                otherDuration: 90 * 60
            )
        )
        XCTAssertFalse(
            PlanningService.overlaps(
                startMinute: 9 * 60,
                duration: 90 * 60,
                otherStartMinute: 10 * 60 + 30,
                otherDuration: 90 * 60
            )
        )
    }

    func testHierarchySelectionClearsIncompatibleDescendants() {
        let subjectA = UUID()
        let subjectB = UUID()
        let moduleA = UUID()
        let moduleB = UUID()
        let topicA = UUID()
        var selection = PlanningHierarchySelection(
            subjectID: subjectA,
            moduleID: moduleA,
            topicID: topicA
        )

        selection.selectSubject(subjectB)
        XCTAssertEqual(selection.subjectID, subjectB)
        XCTAssertNil(selection.moduleID)
        XCTAssertNil(selection.topicID)

        selection.selectModule(moduleB)
        selection.selectTopic(topicA)
        selection.selectModule(moduleA)
        XCTAssertNil(selection.topicID)
    }

    func testMovingBlockIntoAndOutOfTodayUpdatesDateAnalytics() throws {
        let fixture = try makeFixture()
        let today = makeDate(year: 2026, month: 8, day: 15)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        fixture.block.day = tomorrow
        try fixture.context.save()

        XCTAssertTrue(StudyAnalytics.blocks(on: today, from: [fixture.block], calendar: calendar).isEmpty)

        try StudySessionService.move(
            block: fixture.block,
            to: today,
            startMinute: nil,
            calendar: calendar,
            in: fixture.context
        )
        XCTAssertEqual(StudyAnalytics.blocks(on: today, from: [fixture.block], calendar: calendar).count, 1)

        try StudySessionService.move(
            block: fixture.block,
            to: tomorrow,
            startMinute: nil,
            calendar: calendar,
            in: fixture.context
        )
        XCTAssertTrue(StudyAnalytics.blocks(on: today, from: [fixture.block], calendar: calendar).isEmpty)
    }

    func testEditingPreservesBlockIdentityAndHistoricalSnapshots() throws {
        let fixture = try makeFixture()
        let mathematics = Subject(
            name: "Mathematics",
            targetPercentage: 0.18,
            displayOrder: 1,
            accentIdentifier: .mathematics
        )
        let statistics = StudyModule(name: "Statistics", displayOrder: 0, subject: mathematics)
        let probability = Topic(name: "Probability", displayOrder: 0, module: statistics)
        fixture.context.insert(mathematics)
        fixture.context.insert(statistics)
        fixture.context.insert(probability)

        let session = StudySession(
            date: fixture.block.day,
            duration: fixture.block.duration,
            activity: fixture.block.activity,
            subject: fixture.subject,
            module: fixture.module,
            plannedBlock: fixture.block,
            subjectNameSnapshot: fixture.subject.name,
            moduleNameSnapshot: fixture.module.name
        )
        fixture.context.insert(session)
        fixture.block.status = .completed
        fixture.block.linkedSession = session
        let originalID = fixture.block.id
        try fixture.context.save()

        try PlanningService.update(
            block: fixture.block,
            from: PlannedBlockDraft(
                day: fixture.block.day,
                startMinute: nil,
                duration: 60 * 60,
                activity: .questions,
                subject: mathematics,
                module: statistics,
                topic: probability
            ),
            in: fixture.context
        )

        XCTAssertEqual(fixture.block.id, originalID)
        XCTAssertEqual(fixture.block.subject?.name, "Mathematics")
        XCTAssertEqual(fixture.block.topic?.name, "Probability")
        XCTAssertNil(fixture.block.startMinute)
        XCTAssertEqual(session.subjectNameSnapshot, "TMUA")
        XCTAssertEqual(session.moduleNameSnapshot, "Paper 2")
    }

    private func makeFixture() throws -> (
        container: ModelContainer,
        context: ModelContext,
        subject: Subject,
        module: StudyModule,
        block: PlannedStudyBlock
    ) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let subject = Subject(name: "TMUA", targetPercentage: 0.55, displayOrder: 0, accentIdentifier: .tmua)
        let module = StudyModule(name: "Paper 2", displayOrder: 1, subject: subject)
        let block = PlannedStudyBlock(
            day: makeDate(year: 2026, month: 8, day: 10),
            startMinute: 9 * 60,
            duration: 90 * 60,
            activity: .timedQuestions,
            subject: subject,
            module: module,
            calendar: calendar
        )
        context.insert(subject)
        context.insert(module)
        context.insert(block)
        try context.save()
        return (container, context, subject, module, block)
    }

    private func block(
        day: Date,
        startMinute: Int? = nil,
        durationMinutes: Int,
        status: PlannedBlockStatus = .planned,
        createdOffset: TimeInterval = 0
    ) -> PlannedStudyBlock {
        PlannedStudyBlock(
            day: day,
            startMinute: startMinute,
            duration: TimeInterval(durationMinutes * 60),
            activity: .revision,
            status: status,
            createdAt: day.addingTimeInterval(createdOffset),
            calendar: calendar
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }
}
