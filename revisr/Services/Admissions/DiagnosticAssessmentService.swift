import Foundation
import SwiftData

enum DiagnosticAssessmentError: LocalizedError {
    case incompleteProfile
    case changedPaperSelection
    case paperLocked
    case invalidState
    case invalidAnswer
    case invalidMarks
    case wrongQuestion

    var errorDescription: String? {
        switch self {
        case .incompleteProfile: "Finish your preparation details first."
        case .changedPaperSelection: "Saved diagnostic papers no longer match the verified local catalogue. Your work has been preserved for review."
        case .paperLocked: "Complete the first paper before starting the second."
        case .invalidState: "This paper can no longer be changed at this stage."
        case .invalidAnswer: "Choose one answer from A to E."
        case .invalidMarks: "Self-estimated marks must be between 0 and 10."
        case .wrongQuestion: "This question does not belong to the selected paper."
        }
    }
}

@MainActor
enum DiagnosticAssessmentService {
    static func assessmentID(profileID: UUID, exam: PublicExamKind) -> String {
        "public-diagnostic-v1-\(profileID.uuidString)-\(exam.rawValue)"
    }

    static func loadOrCreate(
        settings: AppSettings,
        selection: [DiagnosticPaperSelection],
        in context: ModelContext
    ) throws -> DiagnosticAssessment {
        guard settings.publicOnboardingStage != nil, settings.publicExamDate != nil else {
            throw DiagnosticAssessmentError.incompleteProfile
        }
        guard selection.count == 2 else { throw DiagnosticAssessmentError.changedPaperSelection }
        let id = assessmentID(profileID: settings.id, exam: settings.publicExam)
        let assessments = try context.fetch(FetchDescriptor<DiagnosticAssessment>())
        if let existing = assessments.first(where: { $0.stableID == id }) {
            let saved = try context.fetch(FetchDescriptor<DiagnosticPaperRecord>())
                .filter { $0.assessmentID == id }.sorted { $0.ordinal < $1.ordinal }
            guard saved.map(\.sourceID) == selection.map(\.source.stableSourceID) else {
                throw DiagnosticAssessmentError.changedPaperSelection
            }
            let responses = try context.fetch(FetchDescriptor<DiagnosticResponse>())
            for (paper, selected) in zip(saved, selection) {
                guard Set(responses.filter { $0.paperID == paper.stableID }.map(\.questionID))
                    == Set(selected.questions.map(\.externalQuestionID)) else {
                    throw DiagnosticAssessmentError.changedPaperSelection
                }
            }
            // Re-entering diagnostics after a terminated session cannot establish
            // how long the student was working. Pause any orphaned timer instead
            // of counting time spent outside the app as assessment time.
            let orphaned = saved.filter { $0.status == .answering && $0.runningSince != nil }
            for paper in orphaned { paper.runningSince = nil }
            if !orphaned.isEmpty { try context.save() }
            return existing
        }

        let assessment = DiagnosticAssessment(
            stableID: id,
            profileSettingsID: settings.id,
            exam: settings.publicExam
        )
        context.insert(assessment)
        for selected in selection {
            let paperID = "\(id)-P\(selected.ordinal)"
            let paper = DiagnosticPaperRecord(
                stableID: paperID,
                assessmentID: id,
                sourceID: selected.source.stableSourceID,
                ordinal: selected.ordinal,
                scoringProvenance: settings.publicExam == .bmo
                    ? .selfEstimatedWithoutScheme : .selfMarkedWithPDF
            )
            context.insert(paper)
            for question in selected.questions {
                context.insert(DiagnosticResponse(
                    stableID: "\(paperID)-\(question.externalQuestionID)",
                    paperID: paperID,
                    questionID: question.externalQuestionID
                ))
            }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return assessment
    }

    static func start(
        _ paper: DiagnosticPaperRecord,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        guard paper.status == .notStarted else { throw DiagnosticAssessmentError.invalidState }
        if paper.ordinal == 2 {
            let first = try context.fetch(FetchDescriptor<DiagnosticPaperRecord>()).first {
                $0.assessmentID == paper.assessmentID && $0.ordinal == 1
            }
            guard first?.status == .completed else { throw DiagnosticAssessmentError.paperLocked }
        }
        paper.status = .answering
        paper.startedAt = date
        paper.runningSince = date
        try context.save()
    }

    static func pause(_ paper: DiagnosticPaperRecord, at date: Date = .now, in context: ModelContext) throws {
        guard paper.status == .answering else { throw DiagnosticAssessmentError.invalidState }
        if let runningSince = paper.runningSince {
            paper.accumulatedSeconds += max(0, date.timeIntervalSince(runningSince))
            paper.runningSince = nil
            try context.save()
        }
    }

    static func resume(_ paper: DiagnosticPaperRecord, at date: Date = .now, in context: ModelContext) throws {
        guard paper.status == .answering else { throw DiagnosticAssessmentError.invalidState }
        if paper.runningSince == nil {
            paper.runningSince = date
            try context.save()
        }
    }

    static func recordChoice(
        _ option: String?,
        response: DiagnosticResponse,
        paper: DiagnosticPaperRecord,
        in context: ModelContext
    ) throws {
        try require(response, belongsTo: paper, status: .answering)
        guard paper.scoringProvenance == .selfMarkedWithPDF else {
            throw DiagnosticAssessmentError.invalidState
        }
        if let option, !["A", "B", "C", "D", "E"].contains(option) {
            throw DiagnosticAssessmentError.invalidAnswer
        }
        response.selectedOption = option
        try context.save()
    }

    static func recordProofAttempt(
        _ attempted: Bool,
        response: DiagnosticResponse,
        paper: DiagnosticPaperRecord,
        in context: ModelContext
    ) throws {
        try require(response, belongsTo: paper, status: .answering)
        guard paper.scoringProvenance == .selfEstimatedWithoutScheme else {
            throw DiagnosticAssessmentError.invalidState
        }
        response.wasAttempted = attempted
        if !attempted { response.selfEstimatedMarks = nil }
        try context.save()
    }

    static func recordNotes(
        _ notes: String,
        response: DiagnosticResponse,
        paper: DiagnosticPaperRecord,
        in context: ModelContext
    ) throws {
        guard response.paperID == paper.stableID,
              paper.status == .answering || paper.status == .marking else {
            throw DiagnosticAssessmentError.invalidState
        }
        response.notes = notes
        try context.save()
    }

    static func submitAnswers(
        _ paper: DiagnosticPaperRecord,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        guard paper.status == .answering else { throw DiagnosticAssessmentError.invalidState }
        if let runningSince = paper.runningSince {
            paper.accumulatedSeconds += max(0, date.timeIntervalSince(runningSince))
        }
        paper.runningSince = nil
        paper.submittedAt = date
        paper.status = .marking
        try context.save()
    }

    static func recordMarking(
        _ marking: DiagnosticMarking,
        response: DiagnosticResponse,
        paper: DiagnosticPaperRecord,
        in context: ModelContext
    ) throws {
        try require(response, belongsTo: paper, status: .marking)
        guard paper.scoringProvenance == .selfMarkedWithPDF else {
            throw DiagnosticAssessmentError.invalidState
        }
        guard response.selectedOption != nil || marking == .unassessed else {
            throw DiagnosticAssessmentError.invalidAnswer
        }
        response.marking = marking
        try context.save()
    }

    static func recordEstimatedMarks(
        _ marks: Int?,
        response: DiagnosticResponse,
        paper: DiagnosticPaperRecord,
        in context: ModelContext
    ) throws {
        try require(response, belongsTo: paper, status: .marking)
        guard paper.scoringProvenance == .selfEstimatedWithoutScheme else {
            throw DiagnosticAssessmentError.invalidState
        }
        if let marks, !((0...10).contains(marks) && response.wasAttempted) {
            throw DiagnosticAssessmentError.invalidMarks
        }
        response.selfEstimatedMarks = marks
        try context.save()
    }

    static func complete(
        _ paper: DiagnosticPaperRecord,
        settings: AppSettings,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        guard paper.status == .marking else { throw DiagnosticAssessmentError.invalidState }
        paper.status = .completed
        paper.completedAt = date
        let papers = try context.fetch(FetchDescriptor<DiagnosticPaperRecord>())
            .filter { $0.assessmentID == paper.assessmentID }
        if papers.count == 2 && papers.allSatisfy({ $0.status == .completed }) {
            if let assessment = try context.fetch(FetchDescriptor<DiagnosticAssessment>()).first(where: {
                $0.stableID == paper.assessmentID
            }) {
                assessment.completedAt = date
                if settings.id == assessment.profileSettingsID && settings.publicExam == assessment.exam {
                    settings.publicOnboardingStage = .diagnosticsComplete
                }
            }
        }
        try context.save()
    }

    private static func require(
        _ response: DiagnosticResponse,
        belongsTo paper: DiagnosticPaperRecord,
        status: DiagnosticPaperStatus
    ) throws {
        guard response.paperID == paper.stableID else { throw DiagnosticAssessmentError.wrongQuestion }
        guard paper.status == status else { throw DiagnosticAssessmentError.invalidState }
    }
}
