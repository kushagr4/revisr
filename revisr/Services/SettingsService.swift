import Foundation
import SwiftData

enum SettingsValidation {
    static func wholePercentageTotal(_ values: [Int?]) -> Int {
        values.compactMap { $0 }.reduce(0, +)
    }

    static func isValidWholePercentageGroup(_ values: [Int?]) -> Bool {
        !values.isEmpty
            && values.allSatisfy { value in
                guard let value else { return false }
                return (0...100).contains(value)
            }
            && DomainValidation.isValidPercentageGroup(values.compactMap { $0 }.map { Double($0) / 100 })
    }

    static func wholePercentage(from fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }

    static func fraction(fromWholePercentage percentage: Int) -> Double {
        Double(percentage) / 100
    }

    static func isValidWeeklyTarget(minutes: Int) -> Bool {
        minutes > 0
    }
}

@MainActor
enum SettingsService {
    static func availability(
        for weekday: Weekday,
        in settings: AppSettings
    ) -> DayAvailability {
        settings.availability.first(where: { $0.weekday == weekday })
            ?? DayAvailability(weekday: weekday, isAvailable: true)
    }

    /// An unavailable day retains its previous start restriction. That restriction
    /// is ignored while unavailable and predictably returns if the day is re-enabled.
    static func updateAvailability(
        weekday: Weekday,
        isAvailable: Bool,
        startMinute: Int?,
        settings: AppSettings,
        in context: ModelContext
    ) throws {
        if let startMinute, !(0..<(24 * 60)).contains(startMinute) {
            throw SettingsError.invalidStartTime
        }

        var availability = settings.availability
        if let index = availability.firstIndex(where: { $0.weekday == weekday }) {
            availability[index].isAvailable = isAvailable
            availability[index].startMinute = startMinute
        } else {
            availability.append(
                DayAvailability(
                    weekday: weekday,
                    isAvailable: isAvailable,
                    startMinute: startMinute
                )
            )
        }
        settings.availability = availability.sorted {
            (Weekday.displayOrder.firstIndex(of: $0.weekday) ?? 0)
                < (Weekday.displayOrder.firstIndex(of: $1.weekday) ?? 0)
        }
        try context.save()
    }

    static func saveSubjectTargets(
        tmua: Int,
        furtherMathematics: Int,
        mathematics: Int,
        settings: AppSettings,
        in context: ModelContext
    ) throws {
        let values: [Int?] = [tmua, furtherMathematics, mathematics]
        guard SettingsValidation.isValidWholePercentageGroup(values) else {
            throw SettingsError.invalidTargetAllocation
        }
        settings.tmuaTarget = SettingsValidation.fraction(fromWholePercentage: tmua)
        settings.furtherMathematicsTarget = SettingsValidation.fraction(fromWholePercentage: furtherMathematics)
        settings.mathematicsTarget = SettingsValidation.fraction(fromWholePercentage: mathematics)
        try context.save()
    }

    static func saveTMUATargets(
        paper1: Int,
        paper2: Int,
        settings: AppSettings,
        in context: ModelContext
    ) throws {
        let values: [Int?] = [paper1, paper2]
        guard SettingsValidation.isValidWholePercentageGroup(values) else {
            throw SettingsError.invalidTargetAllocation
        }
        settings.tmuaPaper1Target = SettingsValidation.fraction(fromWholePercentage: paper1)
        settings.tmuaPaper2Target = SettingsValidation.fraction(fromWholePercentage: paper2)
        try context.save()
    }

    static func saveWeeklyTarget(
        minutes: Int,
        settings: AppSettings,
        in context: ModelContext
    ) throws {
        guard SettingsValidation.isValidWeeklyTarget(minutes: minutes) else {
            throw SettingsError.invalidWeeklyTarget
        }
        settings.weeklyTargetMinutes = minutes
        try context.save()
    }

    static func saveExamDate(
        _ date: Date,
        settings: AppSettings,
        calendar: Calendar = DateUtilities.appCalendar(),
        in context: ModelContext
    ) throws {
        settings.tmuaExamDate = calendar.startOfDay(for: date)
        try context.save()
    }
}

enum SettingsError: LocalizedError {
    case invalidStartTime
    case invalidTargetAllocation
    case invalidWeeklyTarget

    var errorDescription: String? {
        switch self {
        case .invalidStartTime:
            "Choose a valid availability time."
        case .invalidTargetAllocation:
            "Targets must each be between 0% and 100% and total 100%."
        case .invalidWeeklyTarget:
            "Weekly study target must be greater than zero."
        }
    }
}

enum SettingsFormatting {
    static func percentage(_ fraction: Double) -> String {
        SettingsValidation.wholePercentage(from: fraction).formatted(.number) + "%"
    }

    static func availabilitySummary(
        _ availability: DayAvailability,
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> String {
        guard availability.isAvailable else { return "Unavailable" }
        guard let minute = availability.startMinute else { return "Available all day" }
        let day = calendar.startOfDay(for: .now)
        let time = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
        return "Available from \(time.formatted(date: .omitted, time: .shortened))"
    }

    static func weeklyTarget(_ minutes: Int) -> String {
        DateUtilities.durationText(TimeInterval(max(0, minutes) * 60))
    }
}
