import Foundation
import SwiftData
import XCTest
@testable import revisr

/// R5: worksheets recorded question by question, the evidence hierarchy, revisits of self-marked
/// mistakes, classification provenance, Practice filters and Saved identities. Uses synthetic
/// content and disposable in-memory stores only.
@MainActor
final class TMUAStudentExperienceTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)
    private var calendar: Calendar { TMUAFixtures.calendar }

    private struct Plan {
        let context: ModelContext
        let container: ModelContainer
        let settings: AppSettings
        let content: TMUAContentContext
        let catalogue: TMUAQuestionCatalogue
        let programme: PublicProgramme
    }

    private func plan(days: Int = 60, weekly: Int = 300, weekdays: Set<Weekday> = TMUAPlannerDeterminismTests.everyDay,
                      session: Int? = nil, allCorrect: Bool = false) throws -> Plan {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let content = try TMUAFixtures.standardContext()
        let catalogue = try TMUAPlannerDeterminismTests.syntheticCatalogue(content: content)
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days, weeklyMinutes: weekly,
            availability: TMUAPlannerDeterminismTests.availability(weekdays), session: session,
            id: TMUAFixtures.pinnedProfileID)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context, allCorrect: allCorrect)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
            calendar: calendar, resourceSessions: true, catalogue: catalogue, in: context)
        return Plan(context: context, container: container, settings: settings, content: content,
                    catalogue: catalogue, programme: programme)
    }

    private func worksheets(_ plan: Plan) throws -> [PublicProgrammeTask] {
        try PublicProgrammeService.tasks(for: plan.programme, in: plan.context)
            .filter { $0.isActive && $0.activity == .topicWorksheet }
    }

    private func record(_ outcome: TMUAResourceOutcome, _ id: String, in task: PublicProgrammeTask, _ plan: Plan,
                        at date: Date? = nil) throws {
        try TMUAProgrammeService.recordWorksheetResult(outcome, questionID: id,
            paperSourceID: try XCTUnwrap(plan.catalogue.entry(id)?.sourceID), task: task, settings: plan.settings,
            at: date ?? today, in: plan.context)
    }

    private func logs(_ plan: Plan) throws -> [TMUAResourceLog] {
        try plan.context.fetch(FetchDescriptor<TMUAResourceLog>())
    }

    // MARK: Worksheet progress and completion

    func testWorksheetStatesFollowRecordedQuestions() throws {
        let plan = try plan()
        let task = try XCTUnwrap(try worksheets(plan).first)
        let ids = TMUAProgrammeService.worksheetQuestionIDs(task.sourceID)
        XCTAssertGreaterThanOrEqual(ids.count, 3)
        func progress() throws -> TMUAWorksheetProgress { TMUAProgrammeService.worksheetProgress(task, logs: try logs(plan)) }
        XCTAssertEqual(try progress().state, .notStarted)
        XCTAssertEqual(try progress().nextQuestionID, ids[0])

        try record(.skipped, ids[0], in: task, plan)
        XCTAssertEqual(try progress().state, .inProgress)
        XCTAssertFalse(try progress().canFinish, "skipping alone finishes nothing")
        XCTAssertThrowsError(try TMUAProgrammeService.finishWorksheet(task, settings: plan.settings, in: plan.context))

        try record(.correct, ids[1], in: task, plan)
        try record(.incorrect, ids[1], in: task, plan, at: today.addingTimeInterval(60))
        XCTAssertEqual(try progress().results[ids[1]], .incorrect, "a later result replaces the earlier one in the tally")
        XCTAssertEqual(try progress().nextQuestionID, ids[2], "work resumes at the first question without a result")
        XCTAssertNil(task.completedAt, "recording results never completes the task by itself")

        try TMUAProgrammeService.finishWorksheet(task, settings: plan.settings, at: today, in: plan.context)
        let finished = try progress()
        XCTAssertEqual(finished.state, .completedWithGaps)
        XCTAssertEqual(finished.count(.correct), 0, "an unanswered question is never counted as correct")
        XCTAssertEqual(finished.unrecorded, ids.count - 2)
        let summary = try XCTUnwrap(try logs(plan).first { $0.programmeTaskID == task.stableID && $0.questionID == nil })
        XCTAssertEqual(summary.correctCount, 0)
        XCTAssertEqual(summary.questionCount, ids.count)
        XCTAssertTrue(task.completionNote.contains("not recorded"), task.completionNote)
        XCTAssertThrowsError(try record(.correct, ids[2], in: task, plan), "a finished worksheet takes no more results")
    }

    func testAFullyRecordedWorksheetCompletesCleanlyAndOnlyItsOwnQuestionsCount() throws {
        let plan = try plan()
        let all = try worksheets(plan)
        let task = try XCTUnwrap(all.first)
        let other = try XCTUnwrap(all.dropFirst().first)
        let ids = TMUAProgrammeService.worksheetQuestionIDs(task.sourceID)
        XCTAssertThrowsError(try record(.correct, try XCTUnwrap(TMUAProgrammeService.worksheetQuestionIDs(other.sourceID).first),
                                        in: task, plan), "only the worksheet's own questions")
        for (offset, id) in ids.enumerated() { try record(offset == 0 ? .partial : .correct, id, in: task, plan) }
        XCTAssertEqual(TMUAProgrammeService.worksheetProgress(task, logs: try logs(plan)).state, .readyToFinish)
        try TMUAProgrammeService.finishWorksheet(task, settings: plan.settings, at: today, in: plan.context)
        let progress = TMUAProgrammeService.worksheetProgress(task, logs: try logs(plan))
        XCTAssertEqual(progress.state, .completed)
        XCTAssertEqual(progress.overallOutcome, .partial)
        XCTAssertEqual(TMUAProgrammeService.worksheetProgress(other, logs: try logs(plan)).recorded, 0)
    }

    /// Self-marked results are never verified evidence: no auto-marked attempt is created, and the
    /// planner's topic priorities are exactly those of a student who recorded nothing.
    func testSelfMarkedResultsNeverBecomeEvidence() throws {
        let plan = try plan()
        let before = try planningPriorities(plan)
        for task in try worksheets(plan).prefix(3) {
            for id in TMUAProgrammeService.worksheetQuestionIDs(task.sourceID) { try record(.incorrect, id, in: task, plan) }
            try TMUAProgrammeService.finishWorksheet(task, settings: plan.settings, at: today, in: plan.context)
        }
        XCTAssertEqual(try plan.context.fetchCount(FetchDescriptor<TMUAPracticeAttempt>()), 0)
        XCTAssertEqual(try planningPriorities(plan), before)
        let snapshot = try XCTUnwrap(try TMUADiagnosticService.load(settings: plan.settings, in: plan.context))
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: plan.content.syllabus)
        XCTAssertEqual(TMUAProgrammeService.worksheetTopicOrder(report: report, syllabus: plan.content.syllabus),
                       TMUAProgrammeService.worksheetTopicOrder(report: report, syllabus: plan.content.syllabus),
                       "worksheet topic order reads the diagnostic only")
    }

    private func planningPriorities(_ plan: Plan) throws -> [PublicTopicPriority] {
        let snapshot = try XCTUnwrap(try TMUADiagnosticService.load(settings: plan.settings, in: plan.context))
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: plan.content.syllabus)
        let evidence = try TMUAProgrammeService.gatherEvidence(settings: plan.settings, snapshot: snapshot, in: plan.context)
        let input = TMUAProgrammeService.planningInput(settings: plan.settings, content: plan.content, report: report,
            evidence: evidence, start: today, examDate: plan.programme.examDateSnapshot, weeklyMinutes: 300,
            excludedQuestionIDs: [], refinement: nil, calendar: calendar)
        return try PublicPlanningEngine.generate(input).priorities
    }

    // MARK: Revisits, weighting and time

    /// A question marked incorrect comes back once in a later worksheet, at least a week on, and says
    /// so; a question marked correct does not; and it never comes back a second time.
    func testSelfMarkedMistakesComeBackOnce() throws {
        let plan = try plan(days: 90)
        let task = try XCTUnwrap(try worksheets(plan).first)
        let ids = TMUAProgrammeService.worksheetQuestionIDs(task.sourceID)
        try record(.incorrect, ids[0], in: task, plan)
        try record(.correct, ids[1], in: task, plan)
        try TMUAProgrammeService.finishWorksheet(task, settings: plan.settings, at: today, in: plan.context)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func revisits(onDay offset: Int, returnedOnDay: Int? = nil, plannedNow: Bool = false) throws -> Set<String> {
            var sheets: [(questions: [String], date: Date, active: Bool)] = [(ids, today, false)]
            if let returned = returnedOnDay { sheets.append(([ids[0]], day(returned), false)) }
            if plannedNow { sheets.append(([ids[0]], day(offset + 2), true)) }
            return TMUAProgrammeService.worksheetRevisits(logs: try logs(plan), worksheets: sheets, today: day(offset),
                                                          calendar: calendar)
        }
        XCTAssertEqual(try revisits(onDay: 3), [], "not within a week")
        XCTAssertEqual(try revisits(onDay: 8), [ids[0]], "the incorrect one only")
        XCTAssertEqual(try revisits(onDay: 8, plannedNow: true), [], "not while it is already planned again")
        XCTAssertEqual(try revisits(onDay: 30, returnedOnDay: 9), [], "after it has come back once, never again")

        // A mistake recorded in Practice, outside any worksheet, also comes back once only.
        let outside = try XCTUnwrap(plan.catalogue.entries.first { $0.answerMode == .selfMarked && !ids.contains($0.id) })
        plan.context.insert(TMUAResourceLog(profileSettingsID: plan.settings.id, sourceID: outside.sourceID ?? "",
                                            questionID: outside.id, outcome: .incorrect, recordedAt: today))
        try plan.context.save()
        let outsideNow = TMUAProgrammeService.worksheetRevisits(logs: try logs(plan), worksheets: [], today: day(8), calendar: calendar)
        XCTAssertTrue(outsideNow.contains(outside.id))
        let outsideAfter = TMUAProgrammeService.worksheetRevisits(logs: try logs(plan),
            worksheets: [([outside.id], day(9), false)], today: day(30), calendar: calendar)
        XCTAssertFalse(outsideAfter.contains(outside.id), "a question first missed outside a worksheet returns once too")

        // In the candidates it leads its topic's queue, and the worksheet reason says so.
        let topic = try XCTUnwrap(plan.catalogue.entry(ids[0])?.topicKey)
        let sheets = TMUAProgrammeService.worksheetCandidates(plan.catalogue.entries, topicOrder: [topic],
            excluded: Set(ids), excludedSources: [], size: 3, revisits: [ids[0]])
        XCTAssertEqual(sheets.first?.questions.first, ids[0])
        XCTAssertTrue(TMUAProgrammeService.worksheetReason(topic: "Algebra", count: 3, revisits: 1)
            .contains("One question you marked incorrect or partly right before comes back once"))

        // Through a real refresh a week later, any worksheet that brings it back says so.
        try TMUAProgrammeService.generateOrRefresh(settings: plan.settings, content: plan.content,
            today: calendar.date(byAdding: .day, value: 8, to: today)!, calendar: calendar, resourceSessions: true,
            catalogue: plan.catalogue, in: plan.context)
        for sheet in try worksheets(plan) where sheet.completedAt == nil
        && TMUAProgrammeService.worksheetQuestionIDs(sheet.sourceID).contains(ids[0]) {
            XCTAssertTrue(sheet.reason.contains("marked incorrect or partly right before"), sheet.reason)
        }
        XCTAssertFalse(try worksheets(plan).contains { $0.completedAt == nil
            && TMUAProgrammeService.worksheetQuestionIDs($0.sourceID).contains(ids[1]) }, "a question marked correct stays done")
    }

    func testWeakDiagnosticTopicsGetTwoWorksheetsPerRound() throws {
        let content = try TMUAFixtures.standardContext()
        let catalogue = try TMUAPlannerDeterminismTests.syntheticCatalogue(content: content)
        let order = TMUAProgrammeService.worksheetTopicOrder(report: nil, syllabus: content.syllabus)
        let plain = TMUAProgrammeService.worksheetCandidates(catalogue.entries, topicOrder: order, excluded: [],
                                                             excludedSources: [], size: 3)
        // A topic with enough questions for two worksheets.
        let counts = Dictionary(plain.map { ($0.topic, 1) }, uniquingKeysWith: +)
        let weak = try XCTUnwrap(order.first { (counts[$0] ?? 0) >= 2 })
        let weighted = TMUAProgrammeService.worksheetCandidates(catalogue.entries, topicOrder: order, excluded: [],
                                                                excludedSources: [], size: 3, weakTopics: [weak])
        let first = try XCTUnwrap(weighted.firstIndex { $0.topic == weak })
        XCTAssertEqual(weighted[first + 1].topic, weak, "a weak topic's second worksheet follows at once, in the same round")
        let plainSecond = try XCTUnwrap(plain.indices.filter { plain[$0].topic == weak }.dropFirst().first)
        XCTAssertLessThan(first + 1, plainSecond, "earlier than plain round-robin would give it")
        XCTAssertEqual(Set(weighted.flatMap(\.questions)).count, weighted.flatMap(\.questions).count)
    }

    /// Worksheet time follows its questions (estimated by level), stays within the day and the
    /// session cap, and a worksheet never exceeds eight questions.
    func testWorksheetMinutesFollowQuestionsAndStayWithinTheDay() throws {
        for (weekly, session) in [(180, nil), (300, 40), (720, nil)] as [(Int, Int?)] {
            let plan = try plan(days: 120, weekly: weekly, session: session)
            let tasks = try PublicProgrammeService.tasks(for: plan.programme, in: plan.context).filter(\.isActive)
            let cap = min(weekly / 7, session ?? .max)
            for (day, dayTasks) in Dictionary(grouping: tasks, by: { calendar.startOfDay(for: $0.scheduledDate) }) {
                XCTAssertLessThanOrEqual(dayTasks.reduce(0) { $0 + $1.allocatedMinutes }, cap + 1, "\(weekly): \(day)")
            }
            for sheet in tasks where sheet.activity == .topicWorksheet {
                let ids = TMUAProgrammeService.worksheetQuestionIDs(sheet.sourceID)
                XCTAssertTrue((2...8).contains(ids.count))
                let estimate = ids.reduce(0) {
                    $0 + TMUAProgrammeService.worksheetQuestionMinutes(difficulty: plan.catalogue.entry($1)?.difficulty)
                }
                XCTAssertEqual(sheet.allocatedMinutes, estimate, "minutes are the questions' estimates")
            }
        }
        XCTAssertEqual(TMUAProgrammeService.worksheetQuestionMinutes(difficulty: 1), 5)
        XCTAssertEqual(TMUAProgrammeService.worksheetQuestionMinutes(difficulty: nil), 6)
        XCTAssertEqual(TMUAProgrammeService.worksheetQuestionMinutes(difficulty: 5), 10)
    }

    // MARK: Evidence hierarchy in the engine

    /// A diagnostic answer sets a topic's evidence level once; it is not counted again as "recent
    /// practice". A recent practice miss does raise the topic.
    func testDiagnosticAnswersAreNotCountedTwiceAsRecentPractice() throws {
        func question(_ id: String, topic: String, outcome: QuestionAttemptOutcome?, practice: Bool) -> PublicPlanningQuestion {
            PublicPlanningQuestion(id: id, sourceID: "s", topic: topic, difficulty: 3, diagnostic: outcome != nil && !practice,
                latestOutcome: outcome, latestAttemptDate: outcome == nil ? nil : today, reviewFlag: false,
                hasSolution: true, outcomeFromPractice: practice)
        }
        let questions = (0..<6).map { question("a\($0)", topic: "Algebra", outcome: $0 < 3 ? .incorrect : nil, practice: false) }
            + (0..<6).map { question("b\($0)", topic: "Logic", outcome: nil, practice: false) }
        var options = PublicPlanningOptions()
        options.recentRankFromPracticeOnly = true
        func rank(_ questions: [PublicPlanningQuestion], _ topic: String) throws -> Int {
            let input = PublicPlanningInput(exam: .tmua, startDate: today,
                examDate: calendar.date(byAdding: .day, value: 30, to: today)!, weeklyMinutes: 300,
                availability: AppSettings.publicDefaultAvailability, diagnosticSignals: [], questions: questions,
                papers: [], calendar: calendar, options: options)
            return try XCTUnwrap(try PublicPlanningEngine.generate(input).priorities.first { $0.topic == topic }).rank
        }
        XCTAssertEqual(try rank(questions, "Algebra"), try rank(questions, "Logic"), "diagnostic misses are not recent practice")
        let practised = questions.map { $0.id == "a0" ? question("a0", topic: "Algebra", outcome: .incorrect, practice: true) : $0 }
        XCTAssertGreaterThan(try rank(practised, "Algebra"), try rank(practised, "Logic"))
    }

    // MARK: Refresh summary

    func testRefreshSummaryReportsTopicsThatLosePractice() {
        let summary = PublicProgrammeService.refreshSummary(before: ["Algebra", "Algebra", "Logic"],
                                                            after: ["Logic", "Logic"], completed: 3, frozen: 1)
        XCTAssertTrue(summary.contains("More Logic (+1)"), summary)
        XCTAssertTrue(summary.contains("less Algebra (-2)"), summary)
    }

    func testRefreshAfterDroppingDaysCanReportLessPractice() throws {
        let plan = try plan(days: 45)
        try PublicPreparationService.saveFlexibleTMUAProfile(examDate: plan.programme.examDateSnapshot, weeklyMinutes: 120,
            availability: TMUAPlannerDeterminismTests.availability([.monday, .thursday]), sessionMinutes: nil, today: today,
            calendar: calendar, settings: plan.settings, in: plan.context)
        try TMUAProgrammeService.generateOrRefresh(settings: plan.settings, content: plan.content, today: today,
            calendar: calendar, resourceSessions: true, catalogue: plan.catalogue, in: plan.context)
        XCTAssertTrue(plan.programme.refreshSummary?.contains("less ") == true, plan.programme.refreshSummary ?? "nil")
    }

    // MARK: Classification provenance

    func testTopicProvenanceSeparatesOutsideUnclassifiedAndDrafts() throws {
        let syllabus = try TMUAFixtures.syllabus
        let registry = try XCTUnwrap(TMUAResourceRegistry.bundled())
        let mock = try XCTUnwrap(registry.providers.first { $0.key == "jzmaths" })
        func question(_ id: String, _ topic: String, part: String? = nil, fit: String? = nil) -> TMUAResourceQuestion {
            var question = TMUAResourceQuestion(id: id, label: "1", page: 2, topic: topic, difficultyLabel: "Core",
                                                paperFit: fit, format: "Multiple choice", autoMarkedItemID: nil, solutionPage: 3)
            question.paperPart = part
            return question
        }
        let solutions = [TMUAResourceSource.SolutionFile(title: "Worked solutions", resourceName: "s", resourceExtension: "pdf", isVideo: false)]
        let source = TMUAResourceSource(id: "SET-A", title: "Set A", provider: mock, family: "JZ Maths TMUA Mock",
            paperLabel: "Set A", year: 2026, questions: [
                question("Q-MAPPED", "Integration", part: "Paper 2"), question("Q-GAMES", "Games, invariants & strategy"),
                question("Q-DRAFT", "Mixed / problem solving", fit: "Paper 1 / Both"),
                question("Q-UNKNOWN", "Mixed / problem solving"), question("Q-BADDRAFT", "Mixed / problem solving")],
            solutions: solutions, access: .studyCopy, labelCorrection: nil)
        var reconciliation = TMUACatalogueReconciliation(version: 1, reviewedOn: "2026-10-29",
            legacyTopicMap: ["Integration": "integration"], duplicates: [], documents: [])
        reconciliation.legacyTopicsOutside = ["Games, invariants & strategy"]
        reconciliation.legacyTopicsUnclassified = ["Mixed / problem solving"]
        reconciliation.topicDrafts = [.init(question: "Q-DRAFT", topic: "algebra", strand: "polynomials", confidence: "high"),
                                      .init(question: "Q-BADDRAFT", topic: "not-a-topic", strand: nil, confidence: "high")]
        let catalogue = TMUAQuestionCatalogue.build(sources: [source], items: [], allVersions: [], syllabus: syllabus,
                                                    reconciliation: reconciliation, distribution: .internal)
        let mapped = try XCTUnwrap(catalogue.entry("Q-MAPPED"))
        XCTAssertEqual(mapped.topicBasis, .libraryIndex)
        XCTAssertEqual(mapped.paperFit, .paper2, "the question's own paper part decides in a combined file")
        XCTAssertEqual(mapped.paperFitBasis, .appearsInPaper)
        XCTAssertEqual(catalogue.entry("Q-GAMES")?.topicBasis, .outsideSpecification)
        let draft = try XCTUnwrap(catalogue.entry("Q-DRAFT"))
        XCTAssertEqual(draft.topicKey, "algebra")
        XCTAssertEqual(draft.strandKey, "polynomials")
        XCTAssertEqual(draft.topicBasis, .provisionalDraft)
        XCTAssertEqual(draft.topicTitle(syllabus), "Algebra (provisional)")
        XCTAssertEqual(catalogue.entry("Q-UNKNOWN")?.topicBasis, .unclassified)
        XCTAssertNil(catalogue.entry("Q-BADDRAFT")?.topicKey, "a draft naming an unknown topic is ignored")
        XCTAssertEqual(catalogue.entry("Q-UNKNOWN")?.topicTitle(syllabus), "Topic not yet classified")

        // Filters keep "outside" and "not yet classified" apart; worksheets use neither.
        XCTAssertEqual(catalogue.entries.filter { TMUACataloguePracticeList.matchesTopic($0, TMUAPracticeFilters.outside) }.map(\.id), ["Q-GAMES"])
        XCTAssertEqual(Set(catalogue.entries.filter { TMUACataloguePracticeList.matchesTopic($0, TMUAPracticeFilters.unclassified) }.map(\.id)),
                       ["Q-UNKNOWN", "Q-BADDRAFT"])
        let sheets = TMUAProgrammeService.worksheetCandidates(catalogue.entries, topicOrder: syllabus.topics.map(\.key),
                                                              excluded: [], excludedSources: [], size: 1)
        XCTAssertTrue(Set(sheets.flatMap(\.questions)).isDisjoint(with: ["Q-GAMES", "Q-UNKNOWN", "Q-BADDRAFT"]))
    }

    /// The bundled reconciliation: only syllabus topics, outside and unclassified kept apart, and
    /// drafts only for questions the index left unclassified.
    func testBundledDraftsAreValidAndOnlyFillUnknownTopics() throws {
        let reconciliation = try XCTUnwrap(TMUACatalogueReconciliation.bundled())
        let syllabus = try TMUAFixtures.syllabus
        let drafts = try XCTUnwrap(reconciliation.topicDrafts)
        XCTAssertFalse(drafts.isEmpty)
        XCTAssertTrue(drafts.allSatisfy { syllabus.topic($0.topic) != nil })
        XCTAssertEqual(Set(drafts.map(\.question)).count, drafts.count)
        XCTAssertTrue(Set(reconciliation.legacyTopicsOutside ?? []).isDisjoint(with: reconciliation.legacyTopicsUnclassified ?? []))
        XCTAssertTrue(reconciliation.topicDraftBasis?.contains("Not reviewed by a person") == true)
        let manifest = try AdmissionsManifest.bundled()
        let index = Dictionary(manifest.questions.map { ($0.externalQuestionID, $0.primaryTopic) }, uniquingKeysWith: { first, _ in first })
        XCTAssertTrue(drafts.allSatisfy { (reconciliation.legacyTopicsUnclassified ?? []).contains(index[$0.question] ?? "") })
    }

    // MARK: Practice status, Saved identities and filters

    func testStatusFiltersAndSavedIdentityAcrossAliases() throws {
        let plan = try plan()
        let item = try XCTUnwrap(plan.content.eligibleItems.first)
        let wrong = try XCTUnwrap(item.options.first { $0.id != item.correctOptionId }?.id)
        try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: wrong, seconds: 30, task: nil,
                                                settings: plan.settings, at: today, in: plan.context)
        // A question flagged under an earlier identity (a merged reprint's ID) is still flagged.
        let native = try XCTUnwrap(plan.catalogue.entry(item.stableId))
        let selfMarked = try XCTUnwrap(plan.catalogue.entries.first { $0.answerMode == .selfMarked })
        let aliased = TMUACatalogueEntry(id: selfMarked.id, aliases: ["OLD-REPRINT-ID"], origin: selfMarked.origin,
            sourceID: selfMarked.sourceID, sourceTitle: selfMarked.sourceTitle, provider: selfMarked.provider,
            label: selfMarked.label, page: selfMarked.page, paperFit: selfMarked.paperFit, topicKey: selfMarked.topicKey,
            legacyTopic: selfMarked.legacyTopic, difficulty: selfMarked.difficulty, difficultyProvenance: "",
            format: selfMarked.format, presentation: selfMarked.presentation, answerMode: selfMarked.answerMode, item: nil,
            versionKeys: [], solutionPage: nil, solutionResource: nil, hasSolution: true, rights: selfMarked.rights,
            publication: selfMarked.publication, reviewStatus: "", attribution: "", sourceURL: nil, fingerprint: "",
            variantOf: nil, alsoAppearsIn: [])
        try TMUAProgrammeService.setReviewFlag(true, itemStableID: "OLD-REPRINT-ID", settings: plan.settings, in: plan.context)
        plan.context.insert(TMUAResourceLog(profileSettingsID: plan.settings.id, sourceID: selfMarked.sourceID ?? "",
                                            questionID: "OLD-REPRINT-ID", outcome: .attempted, recordedAt: today))
        try plan.context.save()
        let progress = TMUACatalogueProgress(settings: plan.settings,
            attempts: try plan.context.fetch(FetchDescriptor<TMUAPracticeAttempt>()), logs: try logs(plan),
            flags: try plan.context.fetch(FetchDescriptor<TMUAReviewFlag>()))
        XCTAssertTrue(progress.matches(native, .previouslyIncorrect))
        XCTAssertTrue(progress.latest(native)?.markedByRevisr == true)
        XCTAssertTrue(progress.isFlagged(aliased))
        XCTAssertTrue(progress.matches(aliased, .notYetChecked))
        XCTAssertFalse(progress.latest(aliased)?.markedByRevisr ?? true)
        let pool = TMUACataloguePracticeList.pool(plan.catalogue, reserved: [])
        var filters = TMUAPracticeFilters()
        filters.status = .previouslyIncorrect
        XCTAssertEqual(TMUACataloguePracticeList.filter(pool, filters, progress: progress, catalogue: plan.catalogue).map(\.id),
                       [native.id])
        filters = TMUAPracticeFilters()
        filters.marking = TMUACatalogueEntry.AnswerMode.selfMarked.rawValue
        let ordered = TMUACataloguePracticeList.filter(pool, filters, progress: progress, catalogue: plan.catalogue)
        XCTAssertEqual(ordered.map { plan.catalogue.position(of: $0.id) }, ordered.map { plan.catalogue.position(of: $0.id) }.sorted(),
                       "practice lists questions in library order")
    }

    func testReservedDiagnosticQuestionsAreHiddenAndNeverOfferedWhole() throws {
        let plan = try plan()
        let item = try XCTUnwrap(plan.content.eligibleItems.first)
        let pool = TMUACataloguePracticeList.pool(plan.catalogue, reserved: [item.stableId])
        XCTAssertFalse(pool.contains { $0.item?.stableId == item.stableId })
    }

    // MARK: Performance (simulator Debug build; indicative only)

    func testPrintPerformanceOfCatalogueAndPractice() throws {
        guard let content = TMUAContentStore.context() else { throw XCTSkip("no bundled content") }
        @discardableResult
        func time(_ label: String, _ body: () throws -> Void) rethrows -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            print(String(format: "PERF %@ %.1f ms", label, ms))
            return ms
        }
        var catalogue: TMUAQuestionCatalogue?
        _ = time("catalogue build (bundled, uncached)") {
            let sources = TMUAResourceCatalogue.build(manifest: try! AdmissionsManifest.bundled(),
                solutions: try? AdmissionsSolutionsManifest.bundled(), registry: TMUAResourceRegistry.bundled()!,
                distribution: content.distribution, items: content.eligibleItems,
                isBundled: { SourceLibraryServiceLookup.paperExists($0) }, supplement: TMUACatalogueReconciliation.bundled())
            catalogue = TMUAQuestionCatalogue.build(sources: sources, items: content.eligibleItems,
                allVersions: content.bank.items, syllabus: content.syllabus,
                reconciliation: TMUACatalogueReconciliation.bundled(), distribution: content.distribution)
        }
        let built = try XCTUnwrap(catalogue)
        let container = try TMUAFixtures.memoryContainer()
        let settings = try TMUAFixtures.profile(in: container.mainContext, today: today, id: TMUAFixtures.pinnedProfileID)
        // A busy student: a result for every fifth question and a flag on every eleventh.
        let logs = built.practicable.enumerated().compactMap { offset, entry -> TMUAResourceLog? in
            guard offset % 5 == 0, entry.item == nil else { return nil }
            return TMUAResourceLog(profileSettingsID: settings.id, sourceID: entry.sourceID ?? "", questionID: entry.id,
                                   outcome: offset % 2 == 0 ? .incorrect : .correct, recordedAt: today)
        }
        let flags = built.practicable.enumerated().compactMap { offset, entry -> TMUAReviewFlag? in
            offset % 11 == 0 ? TMUAReviewFlag(profileSettingsID: settings.id, itemStableID: entry.id, isFlagged: true, at: today) : nil
        }
        var progress: TMUACatalogueProgress?
        _ = time("progress index (\(logs.count) results, \(flags.count) flags)") {
            progress = TMUACatalogueProgress(settings: settings, attempts: [], logs: logs, flags: flags)
        }
        let pool = TMUACataloguePracticeList.pool(built, reserved: [])
        var worst = 0.0
        for status in TMUACatalogueProgress.Status.allCases {
            var filters = TMUAPracticeFilters()
            filters.status = status
            worst = max(worst, time("practice filter \(status.rawValue) over \(pool.count)") {
                _ = TMUACataloguePracticeList.filter(pool, filters, progress: progress!, catalogue: built)
            })
        }
        _ = time("worksheet candidates") {
            _ = TMUAProgrammeService.worksheetCandidates(built.entries,
                topicOrder: TMUAProgrammeService.worksheetTopicOrder(report: nil, syllabus: content.syllabus),
                excluded: [], excludedSources: [], size: 8)
        }
        _ = time("identity lookups x2851") { for entry in built.entries { _ = built.entry(entry.id) } }
        // The heaviest plan: 180 days at 12 hours a week, with library sessions, then a refresh.
        let planContainer = try TMUAFixtures.memoryContainer()
        let planContext = planContainer.mainContext
        let student = try TMUAFixtures.profile(in: planContext, today: today, examInDays: 180, weeklyMinutes: 720,
            availability: TMUAPlannerDeterminismTests.availability(TMUAPlannerDeterminismTests.everyDay),
            id: TMUAFixtures.pinnedProfileID)
        let snapshot = try TMUADiagnosticService.create(settings: student, length: .balanced, content: content,
                                                        at: today, in: planContext)
        try TMUAFixtures.completeAll(snapshot, at: today, in: planContext)
        let generate = try time("generate 180-day 12h plan (bundled, with library)") {
            try TMUAProgrammeService.generateOrRefresh(settings: student, content: content, today: today,
                calendar: calendar, resourceSessions: true, catalogue: built, in: planContext)
        }
        let refresh = try time("refresh the same plan") {
            try TMUAProgrammeService.generateOrRefresh(settings: student, content: content, today: today,
                calendar: calendar, resourceSessions: true, catalogue: built, in: planContext)
        }
        XCTAssertLessThan(max(generate, refresh), 30_000)
        XCTAssertLessThan(worst, 1_000, "filtering stays well under a second even in a Debug simulator build")
    }
}
