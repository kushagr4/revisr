import SwiftData
import XCTest
@testable import revisr

@MainActor
final class TMUAPlanningAndJourneyTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)
    private var calendar: Calendar { TMUAFixtures.calendar }

    private func completedDiagnostic(length: TMUADiagnosticLength, days: Int, weekly: Int = 300,
                                     availability: [DayAvailability] = AppSettings.publicDefaultAvailability,
                                     session: Int? = nil, content: TMUAContentContext,
                                     in context: ModelContext) throws -> AppSettings {
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days, weeklyMinutes: weekly,
                                                availability: availability, session: session)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: length, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        return settings
    }

    private func weekStarts(_ tasks: [PublicProgrammeTask]) -> [Date: Int] {
        Dictionary(grouping: tasks) { calendar.dateInterval(of: .weekOfYear, for: $0.scheduledDate)!.start }
            .mapValues { $0.reduce(0) { $0 + $1.allocatedMinutes } }
    }

    func testPlansFitEveryPreparationWindowAndExcludeExamDay() throws {
        let content = try TMUAFixtures.standardContext()
        for days in [3, 7, 14, 30, 60, 90, 120, 180] {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let settings = try completedDiagnostic(length: .balanced, days: days, content: content, in: context)
            let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                       today: today, calendar: calendar, in: context)
            let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
            let examDay = calendar.startOfDay(for: try XCTUnwrap(settings.publicExamDate))
            XCTAssertFalse(tasks.isEmpty, "\(days)-day window")
            XCTAssertTrue(tasks.allSatisfy { $0.scheduledDate >= calendar.startOfDay(for: today) && $0.scheduledDate < examDay },
                          "\(days)-day window stays inside the window and off exam day")
            for (_, minutes) in weekStarts(tasks) {
                XCTAssertLessThanOrEqual(minutes, 300, "\(days)-day window exceeds weekly capacity")
            }
            if days >= 60 {
                // Paced content and spaced review keep later weeks populated.
                let lastWeek = calendar.date(byAdding: .day, value: -7, to: examDay)!
                XCTAssertTrue(tasks.contains { $0.scheduledDate >= lastWeek }, "\(days)-day window has empty final week")
                XCTAssertTrue(tasks.contains { $0.activity == .spacedReview }, "\(days)-day window")
            }
            if days <= 3 {
                XCTAssertTrue(tasks.filter { $0.questionID != nil }.allSatisfy { $0.activity == .finalReview || $0.activity == .errorReview || $0.activity == .spacedReview })
            }
            let activeIDs = tasks.map(\.stableID)
            XCTAssertEqual(Set(activeIDs).count, activeIDs.count)
        }
    }

    func testOnlyAvailableWeekdaysAndSessionCapAreUsed() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        var availability = AppSettings.publicDefaultAvailability
        for index in availability.indices {
            availability[index].isAvailable = [.tuesday, .saturday].contains(availability[index].weekday)
        }
        let settings = try completedDiagnostic(length: .quick, days: 45, weekly: 480, availability: availability,
                                               session: 60, content: content, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: today, calendar: calendar, in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        XCTAssertFalse(tasks.isEmpty)
        for task in tasks {
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: task.scheduledDate))
            XCTAssertTrue([.tuesday, .saturday].contains(weekday), "task on unavailable day")
        }
        let perDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.scheduledDate) }
            .mapValues { $0.reduce(0) { $0 + $1.allocatedMinutes } }
        XCTAssertTrue(perDay.values.allSatisfy { $0 <= 60 }, "session cap respected")
    }

    func testInsufficientCapacityIsReportedNotSilentlyPlanned() throws {
        XCTAssertNotNil(TMUAAvailabilityEditor.validationMessage(weeklyMinutes: 60,
            availability: AppSettings.publicDefaultAvailability, sessionMinutes: nil))
        XCTAssertNil(TMUAAvailabilityEditor.validationMessage(weeklyMinutes: 180,
            availability: AppSettings.publicDefaultAvailability, sessionMinutes: nil))
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try completedDiagnostic(length: .starter, days: 30, weekly: 60, content: content, in: context)
        XCTAssertThrowsError(try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                        today: today, calendar: calendar, in: context)) {
            XCTAssertEqual($0 as? PublicPlanningError, .insufficientDailyCapacity)
        }
    }

    func testExamDateMustBeInTheFuture() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertThrowsError(try PublicPreparationService.saveFlexibleTMUAProfile(examDate: today, weeklyMinutes: 300,
            availability: AppSettings.publicDefaultAvailability, sessionMinutes: nil, today: today,
            calendar: calendar, settings: settings, in: context))
        XCTAssertEqual(PublicPreparationService.daysUntilExam(TMUAFixtures.date(2027, 3, 31), today: TMUAFixtures.date(2027, 3, 27),
                                                              calendar: calendar), 4, "DST change keeps whole days")
    }

    func testDiagnosticEvidenceShapesPrioritiesAndUnsampledTopicsGetBaseline() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try completedDiagnostic(length: .starter, days: 60, content: content, in: context)
        let snapshot = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        let evidence = try TMUAProgrammeService.gatherEvidence(settings: settings, snapshot: snapshot, in: context)
        let input = TMUAProgrammeService.planningInput(settings: settings, content: content, report: report,
            evidence: evidence, start: today, examDate: try XCTUnwrap(settings.publicExamDate),
            weeklyMinutes: 300, excludedQuestionIDs: [], refinement: nil, calendar: calendar)
        let result = try PublicPlanningEngine.generate(input)
        let unsampled = Set(report.unassessedTopicKeys.map(content.syllabus.topicTitle))
        let plannedTopics = Set(result.tasks.map(\.topic))
        XCTAssertFalse(unsampled.isDisjoint(with: plannedTopics), "unassessed topics still receive baseline revision")
        XCTAssertTrue(result.tasks.contains { $0.activity == .errorReview }, "missed diagnostic questions are reviewed")
        XCTAssertTrue(input.questions.filter(\.diagnostic).allSatisfy { $0.latestOutcome != nil || $0.reviewFlag })
    }

    func testRefinementTaskOfferedForShortDiagnosticsOnly() throws {
        let content = try TMUAFixtures.standardContext()
        for (length, expected) in [(TMUADiagnosticLength.starter, true), (.comprehensive, false)] {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let settings = try completedDiagnostic(length: length, days: 30, content: content, in: context)
            let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                       today: today, calendar: calendar, in: context)
            let tasks = try PublicProgrammeService.tasks(for: programme, in: context)
            XCTAssertEqual(tasks.contains { $0.activity == .diagnosticRefinement }, expected, length.title)
            XCTAssertTrue(tasks.allSatisfy { task in
                task.questionID == nil ? task.activity == .diagnosticRefinement
                    : content.eligibleItems.contains { $0.stableId == task.questionID }
            }, "every task references real eligible content")
        }
    }

    func testRefreshAdaptsToPracticeAndPreservesHistory() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try completedDiagnostic(length: .starter, days: 60, content: content, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: today, calendar: calendar, in: context)
        var tasks = try PublicProgrammeService.tasks(for: programme, in: context)
        let todays = tasks.filter { $0.isActive && $0.questionID != nil && calendar.isDate($0.scheduledDate, inSameDayAs: today) }
        XCTAssertFalse(todays.isEmpty)
        var completedIDs: [String] = []
        for task in todays {
            let item = try XCTUnwrap(content.eligibleItems.first { $0.stableId == task.questionID })
            let attempt = try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: item.correctOptionId == "A" ? "B" : "A",
                seconds: 240, task: task, settings: settings, at: today, in: context)
            XCTAssertFalse(attempt.isCorrect)
            XCTAssertEqual(task.completionAttemptID, attempt.id)
            completedIDs.append(task.stableID)
        }
        XCTAssertThrowsError(try TMUAProgrammeService.recordPractice(item: try XCTUnwrap(content.eligibleItems.first { $0.stableId == todays[0].questionID }),
            selectedOptionID: "A", seconds: 1, task: todays[0], settings: settings, in: context))
        let later = calendar.date(byAdding: .day, value: 10, to: today)!
        let refreshed = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: later, calendar: calendar, in: context)
        XCTAssertEqual(refreshed.revision, 2)
        XCTAssertNotNil(refreshed.refreshSummary)
        tasks = try PublicProgrammeService.tasks(for: refreshed, in: context)
        for id in completedIDs {
            let task = try XCTUnwrap(tasks.first { $0.stableID == id })
            XCTAssertNotNil(task.completedAt, "completed work survives refresh")
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TMUAPracticeAttempt>()), completedIDs.count)
        let active = tasks.filter(\.isActive)
        XCTAssertEqual(Set(active.map(\.stableID)).count, active.count)
        XCTAssertTrue(tasks.filter { !$0.isActive && $0.completedAt == nil }.allSatisfy { $0.scheduledDate >= calendar.startOfDay(for: today) },
                      "retired tasks are kept, not deleted")
        // Missed practice comes back as review once enough days have passed.
        let missed = Set(todays.compactMap(\.questionID))
        XCTAssertTrue(active.contains { $0.completedAt == nil && missed.contains($0.questionID ?? "")
            && ($0.activity == .errorReview || $0.activity == .spacedReview) })
    }

    func testSettingsChangeRebuildsFutureWork() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try completedDiagnostic(length: .quick, days: 40, content: content, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: today, calendar: calendar, in: context)
        XCTAssertFalse(TMUAProgrammeService.settingsChanged(programme, settings: settings, calendar: calendar))
        var availability = settings.publicAvailability
        for index in availability.indices where availability[index].weekday == .monday {
            availability[index].isAvailable = false
        }
        try PublicPreparationService.saveFlexibleTMUAProfile(examDate: try XCTUnwrap(settings.publicExamDate),
            weeklyMinutes: 300, availability: availability, sessionMinutes: 45, today: today, calendar: calendar,
            settings: settings, in: context)
        XCTAssertTrue(TMUAProgrammeService.settingsChanged(programme, settings: settings, calendar: calendar))
        _ = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                       calendar: calendar, in: context)
        let active = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        XCTAssertTrue(active.allSatisfy { calendar.component(.weekday, from: $0.scheduledDate) != Weekday.monday.rawValue })
        XCTAssertEqual(settings.publicOnboardingStage, .programme)
    }

    func testInsufficientRevisionContentLeavesHonestGaps() throws {
        let content = try TMUAFixtures.context(TMUAFixtures.items(paperOne: 5, paperTwo: 5))
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try completedDiagnostic(length: .starter, days: 90, content: content, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: today, calendar: calendar, in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context)
        XCTAssertTrue(tasks.allSatisfy { $0.questionID.map { id in content.eligibleItems.contains { $0.stableId == id } } ?? true },
                      "no fictional question IDs")
        XCTAssertLessThanOrEqual(tasks.filter { $0.questionID != nil }.count, 10 * 7,
                                 "each question appears at most once plus its capped spaced repeats")
        let perQuestion = Dictionary(grouping: tasks.compactMap(\.questionID), by: { $0 }).mapValues(\.count)
        XCTAssertTrue(perQuestion.values.allSatisfy { $0 <= 7 })
    }

    // MARK: Full journey

    func testFullJourneyForEveryLength() throws {
        let content = try TMUAFixtures.standardContext()
        for length in TMUADiagnosticLength.allCases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Revisr-Journey-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = directory.appendingPathComponent("Revisr.store")
            do {
                let container = try AppContainer.make(storeURL: store)
                let context = container.mainContext
                let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: 45)
                XCTAssertEqual(settings.publicOnboardingStage, .diagnostics)
                let snapshot = try TMUADiagnosticService.create(settings: settings, length: length,
                                                                content: content, at: today, in: context)
                let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
                try TMUADiagnosticService.start(paperOne, in: snapshot, at: today, in: context)
                try TMUADiagnosticService.select("A", for: snapshot.items(in: paperOne)[0], in: paperOne,
                                                 at: today.addingTimeInterval(60), in: context)
                try TMUADiagnosticService.pause(paperOne, at: today.addingTimeInterval(90), in: context)
            }
            // Relaunch: resume, finish both sections, view results, plan, practise, adapt.
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try SeedDataService.bootstrapForLaunch(in: context)
            let snapshot = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
            try TMUADiagnosticService.recoverInterruptedTimers(snapshot, in: context)
            let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
            XCTAssertEqual(snapshot.items(in: paperOne)[0].selectedOptionID, "A")
            XCTAssertEqual(paperOne.accumulatedSeconds, 90, accuracy: 0.001)
            try TMUADiagnosticService.resume(paperOne, at: today.addingTimeInterval(3_600), in: context)
            try TMUAFixtures.completeAll(snapshot, at: today.addingTimeInterval(3_600), in: context)
            XCTAssertNotNil(snapshot.diagnostic.initialCompletedAt)
            let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
            XCTAssertEqual(report.questionCount, length.totalQuestions, length.title)
            let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                       today: today, calendar: calendar, in: context)
            XCTAssertEqual(settings.publicOnboardingStage, .programme)
            let first = try XCTUnwrap(PublicProgrammeService.tasks(for: programme, in: context)
                .first { $0.isActive && $0.questionID != nil })
            let item = try XCTUnwrap(content.eligibleItems.first { $0.stableId == first.questionID })
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: item.correctOptionId, seconds: 200,
                                                    task: first, settings: settings, at: today, in: context)
            let refreshed = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                today: calendar.date(byAdding: .day, value: 4, to: today)!, calendar: calendar, in: context)
            XCTAssertEqual(refreshed.revision, 2, length.title)
            XCTAssertNotNil(try PublicProgrammeService.tasks(for: refreshed, in: context)
                .first { $0.stableID == first.stableID }?.completedAt)
        }
    }

    // MARK: Legacy safety

    func testCleanInstallUsesFlexibleFlowWithoutPersonalDefaults() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertEqual(settings.publicOnboardingStage, .profile)
        XCTAssertEqual(settings.publicFlowVersion, 2)
        XCTAssertNil(settings.publicExamDate)
        XCTAssertNil(settings.publicWeeklyTargetMinutes)
        XCTAssertNil(settings.publicDiagnosticLength)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TMUADiagnostic>()), 0)
    }

    func testLegacyPublicProfileMidDiagnosticStaysOnEarlierFlow() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        settings.publicFlowVersion = nil
        try PublicPreparationService.saveProfile(exam: .smc, examDate: calendar.date(byAdding: .day, value: 20, to: today)!,
            weeklyMinutes: 300, availability: AppSettings.publicDefaultAvailability, today: today,
            settings: settings, in: context)
        XCTAssertEqual(settings.publicOnboardingStage, .diagnostics)
        let relaunched = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertNil(relaunched.publicFlowVersion, "a saved earlier-flow profile is not moved automatically")
        XCTAssertEqual(relaunched.publicExam, .smc)
        XCTAssertFalse(relaunched.usesFlexibleTMUAFlow)
    }
}
