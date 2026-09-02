import SwiftData
import XCTest
@testable import revisr

@MainActor
final class AdmissionsDomainTests: XCTestCase {
    func testBundledManifestContainsCompleteValidatedWorkbook() throws {
        let manifest = try AdmissionsManifest.bundled()

        XCTAssertEqual(manifest.formatVersion, 2)
        XCTAssertEqual(manifest.questions.count, 2_600)
        XCTAssertEqual(Set(manifest.questions.map(\.externalQuestionID)).count, 2_600)
        XCTAssertEqual(manifest.sources.count, 136)
        XCTAssertEqual(manifest.programme.days.count, 30)
        XCTAssertEqual(manifest.programme.assignments.count, 530)
        XCTAssertEqual(manifest.profiles.first(where: { $0.kind == .tmua })?.isActive, true)
        XCTAssertEqual(manifest.profiles.first(where: { $0.kind == .csat })?.isActive, false)
    }

    func testEveryProgrammeAssignmentResolvesAndPerDayCountsMatch() throws {
        let manifest = try AdmissionsManifest.bundled()
        let questionIDs = Set(manifest.questions.map(\.externalQuestionID))
        XCTAssertTrue(manifest.programme.assignments.allSatisfy { questionIDs.contains($0.questionID) })

        let assignmentsByDay = Dictionary(grouping: manifest.programme.assignments, by: \.dayNumber)
        for day in manifest.programme.days {
            XCTAssertEqual(assignmentsByDay[day.dayNumber]?.count, day.allocatedQuestionCount)
        }
    }

    func testProgrammeDatesDeriveFromSingleStartDate() {
        let calendar = DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        let programme = AdmissionsProgramme(
            externalProgrammeID: "test",
            admissionsTest: .tmua,
            name: "TMUA 30-Day Programme",
            startDate: start,
            importRevision: "test"
        )

        XCTAssertEqual(programme.date(for: 1, calendar: calendar), start)
        XCTAssertEqual(
            programme.date(for: 30, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))
        )
        XCTAssertEqual(programme.dayNumber(for: start, calendar: calendar), 1)
    }

    func testTMUA2022IsImportedAndProtectedFromAutomaticSelection() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let tmua2022 = questions.filter { $0.family == "TMUA Actual" && $0.year == 2022 }

        XCTAssertEqual(tmua2022.count, 40)
        XCTAssertTrue(tmua2022.allSatisfy { $0.protection == .protectedFromAutomaticSelection })
        XCTAssertTrue(tmua2022.allSatisfy { !$0.isScheduled })

        let selection = ExtraPracticeSelector.select(
            from: tmua2022,
            filter: ExtraPracticeFilter(),
            programme: nil,
            limit: 50
        )
        XCTAssertTrue(selection.isEmpty)
    }

    func testStandbyCountAndStableUnattemptedPreference() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())

        XCTAssertEqual(questions.filter { $0.isStandby }.count, 1_488)
        let first = ExtraPracticeSelector.select(
            from: questions,
            filter: ExtraPracticeFilter(primaryTopic: "Algebra: equations & inequalities"),
            programme: nil,
            limit: 10
        )
        let second = ExtraPracticeSelector.select(
            from: questions,
            filter: ExtraPracticeFilter(primaryTopic: "Algebra: equations & inequalities"),
            programme: nil,
            limit: 10
        )
        XCTAssertEqual(first.map(\.externalQuestionID), second.map(\.externalQuestionID))
        XCTAssertTrue(first.allSatisfy { $0.attempts.isEmpty })
    }

    func testFutureOfficialBenchmarkQuestionIsExcluded() {
        let calendar = DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        let programme = AdmissionsProgramme(
            externalProgrammeID: "test",
            admissionsTest: .tmua,
            name: "Test",
            startDate: start,
            importRevision: "test"
        )
        let day = ProgrammeDay(
            externalDayID: "test-d20",
            dayNumber: 20,
            focus: "Benchmark",
            studyBrief: "",
            allocatedQuestionCount: 1,
            expectedQuestionMinutes: 75,
            expectedReviewMinutes: 60,
            programme: programme
        )
        let question = AdmissionsQuestion(
            externalQuestionID: "TMUA-2020-P1-Q01",
            admissionsTest: .tmua,
            family: "TMUA Actual",
            year: 2020,
            questionLabel: "1",
            primaryTopic: "Algebra",
            difficulty: 3,
            difficultyLabel: "Challenging",
            scheduleEligible: true,
            importRevision: "test"
        )
        let assignment = ProgrammeAssignment(
            externalAssignmentID: "a",
            displayOrder: 0,
            programmeDay: day,
            question: question
        )
        question.programmeAssignments = [assignment]

        XCTAssertTrue(ExtraPracticeSelector.select(
            from: [question],
            filter: ExtraPracticeFilter(),
            programme: programme,
            on: start,
            calendar: calendar
        ).isEmpty)
    }

    func testRepeatedAttemptsPreserveHistoryAndLatestSemantics() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let question = AdmissionsQuestion(
            externalQuestionID: "Q1",
            admissionsTest: .tmua,
            family: "Test",
            questionLabel: "1",
            primaryTopic: "Algebra",
            difficulty: 3,
            difficultyLabel: "Challenging",
            scheduleEligible: true,
            importRevision: "test",
            reviewState: .redo
        )
        context.insert(question)
        let first = QuestionAttempt(
            attemptedAt: Date(timeIntervalSince1970: 100),
            outcome: .incorrect,
            timeTakenSeconds: 372,
            errorType: .approach,
            origin: .questionBank,
            question: question
        )
        let second = QuestionAttempt(
            attemptedAt: Date(timeIntervalSince1970: 200),
            outcome: .correct,
            timeTakenSeconds: 241,
            origin: .needsReview,
            question: question
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertEqual(question.attempts.count, 2)
        XCTAssertEqual(AdmissionsAnalytics.latestMeaningfulAttempt(for: question)?.outcome, .correct)
        XCTAssertEqual(first.errorType, .approach)
        XCTAssertEqual(question.reviewState, .redo)
        XCTAssertEqual(AdmissionsAnalytics.attemptSummary(question.attempts).attemptCount, 2)
    }

    func testAccuracySemanticsKeepPartialAndSkippedDistinct() {
        let question = AdmissionsQuestion(
            externalQuestionID: "Q",
            admissionsTest: .tmua,
            family: "Test",
            questionLabel: "1",
            primaryTopic: "Logic",
            difficulty: 2,
            difficultyLabel: "Core",
            scheduleEligible: true,
            importRevision: "test"
        )
        let attempts = [
            QuestionAttempt(outcome: .correct, timeTakenSeconds: 60, origin: .questionBank, question: question),
            QuestionAttempt(outcome: .incorrect, timeTakenSeconds: 60, origin: .questionBank, question: question),
            QuestionAttempt(outcome: .partial, timeTakenSeconds: 60, origin: .questionBank, question: question),
            QuestionAttempt(outcome: .skipped, timeTakenSeconds: 0, origin: .questionBank, question: question),
        ]
        let summary = AdmissionsAnalytics.attemptSummary(attempts)

        XCTAssertEqual(try XCTUnwrap(summary.accuracy), 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.partialCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
    }

    func testAttemptTimerUsesPersistedTimestampsAcrossInactiveTime() {
        let question = AdmissionsQuestion(
            externalQuestionID: "Q",
            admissionsTest: .tmua,
            family: "Test",
            questionLabel: "1",
            primaryTopic: "Logic",
            difficulty: 2,
            difficultyLabel: "Core",
            scheduleEligible: true,
            importRevision: "test"
        )
        let timer = QuestionAttemptTimerState()
        let start = Date(timeIntervalSince1970: 1_000)
        timer.start(question: question, assignment: nil, at: start)

        XCTAssertEqual(timer.elapsed(at: Date(timeIntervalSince1970: 1_125)), 125)
        timer.pause(at: Date(timeIntervalSince1970: 1_130))
        XCTAssertEqual(timer.elapsed(at: Date(timeIntervalSince1970: 2_000)), 130)
        timer.resume(at: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(timer.elapsed(at: Date(timeIntervalSince1970: 2_045)), 175)
    }
}
