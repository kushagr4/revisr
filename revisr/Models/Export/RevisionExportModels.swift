import Foundation

struct RevisionExportV1: Codable, Equatable, Sendable {
    let export: RevisionExportMetadataV1
    let profile: RevisionProfileExportV1
    let tmua: TMUAContextExportV1
    let programme: ProgrammeSnapshotExportV1
    let performance: PerformanceExportV1
    let needsReview: NeedsReviewExportV1
    let specificationCoverage: SpecificationCoverageExportV1
    let results: [ResultExportV1]
    let standby: StandbyExportV1
    let recentActivity: RecentActivityExportV1
    let upcoming: UpcomingExportV1
    let questionCatalog: [QuestionExportV1]
    let attemptHistory: [QuestionAttemptHistoryExportV1]
}

struct RevisionExportMetadataV1: Codable, Equatable, Sendable {
    let formatIdentifier: String
    let schemaVersion: Int
    let exportedAt: String
    let appName: String
    let appVersion: String
    let appBuild: String
}

struct RevisionProfileExportV1: Codable, Equatable, Sendable {
    let activeAdmissionsTest: String
    let programmeName: String?
    let programmeStartDate: String?
    let currentProgrammeDay: Int?
    let tmuaExamDate: String?
    let csatStatus: String
}

struct TMUAContextExportV1: Codable, Equatable, Sendable {
    let status: String
    let examDate: String?
    let paper1Target: Double?
    let paper2Target: Double?
    let protectionPolicy: String
    let protectedQuestions: [ProtectedQuestionExportV1]
}

struct ProgrammeSnapshotExportV1: Codable, Equatable, Sendable {
    let programmeID: String?
    let name: String?
    let totalDays: Int
    let currentDayNumber: Int?
    let completedDayNumbers: [Int]
    let completedAssignments: Int
    let totalAssignments: Int
    let overdueIncompleteAssignments: [ProgrammeAssignmentExportV1]
    let currentDay: ProgrammeDayExportV1?
}

struct ProgrammeDayExportV1: Codable, Equatable, Sendable {
    let dayID: String
    let dayNumber: Int
    let date: String
    let focus: String
    let studyBrief: String
    let dailyTarget: String?
    let notes: String?
    let expectedQuestionMinutes: Int
    let expectedReviewMinutes: Int
    let expectedTotalMinutes: Int
    let allocatedQuestionCount: Int
    let completedAssignmentCount: Int
    let assignments: [ProgrammeAssignmentExportV1]
    let scheduleOffsetDays: Int?
    let earliestStartMinute: Int?
}

struct ProgrammeAssignmentExportV1: Codable, Equatable, Sendable {
    let assignmentID: String
    let dayNumber: Int
    let questionID: String
    let status: String
    let latestOutcome: String?
    let needsReview: Bool
    let block: String?
    let purpose: String?
    let suggestedTimeCapMinutes: Int?
    let displayOrder: Int
}

struct UpcomingExportV1: Codable, Equatable, Sendable {
    let windowDefinition: String
    let days: [ProgrammeDayExportV1]
}

struct QuestionAttemptHistoryExportV1: Codable, Equatable, Sendable {
    let questionID: String
    let attempts: [AttemptExportV1]
}

struct AttemptExportV1: Codable, Equatable, Sendable {
    let attemptID: String
    let attemptNumber: Int
    let questionID: String
    let attemptedAt: String
    let outcome: String
    let timeTakenSeconds: Int
    let errorType: String?
    let notes: String?
    let origin: String
    let programmeDay: Int?
    let programmeAssignmentID: String?
}

struct QuestionExportV1: Codable, Equatable, Sendable {
    let questionID: String
    let admissionsTest: String
    let primaryPreparationStream: String?
    let intendedUses: [String]?
    let effectivePreparationStreams: [String]?
    let preparationClassificationSource: String?
    let family: String
    let year: Int?
    let paper: String?
    let section: String?
    let questionLabel: String
    let page: Int?
    let primaryTopic: String
    let secondaryTopic: String?
    let reasoningSkill: String?
    let tmuaPaperFit: String?
    let difficulty: Int
    let difficultyLabel: String
    let difficultyProvenance: String?
    let validityState: String?
    let validityReason: String?
    let duplicateReviewState: String?
    let possibleDuplicateQuestionIDs: [String]?
    let tmuaRelevance: Double?
    let format: String?
    let recommendedUse: String?
    let classificationConfidence: String?
    let descriptor: String?
    let sourceID: String?
    let sourceDisplayName: String?
    let sourceFilename: String?
    let solutionAvailable: Bool
    let solutionType: String?
    let solutionStatus: String
    let solutionSourceID: String?
    let solutionMediaType: String?
    let videoAvailable: Bool?
    let reviewState: String
    let notes: String?
    let scheduled: Bool
    let standby: Bool
    let protection: QuestionProtectionExportV1
}

struct QuestionProtectionExportV1: Codable, Equatable, Sendable {
    let policy: String
    let manuallySelectable: Bool
    let excludedFromAutomaticPractice: Bool
    let benchmarkState: String
    let futureProgrammeDay: Int?
}

struct ProtectedQuestionExportV1: Codable, Equatable, Sendable {
    let questionID: String
    let sourceID: String?
    let sourceDisplayName: String?
    let family: String
    let year: Int?
    let paper: String?
    let policy: String
    let manuallySelectable: Bool
    let excludedFromAutomaticPractice: Bool
    let benchmarkState: String
    let futureProgrammeDay: Int?
}

struct PerformanceExportV1: Codable, Equatable, Sendable {
    let accuracyDefinition: String
    let percentageScale: String
    let overall: OverallPerformanceExportV1
    let paperFit: [MetricBreakdownExportV1]
    let difficulty: [MetricBreakdownExportV1]
    let topics: [TopicPerformanceExportV1]
    let errorTypes: [CountExportV1]
}

struct OverallPerformanceExportV1: Codable, Equatable, Sendable {
    let uniqueQuestionsAttempted: Int
    let totalAttempts: Int
    let correctAttempts: Int
    let incorrectAttempts: Int
    let partialAttempts: Int
    let skippedAttempts: Int
    let latestCorrect: Int
    let latestIncorrect: Int
    let latestPartial: Int
    let latestResultAccuracy: Double?
    let attemptLevelAccuracy: Double?
    let averageTimeSeconds: Double?
    let medianTimeSeconds: Double?
}

struct MetricBreakdownExportV1: Codable, Equatable, Sendable {
    let key: String
    let questionsAttempted: Int
    let latestCorrect: Int
    let latestIncorrect: Int
    let latestPartial: Int
    let accuracy: Double?
    let averageTimeSeconds: Double?
}

struct TopicPerformanceExportV1: Codable, Equatable, Sendable {
    let topic: String
    let questionsAttempted: Int
    let latestCorrect: Int
    let latestIncorrect: Int
    let latestPartial: Int
    let accuracy: Double?
    let averageTimeSeconds: Double?
    let needsReviewCount: Int
}

struct CountExportV1: Codable, Equatable, Sendable {
    let key: String
    let count: Int
}

struct NeedsReviewExportV1: Codable, Equatable, Sendable {
    let questions: [QuestionReviewExportV1]
    let topics: [TopicReviewExportV1]
}

struct QuestionReviewExportV1: Codable, Equatable, Sendable {
    let question: QuestionExportV1
    let latestOutcome: String?
    let latestErrorType: String?
    let attemptCount: Int
    let latestAttemptAt: String?
    let reviewState: String
    let notes: String?
}

struct TopicReviewExportV1: Codable, Equatable, Sendable {
    let topicID: String
    let name: String
    let manualStatus: String
    let reviewState: String
    let specificationCoverage: String
    let notes: String?
}

struct SpecificationCoverageExportV1: Codable, Equatable, Sendable {
    let scope: String
    let total: Int
    let covered: Int
    let learning: Int
    let notStarted: Int
    let coveragePercentage: Double?
    let items: [SpecificationItemExportV1]
}

struct SpecificationItemExportV1: Codable, Equatable, Sendable {
    let stableID: String
    let officialCode: String?
    let section: String?
    let title: String
    let coverageStatus: String
    let lastReviewedAt: String?
    let linkedTopic: String?
    let notes: String?
}

struct ResultExportV1: Codable, Equatable, Sendable {
    let resultID: String
    let date: String
    let testOrPaper: String
    let rawScore: Double?
    let maximumScore: Double?
    let scaledScore: Double?
    let percentage: Double?
    let notes: String?
}

struct StandbyExportV1: Codable, Equatable, Sendable {
    let totalQuestions: Int
    let unattemptedQuestions: Int
    let needsReviewCount: Int
    let byPrimaryTopic: [CountExportV1]
    let byDifficulty: [CountExportV1]
    let byPaperFit: [CountExportV1]
    let questions: [QuestionExportV1]
}

struct RecentActivityExportV1: Codable, Equatable, Sendable {
    let selectionDefinition: String
    let attempts: [RecentAttemptExportV1]
}

struct RecentAttemptExportV1: Codable, Equatable, Sendable {
    let attemptedAt: String
    let questionID: String
    let outcome: String
    let timeTakenSeconds: Int
    let errorType: String?
    let reviewState: String
}

struct FullExportManifestV1: Codable, Equatable, Sendable {
    let formatIdentifier: String
    let schemaVersion: Int
    let exportedAt: String
    let appName: String
    let appVersion: String
    let appBuild: String
    let activeAdmissionsTest: String
    let files: [String]
    let exclusions: [String]
}

struct FullProgrammeExportV1: Codable, Equatable, Sendable {
    let programmeID: String
    let name: String
    let admissionsTest: String
    let startDate: String
    let days: [ProgrammeDayExportV1]
}

struct SettingsExportV1: Codable, Equatable, Sendable {
    let activeAdmissionsTest: String
    let tmuaExamDate: String
    let tmuaProgrammeStartDate: String
    let tmuaPaper1Target: Double
    let tmuaPaper2Target: Double
    let csatStatus: String
}

struct TopicExportV1: Codable, Equatable, Sendable {
    let topicID: String
    let admissionsTest: String
    let name: String
    let manualStatus: String
    let needsReview: Bool
    let specificationCoverage: String
    let notes: String?
}

struct SourceExportV1: Codable, Equatable, Sendable {
    let sourceID: String
    let displayName: String
    let filename: String
    let family: String
    let year: Int?
    let paper: String?
    let pageCount: Int?
    let questionUnitCount: Int
    let availability: String
    let containsProtectedQuestions: Bool
    let solutionStatus: String
    let solutionDocumentIDs: [String]
}

struct SolutionDocumentExportV1: Codable, Equatable, Sendable {
    let solutionID: String
    let displayName: String
    let solutionType: String
    let family: String
    let year: Int?
    let paper: String?
    let provenanceOrganization: String
    let provenanceTitle: String
    let originalFilename: String
    let availability: String
    let verifiedSourceMatch: Bool
    let sourceID: String?
    let additionalSourceIDs: [String]?
    let mediaType: String?
    let videoAvailable: Bool?
    let directQuestionMappings: Int
    let sourceLevelMappings: Int
}
