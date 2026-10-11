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
