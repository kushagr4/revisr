import Foundation

enum AdmissionsTestKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case tmua
    case csat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmua: "TMUA"
        case .csat: "CSAT"
        }
    }
}

/// Canonical preparation classification for catalogue content. This is kept
/// separate from `AdmissionsTestKind`, whose persisted value is legacy data.
enum PreparationStreamKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case tmua
    case csat
    case smc
    case bmo
    case cambridgeCSInterview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmua: "TMUA"
        case .csat: "CSAT"
        case .smc: "SMC"
        case .bmo: "BMO"
        case .cambridgeCSInterview: "Cambridge CS Interview"
        }
    }
}

enum DifficultyProvenance: String, Codable, CaseIterable, Identifiable, Sendable {
    case sourceProvided
    case editoriallyEstimated
    case inferred

    var id: String { rawValue }
}

enum QuestionValidityState: String, Codable, CaseIterable, Identifiable, Sendable {
    case usable
    case needsReview
    case invalid

    var id: String { rawValue }
}

enum DuplicateReviewState: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case possibleDuplicate
    case verifiedDistinct
    case confirmedDuplicate

    var id: String { rawValue }
}

enum DuplicateEvidenceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case exactBinaryChecksum
    case normalizedExtractedTextChecksum
    case verifiedSemanticDocumentIdentity
    case verifiedQuestionIdentity
    case possibleDuplicate

    var id: String { rawValue }
}

enum AdmissionsTestStatus: String, Codable, Sendable {
    case active
    case inactive
}

enum QuestionAttemptOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case correct
    case incorrect
    case partial
    case skipped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Incorrect"
        case .partial: "Partial"
        case .skipped: "Skipped"
        }
    }

    var systemImage: String {
        switch self {
        case .correct: "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .skipped: "forward.circle"
        }
    }
}

enum QuestionReviewState: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case needsReview
    case redo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No Review Flag"
        case .needsReview: "Needs Review"
        case .redo: "Redo"
        }
    }
}

enum QuestionErrorType: String, Codable, CaseIterable, Identifiable, Sendable {
    case knowledge
    case approach
    case algebra
    case misread
    case logic
    case slow
    case careless

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum QuestionProtection: String, Codable, Sendable {
    case none
    case protectedFromAutomaticSelection
}

enum QuestionAttemptOrigin: String, Codable, CaseIterable, Sendable {
    case programme
    case questionBank
    case extraPractice
    case needsReview
}

enum SpecificationCoverageState: String, Codable, CaseIterable, Identifiable, Sendable {
    case notStarted
    case learning
    case covered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: "Not Started"
        case .learning: "Learning"
        case .covered: "Covered"
        }
    }
}

enum AttemptTimerStatus: String, Codable, Sendable {
    case idle
    case running
    case paused
}

enum SolutionDocumentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case workedSolution
    case markScheme
    case answerKey
    case solutionsAndInvestigations
    case combinedQuestionsAndSolutions
    case videoSolution
    case examinerReport
    case hintsAndSolutions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workedSolution: "Worked Solution"
        case .markScheme: "Mark Scheme"
        case .answerKey: "Answer Key"
        case .solutionsAndInvestigations: "Solutions & Investigations"
        case .combinedQuestionsAndSolutions: "Questions & Solutions"
        case .videoSolution: "Video Solution"
        case .examinerReport: "Examiner Report"
        case .hintsAndSolutions: "Hints & Solutions"
        }
    }

    var actionTitle: String {
        switch self {
        case .markScheme: "View Mark Scheme"
        case .videoSolution: "Watch Video Solution"
        case .examinerReport: "View Examiner Report"
        case .hintsAndSolutions: "View Hints & Solutions"
        default: "View Solution"
        }
    }

    var preferenceOrder: Int {
        switch self {
        case .workedSolution: 0
        case .solutionsAndInvestigations: 1
        case .combinedQuestionsAndSolutions: 2
        case .markScheme: 3
        case .answerKey: 4
        case .videoSolution: 5
        case .hintsAndSolutions: 6
        case .examinerReport: 7
        }
    }
}

enum SolutionMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case pdf
    case video

    var id: String { rawValue }
}

enum SolutionAvailability: String, Codable, CaseIterable, Identifiable, Sendable {
    case available
    case partial
    case pendingSource
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: "Available"
        case .partial: "Partial"
        case .pendingSource: "Pending Source"
        case .unavailable: "Unavailable"
        }
    }
}

enum SolutionResourceContainer: String, Codable, Sendable {
    case solutionBundle
    case sourcePaperBundle
    case videoBundle
}

enum SolutionMappingConfidence: String, Codable, Sendable {
    case verifiedPage
    case sourceSection
    case paperLevel
}

enum SolutionRevealRequirement: Equatable, Sendable {
    case none
    case unattempted
    case protectedQuestion
}
