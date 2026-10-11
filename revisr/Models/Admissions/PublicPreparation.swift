import Foundation

enum PublicOnboardingStage: String, Sendable {
    case profile
    case diagnostics
    case diagnosticsComplete
    case programme
}

enum PublicExamKind: String, CaseIterable, Identifiable, Sendable {
    case tmua
    case smc
    case bmo

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var preparationStream: PreparationStreamKind {
        switch self {
        case .tmua: .tmua
        case .smc: .smc
        case .bmo: .bmo
        }
    }

    var assessmentStyle: PublicAssessmentStyle {
        switch self {
        case .tmua, .smc: .multipleChoice
        case .bmo: .writtenMarksAndSelfAssessment
        }
    }
}

enum PublicAssessmentStyle: Equatable, Sendable {
    case multipleChoice
    case writtenMarksAndSelfAssessment
}

enum PublicProgrammeAvailability {
    /// Returns nil when a saved schedule has no entry for the date's weekday.
    static func isAvailable(
        on date: Date,
        schedule: [DayAvailability],
        calendar: Calendar
    ) -> Bool? {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else {
            return nil
        }
        return schedule.first { $0.weekday == weekday }?.isAvailable
    }
}
