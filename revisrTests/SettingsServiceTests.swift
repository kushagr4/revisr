import SwiftData
import XCTest
@testable import revisr

@MainActor
final class SettingsServiceTests: XCTestCase {
    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    func testDefaultSettingsIncludeExamAvailabilityTargetsAndWeeklyTarget() {
        let settings = AppSettings(tmuaExamDate: AppSettings.makeDefaultExamDate(calendar: calendar))

        XCTAssertEqual(calendar.component(.year, from: settings.tmuaExamDate), 2026)
        XCTAssertEqual(calendar.component(.month, from: settings.tmuaExamDate), 10)
        XCTAssertEqual(calendar.component(.day, from: settings.tmuaExamDate), 16)
        XCTAssertEqual(settings.weeklyTargetMinutes, 2_040)
        XCTAssertTrue(DomainValidation.isValidPercentageGroup([
            settings.tmuaTarget,
            settings.furtherMathematicsTarget,
            settings.mathematicsTarget
        ]))
        XCTAssertEqual(
            settings.availability.first(where: { $0.weekday == .tuesday })?.startMinute,
            14 * 60
        )
    }

    func testAvailabilityCanBecomeUnavailableAndAvailableWithoutMutatingStudyData() throws {
        let fixture = try makeSeededFixture()
        let originalBlockCount = try fixture.context.fetch(FetchDescriptor<PlannedStudyBlock>()).count
        let originalSessionCount = try fixture.context.fetch(FetchDescriptor<StudySession>()).count

        try SettingsService.updateAvailability(
            weekday: .monday,
            isAvailable: false,
            startMinute: 9 * 60,
            settings: fixture.settings,
            in: fixture.context
        )
        var monday = SettingsService.availability(for: .monday, in: fixture.settings)
        XCTAssertFalse(monday.isAvailable)
        XCTAssertEqual(monday.startMinute, 9 * 60)

        try SettingsService.updateAvailability(
            weekday: .monday,
            isAvailable: true,
            startMinute: monday.startMinute,
            settings: fixture.settings,
            in: fixture.context
        )
        monday = SettingsService.availability(for: .monday, in: fixture.settings)
        XCTAssertTrue(monday.isAvailable)
        XCTAssertEqual(monday.startMinute, 9 * 60)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<PlannedStudyBlock>()).count, originalBlockCount)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudySession>()).count, originalSessionCount)
    }

    func testAvailabilityChangesImmediatelyUpdatePlanningConflicts() throws {
        let fixture = try makeSeededFixture()
        let thursday = makeDate(2026, 8, 13)

        XCTAssertEqual(conflicts(on: thursday, at: nil, settings: fixture.settings), [.unavailableDay])
        try SettingsService.updateAvailability(
            weekday: .thursday,
            isAvailable: true,
            startMinute: nil,
            settings: fixture.settings,
            in: fixture.context
        )
        XCTAssertTrue(conflicts(on: thursday, at: nil, settings: fixture.settings).isEmpty)

        let tuesday = makeDate(2026, 8, 11)
        XCTAssertEqual(conflicts(on: tuesday, at: 12 * 60 + 30, settings: fixture.settings), [.beforeAvailableStart(14 * 60)])
        try SettingsService.updateAvailability(
            weekday: .tuesday,
            isAvailable: true,
            startMinute: 12 * 60,
            settings: fixture.settings,
            in: fixture.context
        )
        XCTAssertTrue(conflicts(on: tuesday, at: 12 * 60 + 30, settings: fixture.settings).isEmpty)
    }

    func testAvailabilityRejectsInvalidStartMinute() throws {
        let fixture = try makeSeededFixture()
        XCTAssertThrowsError(
            try SettingsService.updateAvailability(
                weekday: .monday,
                isAvailable: true,
                startMinute: 24 * 60,
                settings: fixture.settings,
                in: fixture.context
            )
        )
    }

    func testSubjectTargetValidationExamplesAndBounds() {
        XCTAssertTrue(SettingsValidation.isValidWholePercentageGroup([55, 27, 18]))
        XCTAssertTrue(SettingsValidation.isValidWholePercentageGroup([60, 20, 20]))
        XCTAssertFalse(SettingsValidation.isValidWholePercentageGroup([60, 30, 20]))
        XCTAssertFalse(SettingsValidation.isValidWholePercentageGroup([-1, 51, 50]))
        XCTAssertFalse(SettingsValidation.isValidWholePercentageGroup([101, 0, 0]))
        XCTAssertTrue(DomainValidation.isValidPercentageGroup([0.1, 0.2, 0.700000_000_1]))
    }

    func testSubjectTargetsPersistAsDecimalsAndProgressReadsThemImmediately() throws {
        let fixture = try makeSeededFixture()
        try SettingsService.saveSubjectTargets(
            tmua: 60,
            furtherMathematics: 20,
            mathematics: 20,
            settings: fixture.settings,
            in: fixture.context
        )

        XCTAssertEqual(fixture.settings.tmuaTarget, 0.60, accuracy: 0.000_001)
        XCTAssertEqual(fixture.settings.furtherMathematicsTarget, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(fixture.settings.mathematicsTarget, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(
            ProgressAnalytics.targetFraction(for: .tmua, settings: fixture.settings),
            0.60,
            accuracy: 0.000_001
        )
    }

    func testInvalidSubjectTargetDraftIsNotPersisted() throws {
        let fixture = try makeSeededFixture()
        XCTAssertThrowsError(
            try SettingsService.saveSubjectTargets(
                tmua: 60,
                furtherMathematics: 30,
                mathematics: 20,
                settings: fixture.settings,
                in: fixture.context
            )
        )
        XCTAssertEqual(fixture.settings.tmuaTarget, 0.55, accuracy: 0.000_001)
        XCTAssertEqual(fixture.settings.furtherMathematicsTarget, 0.27, accuracy: 0.000_001)
        XCTAssertEqual(fixture.settings.mathematicsTarget, 0.18, accuracy: 0.000_001)
    }

    func testTMUATargetValidationPersistenceAndInvalidDraft() throws {
        XCTAssertTrue(SettingsValidation.isValidWholePercentageGroup([40, 60]))
        XCTAssertTrue(SettingsValidation.isValidWholePercentageGroup([35, 65]))
        XCTAssertFalse(SettingsValidation.isValidWholePercentageGroup([50, 60]))

        let fixture = try makeSeededFixture()
        try SettingsService.saveTMUATargets(
            paper1: 35,
            paper2: 65,
            settings: fixture.settings,
            in: fixture.context
        )
        XCTAssertEqual(fixture.settings.tmuaPaper1Target, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(fixture.settings.tmuaPaper2Target, 0.65, accuracy: 0.000_001)

        XCTAssertThrowsError(
            try SettingsService.saveTMUATargets(
                paper1: 50,
                paper2: 60,
                settings: fixture.settings,
                in: fixture.context
            )
        )
        XCTAssertEqual(fixture.settings.tmuaPaper1Target, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(fixture.settings.tmuaPaper2Target, 0.65, accuracy: 0.000_001)
    }

    func testWeeklyTargetPersistsFormatsAndRejectsZero() throws {
        let fixture = try makeSeededFixture()
        try SettingsService.saveWeeklyTarget(minutes: 33 * 60 + 30, settings: fixture.settings, in: fixture.context)
        XCTAssertEqual(fixture.settings.weeklyTargetMinutes, 2_010)
        XCTAssertEqual(SettingsFormatting.weeklyTarget(fixture.settings.weeklyTargetMinutes), "33h 30m")

        XCTAssertThrowsError(
            try SettingsService.saveWeeklyTarget(minutes: 0, settings: fixture.settings, in: fixture.context)
        )
        XCTAssertEqual(fixture.settings.weeklyTargetMinutes, 2_010)
    }

    func testExamDateSavesAsCalendarDayAndCountdownUpdates() throws {
        let fixture = try makeSeededFixture()
        let source = makeDate(2026, 8, 15, hour: 16)
        let newDate = makeDate(2026, 11, 2, hour: 19)

        try SettingsService.saveExamDate(newDate, settings: fixture.settings, calendar: calendar, in: fixture.context)

        XCTAssertEqual(fixture.settings.tmuaExamDate, calendar.startOfDay(for: newDate))
        XCTAssertEqual(DateUtilities.daysUntil(fixture.settings.tmuaExamDate, from: source, calendar: calendar), 79)
    }

    func testPastExamDateIsAccepted() throws {
        let fixture = try makeSeededFixture()
        let pastDate = makeDate(2025, 10, 16, hour: 23)

        try SettingsService.saveExamDate(pastDate, settings: fixture.settings, calendar: calendar, in: fixture.context)

        XCTAssertEqual(fixture.settings.tmuaExamDate, makeDate(2025, 10, 16))
    }

    func testSeedingCreatesOneCanonicalSettingsRecordAndIsIdempotent() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
        try SeedDataService.seedIfNeeded(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    func testMigrationDeduplicatesSettingsWithoutOverwritingCanonicalUserValues() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let canonical = AppSettings(
            tmuaExamDate: makeDate(2027, 1, 10),
            tmuaTarget: 0.60,
            furtherMathematicsTarget: 0.20,
            mathematicsTarget: 0.20,
            weeklyTargetMinutes: 1_800,
            appliedSeedVersion: 2
        )
        let duplicate = AppSettings(appliedSeedVersion: 0)
        context.insert(canonical)
        context.insert(duplicate)
        try context.save()

        try SeedDataService.seedIfNeeded(in: context)

        let records = try context.fetch(FetchDescriptor<AppSettings>())
        let saved = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(saved.id, canonical.id)
        XCTAssertEqual(saved.tmuaTarget, 0.60, accuracy: 0.000_001)
        XCTAssertEqual(saved.weeklyTargetMinutes, 1_800)
        XCTAssertEqual(saved.appliedSeedVersion, SeedDataService.currentSeedVersion)
    }

    func testPhase3DStyleSettingsRecordReceivesWeeklyDefaultDuringMigration() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let settings = AppSettings(appliedSeedVersion: 2)
        context.insert(settings)
        try context.save()

        try SeedDataService.seedIfNeeded(in: context)

        XCTAssertEqual(settings.weeklyTargetMinutes, 2_040)
        XCTAssertEqual(settings.appliedSeedVersion, SeedDataService.currentSeedVersion)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    private func makeSeededFixture() throws -> (
        container: ModelContainer,
        context: ModelContext,
        settings: AppSettings
    ) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        return (
            container,
            context,
            try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
        )
    }

    private func conflicts(on day: Date, at minute: Int?, settings: AppSettings) -> [PlanningConflict] {
        PlanningService.conflicts(
            day: day,
            startMinute: minute,
            duration: 60 * 60,
            among: [],
            availability: settings.availability,
            calendar: calendar
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
