import SwiftData
import XCTest
@testable import revisr

/// R1 Stage D adaptation scenarios: each refresh must be stable, explainable
/// and keep history.
@MainActor
final class TMUAAdaptationScenarioTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)
    private var calendar: Calendar { TMUAFixtures.calendar }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func setUp(length: TMUADiagnosticLength = .quick, days: Int = 60, weekly: Int = 300,
                       content: TMUAContentContext, allCorrect: Bool = false,
                       in context: ModelContext) throws -> (AppSettings, TMUADiagnosticSnapshot) {
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days, weeklyMinutes: weekly)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: length, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context, allCorrect: allCorrect)
        try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                   calendar: calendar, in: context)
        return (settings, snapshot)
    }

    private func priority(_ topic: String, settings: AppSettings, content: TMUAContentContext,
                          at date: Date, in context: ModelContext) throws -> Int {
        let snapshot = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        let evidence = try TMUAProgrammeService.gatherEvidence(settings: settings, snapshot: snapshot, in: context)
        let input = TMUAProgrammeService.planningInput(settings: settings, content: content, report: report,
            evidence: evidence, start: date, examDate: try XCTUnwrap(settings.publicExamDate), weeklyMinutes: 300,
            excludedQuestionIDs: [], refinement: nil, calendar: calendar)
        return try XCTUnwrap(PublicPlanningEngine.generate(input).priorities.first { $0.topic == topic }).rank
    }

    private func active(_ settings: AppSettings, in context: ModelContext) throws -> [PublicProgrammeTask] {
        try TMUAProgrammeService.tasks(settings: settings, in: context).filter(\.isActive)
    }

    private func practise(_ items: [TMUAContentItem], correct: Bool, settings: AppSettings, at date: Date,
                          in context: ModelContext) throws {
        for item in items {
            let answer = correct ? item.correctOptionId : (item.correctOptionId == "A" ? "B" : "A")
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: answer, seconds: 200, task: nil,
                                                    settings: settings, at: date, in: context)
        }
    }

    func testRepeatedAlgebraMistakesRaiseAlgebraPriority() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (settings, snapshot) = try setUp(content: content, in: context)
        let before = try priority("Algebra", settings: settings, content: content, at: day(1), in: context)
        let seen = Set(snapshot.items.map(\.itemStableID))
        let algebra = content.eligibleItems.filter { $0.taxonomy.topic == "algebra" && !seen.contains($0.stableId) }
        try practise(Array(algebra.prefix(3)), correct: false, settings: settings, at: day(1), in: context)
        let after = try priority("Algebra", settings: settings, content: content, at: day(1), in: context)
        XCTAssertGreaterThan(after, before, "recent algebra misses raise its priority")
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: day(1), calendar: calendar, in: context)
        let summary = try XCTUnwrap(programme.refreshSummary)
        XCTAssertTrue(summary.contains("kept"), summary)
        // Missed practice returns as error review after the three-day gap.
        let missedIDs = Set(algebra.prefix(3).map(\.stableId))
        XCTAssertTrue(try active(settings, in: context).contains {
            missedIDs.contains($0.questionID ?? "") && $0.activity == .errorReview && $0.scheduledDate >= day(4)
        })
    }

    func testImprovingLogicLowersLogicPriority() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (settings, snapshot) = try setUp(content: content, in: context)
        let before = try priority("Logic of arguments", settings: settings, content: content, at: day(2), in: context)
        let seen = Set(snapshot.items.map(\.itemStableID))
        let logic = content.eligibleItems.filter { $0.taxonomy.topic == "logic" && !seen.contains($0.stableId) }
        XCTAssertGreaterThanOrEqual(logic.count, 2)
        try practise(Array(logic.prefix(2)), correct: true, settings: settings, at: day(2), in: context)
        let after = try priority("Logic of arguments", settings: settings, content: content, at: day(2), in: context)
        XCTAssertLessThan(after, before, "recent logic successes lower its priority")
    }

    func testUnassessedTopicsStillGetBaselinePractice() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (settings, snapshot) = try setUp(length: .starter, content: content, in: context)
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        let unassessed = Set(report.unassessedTopicKeys.map(content.syllabus.topicTitle))
        XCTAssertFalse(unassessed.isEmpty)
        let firstWeeks = try active(settings, in: context).filter { $0.scheduledDate < day(21) }
        let covered = unassessed.intersection(firstWeeks.map(\.topic))
        XCTAssertGreaterThanOrEqual(Double(covered.count) / Double(unassessed.count), 0.8,
            "most unassessed topics appear in the first three weeks: missing \(unassessed.subtracting(covered).sorted())")
    }

    /// Expansion questions are withdrawn from planned practice at once, so a
    /// worked solution cannot be seen before the question is answered.
    func testExpansionReservesQuestionsAndPreservesEarlierWork() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (settings, snapshot) = try setUp(length: .starter, content: content, in: context)
        let todays = try active(settings, in: context).filter { $0.questionID != nil && calendar.isDate($0.scheduledDate, inSameDayAs: today) }
        for task in todays.prefix(2) {
            let item = try XCTUnwrap(content.eligibleItems.first { $0.stableId == task.questionID })
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: item.correctOptionId, seconds: 100,
                                                    task: task, settings: settings, at: today, in: context)
        }
        let completedBefore = try TMUAProgrammeService.tasks(settings: settings, in: context).filter { $0.completedAt != nil }
        let plannedBefore = Set(try active(settings, in: context).compactMap(\.questionID))
        let expanded = try TMUAProgrammeService.expandDiagnostic(snapshot, to: .balanced, settings: settings,
            content: content, today: day(2), calendar: calendar, in: context)
        let reserved = TMUAProgrammeService.reservedStableIDs(snapshot: expanded)
        XCTAssertEqual(reserved.count, 10)
        XCTAssertFalse(plannedBefore.isDisjoint(with: reserved),
                       "fixture check: the expansion picked at least one question that was already planned")
        let after = try active(settings, in: context)
        XCTAssertTrue(after.filter { $0.completedAt == nil }.allSatisfy { !reserved.contains($0.questionID ?? "") },
                      "no open practice task shows a reserved question")
        for task in completedBefore {
            XCTAssertNotNil(task.completedAt)
            XCTAssertTrue(task.isActive || task.completedAt != nil)
        }
        // Submitting the added round releases the questions as diagnostic evidence.
        try TMUAFixtures.completeAll(expanded, at: day(3), in: context)
        let final = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                               today: day(3), calendar: calendar, in: context)
        XCTAssertGreaterThan(final.revision, 2)
        let reloaded = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
        XCTAssertTrue(TMUAProgrammeService.reservedStableIDs(snapshot: reloaded).isEmpty)
        XCTAssertEqual(reloaded.items.filter { $0.sectionID.hasSuffix("-R0-P1") }.compactMap(\.marking),
                       snapshot.items.filter { $0.sectionID.hasSuffix("-R0-P1") }.compactMap(\.marking),
                       "earlier marks unchanged")
    }

    func testMissedStudyDaysAreRescheduledOnRefresh() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (settings, _) = try setUp(content: content, in: context)
        let refreshDay = calendar.startOfDay(for: day(5))
        let missed = try active(settings, in: context).filter { $0.scheduledDate < refreshDay && $0.questionID != nil }
        XCTAssertFalse(missed.isEmpty)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: day(5), calendar: calendar, in: context)
        let all = try TMUAProgrammeService.tasks(settings: settings, in: context)
        XCTAssertFalse(all.contains { $0.isActive && $0.completedAt == nil && $0.scheduledDate < refreshDay },
                       "no stale missed task stays active")
        XCTAssertTrue(missed.allSatisfy { task in all.contains { $0.stableID == task.stableID } },
                      "missed tasks are retired, not deleted")
        let future = Set(all.filter { $0.isActive && $0.scheduledDate >= refreshDay }.compactMap(\.questionID))
        let rescheduled = Set(missed.compactMap(\.questionID)).intersection(future)
        XCTAssertGreaterThanOrEqual(Double(rescheduled.count) / Double(Set(missed.compactMap(\.questionID)).count), 0.8,
                                    "missed practice comes back into the plan")
        XCTAssertNotNil(programme.refreshSummary)
    }

    func testWeeklyTimeChangesRebuildFutureCapacity() throws {
        let content = try TMUAFixtures.standardContext()
        for (newWeekly, check) in [(120, "reduced"), (600, "increased")] {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let (settings, _) = try setUp(content: content, in: context)
            let firstTask = try XCTUnwrap(try active(settings, in: context).first { $0.questionID != nil && calendar.isDate($0.scheduledDate, inSameDayAs: today) })
            let item = try XCTUnwrap(content.eligibleItems.first { $0.stableId == firstTask.questionID })
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: item.correctOptionId, seconds: 90,
                                                    task: firstTask, settings: settings, at: today, in: context)
            let beforeWeekly = try active(settings, in: context).filter { $0.scheduledDate >= day(7) && $0.scheduledDate < day(14) }
                .reduce(0) { $0 + $1.allocatedMinutes }
            try PublicPreparationService.saveFlexibleTMUAProfile(examDate: try XCTUnwrap(settings.publicExamDate),
                weeklyMinutes: newWeekly, availability: settings.publicAvailability, sessionMinutes: nil,
                today: day(1), calendar: calendar, settings: settings, in: context)
            try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: day(1),
                                                       calendar: calendar, in: context)
            let tasks = try active(settings, in: context)
            let weeks = Dictionary(grouping: tasks.filter { $0.scheduledDate >= day(1) && $0.completedAt == nil }) {
                calendar.dateInterval(of: .weekOfYear, for: $0.scheduledDate)!.start
            }.mapValues { $0.reduce(0) { $0 + $1.allocatedMinutes } }
            XCTAssertTrue(weeks.values.allSatisfy { $0 <= newWeekly }, "\(check): new capacity respected")
            let afterWeekly = tasks.filter { $0.scheduledDate >= day(7) && $0.scheduledDate < day(14) }
                .reduce(0) { $0 + $1.allocatedMinutes }
            if newWeekly < 300 { XCTAssertLessThan(afterWeekly, beforeWeekly, check) }
            else { XCTAssertGreaterThan(afterWeekly, beforeWeekly, check) }
            XCTAssertNotNil(try TMUAProgrammeService.tasks(settings: settings, in: context)
                .first { $0.stableID == firstTask.stableID }?.completedAt, "\(check): completed task kept")
        }
    }

    func testExamDateMovesEarlierOrLater() throws {
        let content = try TMUAFixtures.standardContext()
        for newDays in [20, 90] {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let (settings, _) = try setUp(content: content, in: context)
            let firstTask = try XCTUnwrap(try active(settings, in: context).first { $0.questionID != nil && calendar.isDate($0.scheduledDate, inSameDayAs: today) })
            let item = try XCTUnwrap(content.eligibleItems.first { $0.stableId == firstTask.questionID })
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: item.correctOptionId, seconds: 90,
                                                    task: firstTask, settings: settings, at: today, in: context)
            let newExam = day(newDays)
            try PublicPreparationService.saveFlexibleTMUAProfile(examDate: newExam, weeklyMinutes: 300,
                availability: settings.publicAvailability, sessionMinutes: nil, today: day(1), calendar: calendar,
                settings: settings, in: context)
            let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                       today: day(1), calendar: calendar, in: context)
            let tasks = try active(settings, in: context)
            XCTAssertFalse(tasks.contains { $0.completedAt == nil && $0.scheduledDate >= calendar.startOfDay(for: newExam) },
                           "\(newDays): nothing on or after the new exam day")
            if newDays > 60 {
                XCTAssertTrue(tasks.contains { $0.scheduledDate >= day(60) && $0.scheduledDate < newExam },
                              "later exam: plan extends into the new weeks")
            }
            XCTAssertEqual(calendar.startOfDay(for: programme.examDateSnapshot), calendar.startOfDay(for: newExam))
            XCTAssertNotNil(try TMUAProgrammeService.tasks(settings: settings, in: context)
                .first { $0.stableID == firstTask.stableID }?.completedAt, "completed task kept")
        }
    }
}
