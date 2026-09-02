import Foundation
import SwiftData

enum StudyResultKind: String, Identifiable, Sendable {
    case tmua
    case aLevel

    var id: Self { self }
    var title: String { self == .tmua ? "TMUA Result" : "A-Level Result" }
}

struct StudyResultInput {
    var date: Date
    var label: String
    var rawScore: Double?
    var maximumScore: Double?
    var scaledScore: Double?
    var notes: String
    var subject: Subject
    var module: StudyModule?
}

enum StudyResultError: LocalizedError, Equatable {
    case missingLabel
    case incompleteRawScore
    case invalidRawScore
    case invalidScaledScore
    case missingTMUAScore
    case missingALevelScore

    var errorDescription: String? {
        switch self {
        case .missingLabel: "Enter a paper or module name."
        case .incompleteRawScore: "Enter both the raw score and maximum score, or leave both blank."
        case .invalidRawScore: "The raw score must be between zero and the maximum score."
        case .invalidScaledScore: "Enter a sensible scaled score between 0 and 20. Revisr does not convert raw marks to scaled scores."
        case .missingTMUAScore: "Enter a raw score or a scaled score."
        case .missingALevelScore: "Enter a raw score and maximum score."
        }
    }
}

@MainActor
enum StudyResultService {
    static func validate(_ input: StudyResultInput, kind: StudyResultKind) throws {
        guard !input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyResultError.missingLabel
        }

        let hasRaw = input.rawScore != nil || input.maximumScore != nil
        if hasRaw {
            guard let raw = input.rawScore, let maximum = input.maximumScore else {
                throw StudyResultError.incompleteRawScore
            }
            guard DomainValidation.isValidResult(rawScore: raw, maximumScore: maximum) else {
                throw StudyResultError.invalidRawScore
            }
        }

        if let scaled = input.scaledScore,
           !DomainValidation.isSensibleScaledScore(scaled) {
            throw StudyResultError.invalidScaledScore
        }

        switch kind {
        case .tmua:
            guard hasRaw || input.scaledScore != nil else { throw StudyResultError.missingTMUAScore }
        case .aLevel:
            guard hasRaw else { throw StudyResultError.missingALevelScore }
        }
    }

    @discardableResult
    static func create(
        input: StudyResultInput,
        kind: StudyResultKind,
        in context: ModelContext
    ) throws -> StudyResult {
        try validate(input, kind: kind)
        let result = StudyResult(
            date: input.date,
            paperOrModuleLabel: input.label.trimmingCharacters(in: .whitespacesAndNewlines),
            rawScore: input.rawScore,
            maximumScore: input.maximumScore,
            scaledScore: input.scaledScore,
            notes: input.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: input.subject,
            module: input.module,
            subjectNameSnapshot: input.subject.name,
            moduleNameSnapshot: input.module?.name
        )
        context.insert(result)
        try context.save()
        return result
    }

    static func update(
        _ result: StudyResult,
        input: StudyResultInput,
        kind: StudyResultKind,
        in context: ModelContext
    ) throws {
        try validate(input, kind: kind)
        result.date = input.date
        result.paperOrModuleLabel = input.label.trimmingCharacters(in: .whitespacesAndNewlines)
        result.rawScore = input.rawScore
        result.maximumScore = input.maximumScore
        result.scaledScore = input.scaledScore
        result.notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        result.subject = input.subject
        result.module = input.module
        result.subjectNameSnapshot = input.subject.name
        result.moduleNameSnapshot = input.module?.name
        try context.save()
    }

    static func delete(_ result: StudyResult, in context: ModelContext) throws {
        context.delete(result)
        try context.save()
    }
}
