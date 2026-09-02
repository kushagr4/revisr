import Foundation
import SwiftData

enum PlanningConflict: Equatable, Hashable {
    case unavailableDay
    case beforeAvailableStart(Int)
    case overlap

    func message(for day: Date, calendar: Calendar = DateUtilities.appCalendar()) -> String {
        switch self {
        case .unavailableDay:
            let weekday = day.formatted(.dateTime.weekday(.wide))
            return "\(weekday) is normally unavailable. You can still save this block."
        case .beforeAvailableStart(let minute):
            let start = calendar.startOfDay(for: day)
            let time = calendar.date(byAdding: .minute, value: minute, to: start) ?? start
            return "This day is normally available from \(time.formatted(date: .omitted, time: .shortened))."
        case .overlap:
            return "This overlaps with another study block. You can still save it."
        }
    }
}

struct PlanningHierarchySelection: Equatable {
    var subjectID: UUID?
    var moduleID: UUID?
    var topicID: UUID?

    mutating func selectSubject(_ id: UUID?) {
        guard subjectID != id else { return }
        subjectID = id
        moduleID = nil
        topicID = nil
    }

    mutating func selectModule(_ id: UUID?) {
        guard moduleID != id else { return }
        moduleID = id
        topicID = nil
    }

    mutating func selectTopic(_ id: UUID?) {
        topicID = id
    }
}

struct PlannedBlockDraft {
    var day: Date
    var startMinute: Int?
    var duration: TimeInterval
    var activity: StudyActivity
    var subject: Subject
    var module: StudyModule?
    var topic: Topic?
}

enum PlanningService {
    static func conflicts(
        day: Date,
        startMinute: Int?,
        duration: TimeInterval,
        excluding blockID: UUID? = nil,
        among blocks: [PlannedStudyBlock],
        availability: [DayAvailability],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> [PlanningConflict] {
        var conflicts: [PlanningConflict] = []
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
        let dayAvailability = availability.first(where: { $0.weekday == weekday })

        if dayAvailability?.isAvailable == false {
            conflicts.append(.unavailableDay)
        } else if let startMinute,
                  let availableStart = dayAvailability?.startMinute,
                  startMinute < availableStart {
            conflicts.append(.beforeAvailableStart(availableStart))
        }

        if let startMinute,
           blocks.contains(where: { existing in
               guard existing.id != blockID,
                     let otherStartMinute = existing.startMinute,
                     DateUtilities.isSameDay(existing.day, day, calendar: calendar)
               else { return false }
               return overlaps(
                   startMinute: startMinute,
                   duration: duration,
                   otherStartMinute: otherStartMinute,
                   otherDuration: existing.duration
               )
           }) {
            conflicts.append(.overlap)
        }

        return conflicts
    }

    static func conflicts(
        for block: PlannedStudyBlock,
        among blocks: [PlannedStudyBlock],
        availability: [DayAvailability],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> [PlanningConflict] {
        conflicts(
            day: block.day,
            startMinute: block.startMinute,
            duration: block.duration,
            excluding: block.id,
            among: blocks,
            availability: availability,
            calendar: calendar
        )
    }

    static func overlaps(
        startMinute: Int,
        duration: TimeInterval,
        otherStartMinute: Int,
        otherDuration: TimeInterval
    ) -> Bool {
        let start = TimeInterval(startMinute * 60)
        let end = start + max(0, duration)
        let otherStart = TimeInterval(otherStartMinute * 60)
        let otherEnd = otherStart + max(0, otherDuration)
        return start < otherEnd && otherStart < end
    }

    @MainActor
    static func create(from draft: PlannedBlockDraft, in context: ModelContext) throws -> PlannedStudyBlock {
        try validate(draft)
        let block = PlannedStudyBlock(
            day: draft.day,
            startMinute: draft.startMinute,
            duration: draft.duration,
            activity: draft.activity,
            subject: draft.subject,
            module: draft.module,
            topic: draft.topic,
            calendar: DateUtilities.appCalendar()
        )
        context.insert(block)
        try context.save()
        return block
    }

    @MainActor
    static func update(
        block: PlannedStudyBlock,
        from draft: PlannedBlockDraft,
        in context: ModelContext
    ) throws {
        try validate(draft)
        let calendar = DateUtilities.appCalendar()
        block.day = calendar.startOfDay(for: draft.day)
        block.startMinute = draft.startMinute
        block.duration = draft.duration
        block.activity = draft.activity
        block.subject = draft.subject
        block.module = draft.module
        block.topic = draft.topic
        try context.save()
    }

    private static func validate(_ draft: PlannedBlockDraft) throws {
        guard DomainValidation.isValidDuration(draft.duration) else {
            throw PlanningError.invalidDuration
        }
        if let module = draft.module, module.subject?.id != draft.subject.id {
            throw PlanningError.invalidHierarchy
        }
        if let topic = draft.topic {
            guard let module = draft.module, topic.module?.id == module.id else {
                throw PlanningError.invalidHierarchy
            }
        }
    }
}

enum PlanningError: LocalizedError {
    case invalidDuration
    case invalidHierarchy

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            "Choose a study duration greater than zero."
        case .invalidHierarchy:
            "The selected subject, module, and topic do not belong together."
        }
    }
}
