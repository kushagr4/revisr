import Foundation
import SwiftData

struct TopicDraft {
    var name: String
    var status: TopicStatus
    var needsReview: Bool
    var notes: String
    var module: StudyModule
}

enum TopicError: LocalizedError, Equatable {
    case missingName
    case duplicateName
    case invalidHierarchy
    case cannotMoveSeeded
    case cannotDeleteSeeded

    var errorDescription: String? {
        switch self {
        case .missingName: "Enter a topic name."
        case .duplicateName: "A topic with this name already exists in the selected module."
        case .invalidHierarchy: "Choose a module that belongs to a subject."
        case .cannotMoveSeeded: "Seeded curriculum topics cannot be moved to another module."
        case .cannotDeleteSeeded: "Seeded curriculum topics cannot be deleted."
        }
    }
}

@MainActor
enum TopicService {
    static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func validate(
        _ draft: TopicDraft,
        existingTopics: [Topic],
        excluding topicID: UUID? = nil
    ) throws {
        let normalized = normalizedName(draft.name)
        guard !normalized.isEmpty else { throw TopicError.missingName }
        guard draft.module.subject != nil else { throw TopicError.invalidHierarchy }
        if existingTopics.contains(where: {
            $0.id != topicID
                && $0.module?.id == draft.module.id
                && normalizedName($0.name) == normalized
        }) {
            throw TopicError.duplicateName
        }
    }

    @discardableResult
    static func create(
        from draft: TopicDraft,
        existingTopics: [Topic],
        in context: ModelContext
    ) throws -> Topic {
        try validate(draft, existingTopics: existingTopics)
        let nextOrder = (draft.module.topics.map(\.displayOrder).max() ?? -1) + 1
        let topic = Topic(
            name: cleanedName(draft.name),
            status: draft.status,
            needsReview: draft.needsReview,
            notes: cleanedNotes(draft.notes),
            displayOrder: nextOrder,
            isCustom: true,
            module: draft.module
        )
        context.insert(topic)
        try context.save()
        return topic
    }

    static func update(
        _ topic: Topic,
        from draft: TopicDraft,
        existingTopics: [Topic],
        in context: ModelContext
    ) throws {
        try validate(draft, existingTopics: existingTopics, excluding: topic.id)
        if !topic.isCustom, topic.module?.id != draft.module.id {
            throw TopicError.cannotMoveSeeded
        }
        if topic.isCustom, topic.module?.id != draft.module.id {
            topic.displayOrder = (draft.module.topics.map(\.displayOrder).max() ?? -1) + 1
            topic.module = draft.module
        }
        topic.name = cleanedName(draft.name)
        topic.status = draft.status
        topic.needsReview = draft.needsReview
        topic.notes = cleanedNotes(draft.notes)
        try context.save()
    }

    static func setStatus(_ status: TopicStatus, for topic: Topic, in context: ModelContext) throws {
        topic.status = status
        try context.save()
    }

    static func setNeedsReview(_ needsReview: Bool, for topic: Topic, in context: ModelContext) throws {
        topic.needsReview = needsReview
        try context.save()
    }

    static func delete(_ topic: Topic, in context: ModelContext) throws {
        guard topic.isCustom else { throw TopicError.cannotDeleteSeeded }

        for session in try context.fetch(FetchDescriptor<StudySession>()) where session.topic?.id == topic.id {
            session.topic = nil
        }
        for block in try context.fetch(FetchDescriptor<PlannedStudyBlock>()) where block.topic?.id == topic.id {
            block.topic = nil
        }
        context.delete(topic)
        try context.save()
    }

    private static func cleanedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func cleanedNotes(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
