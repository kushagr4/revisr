import Foundation
import SwiftData

@Model
final class StudySession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var actualStartDate: Date?
    var endDate: Date?
    var duration: TimeInterval
    var activityRawValue: String
    var notes: String

    var subject: Subject?
    var module: StudyModule?
    var topic: Topic?
    var plannedBlock: PlannedStudyBlock?

    var subjectNameSnapshot: String
    var moduleNameSnapshot: String?
    var topicNameSnapshot: String?

    var activity: StudyActivity {
        get { StudyActivity(rawValue: activityRawValue) ?? .revision }
        set { activityRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date,
        actualStartDate: Date? = nil,
        endDate: Date? = nil,
        duration: TimeInterval,
        activity: StudyActivity,
        notes: String = "",
        subject: Subject? = nil,
        module: StudyModule? = nil,
        topic: Topic? = nil,
        plannedBlock: PlannedStudyBlock? = nil,
        subjectNameSnapshot: String,
        moduleNameSnapshot: String? = nil,
        topicNameSnapshot: String? = nil
    ) {
        self.id = id
        self.date = date
        self.actualStartDate = actualStartDate
        self.endDate = endDate
        self.duration = duration
        self.activityRawValue = activity.rawValue
        self.notes = notes
        self.subject = subject
        self.module = module
        self.topic = topic
        self.plannedBlock = plannedBlock
        self.subjectNameSnapshot = subjectNameSnapshot
        self.moduleNameSnapshot = moduleNameSnapshot
        self.topicNameSnapshot = topicNameSnapshot
    }
}
