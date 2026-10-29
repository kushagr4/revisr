import Foundation
import SwiftData

enum TMUAResourceOutcome: String, CaseIterable, Codable, Sendable {
    case correct
    case incorrect
    case partial
    /// Worked but not yet marked against the solution.
    case attempted
    /// R5: left out on purpose. Never counted as worked, let alone correct.
    case skipped

    var title: String {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Incorrect"
        case .partial: "Partly right"
        case .attempted: "Not yet checked"
        case .skipped: "Skipped"
        }
    }

    /// A whole paper is recorded as worked or not; skipping it is not a result.
    static let paperOutcomes: [Self] = [.correct, .partial, .incorrect, .attempted]
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

    /// The raw value is a string, so outcomes added later need no migration; an unknown one reads as
    /// "not yet checked" rather than as a result.
    var outcome: TMUAResourceOutcome { TMUAResourceOutcome(rawValue: outcomeRawValue) ?? .attempted }

    /// Orders results by time, then by content (never by record ID), so ties read the same way in
    /// every store.
    static func isEarlier(_ lhs: TMUAResourceLog, _ rhs: TMUAResourceLog) -> Bool {
        (lhs.recordedAt, lhs.outcomeRawValue, lhs.programmeTaskID ?? "", lhs.sourceID, lhs.minutes ?? -1)
            < (rhs.recordedAt, rhs.outcomeRawValue, rhs.programmeTaskID ?? "", rhs.sourceID, rhs.minutes ?? -1)
    }

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
