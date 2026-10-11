import Foundation
import SwiftData

/// Public plans are separate from imported personal AdmissionsProgramme rows.
@Model
final class PublicProgramme {
    @Attribute(.unique) var stableID: String
    var profileSettingsID: UUID
    var examRawValue: String
    var generatedAt: Date
    var refreshedAt: Date
    var revision: Int
    var examDateSnapshot: Date
    var weeklyMinutesSnapshot: Int
    var availabilitySnapshotData: Data
    var completedCountAtRefresh: Int

    var exam: PublicExamKind { PublicExamKind(rawValue: examRawValue) ?? .tmua }
    var availabilitySnapshot: [DayAvailability] {
        (try? JSONDecoder().decode([DayAvailability].self, from: availabilitySnapshotData)) ?? []
    }

    init(stableID: String, profileSettingsID: UUID, exam: PublicExamKind,
         generatedAt: Date, examDate: Date, weeklyMinutes: Int,
         availability: [DayAvailability]) {
        self.stableID = stableID
        self.profileSettingsID = profileSettingsID
        self.examRawValue = exam.rawValue
        self.generatedAt = generatedAt
        self.refreshedAt = generatedAt
        self.revision = 1
        self.examDateSnapshot = examDate
        self.weeklyMinutesSnapshot = weeklyMinutes
        self.availabilitySnapshotData = (try? JSONEncoder().encode(availability)) ?? Data()
        self.completedCountAtRefresh = 0
    }
}

@Model
final class PublicProgrammeTask {
    @Attribute(.unique) var stableID: String
    var programmeID: String
    var scheduledDate: Date
    var questionID: String?
    var sourceID: String
    var topic: String
    var allocatedMinutes: Int
    var activityRawValue: String
    var reason: String
    var isActive: Bool
    var completedAt: Date?
    var completionAttemptID: UUID?
    var completionNote: String

    var activity: PublicPlanningActivity {
        PublicPlanningActivity(rawValue: activityRawValue) ?? .targeted
    }

    init(stableID: String, programmeID: String, task: PublicPlannedTask) {
        self.stableID = stableID
        self.programmeID = programmeID
        self.scheduledDate = task.date
        self.questionID = task.questionID
        self.sourceID = task.sourceID
        self.topic = task.topic
        self.allocatedMinutes = task.minutes
        self.activityRawValue = task.activity.rawValue
        self.reason = task.reason
        self.isActive = true
        self.completionNote = ""
    }
}

struct PublicProgrammeProgressSnapshot {
    let plannedTaskCount: Int
    let completedTaskCount: Int
    let activeTaskCount: Int
    let completedAttemptIDs: Set<UUID>

    init(tasks: [PublicProgrammeTask]) {
        let trackedTasks = tasks.filter { $0.isActive || $0.completedAt != nil }
        plannedTaskCount = trackedTasks.count
        completedTaskCount = trackedTasks.filter { $0.completedAt != nil }.count
        activeTaskCount = trackedTasks.filter(\.isActive).count
        completedAttemptIDs = Set(trackedTasks.compactMap(\.completionAttemptID))
    }
}
