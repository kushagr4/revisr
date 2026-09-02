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
        self.tmuaProgrammeStartDate = tmuaProgrammeStartDate ?? Self.makeDefaultProgrammeStartDate()
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
