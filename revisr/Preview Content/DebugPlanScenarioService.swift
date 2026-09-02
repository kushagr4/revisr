#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DebugPlanScenarioService {
    static func applyIfRequested(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--plan-demo") || arguments.contains("--plan-tuesday") else { return }
        let calendar = DateUtilities.appCalendar()
        let today: Date
        if arguments.contains("--plan-tuesday") {
            let monday = DateUtilities.startOfWeek(for: .now, calendar: calendar)
            today = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        } else {
            today = calendar.startOfDay(for: .now)
        }
        let blocks = StudyAnalytics.blocks(
            on: today,
            from: try context.fetch(FetchDescriptor<PlannedStudyBlock>()),
            calendar: calendar
        )

        for (index, block) in blocks.prefix(2).enumerated() {
            block.startMinute = 9 * 60 + index * 150
        }
        blocks.dropFirst(2).forEach { $0.startMinute = nil }

        if let completed = blocks.first, completed.linkedSession == nil {
            completed.status = .completed
            let session = StudySession(
                date: completed.scheduledStart(using: calendar) ?? today,
                duration: max(5 * 60, completed.duration - 15 * 60),
                activity: completed.activity,
                subject: completed.subject,
                module: completed.module,
                topic: completed.topic,
                plannedBlock: completed,
                subjectNameSnapshot: completed.subject?.name ?? "Study",
                moduleNameSnapshot: completed.module?.name,
                topicNameSnapshot: completed.topic?.name
            )
            context.insert(session)
            completed.linkedSession = session
        }

        try context.save()
    }
}
#endif
