import Foundation
import SwiftData

@Model
final class Subject {
    @Attribute(.unique) var id: UUID
    var name: String
    var targetPercentage: Double
    var displayOrder: Int
    var accentIdentifierRawValue: String?
    /// Legacy school subjects remain in migrated stores but are excluded from all
    /// current admissions-preparation workflows.
    var isActiveForStudy: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \StudyModule.subject)
    var modules: [StudyModule]

    var accentIdentifier: SubjectAccentID? {
        get { accentIdentifierRawValue.flatMap(SubjectAccentID.init(rawValue:)) }
        set { accentIdentifierRawValue = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        targetPercentage: Double,
        displayOrder: Int,
        accentIdentifier: SubjectAccentID? = nil,
        isActiveForStudy: Bool = true,
        modules: [StudyModule] = []
    ) {
        self.id = id
        self.name = name
        self.targetPercentage = targetPercentage
        self.displayOrder = displayOrder
        self.accentIdentifierRawValue = accentIdentifier?.rawValue
        self.isActiveForStudy = isActiveForStudy
        self.modules = modules
    }
}
