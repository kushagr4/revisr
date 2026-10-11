import SwiftData
import XCTest
@testable import revisr

@MainActor
final class PublicPreparationFoundationTests: XCTestCase {
    func testFreshBootstrapImportsCatalogueWithoutPersonalProgramme() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertEqual(settings.publicOnboardingStage, .profile)
        XCTAssertEqual(settings.publicExam, .tmua)
        XCTAssertNil(settings.publicExamDate)
        XCTAssertNil(settings.tmuaProgrammeStartDate)
        XCTAssertEqual(settings.publicAvailability.count, 7)
        XCTAssertTrue(settings.publicAvailability.allSatisfy(\.isAvailable))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 2_600)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocument>()), 136)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolutionDocument>()), 120)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()), 2_364)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StudySession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Subject>()), 0)
        XCTAssertEqual(try XCTUnwrap(context.fetch(FetchDescriptor<AdmissionsImportState>()).first).assignmentCount, 0)

        _ = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 2_600)
    }

    func testPreparationChoicesPersistAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-PublicFoundation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")
        let calendar = DateUtilities.appCalendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let today = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 9)))
        let examDate = try XCTUnwrap(calendar.date(from: .init(year: 2027, month: 1, day: 15)))

        do {
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try SeedDataService.bootstrapForLaunch(in: context)
            var availability = AppSettings.publicDefaultAvailability
            availability[3].isAvailable = false
            try PublicPreparationService.saveProfile(
                exam: .bmo,
                examDate: examDate,
                weeklyMinutes: 480,
                availability: availability,
                today: today,
                calendar: calendar,
                settings: settings,
                in: context
            )
            XCTAssertEqual(settings.publicOnboardingStage, .diagnostics)
        }

        let reopened = try AppContainer.make(storeURL: store)
        let context = reopened.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertEqual(settings.publicOnboardingStage, .diagnostics)
        XCTAssertEqual(settings.publicExam, .bmo)
        XCTAssertEqual(settings.publicWeeklyTargetMinutes, 480)
        XCTAssertEqual(settings.publicAvailability.first { $0.weekday == .thursday }?.isAvailable, false)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(settings.publicExamDate), inSameDayAs: examDate))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 0)
    }

    func testExistingStoreKeepsLegacyProgrammeAndHistory() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let assignment = try XCTUnwrap(context.fetch(FetchDescriptor<ProgrammeAssignment>()).first)
        let attemptID = UUID()
        context.insert(QuestionAttempt(
            id: attemptID,
            outcome: .correct,
            timeTakenSeconds: 120,
            origin: .programme,
            question: assignment.question,
            programmeAssignment: assignment
        ))
        try context.save()

        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertNil(settings.publicOnboardingStage)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 894)
        XCTAssertEqual(try context.fetch(FetchDescriptor<QuestionAttempt>()).map(\.id), [attemptID])
        XCTAssertNotNil(settings.tmuaProgrammeStartDate)
    }

    func testSupportedExamsKeepDistinctAssessmentStyles() {
        XCTAssertEqual(PublicExamKind.allCases, [.tmua, .smc, .bmo])
        XCTAssertEqual(PublicExamKind.tmua.preparationStream, .tmua)
        XCTAssertEqual(PublicExamKind.smc.preparationStream, .smc)
        XCTAssertEqual(PublicExamKind.bmo.preparationStream, .bmo)
        XCTAssertEqual(PublicExamKind.tmua.assessmentStyle, .multipleChoice)
        XCTAssertEqual(PublicExamKind.smc.assessmentStyle, .multipleChoice)
        XCTAssertEqual(PublicExamKind.bmo.assessmentStyle, .writtenMarksAndSelfAssessment)
    }

    func testInvalidProfileDoesNotAdvanceOnboarding() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertThrowsError(try PublicPreparationService.saveProfile(
            exam: .smc,
            examDate: today,
            weeklyMinutes: 300,
            availability: AppSettings.publicDefaultAvailability,
            today: today,
            settings: settings,
            in: context
        ))
        XCTAssertEqual(settings.publicOnboardingStage, .profile)
        XCTAssertNil(settings.publicExamDate)
    }
}
