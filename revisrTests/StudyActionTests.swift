import SwiftData
import XCTest
@testable import revisr

@MainActor
final class StudyActionTests: XCTestCase {
    func testCompleteCreatesExactlyOneSession() throws {
        let fixture = try makeFixture()

        let first = try StudySessionService.complete(
            block: fixture.block,
            actualDuration: 75 * 60,
            in: fixture.context
        )
        let second = try StudySessionService.complete(
            block: fixture.block,
            actualDuration: 90 * 60,
            in: fixture.context
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(fixture.block.status, .completed)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudySession>()).count, 1)
    }

    func testTimerPauseResumeBackgroundAndFinishCreateOneSession() throws {
        let fixture = try makeFixture()
        let state = StudyTimerState()
        fixture.context.insert(state)
        let start = Date(timeIntervalSince1970: 1_776_427_200)

        try StudyTimerService.start(
            state: state,
            subject: fixture.subject,
            module: fixture.module,
            plannedBlock: fixture.block,
            activity: .timedQuestions,
            at: start
        )
        state.pause(at: start.addingTimeInterval(30 * 60))
        state.resume(at: start.addingTimeInterval(60 * 60))

        let first = try StudyTimerService.finish(
            state: state,
            at: start.addingTimeInterval(105 * 60),
            in: fixture.context
        )
        let second = try StudyTimerService.finish(
            state: state,
            at: start.addingTimeInterval(106 * 60),
            in: fixture.context
        )

        XCTAssertEqual(try XCTUnwrap(first).duration, 75 * 60, accuracy: 0.001)
        XCTAssertNil(second)
        XCTAssertEqual(fixture.block.status, .completed)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudySession>()).count, 1)
        XCTAssertEqual(state.status, .idle)
    }

    func testRecoveredTimerForCompletedBlockDoesNotDuplicateSession() throws {
        let fixture = try makeFixture()
        let existing = try StudySessionService.complete(
            block: fixture.block,
            actualDuration: 60 * 60,
            in: fixture.context
        )
        let state = StudyTimerState()
        fixture.context.insert(state)

        try StudyTimerService.start(
            state: state,
            subject: fixture.subject,
            module: fixture.module,
            plannedBlock: fixture.block,
            activity: .timedQuestions,
            at: Date(timeIntervalSince1970: 1_776_427_200)
        )
        let recovered = try StudyTimerService.finish(
            state: state,
            at: Date(timeIntervalSince1970: 1_776_430_800),
            in: fixture.context
        )

        XCTAssertEqual(recovered?.id, existing.id)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudySession>()).count, 1)
        XCTAssertEqual(state.status, .idle)
    }

    func testSkipCreatesNoSessionAndDuplicateStartsClean() throws {
        let fixture = try makeFixture()
        try StudySessionService.skip(block: fixture.block, in: fixture.context)
        let duplicate = try StudySessionService.duplicate(block: fixture.block, in: fixture.context)

        XCTAssertEqual(fixture.block.status, .skipped)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<StudySession>()).isEmpty)
        XCTAssertEqual(duplicate.status, .planned)
        XCTAssertNil(duplicate.linkedSession)
        XCTAssertEqual(duplicate.subject?.id, fixture.subject.id)
        XCTAssertEqual(duplicate.module?.id, fixture.module.id)
    }

    func testMovePreservesUnscheduledState() throws {
        let fixture = try makeFixture()
        let calendar = DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let target = calendar.date(byAdding: .day, value: 2, to: fixture.block.day)!

        try StudySessionService.move(
            block: fixture.block,
            to: target,
            startMinute: nil,
            calendar: calendar,
            in: fixture.context
        )

        XCTAssertTrue(calendar.isDate(fixture.block.day, inSameDayAs: target))
        XCTAssertNil(fixture.block.startMinute)
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
            day: Date(timeIntervalSince1970: 1_776_384_000),
            duration: 90 * 60,
            activity: .timedQuestions,
            subject: subject,
            module: module
        )
        context.insert(subject)
        context.insert(module)
        context.insert(block)
        try context.save()
        return (container, context, subject, module, block)
    }
}
