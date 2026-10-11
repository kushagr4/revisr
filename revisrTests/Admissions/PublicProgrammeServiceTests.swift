import SwiftData
import XCTest
@testable import revisr

@MainActor
final class PublicProgrammeServiceTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_791_504_000) // 9 Oct 2026 UTC

    private func prepare(exam: PublicExamKind = .tmua, days: Int = 30,
                         in context: ModelContext) throws -> AppSettings {
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let examDate = Calendar.current.date(byAdding: .day, value: days, to: today)!
        try PublicPreparationService.saveProfile(exam: exam, examDate: examDate,
            weeklyMinutes: 600, availability: AppSettings.publicDefaultAvailability,
            today: today, settings: settings, in: context)
        let selected = try DiagnosticPaperSelector.select(exam: exam,
            sources: context.fetch(FetchDescriptor<SourceDocument>()),
            questions: context.fetch(FetchDescriptor<AdmissionsQuestion>()),
            solutions: context.fetch(FetchDescriptor<SolutionDocument>()),
            links: context.fetch(FetchDescriptor<QuestionSolutionLink>()))
        let assessment = try DiagnosticAssessmentService.loadOrCreate(
            settings: settings, selection: selected, in: context)
        let papers = try context.fetch(FetchDescriptor<DiagnosticPaperRecord>())
            .filter { $0.assessmentID == assessment.stableID }.sorted { $0.ordinal < $1.ordinal }
        for paper in papers {
            try DiagnosticAssessmentService.start(paper, at: today, in: context)
            try DiagnosticAssessmentService.submitAnswers(paper, at: today, in: context)
            try DiagnosticAssessmentService.complete(paper, settings: settings, at: today, in: context)
        }
        return settings
    }

    func testCleanGenerationAndRelaunchRemainSeparateFromLegacyProgramme() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Public-Plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")
        var firstID = ""
        var firstTaskID = ""
        do {
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try prepare(in: context)
            let plan = try PublicProgrammeService.generateIfNeeded(settings: settings, today: today, in: context)
            let tasks = try PublicProgrammeService.tasks(for: plan, in: context)
            XCTAssertFalse(tasks.isEmpty)
            XCTAssertEqual(settings.publicOnboardingStage, .programme)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), 0)
            firstID = plan.stableID
            firstTaskID = tasks[0].stableID
            XCTAssertEqual(try PublicProgrammeService.generateIfNeeded(settings: settings, today: today, in: context).revision, 1)
            XCTAssertEqual(try PublicProgrammeService.tasks(for: plan, in: context).count, tasks.count)
        }
        let reopened = try AppContainer.make(storeURL: store)
        let context = reopened.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let plan = try XCTUnwrap(PublicProgrammeService.load(settings: settings, in: context))
        XCTAssertEqual(plan.stableID, firstID)
        XCTAssertEqual(settings.publicOnboardingStage, .programme)
        XCTAssertTrue(try PublicProgrammeService.tasks(for: plan, in: context)
            .contains { $0.stableID == firstTaskID })
    }

    func testCompletionAndRefreshPreserveHistoryAndAvoidOverdueBacklog() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let settings = try prepare(in: context)
        let plan = try PublicProgrammeService.generateIfNeeded(settings: settings, today: today, in: context)
        let initial = try PublicProgrammeService.tasks(for: plan, in: context)
        let task = try XCTUnwrap(initial.first { $0.questionID != nil })
        let question = try XCTUnwrap(context.fetch(FetchDescriptor<AdmissionsQuestion>())
            .first { $0.externalQuestionID == task.questionID })
        try PublicProgrammeService.completeQuestion(task, question: question, outcome: .incorrect,
            seconds: 240, errorType: .algebra, notes: "Check working", at: today, in: context)
        XCTAssertThrowsError(try PublicProgrammeService.completeQuestion(task, question: question,
            outcome: .correct, seconds: 1, errorType: nil, notes: "", in: context))
        let attemptID = try XCTUnwrap(task.completionAttemptID)
        let attempts = try context.fetch(FetchDescriptor<QuestionAttempt>())
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].id, attemptID)
        XCTAssertEqual(attempts[0].outcome, .incorrect)
        let later = Calendar.current.date(byAdding: .day, value: 6, to: today)!
        _ = try PublicProgrammeService.refresh(settings: settings, today: later, in: context)
        XCTAssertEqual(task.completionAttemptID, attemptID)
        XCTAssertNotNil(task.completedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), 1)
        let updated = try PublicProgrammeService.tasks(for: plan, in: context)
        XCTAssertTrue(updated.filter { $0.scheduledDate < Calendar.current.startOfDay(for: later)
            && $0.completedAt == nil }.allSatisfy { !$0.isActive })
        XCTAssertEqual(Set(updated.filter(\.isActive).map(\.stableID)).count,
                       updated.filter(\.isActive).count)
    }

    func testAllExamsUseEligibleQuestionsAndShortWindow() throws {
        for exam in PublicExamKind.allCases {
            let container = try AppContainer.make(isStoredInMemoryOnly: true)
            let context = container.mainContext
            let settings = try prepare(exam: exam, days: 7, in: context)
            let plan = try PublicProgrammeService.generateIfNeeded(settings: settings, today: today, in: context)
            let tasks = try PublicProgrammeService.tasks(for: plan, in: context).filter(\.isActive)
            XCTAssertFalse(tasks.isEmpty, "\(exam)")
            let questions = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AdmissionsQuestion>())
                .map { ($0.externalQuestionID, $0) })
            XCTAssertTrue(tasks.compactMap(\.questionID).allSatisfy { id in
                guard let question = questions[id] else { return false }
                return question.protection == .none && question.scheduleEligible
                    && question.isUsefulFor(exam.preparationStream)
                    && question.family != "TMUA Actual"
            }, "\(exam)")
            XCTAssertTrue(tasks.allSatisfy { $0.scheduledDate < settings.publicExamDate! })
        }
    }

    func testProgressSnapshotExcludesRetiredIncompleteTasksAndKeepsCompletedHistory() {
        let planned = PublicPlannedTask(date: today, questionID: "Q-1", sourceID: "SRC-1",
            topic: "Algebra", minutes: 15, activity: .targeted, reason: "Diagnostic evidence")
        let active = PublicProgrammeTask(stableID: "active", programmeID: "P", task: planned)
        let completed = PublicProgrammeTask(stableID: "completed", programmeID: "P", task: planned)
        completed.completedAt = today
        let attemptID = UUID()
        completed.completionAttemptID = attemptID
        let retiredIncomplete = PublicProgrammeTask(stableID: "retired", programmeID: "P", task: planned)
        retiredIncomplete.isActive = false
        let retiredCompleted = PublicProgrammeTask(stableID: "retired-completed", programmeID: "P", task: planned)
        retiredCompleted.isActive = false
        retiredCompleted.completedAt = today

        let snapshot = PublicProgrammeProgressSnapshot(tasks: [active, completed, retiredIncomplete, retiredCompleted])

        XCTAssertEqual(snapshot.plannedTaskCount, 3)
        XCTAssertEqual(snapshot.completedTaskCount, 2)
        XCTAssertEqual(snapshot.activeTaskCount, 2)
        XCTAssertEqual(snapshot.completedAttemptIDs, [attemptID])
    }

    func testEmptyProgressSnapshotHasNoArtificialDenominator() {
        let snapshot = PublicProgrammeProgressSnapshot(tasks: [])

        XCTAssertEqual(snapshot.plannedTaskCount, 0)
        XCTAssertEqual(snapshot.completedTaskCount, 0)
        XCTAssertEqual(snapshot.activeTaskCount, 0)
        XCTAssertTrue(snapshot.completedAttemptIDs.isEmpty)
    }

    func testRepeatedQuestionWorkKeepsSeparateTaskAndAttemptCounts() {
        let planned = PublicPlannedTask(date: today, questionID: "Q-1", sourceID: "SRC-1",
            topic: "Algebra", minutes: 15, activity: .targeted, reason: "Review recorded work")
        let first = PublicProgrammeTask(stableID: "repeat-1", programmeID: "P", task: planned)
        first.completedAt = today
        first.completionAttemptID = UUID()
        let second = PublicProgrammeTask(stableID: "repeat-2", programmeID: "P", task: planned)
        second.completedAt = today.addingTimeInterval(60)
        second.completionAttemptID = UUID()

        let snapshot = PublicProgrammeProgressSnapshot(tasks: [first, second])

        XCTAssertEqual(snapshot.plannedTaskCount, 2)
        XCTAssertEqual(snapshot.completedTaskCount, 2)
        XCTAssertEqual(snapshot.completedAttemptIDs.count, 2)
    }

    func testSavedAvailabilityDistinguishesRestDayFromMissingScheduleEntry() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        let schedule = [DayAvailability(weekday: .sunday, isAvailable: false)]

        XCTAssertEqual(PublicProgrammeAvailability.isAvailable(
            on: sunday, schedule: schedule, calendar: calendar), false)
        XCTAssertNil(PublicProgrammeAvailability.isAvailable(
            on: sunday, schedule: [], calendar: calendar))
    }
}
