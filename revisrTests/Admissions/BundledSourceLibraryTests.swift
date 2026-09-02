import PDFKit
import SwiftData
import XCTest
@testable import revisr

@MainActor
final class BundledSourceLibraryTests: XCTestCase {
    func testAllManifestSourcesResolveToUniqueReadableBundledPDFs() throws {
        let fixture = try makeFixture()
        let sources = try fixture.context.fetch(FetchDescriptor<SourceDocument>())
        let audit = SourceLibraryService.audit(sources: sources)

        XCTAssertEqual(sources.count, 136)
        XCTAssertEqual(audit.expectedCount, 136)
        XCTAssertEqual(audit.resolvedCount, 136)
        XCTAssertTrue(audit.missingSourceIDs.isEmpty)
        XCTAssertTrue(audit.duplicateResourceURLs.isEmpty)
        XCTAssertTrue(audit.isComplete)

        let resolved = try sources.map { source in
            try XCTUnwrap(SourceLibraryService.bundledURL(for: source))
        }
        XCTAssertEqual(Set(resolved.map(\.standardizedFileURL)).count, 136)
        for url in resolved {
            let document = try XCTUnwrap(PDFDocument(url: url), url.lastPathComponent)
            XCTAssertGreaterThan(document.pageCount, 0, url.lastPathComponent)
        }
    }

    func testEveryQuestionResolvesThroughItsSourceAndRepresentativeFamiliesOpen() throws {
        let fixture = try makeFixture()
        let questions = try fixture.context.fetch(FetchDescriptor<AdmissionsQuestion>())

        XCTAssertEqual(questions.count, 2_600)
        XCTAssertEqual(Set(questions.map(\.externalQuestionID)).count, 2_600)
        XCTAssertTrue(questions.allSatisfy { question in
            guard let source = question.sourceDocument else { return false }
            return SourceLibraryService.bundledURL(for: source) != nil
        })

        for family in ["TMUA Actual", "SMC", "MAT", "TMUA Mock", "STEP", "JZ Maths TMUA Mock", "MioMath TMUA Mock", "Tyler Topic Bank"] {
            let question = try XCTUnwrap(questions.first { $0.family == family }, family)
            let source = try XCTUnwrap(question.sourceDocument)
            let url = try XCTUnwrap(SourceLibraryService.bundledURL(for: source))
            XCTAssertNotNil(PDFDocument(url: url), family)
        }
    }

    func testMissingSourceAuditAndWorkbookPageConversion() throws {
        let missing = SourceDocument(
            stableSourceID: "SRC-NOT-IN-BUNDLE",
            displayName: "Missing",
            expectedFilename: "Missing.pdf",
            family: "Test",
            importRevision: "test"
        )
        let audit = SourceLibraryService.audit(sources: [missing])

        XCTAssertEqual(audit.expectedCount, 1)
        XCTAssertEqual(audit.resolvedCount, 0)
        XCTAssertEqual(audit.missingSourceIDs, ["SRC-NOT-IN-BUNDLE"])
        XCTAssertFalse(audit.isComplete)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: nil, pageCount: 10), 0)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: 1, pageCount: 10), 0)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: 4, pageCount: 10), 3)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: 0, pageCount: 10), 0)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: 50, pageCount: 10), 9)
        XCTAssertEqual(SourceLibraryService.pdfPageIndex(for: 4, pageCount: 0), 0)
    }

    func testResourceLookupDoesNotMutateDataAndProtectionRemainsIndependent() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let sources = try context.fetch(FetchDescriptor<SourceDocument>())
        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let protectedBefore = questions.filter { $0.protection != .none }
            .map { "\($0.externalQuestionID)|\($0.protectionRawValue)|\($0.reviewStateRawValue)|\($0.userNotes)" }
        let countsBefore = try counts(in: context)

        XCTAssertEqual(protectedBefore.count, 40)
        XCTAssertTrue(questions.filter { $0.protection != .none }.allSatisfy { question in
            guard
                  let source = question.sourceDocument else { return false }
            return SourceLibraryService.bundledURL(for: source) != nil
        })
        _ = SourceLibraryService.audit(sources: sources)
        sources.forEach { _ = SourceLibraryService.resolvedURL(for: $0) }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try counts(in: context), countsBefore)
        XCTAssertEqual(
            questions.filter { $0.protection != .none }
                .map { "\($0.externalQuestionID)|\($0.protectionRawValue)|\($0.reviewStateRawValue)|\($0.userNotes)" },
            protectedBefore
        )
    }

    private func makeFixture() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        try SeedDataService.seedIfNeeded(in: context)
        return (container, context)
    }

    private func counts(in context: ModelContext) throws -> [String: Int] {
        [
            "sources": try context.fetchCount(FetchDescriptor<SourceDocument>()),
            "questions": try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()),
            "assignments": try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()),
            "days": try context.fetchCount(FetchDescriptor<ProgrammeDay>()),
            "attempts": try context.fetchCount(FetchDescriptor<QuestionAttempt>()),
            "sessions": try context.fetchCount(FetchDescriptor<StudySession>()),
            "results": try context.fetchCount(FetchDescriptor<StudyResult>())
        ]
    }
}
