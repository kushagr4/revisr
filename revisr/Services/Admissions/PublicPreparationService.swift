import Foundation
import SwiftData

enum PublicPreparationError: LocalizedError {
    case invalidExamDate
    case invalidWeeklyTarget
    case noAvailableDays

    var errorDescription: String? {
        switch self {
        case .invalidExamDate: "Choose a future examination date."
        case .invalidWeeklyTarget: "Choose a weekly study target greater than zero."
        case .noAvailableDays: "Make at least one day available for study."
        }
    }
}

@MainActor
enum PublicPreparationService {
    static func saveProfile(
        exam: PublicExamKind,
        examDate: Date,
        weeklyMinutes: Int,
        availability: [DayAvailability],
        today: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar(),
        settings: AppSettings,
        in context: ModelContext
    ) throws {
        let date = calendar.startOfDay(for: examDate)
        guard date > calendar.startOfDay(for: today) else {
            throw PublicPreparationError.invalidExamDate
        }
        guard weeklyMinutes > 0 else {
            throw PublicPreparationError.invalidWeeklyTarget
        }
        guard Set(availability.map(\.weekday)).count == Weekday.allCases.count,
              availability.count == Weekday.allCases.count,
              availability.contains(where: \.isAvailable) else {
            throw PublicPreparationError.noAvailableDays
        }

        settings.publicExam = exam
        settings.publicExamDate = date
        settings.publicWeeklyTargetMinutes = weeklyMinutes
        settings.publicAvailability = availability
        let diagnosticID = DiagnosticAssessmentService.assessmentID(profileID: settings.id, exam: exam)
        let completed = try context.fetch(FetchDescriptor<DiagnosticAssessment>()).contains {
            $0.stableID == diagnosticID && $0.completedAt != nil
        }
        let programmeID = PublicProgrammeService.programmeID(settings: settings)
        let programmes = try context.fetch(FetchDescriptor<PublicProgramme>())
        let hasProgramme = completed && programmes.contains { $0.stableID == programmeID }
        settings.publicOnboardingStage = hasProgramme ? .programme : completed ? .diagnosticsComplete : .diagnostics
        try context.save()
    }
}

extension PublicPreparationService {
    /// Saves the flexible TMUA profile. Existing diagnostic and programme
    /// records are kept; only the onboarding stage is recalculated from them.
    static func saveFlexibleTMUAProfile(
        examDate: Date,
        weeklyMinutes: Int,
        availability: [DayAvailability],
        sessionMinutes: Int?,
        today: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar(),
        settings: AppSettings,
        in context: ModelContext
    ) throws {
        let date = calendar.startOfDay(for: examDate)
        guard date > calendar.startOfDay(for: today) else { throw PublicPreparationError.invalidExamDate }
        guard weeklyMinutes > 0 else { throw PublicPreparationError.invalidWeeklyTarget }
        guard Set(availability.map(\.weekday)).count == Weekday.allCases.count,
              availability.count == Weekday.allCases.count,
              availability.contains(where: \.isAvailable) else {
            throw PublicPreparationError.noAvailableDays
        }
        if let sessionMinutes, sessionMinutes < PublicPlanningPolicy.questionMinutes(for: .tmua) {
            throw PublicPreparationError.invalidWeeklyTarget
        }
        settings.publicExam = .tmua
        settings.publicFlowVersion = 2
        settings.publicExamDate = date
        settings.publicWeeklyTargetMinutes = weeklyMinutes
        settings.publicAvailability = availability
        settings.publicSessionMinutes = sessionMinutes
        let diagnostic = try TMUADiagnosticService.load(settings: settings, in: context)
        let programme = try TMUAProgrammeService.load(settings: settings, in: context)
        settings.publicOnboardingStage = programme != nil ? .programme
            : diagnostic?.isInitialComplete == true ? .diagnosticsComplete : .diagnostics
        try context.save()
    }

    /// Days from today until the exam, excluding exam day itself, counted in
    /// calendar days so daylight-saving changes cannot shift the result.
    static func daysUntilExam(_ examDate: Date, today: Date = .now,
                              calendar: Calendar = DateUtilities.appCalendar()) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                to: calendar.startOfDay(for: examDate)).day ?? 0
    }

    static func studyDaysBeforeExam(_ examDate: Date, availability: [DayAvailability], today: Date = .now,
                                    calendar: Calendar = DateUtilities.appCalendar()) -> Int {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: examDate)
        var count = 0
        var date = start
        while date < end {
            if PublicProgrammeAvailability.isAvailable(on: date, schedule: availability, calendar: calendar) == true {
                count += 1
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? end
        }
        return count
    }
}
