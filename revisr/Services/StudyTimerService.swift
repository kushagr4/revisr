import Foundation
import SwiftData

@MainActor
enum StudyTimerService {
    static func start(
        state: StudyTimerState,
        subject: Subject,
        module: StudyModule? = nil,
        topic: Topic? = nil,
        plannedBlock: PlannedStudyBlock? = nil,
        activity: StudyActivity,
        plannedDuration: TimeInterval? = nil,
        at date: Date = .now
    ) throws {
        guard state.status == .idle else {
            throw StudyActionError.activeTimerExists
        }
        state.subject = subject
        state.module = module
        state.topic = topic
        state.plannedBlock = plannedBlock
        state.activity = activity
        state.plannedDuration = plannedDuration
        state.start(at: date)
    }

    @discardableResult
    static func finish(
        state: StudyTimerState,
        notes: String = "",
        at date: Date = .now,
        in context: ModelContext
    ) throws -> StudySession? {
        guard state.status != .idle, let subject = state.subject else { return nil }

        if let block = state.plannedBlock,
           let existing = try StudySessionService.existingSession(for: block, in: context) {
            state.reset()
            try context.save()
            return existing
        }

        let duration = state.elapsed(at: date)
        guard DomainValidation.isValidDuration(duration) else { return nil }

        let block = state.plannedBlock
        let session = StudySession(
            date: state.startedAt ?? date,
            actualStartDate: state.startedAt,
            endDate: date,
            duration: duration,
            activity: state.activity,
            notes: notes,
            subject: subject,
            module: state.module,
            topic: state.topic,
            plannedBlock: block,
            subjectNameSnapshot: subject.name,
            moduleNameSnapshot: state.module?.name,
            topicNameSnapshot: state.topic?.name
        )

        context.insert(session)
        block?.linkedSession = session
        block?.status = .completed
        state.reset()
        try context.save()
        return session
    }
}
