import Foundation
import SwiftData

@Model
final class StudyModule {
    @Attribute(.unique) var id: UUID
    var name: String
    var displayOrder: Int
    var subject: Subject?

    @Relationship(deleteRule: .cascade, inverse: \Topic.module)
    var topics: [Topic]

    init(
        id: UUID = UUID(),
        name: String,
        displayOrder: Int,
        subject: Subject? = nil,
        topics: [Topic] = []
    ) {
        self.id = id
        self.name = name
        self.displayOrder = displayOrder
        self.subject = subject
        self.topics = topics
    }
}
