import Foundation
import SwiftData

@Model
final class StudyResult {
    @Attribute(.unique) var id: UUID
    var date: Date
    var paperOrModuleLabel: String
    var rawScore: Double?
    var maximumScore: Double?
    var scaledScore: Double?
    var notes: String

    var subject: Subject?
    var module: StudyModule?

    var subjectNameSnapshot: String
    var moduleNameSnapshot: String?

    /// A validated raw-score ratio, or `nil` for scaled-only results.
    var rawPercentage: Double? {
        guard
            let rawScore,
            let maximumScore,
            DomainValidation.isValidResult(rawScore: rawScore, maximumScore: maximumScore)
        else { return nil }
        return rawScore / maximumScore
    }

    /// Kept as a non-optional convenience for existing summary surfaces.
    var percentage: Double {
        rawPercentage ?? 0
    }

    init(
        id: UUID = UUID(),
        date: Date,
        paperOrModuleLabel: String,
        rawScore: Double? = nil,
        maximumScore: Double? = nil,
        scaledScore: Double? = nil,
        notes: String = "",
        subject: Subject? = nil,
        module: StudyModule? = nil,
        subjectNameSnapshot: String,
        moduleNameSnapshot: String? = nil
    ) {
        self.id = id
        self.date = date
        self.paperOrModuleLabel = paperOrModuleLabel
        self.rawScore = rawScore
        self.maximumScore = maximumScore
        self.scaledScore = scaledScore
        self.notes = notes
        self.subject = subject
        self.module = module
        self.subjectNameSnapshot = subjectNameSnapshot
        self.moduleNameSnapshot = moduleNameSnapshot
    }
}
