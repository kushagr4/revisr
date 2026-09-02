import Foundation
import SwiftData

@Model
final class WeeklyFocus {
    @Attribute(.unique) var id: UUID
    var weekStart: Date
    var title: String
    var displayOrder: Int

    init(id: UUID = UUID(), weekStart: Date, title: String, displayOrder: Int) {
        self.id = id
        self.weekStart = weekStart
        self.title = title
        self.displayOrder = displayOrder
    }
}
