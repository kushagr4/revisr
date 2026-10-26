import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var tmuaExamDate: Date
    var availabilityData: Data
    var tmuaTarget: Double
    var furtherMathematicsTarget: Double
    var mathematicsTarget: Double
    var tmuaPaper1Target: Double
    var tmuaPaper2Target: Double
    /// Stored as whole minutes so the weekly target is exact and migration-safe.
    var weeklyTargetMinutes: Int = 2_040
    /// Added additively so older local stores migrate without rewriting settings.
    var activeAdmissionsTestRawValue: String? = nil
    var tmuaProgrammeStartDate: Date? = nil
    /// Nil identifies a pre-public-installation store. Its personal settings and
    /// programme are never interpreted as a new student's onboarding choices.
    var publicOnboardingStageRawValue: String? = nil
    var publicExamRawValue: String? = nil
    var publicExamDate: Date? = nil
    var publicWeeklyTargetMinutes: Int? = nil
    var publicAvailabilityData: Data? = nil
    /// Nil keeps an existing public profile on the earlier PDF diagnostic flow;
    /// 2 is the flexible native TMUA journey. Neither rewrites earlier records.
    var publicFlowVersion: Int? = nil
    var publicDiagnosticLengthRawValue: String? = nil
    /// Optional cap on minutes planned for any single study day.
    var publicSessionMinutes: Int? = nil
    /// Enables additive seed migrations without recreating content the user deleted.
    var appliedSeedVersion: Int

    var availability: [DayAvailability] {
        get {
            (try? JSONDecoder().decode([DayAvailability].self, from: availabilityData))
                ?? Self.defaultAvailability
        }
        set {
            availabilityData = (try? JSONEncoder().encode(newValue)) ?? availabilityData
        }
    }

    var activeAdmissionsTest: AdmissionsTestKind {
        get { activeAdmissionsTestRawValue.flatMap(AdmissionsTestKind.init(rawValue:)) ?? .tmua }
        set { activeAdmissionsTestRawValue = newValue.rawValue }
    }

    var publicOnboardingStage: PublicOnboardingStage? {
        get {
            guard let rawValue = publicOnboardingStageRawValue else { return nil }
            return PublicOnboardingStage(rawValue: rawValue) ?? .profile
        }
        set { publicOnboardingStageRawValue = newValue?.rawValue }
    }

    var publicExam: PublicExamKind {
        get { publicExamRawValue.flatMap(PublicExamKind.init(rawValue:)) ?? .tmua }
        set { publicExamRawValue = newValue.rawValue }
    }

    var publicAvailability: [DayAvailability] {
        get {
            publicAvailabilityData.flatMap { try? JSONDecoder().decode([DayAvailability].self, from: $0) }
                ?? Self.publicDefaultAvailability
        }
        set { publicAvailabilityData = try? JSONEncoder().encode(newValue) }
    }

    var publicDiagnosticLength: TMUADiagnosticLength? {
        get { publicDiagnosticLengthRawValue.flatMap(TMUADiagnosticLength.init(rawValue:)) }
        set { publicDiagnosticLengthRawValue = newValue?.rawValue }
    }

    /// True for profiles on the flexible native TMUA journey.
    var usesFlexibleTMUAFlow: Bool { publicFlowVersion == 2 && publicExam == .tmua }

    var effectiveTMUAProgrammeStartDate: Date {
        tmuaProgrammeStartDate ?? Self.makeDefaultProgrammeStartDate()
    }

    init(
        id: UUID = UUID(),
        tmuaExamDate: Date = AppSettings.makeDefaultExamDate(),
        availability: [DayAvailability] = AppSettings.defaultAvailability,
        tmuaTarget: Double = 0.55,
        furtherMathematicsTarget: Double = 0.27,
        mathematicsTarget: Double = 0.18,
        tmuaPaper1Target: Double = 0.40,
        tmuaPaper2Target: Double = 0.60,
        weeklyTargetMinutes: Int = 2_040,
        activeAdmissionsTest: AdmissionsTestKind = .tmua,
        tmuaProgrammeStartDate: Date? = nil,
        usesLegacyProgrammeStartDate: Bool = true,
        appliedSeedVersion: Int = 0
    ) {
        self.id = id
        self.tmuaExamDate = tmuaExamDate
        self.availabilityData = (try? JSONEncoder().encode(availability)) ?? Data()
        self.tmuaTarget = tmuaTarget
        self.furtherMathematicsTarget = furtherMathematicsTarget
        self.mathematicsTarget = mathematicsTarget
        self.tmuaPaper1Target = tmuaPaper1Target
        self.tmuaPaper2Target = tmuaPaper2Target
        self.weeklyTargetMinutes = weeklyTargetMinutes
        self.activeAdmissionsTestRawValue = activeAdmissionsTest.rawValue
        self.tmuaProgrammeStartDate = tmuaProgrammeStartDate
            ?? (usesLegacyProgrammeStartDate ? Self.makeDefaultProgrammeStartDate() : nil)
        self.appliedSeedVersion = appliedSeedVersion
    }

    static let defaultAvailability: [DayAvailability] = [
        DayAvailability(weekday: .monday, isAvailable: true),
        DayAvailability(weekday: .tuesday, isAvailable: true, startMinute: 14 * 60),
        DayAvailability(weekday: .wednesday, isAvailable: true),
        DayAvailability(weekday: .thursday, isAvailable: false),
        DayAvailability(weekday: .friday, isAvailable: true),
        DayAvailability(weekday: .saturday, isAvailable: true),
        DayAvailability(weekday: .sunday, isAvailable: false)
    ]

    static let publicDefaultAvailability: [DayAvailability] = Weekday.displayOrder.map {
        DayAvailability(weekday: $0, isAvailable: true)
    }

    static func makeDefaultExamDate(calendar: Calendar = .autoupdatingCurrent) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 10
        components.day = 16
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_792_108_800)
    }

    static func makeDefaultProgrammeStartDate(calendar: Calendar = .autoupdatingCurrent) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 8
        components.day = 22
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_777_075_200)
    }
}
