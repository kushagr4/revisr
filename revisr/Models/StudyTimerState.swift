import Foundation
import SwiftData

@Model
final class StudyTimerState {
    @Attribute(.unique) var id: UUID
    var statusRawValue: String
    var startedAt: Date?
    var runningSince: Date?
    var accumulatedDuration: TimeInterval
    var plannedDuration: TimeInterval?
    var activityRawValue: String

    var subject: Subject?
    var module: StudyModule?
    var topic: Topic?
    var plannedBlock: PlannedStudyBlock?

    var status: StudyTimerStatus {
        get { StudyTimerStatus(rawValue: statusRawValue) ?? .idle }
        set { statusRawValue = newValue.rawValue }
    }

    var activity: StudyActivity {
        get { StudyActivity(rawValue: activityRawValue) ?? .revision }
        set { activityRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        status: StudyTimerStatus = .idle,
        startedAt: Date? = nil,
        runningSince: Date? = nil,
        accumulatedDuration: TimeInterval = 0,
        plannedDuration: TimeInterval? = nil,
        activity: StudyActivity = .revision,
        subject: Subject? = nil,
        module: StudyModule? = nil,
        topic: Topic? = nil,
        plannedBlock: PlannedStudyBlock? = nil
    ) {
        self.id = id
        self.statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.runningSince = runningSince
        self.accumulatedDuration = accumulatedDuration
        self.plannedDuration = plannedDuration
        self.activityRawValue = activity.rawValue
        self.subject = subject
        self.module = module
        self.topic = topic
        self.plannedBlock = plannedBlock
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        guard status == .running, let runningSince else { return accumulatedDuration }
        return accumulatedDuration + max(0, date.timeIntervalSince(runningSince))
    }

    func start(at date: Date = .now) {
        startedAt = date
        runningSince = date
        accumulatedDuration = 0
        status = .running
    }

    func pause(at date: Date = .now) {
        accumulatedDuration = elapsed(at: date)
        runningSince = nil
        status = .paused
    }

    func resume(at date: Date = .now) {
        runningSince = date
        status = .running
    }

    func reset() {
        status = .idle
        startedAt = nil
        runningSince = nil
        accumulatedDuration = 0
        plannedDuration = nil
        subject = nil
        module = nil
        topic = nil
        plannedBlock = nil
    }
}
