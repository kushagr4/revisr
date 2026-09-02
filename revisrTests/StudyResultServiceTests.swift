import SwiftData
import XCTest
@testable import revisr

@MainActor
final class StudyResultServiceTests: XCTestCase {
    func testTMUAScaledOnlyCreationPersists() throws {
        let fixture = try makeFixture()
        let input = StudyResultInput(
            date: .now,
            label: "Paper 1",
            rawScore: nil,
            maximumScore: nil,
            scaledScore: 7.2,
            notes: "Timed paper",
            subject: fixture.tmua,
            module: fixture.tmua.modules.first
        )

        let created = try StudyResultService.create(input: input, kind: .tmua, in: fixture.context)

        XCTAssertNil(created.rawPercentage)
        XCTAssertEqual(created.scaledScore, 7.2)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudyResult>()).count, 1)
    }

    func testTMUARequiresAtLeastOneMeaningfulRepresentation() throws {
        let fixture = try makeFixture()
        let input = StudyResultInput(
            date: .now,
            label: "Paper 1",
            rawScore: nil,
            maximumScore: nil,
            scaledScore: nil,
            notes: "",
            subject: fixture.tmua,
            module: nil
        )

        XCTAssertThrowsError(try StudyResultService.validate(input, kind: .tmua)) { error in
            XCTAssertEqual(error as? StudyResultError, .missingTMUAScore)
        }
    }

    func testRawScoreValidationRejectsIncompleteAndOutOfRangeValues() throws {
        let fixture = try makeFixture()
        var input = StudyResultInput(
            date: .now,
            label: "Paper 2",
            rawScore: 21,
            maximumScore: 20,
            scaledScore: nil,
            notes: "",
            subject: fixture.tmua,
            module: nil
        )

        XCTAssertThrowsError(try StudyResultService.validate(input, kind: .tmua)) { error in
            XCTAssertEqual(error as? StudyResultError, .invalidRawScore)
        }
        input.rawScore = 12
        input.maximumScore = nil
        XCTAssertThrowsError(try StudyResultService.validate(input, kind: .tmua)) { error in
            XCTAssertEqual(error as? StudyResultError, .incompleteRawScore)
        }
    }

    func testEditingTMUAResultPreservesIdentityAndUpdatesSnapshot() throws {
        let fixture = try makeFixture()
        let created = try StudyResultService.create(
            input: StudyResultInput(
                date: .now,
                label: "Paper 1",
                rawScore: 15,
                maximumScore: 20,
                scaledScore: 7.0,
                notes: "First",
                subject: fixture.tmua,
                module: fixture.tmua.modules.first
            ),
            kind: .tmua,
            in: fixture.context
        )
        let originalID = created.id

        try StudyResultService.update(
            created,
            input: StudyResultInput(
                date: .now,
                label: "Paper 2",
                rawScore: 16,
                maximumScore: 20,
                scaledScore: 7.4,
                notes: "Corrected",
                subject: fixture.tmua,
                module: fixture.tmua.modules.last
            ),
            kind: .tmua,
            in: fixture.context
        )

        XCTAssertEqual(created.id, originalID)
        XCTAssertEqual(created.subjectNameSnapshot, "TMUA")
        XCTAssertEqual(created.paperOrModuleLabel, "Paper 2")
        XCTAssertEqual(try XCTUnwrap(created.rawPercentage), 0.8, accuracy: 0.000_001)
    }

    func testDeletingResultDoesNotDeleteStudySession() throws {
        let fixture = try makeFixture()
        let session = StudySession(
            date: .now,
            duration: 60 * 60,
            activity: .revision,
            subject: fixture.tmua,
            subjectNameSnapshot: fixture.tmua.name
        )
        fixture.context.insert(session)
        let result = try StudyResultService.create(
            input: StudyResultInput(
                date: .now,
                label: "Paper 1",
                rawScore: 15,
                maximumScore: 20,
                scaledScore: nil,
                notes: "",
                subject: fixture.tmua,
                module: nil
            ),
            kind: .tmua,
            in: fixture.context
        )

        try StudyResultService.delete(result, in: fixture.context)

        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<StudyResult>()).isEmpty)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudySession>()).count, 1)
    }

    private func makeFixture() throws -> (
        container: ModelContainer,
        context: ModelContext,
        tmua: Subject
    ) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        return (container, context, subjects.first(where: { $0.name == "TMUA" })!)
    }
}
