#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DebugTodayScenarioService {
    static func applyIfRequested(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--today-demo") || arguments.contains("--today-unavailable") else { return }

        if arguments.contains("--today-unavailable") {
            try deleteTodayBlocks(in: context)
            try markTodayUnavailable(in: context)
            return
        }

        try deleteTodayBlocks(in: context)

        let calendar = DateUtilities.appCalendar()
        let now = Date.now
        guard StudyAnalytics.blocks(
            on: now,
            from: try context.fetch(FetchDescriptor<PlannedStudyBlock>()),
            calendar: calendar
        ).isEmpty else { return }

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        guard
            let tmua = subjects.first(where: { $0.name == "TMUA" }),
            let maths = subjects.first(where: { $0.name == "Mathematics" }),
            let further = subjects.first(where: { $0.name == "Further Mathematics" })
        else { return }

        let paper2 = tmua.modules.first(where: { $0.name == "Paper 2" })
        let statistics = maths.modules.first(where: { $0.name == "Statistics" })
        let fs1 = further.modules.first(where: { $0.name == "FS1" })
        let today = calendar.startOfDay(for: now)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        let completed = PlannedStudyBlock(
            day: today,
            startMinute: max(0, minute - 150),
            duration: 90 * 60,
            activity: .timedQuestions,
            status: .completed,
            subject: tmua,
            module: paper2,
            calendar: calendar
        )
        let session = StudySession(
            date: completed.scheduledStart(using: calendar) ?? today,
            duration: 80 * 60,
            activity: .timedQuestions,
            subject: tmua,
            module: paper2,
            plannedBlock: completed,
            subjectNameSnapshot: tmua.name,
            moduleNameSnapshot: paper2?.name
        )
        completed.linkedSession = session
        context.insert(completed)
        context.insert(session)

        let activeBlock = PlannedStudyBlock(
            day: today,
            startMinute: max(0, minute - 12),
            duration: 90 * 60,
            activity: .questions,
            subject: maths,
            module: statistics,
            topic: statistics?.topics.first(where: { $0.name == "Probability" }),
            calendar: calendar
        )
        context.insert(activeBlock)
        context.insert(
            PlannedStudyBlock(
                day: today,
                duration: 60 * 60,
                activity: .revision,
                subject: further,
                module: fs1,
                topic: fs1?.topics.first,
                calendar: calendar
            )
        )
        context.insert(
            StudySession(
                date: now.addingTimeInterval(-15 * 60),
                duration: 25 * 60,
                activity: .recall,
                subject: further,
                module: fs1,
                subjectNameSnapshot: further.name,
                moduleNameSnapshot: fs1?.name
            )
        )

        if let timerState = try context.fetch(FetchDescriptor<StudyTimerState>()).first {
            try StudyTimerService.start(
                state: timerState,
                subject: maths,
                module: statistics,
                topic: statistics?.topics.first(where: { $0.name == "Probability" }),
                plannedBlock: activeBlock,
                activity: .questions,
                plannedDuration: activeBlock.duration,
                at: now.addingTimeInterval(-12 * 60)
            )
        }
        try context.save()
    }

    private static func markTodayUnavailable(in context: ModelContext) throws {
        guard let settings = try context.fetch(FetchDescriptor<AppSettings>()).first else { return }
        let calendar = DateUtilities.appCalendar()
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: Date.now)) else { return }
        var availability = settings.availability
        if let index = availability.firstIndex(where: { $0.weekday == weekday }) {
            availability[index].isAvailable = false
        }
        settings.availability = availability
        try context.save()
    }

    private static func deleteTodayBlocks(in context: ModelContext) throws {
        let calendar = DateUtilities.appCalendar()
        let blocks = StudyAnalytics.blocks(
            on: .now,
            from: try context.fetch(FetchDescriptor<PlannedStudyBlock>()),
            calendar: calendar
        )
        blocks.forEach(context.delete)
        try context.save()
    }
}
#endif
