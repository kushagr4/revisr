import SwiftData
import XCTest
@testable import revisr

@MainActor
final class DiagnosticWorkflowTests: XCTestCase {
    private let examDate = Date(timeIntervalSince1970: 1_830_000_000)

    func testSelectionForAllExamsUsesDistinctEligibleCompletePapers() throws {
        let fixture = try freshFixture()
        for exam in PublicExamKind.allCases {
            let selected = try selections(exam: exam, in: fixture.context)
            XCTAssertEqual(selected.count, 2)
            XCTAssertEqual(Set(selected.map(\.source.stableSourceID)).count, 2)
            XCTAssertEqual(Set(selected.flatMap(\.questions).map(\.externalQuestionID)).count,
                           2 * DiagnosticPaperPolicy.forExam(exam).questionCount)
            XCTAssertTrue(selected.flatMap(\.questions).allSatisfy {
                $0.protection == .none && $0.scheduleEligible && $0.validityState == .usable
            })
            XCTAssertTrue(selected.allSatisfy { SourceLibraryService.bundledURL(for: $0.source) != nil })
            if exam == .bmo {
                XCTAssertTrue(selected.allSatisfy { $0.solution == nil })
                XCTAssertEqual(selected.first?.policy.maximumMarksPerQuestion, 10)
                XCTAssertEqual(selected.first?.policy.durationMinutes, 210)
            } else {
                XCTAssertTrue(selected.allSatisfy { $0.solution != nil })
            }
        }
        XCTAssertEqual(try selections(exam: .tmua, in: fixture.context).map(\.source.stableSourceID),
                       DiagnosticPaperPolicy.forExam(.tmua).sourceIDs)
    }

    func testSelectorRejectsProtectedQuestionAndMissingVerifiedSolution() throws {
        let fixture = try freshFixture()
        let selected = try selections(exam: .tmua, in: fixture.context)
        let question = try XCTUnwrap(selected.first?.questions.first)
        question.protection = .protectedFromAutomaticSelection
        XCTAssertThrowsError(try selections(exam: .tmua, in: fixture.context)) {
            XCTAssertEqual($0 as? DiagnosticSelectionError, .ineligibleQuestion(question.externalQuestionID))
        }
        question.protection = .none
        let solution = try XCTUnwrap(selected.first?.solution)
        solution.isVerified = false
        XCTAssertThrowsError(try selections(exam: .tmua, in: fixture.context)) {
            XCTAssertEqual($0 as? DiagnosticSelectionError, .missingSolution(selected[0].source.stableSourceID))
        }
    }

    func testDraftSubmitMarkAndRelaunchNeverCreateHistoricalAttempt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Diagnostic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")
        let firstID: String
        let responseID: String
        do {
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try SeedDataService.bootstrapForLaunch(in: context)
            try configure(.tmua, settings: settings, in: context)
            let selected = try selections(exam: .tmua, in: context)
            let assessment = try DiagnosticAssessmentService.loadOrCreate(
                settings: settings, selection: selected, in: context
            )
            let papers = try diagnosticPapers(assessment, in: context)
            let first = papers[0]
            firstID = first.stableID
            let response = try XCTUnwrap(responses(for: first, in: context).first)
            responseID = response.stableID
            XCTAssertThrowsError(try DiagnosticAssessmentService.start(papers[1], in: context))
            try DiagnosticAssessmentService.start(first, at: Date(timeIntervalSince1970: 100), in: context)
            try DiagnosticAssessmentService.recordChoice("A", response: response, paper: first, in: context)
            try DiagnosticAssessmentService.pause(first, at: Date(timeIntervalSince1970: 130), in: context)
            XCTAssertEqual(first.accumulatedSeconds, 30)
            XCTAssertNil(first.runningSince)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), 0)
        }

        let reopened = try AppContainer.make(storeURL: store)
        let context = reopened.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let selected = try selections(exam: .tmua, in: context)
        let assessment = try DiagnosticAssessmentService.loadOrCreate(
            settings: settings, selection: selected, in: context
        )
        let papers = try diagnosticPapers(assessment, in: context)
        let first = papers[0]
        let response = try XCTUnwrap(responses(for: first, in: context).first { $0.stableID == responseID })
        XCTAssertEqual(first.stableID, firstID)
        XCTAssertEqual(first.status, .answering)
        XCTAssertEqual(response.selectedOption, "A")
        try DiagnosticAssessmentService.resume(first, at: Date(timeIntervalSince1970: 200), in: context)
        try DiagnosticAssessmentService.submitAnswers(first, at: Date(timeIntervalSince1970: 220), in: context)
        XCTAssertEqual(first.accumulatedSeconds, 50)
        XCTAssertThrowsError(try DiagnosticAssessmentService.recordChoice("B", response: response, paper: first, in: context))
        try DiagnosticAssessmentService.recordMarking(.correct, response: response, paper: first, in: context)
        try DiagnosticAssessmentService.complete(first, settings: settings, in: context)
        XCTAssertThrowsError(try DiagnosticAssessmentService.complete(first, settings: settings, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiagnosticAssessment>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiagnosticPaperRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiagnosticResponse>()), 40)
        try DiagnosticAssessmentService.start(papers[1], in: context)
        try DiagnosticAssessmentService.submitAnswers(papers[1], in: context)
        try DiagnosticAssessmentService.complete(papers[1], settings: settings, in: context)
        XCTAssertNotNil(assessment.completedAt)
        XCTAssertEqual(settings.publicOnboardingStage, .diagnosticsComplete)
    }

    func testAbruptRelaunchPausesOrphanedTimerWithoutCountingOfflineTime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Diagnostic-Timer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")
        do {
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try SeedDataService.bootstrapForLaunch(in: context)
            try configure(.tmua, settings: settings, in: context)
            let selected = try selections(exam: .tmua, in: context)
            let assessment = try DiagnosticAssessmentService.loadOrCreate(
                settings: settings, selection: selected, in: context
            )
            let paper = try diagnosticPapers(assessment, in: context)[0]
            try DiagnosticAssessmentService.start(paper, at: Date(timeIntervalSince1970: 100), in: context)
            XCTAssertNotNil(paper.runningSince)
        }
        let reopened = try AppContainer.make(storeURL: store)
        let context = reopened.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let selected = try selections(exam: .tmua, in: context)
        let assessment = try DiagnosticAssessmentService.loadOrCreate(
            settings: settings, selection: selected, in: context
        )
        let paper = try diagnosticPapers(assessment, in: context)[0]
        XCTAssertEqual(paper.status, .answering)
        XCTAssertNil(paper.runningSince)
        XCTAssertEqual(paper.accumulatedSeconds, 0)
    }

    func testSMCOfficialStylePointsUseOnlyConfirmedSelfMarking() throws {
        let fixture = try freshFixture()
        try configure(.smc, settings: fixture.settings, in: fixture.context)
        let selected = try selections(exam: .smc, in: fixture.context)
        let assessment = try DiagnosticAssessmentService.loadOrCreate(
            settings: fixture.settings, selection: selected, in: fixture.context
        )
        let paper = try diagnosticPapers(assessment, in: fixture.context)[0]
        let rows = try responses(for: paper, in: fixture.context)
        try DiagnosticAssessmentService.start(paper, in: fixture.context)
        try DiagnosticAssessmentService.recordChoice("A", response: rows[0], paper: paper, in: fixture.context)
        try DiagnosticAssessmentService.recordChoice("B", response: rows[1], paper: paper, in: fixture.context)
        try DiagnosticAssessmentService.submitAnswers(paper, in: fixture.context)
        let partial = DiagnosticAnalysis.report(exam: .smc, papers: [paper], responses: rows, questions: selected[0].questions)
        XCTAssertTrue(partial.papers[0].displayScore.contains("unassessed"))
        try DiagnosticAssessmentService.recordMarking(.correct, response: rows[0], paper: paper, in: fixture.context)
        try DiagnosticAssessmentService.recordMarking(.incorrect, response: rows[1], paper: paper, in: fixture.context)
        let finished = DiagnosticAnalysis.report(exam: .smc, papers: [paper], responses: rows, questions: selected[0].questions)
        XCTAssertEqual(finished.papers[0].displayScore, "28 / 125 self-marked SMC points")
        XCTAssertEqual(finished.papers[0].answeredCount, 2)
        XCTAssertEqual(finished.papers[0].assessedCount, 2)
    }

    func testBMOSelfEstimatedMarksRemainSeparateFromExaminerScore() throws {
        let fixture = try freshFixture()
        try configure(.bmo, settings: fixture.settings, in: fixture.context)
        let selected = try selections(exam: .bmo, in: fixture.context)
        let assessment = try DiagnosticAssessmentService.loadOrCreate(
            settings: fixture.settings, selection: selected, in: fixture.context
        )
        let paper = try diagnosticPapers(assessment, in: fixture.context)[0]
        let rows = try responses(for: paper, in: fixture.context)
        try DiagnosticAssessmentService.start(paper, in: fixture.context)
        try DiagnosticAssessmentService.recordProofAttempt(true, response: rows[0], paper: paper, in: fixture.context)
        try DiagnosticAssessmentService.recordNotes("Proof on paper", response: rows[0], paper: paper, in: fixture.context)
        try DiagnosticAssessmentService.submitAnswers(paper, in: fixture.context)
        XCTAssertThrowsError(try DiagnosticAssessmentService.recordEstimatedMarks(11, response: rows[0], paper: paper, in: fixture.context))
        try DiagnosticAssessmentService.recordEstimatedMarks(7, response: rows[0], paper: paper, in: fixture.context)
        XCTAssertThrowsError(try DiagnosticAssessmentService.recordEstimatedMarks(5, response: rows[1], paper: paper, in: fixture.context))
        let report = DiagnosticAnalysis.report(exam: .bmo, papers: [paper], responses: rows, questions: selected[0].questions)
        XCTAssertEqual(report.papers[0].displayScore, "7 / 60 self-estimated marks")
        XCTAssertTrue(report.papers[0].provenance.contains("Self-estimate only"))
        XCTAssertEqual(rows[0].notes, "Proof on paper")
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<QuestionAttempt>()), 0)
    }

    func testTopicSignalNeedsRepeatedEvidenceAcrossPapers() throws {
        let fixture = try freshFixture()
        let selected = try selections(exam: .tmua, in: fixture.context)
        let geometry = selected.flatMap(\.questions).filter { $0.primaryTopic == "Geometry & mensuration" }
        XCTAssertGreaterThanOrEqual(geometry.count, 4)
        let papers = [
            DiagnosticPaperRecord(stableID: "P1", assessmentID: "A", sourceID: selected[0].source.stableSourceID,
                                  ordinal: 1, scoringProvenance: .selfMarkedWithPDF),
            DiagnosticPaperRecord(stableID: "P2", assessmentID: "A", sourceID: selected[1].source.stableSourceID,
                                  ordinal: 2, scoringProvenance: .selfMarkedWithPDF)
        ]
        let wrong = geometry.prefix(3).map { question -> DiagnosticResponse in
            let paperID = question.sourceDocument?.stableSourceID == papers[0].sourceID ? "P1" : "P2"
            let response = DiagnosticResponse(stableID: question.externalQuestionID, paperID: paperID,
                                              questionID: question.externalQuestionID)
            response.selectedOption = "A"
            response.marking = .incorrect
            return response
        }
        let oneWrong = DiagnosticAnalysis.report(exam: .tmua, papers: papers,
                                                 responses: [wrong[0]], questions: geometry)
        XCTAssertEqual(oneWrong.topics.first?.level, .insufficient)
        let four = Array(geometry.prefix(3)) + [try XCTUnwrap(geometry.first {
            $0.sourceDocument?.stableSourceID == papers[1].sourceID
        })]
        let fourRows = four.map { question -> DiagnosticResponse in
            let paperID = question.sourceDocument?.stableSourceID == papers[0].sourceID ? "P1" : "P2"
            let response = DiagnosticResponse(stableID: question.externalQuestionID, paperID: paperID,
                                              questionID: question.externalQuestionID)
            response.selectedOption = "A"
            response.marking = .incorrect
            return response
        }
        let report = DiagnosticAnalysis.report(exam: .tmua, papers: papers, responses: fourRows, questions: geometry)
        XCTAssertEqual(report.topics.first?.assessedCount, 4)
        XCTAssertEqual(report.topics.first?.level, .strongDifficulty)
    }

    func testChangingExaminationPreservesCompletedDiagnosticHistory() throws {
        let fixture = try freshFixture()
        try configure(.tmua, settings: fixture.settings, in: fixture.context)
        let tmuaSelection = try selections(exam: .tmua, in: fixture.context)
        let tmua = try DiagnosticAssessmentService.loadOrCreate(settings: fixture.settings,
                                                                 selection: tmuaSelection, in: fixture.context)
        try configure(.smc, settings: fixture.settings, in: fixture.context)
        let smcSelection = try selections(exam: .smc, in: fixture.context)
        let smc = try DiagnosticAssessmentService.loadOrCreate(settings: fixture.settings,
                                                                selection: smcSelection, in: fixture.context)
        XCTAssertNotEqual(tmua.stableID, smc.stableID)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<DiagnosticAssessment>()), 2)
        try configure(.tmua, settings: fixture.settings, in: fixture.context)
        XCTAssertEqual(try DiagnosticAssessmentService.loadOrCreate(settings: fixture.settings,
            selection: tmuaSelection, in: fixture.context).stableID, tmua.stableID)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<DiagnosticPaperRecord>()), 4)
    }

    private func freshFixture() throws -> (container: ModelContainer, context: ModelContext, settings: AppSettings) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        return (container, context, settings)
    }

    private func configure(_ exam: PublicExamKind, settings: AppSettings, in context: ModelContext) throws {
        try PublicPreparationService.saveProfile(
            exam: exam, examDate: examDate, weeklyMinutes: 600,
            availability: AppSettings.publicDefaultAvailability,
            today: Date(timeIntervalSince1970: 1_790_000_000),
            settings: settings, in: context
        )
    }

    private func selections(exam: PublicExamKind, in context: ModelContext) throws -> [DiagnosticPaperSelection] {
        try DiagnosticPaperSelector.select(
            exam: exam,
            sources: context.fetch(FetchDescriptor<SourceDocument>()),
            questions: context.fetch(FetchDescriptor<AdmissionsQuestion>()),
            solutions: context.fetch(FetchDescriptor<SolutionDocument>()),
            links: context.fetch(FetchDescriptor<QuestionSolutionLink>())
        )
    }

    private func diagnosticPapers(_ assessment: DiagnosticAssessment, in context: ModelContext) throws -> [DiagnosticPaperRecord] {
        try context.fetch(FetchDescriptor<DiagnosticPaperRecord>())
            .filter { $0.assessmentID == assessment.stableID }.sorted { $0.ordinal < $1.ordinal }
    }

    private func responses(for paper: DiagnosticPaperRecord, in context: ModelContext) throws -> [DiagnosticResponse] {
        try context.fetch(FetchDescriptor<DiagnosticResponse>())
            .filter { $0.paperID == paper.stableID }.sorted { $0.questionID < $1.questionID }
    }
}
