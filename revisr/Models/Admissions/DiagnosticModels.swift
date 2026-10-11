import Foundation
import SwiftData

enum DiagnosticPaperStatus: String, Sendable {
    case notStarted
    case answering
    case marking
    case completed
}

enum DiagnosticMarking: String, Sendable {
    case unassessed
    case correct
    case incorrect
}

enum DiagnosticScoringProvenance: String, Sendable {
    case selfMarkedWithPDF
    case selfEstimatedWithoutScheme
}

/// Stable, exam-scoped diagnostic history. The profile UUID links to the
/// public AppSettings record without changing legacy settings relationships.
@Model
final class DiagnosticAssessment {
    @Attribute(.unique) var stableID: String
    var profileSettingsID: UUID
    var examRawValue: String
    var createdAt: Date
    var completedAt: Date?

    var exam: PublicExamKind { PublicExamKind(rawValue: examRawValue) ?? .tmua }

    init(stableID: String, profileSettingsID: UUID, exam: PublicExamKind, createdAt: Date = .now) {
        self.stableID = stableID
        self.profileSettingsID = profileSettingsID
        self.examRawValue = exam.rawValue
        self.createdAt = createdAt
    }
}

@Model
final class DiagnosticPaperRecord {
    @Attribute(.unique) var stableID: String
    var assessmentID: String
    var sourceID: String
    var ordinal: Int
    var statusRawValue: String
    var startedAt: Date?
    var submittedAt: Date?
    var completedAt: Date?
    var accumulatedSeconds: Double
    var runningSince: Date?
    var scoringProvenanceRawValue: String

    var status: DiagnosticPaperStatus {
        get { DiagnosticPaperStatus(rawValue: statusRawValue) ?? .notStarted }
        set { statusRawValue = newValue.rawValue }
    }

    var scoringProvenance: DiagnosticScoringProvenance {
        DiagnosticScoringProvenance(rawValue: scoringProvenanceRawValue) ?? .selfMarkedWithPDF
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    init(
        stableID: String,
        assessmentID: String,
        sourceID: String,
        ordinal: Int,
        scoringProvenance: DiagnosticScoringProvenance
    ) {
        self.stableID = stableID
        self.assessmentID = assessmentID
        self.sourceID = sourceID
        self.ordinal = ordinal
        self.statusRawValue = DiagnosticPaperStatus.notStarted.rawValue
        self.accumulatedSeconds = 0
        self.scoringProvenanceRawValue = scoringProvenance.rawValue
    }
}

@Model
final class DiagnosticResponse {
    @Attribute(.unique) var stableID: String
    var paperID: String
    var questionID: String
    var selectedOption: String?
    var wasAttempted: Bool
    var markingRawValue: String
    var selfEstimatedMarks: Int?
    var notes: String

    var marking: DiagnosticMarking {
        get { DiagnosticMarking(rawValue: markingRawValue) ?? .unassessed }
        set { markingRawValue = newValue.rawValue }
    }

    init(stableID: String, paperID: String, questionID: String) {
        self.stableID = stableID
        self.paperID = paperID
        self.questionID = questionID
        self.wasAttempted = false
        self.markingRawValue = DiagnosticMarking.unassessed.rawValue
        self.notes = ""
    }
}
