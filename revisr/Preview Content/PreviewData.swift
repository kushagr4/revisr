import Foundation
import SwiftData

enum TodayPreviewScenario: Equatable {
    case normal
    case empty
    case completed
    case unavailable
}

enum PlanPreviewScenario: Equatable {
    case normalMonday
    case tuesday
    case unavailableThursday
    case unavailableException
    case mixedStatus
    case emptyFutureWeek
}

enum ProgressPreviewScenario: Equatable {
    case populatedWeek
    case noStudy
    case studyWithoutResults
    case oneTMUAResult
    case severalTMUAResults
}

enum TopicsPreviewScenario: Equatable {
    case populated
    case noNeedsReview
    case neverStudied
}

@MainActor
enum PreviewData {
    static func makeContainer() throws -> ModelContainer {
        try makeTodayContainer(scenario: .normal)
    }

    static func makeSettingsContainer() throws -> ModelContainer {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        try SeedDataService.seedIfNeeded(in: container.mainContext)
        return container
    }

    static func settings(in container: ModelContainer) throws -> AppSettings {
        try container.mainContext.fetch(FetchDescriptor<AppSettings>()).first
            ?? { throw PreviewDataError.missingSettings }()
    }

    static func makeTodayContainer(scenario: TodayPreviewScenario) throws -> ModelContainer {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)

        for block in try context.fetch(FetchDescriptor<PlannedStudyBlock>()) {
            context.delete(block)
        }
        try context.save()

        if scenario == .unavailable {
            try markTodayUnavailable(in: context)
            return container
        }
        guard scenario != .empty else { return container }

        let subjects = try context.fetch(
            FetchDescriptor<Subject>(sortBy: [SortDescriptor(\Subject.displayOrder)])
        )
        guard
            let tmua = subjects.first(where: { $0.name == "TMUA" }),
            let further = subjects.first(where: { $0.name == "Further Mathematics" }),
            let maths = subjects.first(where: { $0.name == "Mathematics" })
        else { return container }

        let paper2 = tmua.modules.first(where: { $0.name == "Paper 2" })
        let fs1 = further.modules.first(where: { $0.name == "FS1" })
        let statistics = maths.modules.first(where: { $0.name == "Statistics" })
        let calendar = DateUtilities.appCalendar()
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let currentMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let firstStart = max(0, currentMinute - 150)
        let currentStart = max(0, currentMinute - 12)
        let nextStart = min(23 * 60, currentMinute + 75)

        let completedBlock = PlannedStudyBlock(
            day: today,
            startMinute: firstStart,
            duration: 90 * 60,
            activity: .timedQuestions,
            status: .completed,
            subject: tmua,
            module: paper2,
            calendar: calendar
        )
        let completedSession = StudySession(
            date: completedBlock.scheduledStart(using: calendar) ?? today,
            actualStartDate: completedBlock.scheduledStart(using: calendar),
            duration: 75 * 60,
            activity: .timedQuestions,
            subject: tmua,
            module: paper2,
            plannedBlock: completedBlock,
            subjectNameSnapshot: tmua.name,
            moduleNameSnapshot: paper2?.name
        )
        completedBlock.linkedSession = completedSession
        context.insert(completedBlock)
        context.insert(completedSession)

        let currentBlock = PlannedStudyBlock(
            day: today,
            startMinute: currentStart,
            duration: 60 * 60,
            activity: .questions,
            subject: maths,
            module: statistics,
            topic: statistics?.topics.first(where: { $0.name == "Probability" }),
            calendar: calendar
        )
        let upcomingBlock = PlannedStudyBlock(
            day: today,
            startMinute: nextStart,
            duration: 90 * 60,
            activity: .revision,
            subject: further,
            module: fs1,
            topic: fs1?.topics.first(where: { $0.name == "Hypothesis Testing" }),
            calendar: calendar
        )
        let anyTimeBlock = PlannedStudyBlock(
            day: today,
            duration: 45 * 60,
            activity: .recall,
            subject: further,
            module: fs1,
            calendar: calendar
        )
        context.insert(currentBlock)
        context.insert(upcomingBlock)
        context.insert(anyTimeBlock)

        if scenario == .completed {
            for block in [currentBlock, upcomingBlock, anyTimeBlock] {
                let session = StudySession(
                    date: block.scheduledStart(using: calendar) ?? today.addingTimeInterval(16 * 60 * 60),
                    duration: block.duration,
                    activity: block.activity,
                    subject: block.subject,
                    module: block.module,
                    topic: block.topic,
                    plannedBlock: block,
                    subjectNameSnapshot: block.subject?.name ?? "Study",
                    moduleNameSnapshot: block.module?.name,
                    topicNameSnapshot: block.topic?.name
                )
                context.insert(session)
                block.linkedSession = session
                block.status = .completed
            }
        } else {
            context.insert(
                PlannedStudyBlock(
                    day: today,
                    startMinute: min(23 * 60 + 30, nextStart + 110),
                    duration: 30 * 60,
                    activity: .review,
                    status: .skipped,
                    subject: maths,
                    module: statistics,
                    calendar: calendar
                )
            )
            context.insert(
                StudySession(
                    date: now.addingTimeInterval(-20 * 60),
                    duration: 30 * 60,
                    activity: .recall,
                    subject: further,
                    module: fs1,
                    subjectNameSnapshot: further.name,
                    moduleNameSnapshot: fs1?.name
                )
            )

            if let timerState = try context.fetch(FetchDescriptor<StudyTimerState>()).first {
                timerState.subject = currentBlock.subject
                timerState.module = currentBlock.module
                timerState.topic = currentBlock.topic
                timerState.plannedBlock = currentBlock
                timerState.activity = currentBlock.activity
                timerState.plannedDuration = currentBlock.duration
                timerState.start(at: now.addingTimeInterval(-12 * 60))
            }
        }

        context.insert(
            StudyResult(
                date: calendar.date(byAdding: .day, value: -3, to: today) ?? today,
                paperOrModuleLabel: "Paper 2",
                rawScore: 15,
                maximumScore: 20,
                scaledScore: 7.4,
                subject: tmua,
                module: paper2,
                subjectNameSnapshot: tmua.name,
                moduleNameSnapshot: paper2?.name
            )
        )
        try context.save()
        return container
    }

    static func planPreviewDate(for scenario: PlanPreviewScenario) -> Date {
        let calendar = DateUtilities.appCalendar()
        let monday = DateUtilities.startOfWeek(for: .now, calendar: calendar)
        let offset: Int = switch scenario {
        case .normalMonday, .mixedStatus: 0
        case .tuesday: 1
        case .unavailableThursday, .unavailableException: 3
        case .emptyFutureWeek: 7
        }
        return calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
    }

    static func makePlanContainer(scenario: PlanPreviewScenario) throws -> ModelContainer {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let calendar = DateUtilities.appCalendar()
        let selectedDay = planPreviewDate(for: scenario)
        let weekBlocks = StudyAnalytics.blocks(
            inWeekContaining: selectedDay,
            from: try context.fetch(FetchDescriptor<PlannedStudyBlock>()),
            calendar: calendar
        )

        if scenario == .emptyFutureWeek || scenario == .unavailableThursday {
            return container
        }

        let dayBlocks = StudyAnalytics.blocks(on: selectedDay, from: weekBlocks, calendar: calendar)
        if scenario == .unavailableException {
            let subjects = try context.fetch(FetchDescriptor<Subject>())
            if let tmua = subjects.first(where: { $0.name == "TMUA" }) {
                context.insert(
                    PlannedStudyBlock(
                        day: selectedDay,
                        startMinute: 10 * 60,
                        duration: 90 * 60,
                        activity: .timedQuestions,
                        subject: tmua,
                        module: tmua.modules.first(where: { $0.name == "Paper 2" }),
                        calendar: calendar
                    )
                )
            }
        } else {
            for (index, block) in dayBlocks.prefix(3).enumerated() {
                block.startMinute = 9 * 60 + index * 110
            }
            dayBlocks.dropFirst(3).forEach { $0.startMinute = nil }

            if scenario == .tuesday, let first = dayBlocks.first {
                first.startMinute = 11 * 60
            }

            if scenario == .mixedStatus {
                if let completed = dayBlocks.first {
                    completed.status = .completed
                    let session = StudySession(
                        date: completed.scheduledStart(using: calendar) ?? selectedDay,
                        duration: completed.duration,
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
                if dayBlocks.count > 1 {
                    dayBlocks[1].status = .skipped
                }
            }
        }

        try context.save()
        return container
    }

    static func makeProgressContainer(scenario: ProgressPreviewScenario) throws -> ModelContainer {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let subjects = try context.fetch(
            FetchDescriptor<Subject>(sortBy: [SortDescriptor(\Subject.displayOrder)])
        )
        guard
            let tmua = subjects.first(where: { $0.name == "TMUA" }),
            let further = subjects.first(where: { $0.name == "Further Mathematics" }),
            let maths = subjects.first(where: { $0.name == "Mathematics" })
        else { return container }

        if scenario != .noStudy && scenario != .oneTMUAResult {
            let sessionSeeds: [(Subject, Int, Int)] = [
                (tmua, -5, 95), (further, -4, 60), (tmua, -3, 80),
                (maths, -2, 55), (further, -1, 75), (tmua, 0, 65)
            ]
            for (subject, offset, minutes) in sessionSeeds {
                context.insert(
                    StudySession(
                        date: calendar.date(byAdding: .day, value: offset, to: today) ?? today,
                        duration: TimeInterval(minutes * 60),
                        activity: .revision,
                        subject: subject,
                        module: subject.modules.sorted(by: { $0.displayOrder < $1.displayOrder }).first,
                        subjectNameSnapshot: subject.name
                    )
                )
            }
        }

        if scenario == .oneTMUAResult || scenario == .populatedWeek || scenario == .severalTMUAResults {
            let count = scenario == .oneTMUAResult ? 1 : (scenario == .severalTMUAResults ? 6 : 4)
            for index in 0..<count {
                let paper = index.isMultiple(of: 2) ? "Paper 1" : "Paper 2"
                context.insert(
                    StudyResult(
                        date: calendar.date(byAdding: .day, value: -(count - index), to: today) ?? today,
                        paperOrModuleLabel: paper,
                        rawScore: Double(12 + index),
                        maximumScore: 20,
                        scaledScore: 5.8 + Double(index) * 0.35,
                        subject: tmua,
                        module: tmua.modules.first(where: { $0.name == paper }),
                        subjectNameSnapshot: tmua.name,
                        moduleNameSnapshot: paper
                    )
                )
            }
        }

        if scenario == .populatedWeek {
            context.insert(
                StudyResult(
                    date: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                    paperOrModuleLabel: "Pure mock",
                    rawScore: 61,
                    maximumScore: 75,
                    subject: maths,
                    module: maths.modules.first(where: { $0.name == "Pure" }),
                    subjectNameSnapshot: maths.name,
                    moduleNameSnapshot: "Pure"
                )
            )
            context.insert(
                StudyResult(
                    date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                    paperOrModuleLabel: "CP1 assessment",
                    rawScore: 54,
                    maximumScore: 75,
                    subject: further,
                    module: further.modules.first(where: { $0.name == "CP1" }),
                    subjectNameSnapshot: further.name,
                    moduleNameSnapshot: "CP1"
                )
            )
        }

        try context.save()
        return container
    }

    static func makeTopicsContainer(scenario: TopicsPreviewScenario) throws -> ModelContainer {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let topics = try context.fetch(FetchDescriptor<Topic>())

        if scenario == .noNeedsReview {
            topics.forEach { $0.needsReview = false }
            try context.save()
            return container
        }

        guard scenario == .populated else { return container }
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let seeds: [(String, String, Int, Int, StudyActivity)] = [
            ("Complex Numbers", "CP1", -3, 90, .questions),
            ("Complex Numbers", "CP1", -8, 60, .revision),
            ("Probability", "Statistics", -2, 75, .questions),
            ("Integration", "CP2", -5, 50, .recall),
            ("Momentum", "FM1", -1, 45, .review)
        ]
        for (topicName, moduleName, offset, minutes, activity) in seeds {
            guard let topic = topics.first(where: { $0.name == topicName && $0.module?.name == moduleName }),
                  let module = topic.module,
                  let subject = module.subject else { continue }
            context.insert(
                StudySession(
                    date: calendar.date(byAdding: .day, value: offset, to: today) ?? today,
                    duration: TimeInterval(minutes * 60),
                    activity: activity,
                    subject: subject,
                    module: module,
                    topic: topic,
                    subjectNameSnapshot: subject.name,
                    moduleNameSnapshot: module.name,
                    topicNameSnapshot: topic.name
                )
            )
        }
        topics.first(where: { $0.name == "Complex Numbers" && $0.module?.name == "CP1" })?.notes = "Revisit loci arguments and geometric interpretations."
        try context.save()
        return container
    }

    static func topic(
        named name: String,
        module moduleName: String,
        in container: ModelContainer
    ) throws -> Topic {
        try container.mainContext.fetch(FetchDescriptor<Topic>()).first(where: {
            $0.name == name && $0.module?.name == moduleName
        }) ?? { throw PreviewDataError.missingTopic }()
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
}

private enum PreviewDataError: Error {
    case missingTopic
    case missingSettings
}
