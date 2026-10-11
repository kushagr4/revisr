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
