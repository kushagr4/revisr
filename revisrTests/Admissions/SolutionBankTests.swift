import PDFKit
import SwiftData
import XCTest
@testable import revisr

@MainActor
final class SolutionBankTests: XCTestCase {
    func testManifestIdentityCountsAndKnownHonestGaps() throws {
        let manifest = try AdmissionsSolutionsManifest.bundled()

        XCTAssertEqual(manifest.formatVersion, 2)
        XCTAssertEqual(manifest.documents.count, 120)
        XCTAssertEqual(Set(manifest.documents.map(\.stableSolutionID)).count, 120)
        XCTAssertEqual(manifest.links.count, 2_364)
        XCTAssertEqual(Set(manifest.links.map(\.stableLinkID)).count, 2_364)
        XCTAssertEqual(manifest.documents.filter { $0.resourceContainer == .solutionBundle }.count, 106)
        XCTAssertEqual(manifest.documents.filter { $0.mediaKind == .video }.count, 8)
        XCTAssertEqual(manifest.documents.filter { $0.sourceID == nil }.count, 10)
        let canonicalFilenames = Set(manifest.documents.map(\.originalFilename))
        XCTAssertFalse(canonicalFilenames.contains("IMC-2021-Solutions (2).pdf"))
        XCTAssertFalse(canonicalFilenames.contains("TMUA-early-specimen-paper-1-worked-answers.pdf"))
        XCTAssertFalse(canonicalFilenames.contains("TMUA-early-specimen-paper-2-worked-answers.pdf"))
        XCTAssertFalse(manifest.links.contains { $0.questionID == "MAT-2010-Q06" })
        XCTAssertFalse(manifest.links.contains { $0.questionID == "MAT-2011-Q07" })
    }

    func testImportIsIncrementalAndIdempotent() throws {
        let fixture = try makeFixture()
        let before = try counts(in: fixture.context)
        let firstIDs = Set(try fixture.context.fetch(FetchDescriptor<SolutionDocument>()).map(\.stableSolutionID))

        try AdmissionsSolutionsImportService.seedBundledManifestIfNeeded(in: fixture.context)
        try AdmissionsSolutionsImportService.seedBundledManifestIfNeeded(in: fixture.context)

        XCTAssertEqual(try counts(in: fixture.context), before)
        XCTAssertEqual(Set(try fixture.context.fetch(FetchDescriptor<SolutionDocument>()).map(\.stableSolutionID)), firstIDs)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testEverySolutionDocumentResolvesToReadableLocalResource() throws {
        let fixture = try makeFixture()
        let documents = try fixture.context.fetch(FetchDescriptor<SolutionDocument>())
        let audit = SolutionLibraryService.audit(documents: documents)

        XCTAssertEqual(audit.expectedCount, 120)
        XCTAssertEqual(audit.resolvedCount, 120)
        XCTAssertTrue(audit.isComplete)
        for document in documents {
            let url = try XCTUnwrap(SolutionLibraryService.bundledURL(for: document))
            if document.mediaKind == .video {
                XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0, 0)
            } else {
                XCTAssertGreaterThan(try XCTUnwrap(PDFDocument(url: url)).pageCount, 0)
            }
        }
    }

    func testComputedCoverageSeparatesAvailablePartialAndPending() throws {
        let fixture = try makeFixture()
        let sources = try fixture.context.fetch(FetchDescriptor<SourceDocument>()).filter { $0.questionUnitCount > 0 }
        let documents = try fixture.context.fetch(FetchDescriptor<SolutionDocument>())
        let links = try fixture.context.fetch(FetchDescriptor<QuestionSolutionLink>())
        let statuses = sources.map {
            SolutionLibraryService.availability(for: $0, documents: documents, links: links)
        }

        XCTAssertEqual(sources.count, 133)
        XCTAssertEqual(statuses.filter { $0 == .available }.count, 74)
        XCTAssertEqual(statuses.filter { $0 == .partial }.count, 32)
        XCTAssertEqual(statuses.filter { $0 == .pendingSource }.count, 27)
        XCTAssertEqual(sources.filter { source in
            SolutionLibraryService.availability(for: source, documents: documents, links: links) == .pendingSource
        }.reduce(0) { $0 + $1.questionUnitCount }, 326)
    }

    func testVerifiedPagesMultiQuestionPagesAndDocumentTypes() throws {
        let fixture = try makeFixture()
        let links = try fixture.context.fetch(FetchDescriptor<QuestionSolutionLink>())

        XCTAssertEqual(try link("TMUA-2019-P1-Q06", in: links).startPage, 8)
        XCTAssertEqual(try link("SMC-2018-Q22", in: links).startPage, 4)
        XCTAssertEqual(try link("MAT-2021-Q1A", in: links).startPage, 1)
        XCTAssertEqual(try link("MAT-2021-Q1B", in: links).startPage, 1)
        XCTAssertEqual(try link("MAT-2021-Q1C", in: links).startPage, 1)
        XCTAssertEqual(try link("MAT-2021-Q02", in: links).startPage, 4)
        XCTAssertEqual(try link("MAT-2021-Q02", in: links).solutionDocument?.solutionType, .markScheme)
        XCTAssertEqual(try link("MAC-2010-Q01", in: links).mappingConfidence, .sourceSection)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: 8, pageCount: 23), 7)
    }

    func testRevealPolicyWarnsBeforeAttemptAndAlwaysProtectsBenchmarks() throws {
        let fixture = try makeFixture()
        let questions = try fixture.context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let ordinary = try XCTUnwrap(questions.first {
            $0.protection == .none && $0.programmeAssignments.isEmpty
        })
        let protected = try XCTUnwrap(questions.first { $0.protection != .none })

        XCTAssertEqual(SolutionLibraryService.revealRequirement(for: ordinary), .unattempted)
        XCTAssertEqual(SolutionLibraryService.revealRequirement(for: protected), .protectedQuestion)

        let calendar = DateUtilities.appCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        let programme = AdmissionsProgramme(
            externalProgrammeID: "future-test",
            admissionsTest: .tmua,
            name: "Future",
            startDate: start,
            importRevision: "test"
        )
        let futureDay = ProgrammeDay(
            externalDayID: "future-day",
            dayNumber: 10,
            focus: "Benchmark",
            studyBrief: "",
            allocatedQuestionCount: 1,
            expectedQuestionMinutes: 75,
            expectedReviewMinutes: 30,
            programme: programme
        )
        ordinary.family = "TMUA Actual"
        ordinary.programmeAssignments = [ProgrammeAssignment(
            externalAssignmentID: "future-assignment",
            displayOrder: 0,
            programmeDay: futureDay,
            question: ordinary
        )]
        XCTAssertEqual(
            SolutionLibraryService.revealRequirement(
                for: ordinary,
                now: calendar.date(byAdding: .day, value: 1, to: start)!,
                calendar: calendar
            ),
            .protectedQuestion
        )
        ordinary.attempts.append(QuestionAttempt(
            outcome: .incorrect,
            timeTakenSeconds: 60,
            origin: .questionBank,
            question: ordinary
        ))
        protected.attempts.append(QuestionAttempt(
            outcome: .correct,
            timeTakenSeconds: 60,
            origin: .questionBank,
            question: protected
        ))
        ordinary.programmeAssignments = []
        ordinary.family = "Test"
        XCTAssertEqual(SolutionLibraryService.revealRequirement(for: ordinary), .none)
        XCTAssertEqual(SolutionLibraryService.revealRequirement(for: protected), .protectedQuestion)
    }

    func testResolutionLookupIsReadOnlyAndExportContainsMetadataButNoPDFs() throws {
        let fixture = try makeFixture()
        let questions = try fixture.context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let links = try fixture.context.fetch(FetchDescriptor<QuestionSolutionLink>())
        let question = try XCTUnwrap(questions.first { $0.externalQuestionID == "TMUA-2019-P1-Q06" })
        let countsBefore = try counts(in: fixture.context)

        let resolutions = SolutionLibraryService.resolutions(for: question, links: links)
        XCTAssertEqual(resolutions.first?.link.startPage, 8)
        XCTAssertEqual(try counts(in: fixture.context), countsBefore)
        XCTAssertFalse(fixture.context.hasChanges)

        let dataSet = try RevisionExportService.buildDataSet(in: fixture.context)
        XCTAssertEqual(dataSet.solutions.count, 120)
        let exportedQuestion = try XCTUnwrap(dataSet.allQuestions.first { $0.questionID == question.externalQuestionID })
        XCTAssertTrue(exportedQuestion.solutionAvailable)
        XCTAssertEqual(exportedQuestion.solutionType, "workedSolution")
        let archive = try RevisionExportService.makeFullArchiveData(from: dataSet, now: .now)
        let names = try ZIPArchiveWriter.entryNames(in: archive)
        XCTAssertTrue(names.contains("solutions.json"))
        XCTAssertFalse(names.contains { $0.lowercased().hasSuffix(".pdf") })
    }

    func testQuestionBankSolutionIndexMatchesCanonicalLookups() throws {
        let fixture = try makeFixture()
        let questions = try fixture.context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let sources = try fixture.context.fetch(FetchDescriptor<SourceDocument>())
        let documents = try fixture.context.fetch(FetchDescriptor<SolutionDocument>())
        let links = try fixture.context.fetch(FetchDescriptor<QuestionSolutionLink>())
        let index = QuestionBankSolutionIndex(documents: documents, links: links)
        let expectedLinks = Dictionary(grouping: links.filter(\.isImportedActive)) {
            $0.question?.externalQuestionID ?? ""
        }

        for question in questions {
            XCTAssertEqual(
                index.links(for: question).map(\.stableLinkID).sorted(),
                (expectedLinks[question.externalQuestionID] ?? []).map(\.stableLinkID).sorted(),
                question.externalQuestionID
            )
        }
        for source in sources {
            XCTAssertEqual(
                index.availability(for: source),
                SolutionLibraryService.availability(for: source, documents: documents, links: links),
                source.stableSourceID
            )
        }
        XCTAssertFalse(fixture.context.hasChanges)
    }

    private func makeFixture() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        return (container, context)
    }

    private func link(_ questionID: String, in links: [QuestionSolutionLink]) throws -> QuestionSolutionLink {
        try XCTUnwrap(links.first { $0.question?.externalQuestionID == questionID }, questionID)
    }

    private func counts(in context: ModelContext) throws -> [String: Int] {
        [
            "solutions": try context.fetchCount(FetchDescriptor<SolutionDocument>()),
            "links": try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()),
            "questions": try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()),
            "attempts": try context.fetchCount(FetchDescriptor<QuestionAttempt>()),
            "assignments": try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()),
            "sessions": try context.fetchCount(FetchDescriptor<StudySession>()),
            "results": try context.fetchCount(FetchDescriptor<StudyResult>())
        ]
    }
}
