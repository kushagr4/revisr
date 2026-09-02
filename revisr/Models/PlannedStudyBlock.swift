import Foundation
import SwiftData

@Model
final class PlannedStudyBlock {
    @Attribute(.unique) var id: UUID
    /// A start-of-day value in the calendar used when the block was created.
    var day: Date
    /// Local wall-clock minutes after midnight. `nil` means intentionally unscheduled.
    var startMinute: Int?
    var duration: TimeInterval
    var activityRawValue: String
    var statusRawValue: String
    var createdAt: Date

    var subject: Subject?
    var module: StudyModule?
    var topic: Topic?

    @Relationship(deleteRule: .nullify, inverse: \StudySession.plannedBlock)
    var linkedSession: StudySession?

    var activity: StudyActivity {
        get { StudyActivity(rawValue: activityRawValue) ?? .revision }
        set { activityRawValue = newValue.rawValue }
    }

    var status: PlannedBlockStatus {
        get { PlannedBlockStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }

    var isScheduled: Bool { startMinute != nil }

    init(
        id: UUID = UUID(),
        day: Date,
        startMinute: Int? = nil,
        duration: TimeInterval,
        activity: StudyActivity,
        status: PlannedBlockStatus = .planned,
        createdAt: Date = .now,
        subject: Subject? = nil,
        module: StudyModule? = nil,
        topic: Topic? = nil,
        linkedSession: StudySession? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.id = id
        self.day = calendar.startOfDay(for: day)
        self.startMinute = startMinute
        self.duration = duration
        self.activityRawValue = activity.rawValue
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.subject = subject
        self.module = module
        self.topic = topic
        self.linkedSession = linkedSession
    }

    func scheduledStart(using calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard let startMinute else { return nil }
        return calendar.date(byAdding: .minute, value: startMinute, to: calendar.startOfDay(for: day))
    }
}
