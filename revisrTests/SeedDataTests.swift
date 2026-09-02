import SwiftData
import XCTest
@testable import revisr

@MainActor
final class SeedDataTests: XCTestCase {
    func testFreshSeedCreatesAdmissionsDomainsWithoutSchoolSubjectsOrWeeklyPlan() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(in: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        XCTAssertEqual(subjects.map(\.name), ["TMUA"])
        XCTAssertTrue(subjects.allSatisfy { $0.isActiveForStudy })
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlannedStudyBlock>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WeeklyFocus>()).isEmpty)

        let profiles = try context.fetch(FetchDescriptor<AdmissionsTestProfile>())
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.first(where: { $0.kind == .tmua })?.status, .active)
        XCTAssertEqual(profiles.first(where: { $0.kind == .csat })?.status, .inactive)
    }

    func testAdmissionsSeedIsIdempotent() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(in: context)
        try SeedDataService.seedIfNeeded(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<AdmissionsQuestion>()).count, 2_600)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgrammeDay>()).count, 30)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgrammeAssignment>()).count, 894)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter(\.isImportedActive).count,
            452
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<SourceDocument>()).count, 136)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AdmissionsImportState>()).count, 1)
    }

    func testMigrationArchivesSchoolSubjectsWithoutDeletingHistoricalRecords() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let maths = Subject(name: "Mathematics", targetPercentage: 0.5, displayOrder: 0)
        let further = Subject(name: "Further Mathematics", targetPercentage: 0.5, displayOrder: 1)
        let module = StudyModule(name: "CP1", displayOrder: 0, subject: further)
        let topic = Topic(name: "Complex Numbers", displayOrder: 0, module: module)
        let session = StudySession(
            date: .now,
            duration: 3_600,
            activity: .revision,
            subject: further,
            module: module,
            topic: topic,
            subjectNameSnapshot: "Further Mathematics",
            moduleNameSnapshot: "CP1",
            topicNameSnapshot: "Complex Numbers"
        )
        let result = StudyResult(
            date: .now,
            paperOrModuleLabel: "CP1",
            rawScore: 50,
            maximumScore: 75,
            subject: further,
            module: module,
            subjectNameSnapshot: "Further Mathematics",
            moduleNameSnapshot: "CP1"
        )
        let block = PlannedStudyBlock(
            day: .now,
            duration: 3_600,
            activity: .questions,
            subject: maths
        )
        context.insert(AppSettings(appliedSeedVersion: 3))
        [maths, further].forEach(context.insert)
        context.insert(module)
        context.insert(topic)
        context.insert(session)
        context.insert(result)
        context.insert(block)
        try context.save()

        try SeedDataService.seedIfNeeded(in: context)

        XCTAssertFalse(maths.isActiveForStudy)
        XCTAssertFalse(further.isActiveForStudy)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudySession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyResult>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedStudyBlock>()).count, 1)
        XCTAssertEqual(session.subjectNameSnapshot, "Further Mathematics")
        XCTAssertEqual(result.subjectNameSnapshot, "Further Mathematics")
    }

    func testBasicTMUAStudySessionStillPreservesHistoricalLabels() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let subject = try XCTUnwrap(context.fetch(FetchDescriptor<Subject>()).first)
        let paper2 = try XCTUnwrap(subject.modules.first(where: { $0.name == "Paper 2" }))

        context.insert(StudySession(
            date: .now,
            duration: 3_600,
            activity: .timedQuestions,
            subject: subject,
            module: paper2,
            subjectNameSnapshot: subject.name,
            moduleNameSnapshot: paper2.name
        ))
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<StudySession>()).first)
        XCTAssertEqual(saved.subjectNameSnapshot, "TMUA")
        XCTAssertEqual(saved.moduleNameSnapshot, "Paper 2")
    }
}
