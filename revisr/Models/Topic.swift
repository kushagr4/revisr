import Foundation
import SwiftData

@Model
final class Topic {
    @Attribute(.unique) var id: UUID
    var name: String
    var statusRawValue: String
    var needsReview: Bool
    var notes: String
    var displayOrder: Int
    /// Seeded curriculum remains protected; user-created topics may be moved or deleted.
    var isCustom: Bool = false
    var module: StudyModule?

    var status: TopicStatus {
        get { TopicStatus(rawValue: statusRawValue) ?? .good }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        status: TopicStatus = .good,
        needsReview: Bool = false,
        notes: String = "",
        displayOrder: Int,
        isCustom: Bool = false,
        module: StudyModule? = nil
    ) {
        self.id = id
        self.name = name
        self.statusRawValue = status.rawValue
        self.needsReview = needsReview
        self.notes = notes
        self.displayOrder = displayOrder
        self.isCustom = isCustom
        self.module = module
    }
}
