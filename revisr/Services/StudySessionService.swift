import Foundation
import SwiftData

enum StudySessionService {
    @MainActor
    @discardableResult
    static func complete(
        block: PlannedStudyBlock,
        actualDuration: TimeInterval,
        in context: ModelContext
    ) throws -> StudySession {
        guard DomainValidation.isValidDuration(actualDuration) else {
            throw StudyActionError.invalidDuration
        }

        if let existing = try existingSession(for: block, in: context) {
            block.linkedSession = existing
            block.status = .completed
            try context.save()
            return existing
        }

        guard let subject = block.subject else {
            throw StudyActionError.missingSubject
        }

        let session = StudySession(
            date: block.scheduledStart() ?? block.day,
            duration: actualDuration,
            activity: block.activity,
            subject: subject,
            module: block.module,
            topic: block.topic,
            plannedBlock: block,
            subjectNameSnapshot: subject.name,
            moduleNameSnapshot: block.module?.name,
            topicNameSnapshot: block.topic?.name
        )
        context.insert(session)
        block.linkedSession = session
        block.status = .completed
        try context.save()
        return session
    }

    @MainActor
    static func skip(block: PlannedStudyBlock, in context: ModelContext) throws {
        guard try existingSession(for: block, in: context) == nil else {
            throw StudyActionError.alreadyCompleted
        }
        block.status = .skipped
        try context.save()
    }

    @MainActor
    static func duplicate(
        block: PlannedStudyBlock,
        in context: ModelContext
    ) throws -> PlannedStudyBlock {
        let duplicate = PlannedStudyBlock(
            day: block.day,
            startMinute: block.startMinute,
            duration: block.duration,
            activity: block.activity,
            status: .planned,
            subject: block.subject,
            module: block.module,
            topic: block.topic,
            calendar: DateUtilities.appCalendar()
        )
        context.insert(duplicate)
        try context.save()
        return duplicate
    }

    @MainActor
    static func move(
        block: PlannedStudyBlock,
        to day: Date,
        startMinute: Int?,
        calendar: Calendar = DateUtilities.appCalendar(),
        in context: ModelContext
    ) throws {
        block.day = calendar.startOfDay(for: day)
        block.startMinute = startMinute
        try context.save()
    }

    @MainActor
    static func delete(block: PlannedStudyBlock, in context: ModelContext) throws {
        if let session = try existingSession(for: block, in: context) {
            session.plannedBlock = nil
            block.linkedSession = nil
        }
        context.delete(block)
        try context.save()
    }

    @MainActor
    static func existingSession(
        for block: PlannedStudyBlock,
        in context: ModelContext
    ) throws -> StudySession? {
        if let linkedSession = block.linkedSession {
            return linkedSession
        }

        return try context.fetch(FetchDescriptor<StudySession>())
            .first(where: { $0.plannedBlock?.id == block.id })
    }
}

enum StudyActionError: LocalizedError {
    case activeTimerExists
    case alreadyCompleted
    case invalidDuration
    case missingSubject

    var errorDescription: String? {
        switch self {
        case .activeTimerExists: "Finish the current study session before changing or starting another block."
        case .alreadyCompleted: "This block already has completed study attached to it."
        case .invalidDuration: "Choose a study duration greater than zero."
        case .missingSubject: "This study block no longer has a subject."
        }
    }
}
