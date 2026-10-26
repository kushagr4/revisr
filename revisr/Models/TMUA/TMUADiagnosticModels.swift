import Foundation
import SwiftData

enum TMUASectionStatus: String, Sendable {
    case notStarted
    case inProgress
    case submitted
}

enum TMUAItemMarking: String, Sendable {
    case correct
    case incorrect
    case unanswered
}

/// A student's flexible TMUA diagnostic. Rounds are append-only: the initial
/// round and each later expansion keep their own sections and timing.
@Model
final class TMUADiagnostic {
    @Attribute(.unique) var stableID: String
    var profileSettingsID: UUID
    var createdAt: Date
    var initialLengthRawValue: String
    var targetLengthRawValue: String
    var bankVersion: String
    var distributionRawValue: String
    var contentPolicyVersion: String
    var selectorVersion: String
    var taxonomyVersion: String
    var sourceCompositionNote: String
    var initialCompletedAt: Date?
    var lastSubmittedAt: Date?

    var initialLength: TMUADiagnosticLength {
        TMUADiagnosticLength(rawValue: initialLengthRawValue) ?? .starter
    }

    var targetLength: TMUADiagnosticLength {
        get { TMUADiagnosticLength(rawValue: targetLengthRawValue) ?? initialLength }
        set { targetLengthRawValue = newValue.rawValue }
    }

    init(stableID: String, profileSettingsID: UUID, length: TMUADiagnosticLength,
         bankVersion: String, distribution: TMUAContentDistribution,
         sourceCompositionNote: String, createdAt: Date = .now) {
        self.stableID = stableID
        self.profileSettingsID = profileSettingsID
        self.createdAt = createdAt
        self.initialLengthRawValue = length.rawValue
        self.targetLengthRawValue = length.rawValue
        self.bankVersion = bankVersion
        self.distributionRawValue = distribution.rawValue
        self.contentPolicyVersion = TMUAContentPolicy.version
        self.selectorVersion = TMUADiagnosticSelector.version
        self.taxonomyVersion = TMUASyllabus.currentVersion
        self.sourceCompositionNote = sourceCompositionNote
    }
}

@Model
final class TMUADiagnosticSection {
    @Attribute(.unique) var stableID: String
    var diagnosticID: String
    var round: Int
    var paperRawValue: Int
    var roundTargetLengthRawValue: String
    var statusRawValue: String
    var currentIndex: Int
    var accumulatedSeconds: Double
    var runningSince: Date?
    var startedAt: Date?
    var submittedAt: Date?
    var lastSavedAt: Date?
    var advisoryMinutes: Int
    var pauseCount: Int
    var recoveredInterruptionCount: Int

    var paper: TMUAPaper { TMUAPaper(rawValue: paperRawValue) ?? .one }
    var roundTargetLength: TMUADiagnosticLength {
        TMUADiagnosticLength(rawValue: roundTargetLengthRawValue) ?? .starter
    }

    var status: TMUASectionStatus {
        get { TMUASectionStatus(rawValue: statusRawValue) ?? .notStarted }
        set { statusRawValue = newValue.rawValue }
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    init(stableID: String, diagnosticID: String, round: Int, paper: TMUAPaper,
         roundTarget: TMUADiagnosticLength, advisoryMinutes: Int) {
        self.stableID = stableID
        self.diagnosticID = diagnosticID
        self.round = round
        self.paperRawValue = paper.rawValue
        self.roundTargetLengthRawValue = roundTarget.rawValue
        self.statusRawValue = TMUASectionStatus.notStarted.rawValue
        self.currentIndex = 0
        self.accumulatedSeconds = 0
        self.advisoryMinutes = advisoryMinutes
        self.pauseCount = 0
        self.recoveredInterruptionCount = 0
    }
}

/// One pinned question version inside a section. The content snapshot keeps
/// the draft renderable and markable even if a later bank drops the version.
@Model
final class TMUADiagnosticItem {
    @Attribute(.unique) var stableID: String
    var sectionID: String
    var diagnosticID: String
    var ordinal: Int
    var itemStableID: String
    var itemVersion: Int
    var versionKey: String
    var paperRawValue: Int
    var topicKey: String
    var strandKey: String
    var skillKey: String?
    var difficulty: Int
    var categoryRawValue: String
    var contentSnapshot: Data
    var selectedOptionID: String?
    var answeredAt: Date?
    var isFlagged: Bool
    var markingRawValue: String?

    var category: TMUAContentCategory {
        TMUAContentCategory(rawValue: categoryRawValue) ?? .revisrOriginal
    }

    var marking: TMUAItemMarking? {
        markingRawValue.flatMap(TMUAItemMarking.init(rawValue:))
    }

    var content: TMUAContentItem? {
        try? JSONDecoder().decode(TMUAContentItem.self, from: contentSnapshot)
    }

    init(sectionID: String, diagnosticID: String, ordinal: Int, item: TMUAContentItem) {
        self.stableID = "\(sectionID)-\(item.versionKey)"
        self.sectionID = sectionID
        self.diagnosticID = diagnosticID
        self.ordinal = ordinal
        self.itemStableID = item.stableId
        self.itemVersion = item.version
        self.versionKey = item.versionKey
        self.paperRawValue = item.paper
        self.topicKey = item.taxonomy.topic
        self.strandKey = item.taxonomy.strand
        self.skillKey = item.taxonomy.skill
        self.difficulty = item.difficulty
        self.categoryRawValue = item.category.rawValue
        self.contentSnapshot = (try? JSONEncoder().encode(item)) ?? Data()
        self.isFlagged = false
    }
}

enum TMUAPracticeOrigin: String, Sendable {
    case programme
    case questionBank
}

/// A native practice attempt, marked automatically from the pinned key.
@Model
final class TMUAPracticeAttempt {
    @Attribute(.unique) var id: UUID
    var profileSettingsID: UUID
    var itemStableID: String
    var itemVersion: Int
    var topicKey: String
    var strandKey: String
    var paperRawValue: Int
    var attemptedAt: Date
    var selectedOptionID: String
    var isCorrect: Bool
    var seconds: Int
    var originRawValue: String
    var programmeTaskID: String?

    var origin: TMUAPracticeOrigin { TMUAPracticeOrigin(rawValue: originRawValue) ?? .questionBank }

    init(profileSettingsID: UUID, item: TMUAContentItem, selectedOptionID: String,
         seconds: Int, origin: TMUAPracticeOrigin, programmeTaskID: String?, at date: Date) {
        self.id = UUID()
        self.profileSettingsID = profileSettingsID
        self.itemStableID = item.stableId
        self.itemVersion = item.version
        self.topicKey = item.taxonomy.topic
        self.strandKey = item.taxonomy.strand
        self.paperRawValue = item.paper
        self.attemptedAt = date
        self.selectedOptionID = selectedOptionID
        self.isCorrect = selectedOptionID == item.correctOptionId
        self.seconds = max(0, seconds)
        self.originRawValue = origin.rawValue
        self.programmeTaskID = programmeTaskID
    }
}

@Model
final class TMUAReviewFlag {
    @Attribute(.unique) var stableID: String
    var profileSettingsID: UUID
    var itemStableID: String
    var isFlagged: Bool
    var updatedAt: Date

    init(profileSettingsID: UUID, itemStableID: String, isFlagged: Bool, at date: Date) {
        self.stableID = "\(profileSettingsID.uuidString)-\(itemStableID)"
        self.profileSettingsID = profileSettingsID
        self.itemStableID = itemStableID
        self.isFlagged = isFlagged
        self.updatedAt = date
    }
}
