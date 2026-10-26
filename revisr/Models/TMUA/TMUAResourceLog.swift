import Foundation
import SwiftData

enum TMUAResourceOutcome: String, CaseIterable, Codable, Sendable {
    case correct
    case incorrect
    case partial
    case attempted

    var title: String {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Incorrect"
        case .partial: "Partly right"
        case .attempted: "Attempted"
        }
    }
}

/// A result the student recorded themselves for a paper or question that Revisr cannot mark:
/// a bundled study copy without an answer key, or a paper on a provider's website.
/// Kept apart from `TMUAPracticeAttempt`, so self-reports never count as verified evidence.
@Model
final class TMUAResourceLog {
    @Attribute(.unique) var id: UUID
    var profileSettingsID: UUID
    var sourceID: String
    /// Nil for a result covering the whole paper.
    var questionID: String?
    var outcomeRawValue: String
    /// Whole-paper score, when recorded.
    var correctCount: Int?
    var questionCount: Int?
    var minutes: Int?
    var recordedAt: Date
    var programmeTaskID: String?

    var outcome: TMUAResourceOutcome { TMUAResourceOutcome(rawValue: outcomeRawValue) ?? .attempted }

    init(profileSettingsID: UUID, sourceID: String, questionID: String?, outcome: TMUAResourceOutcome,
         correctCount: Int? = nil, questionCount: Int? = nil, minutes: Int? = nil,
         recordedAt: Date = .now, programmeTaskID: String? = nil) {
        id = UUID()
        self.profileSettingsID = profileSettingsID
        self.sourceID = sourceID
        self.questionID = questionID
        outcomeRawValue = outcome.rawValue
        self.correctCount = correctCount
        self.questionCount = questionCount
        self.minutes = minutes
        self.recordedAt = recordedAt
        self.programmeTaskID = programmeTaskID
    }
}
