import Foundation
import SwiftData

enum TMUAProgrammeError: LocalizedError, Equatable {
    case diagnosticIncomplete
    case questionUnavailable
    case taskAlreadyComplete
    case invalidTask

    var errorDescription: String? {
        switch self {
        case .diagnosticIncomplete: "Submit both diagnostic sections before generating your plan."
        case .questionUnavailable: "This question is no longer available in this build. Your earlier work is unchanged."
        case .taskAlreadyComplete: "This task is already complete. Your earlier work is unchanged."
        case .invalidTask: "This task cannot be completed in its current state."
        }
    }
}

/// Value inputs gathered from SwiftData so the planning input can be built
/// (and tested) without a model context.
struct TMUAPlanningEvidence {
    var diagnosticItems: [TMUADiagnosticItem]
    var diagnosticSubmittedAt: [String: Date]
    var attempts: [TMUAPracticeAttempt]
    var flaggedStableIDs: Set<String>
}

@MainActor
enum TMUAProgrammeService {
    static let spacedReviewIntervalDays = 7

    static func programmeID(settings: AppSettings) -> String {
        "tmua-flex-programme-v1-\(settings.id.uuidString)"
    }

    static func refinementSourceID(for length: TMUADiagnosticLength) -> String {
        "diagnostic-expansion-\(length.rawValue)"
    }

    static func load(settings: AppSettings, in context: ModelContext) throws -> PublicProgramme? {
        try PublicProgrammeService.load(programmeID: programmeID(settings: settings), in: context)
    }

    static func tasks(settings: AppSettings, in context: ModelContext) throws -> [PublicProgrammeTask] {
        guard let programme = try load(settings: settings, in: context) else { return [] }
        return try PublicProgrammeService.tasks(for: programme, in: context)
    }

    static func settingsChanged(_ programme: PublicProgramme, settings: AppSettings,
                                calendar: Calendar = DateUtilities.appCalendar()) -> Bool {
        PublicProgrammeService.settingsChanged(programme, settings: settings, calendar: calendar)
            || programme.sessionMinutesSnapshot != settings.publicSessionMinutes
    }

    @discardableResult
    static func generateOrRefresh(settings: AppSettings, content: TMUAContentContext,
                                  today: Date = .now, calendar: Calendar = DateUtilities.appCalendar(),
                                  in context: ModelContext) throws -> PublicProgramme {
        guard let examDate = settings.publicExamDate, let weekly = settings.publicWeeklyTargetMinutes,
              let snapshot = try TMUADiagnosticService.load(settings: settings, in: context),
              snapshot.isInitialComplete else {
            throw TMUAProgrammeError.diagnosticIncomplete
        }
        let evidence = try gatherEvidence(settings: settings, snapshot: snapshot, in: context)
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        let existingTasks = try tasks(settings: settings, in: context)
        let refinement = refinementMinutes(snapshot: snapshot, settings: settings, content: content,
                                           existingTasks: existingTasks, in: context)
        return try PublicProgrammeService.applyPlan(
            programmeID: programmeID(settings: settings), settings: settings, examDate: examDate,
            weeklyMinutes: weekly, today: today, calendar: calendar,
            changed: { settingsChanged($0, settings: settings, calendar: calendar) },
            in: context) { start, excluded in
            planningInput(settings: settings, content: content, report: report, evidence: evidence,
                          start: start, examDate: examDate, weeklyMinutes: weekly,
                          excludedQuestionIDs: excluded, refinement: refinement.map {
                              ($0, refinementSourceID(for: snapshot.diagnostic.targetLength)) },
                          calendar: calendar)
        }
    }

    static func planningInput(
        settings: AppSettings,
        content: TMUAContentContext,
        report: TMUADiagnosticReport,
        evidence: TMUAPlanningEvidence,
        start: Date,
        examDate: Date,
        weeklyMinutes: Int,
        excludedQuestionIDs: Set<String>,
        refinement: (minutes: Int, sourceID: String)?,
        calendar: Calendar
    ) -> PublicPlanningInput {
        let latestAttempt = Dictionary(grouping: evidence.attempts, by: \.itemStableID)
            .compactMapValues { $0.max { $0.attemptedAt < $1.attemptedAt } }
        let diagnosticByID = Dictionary(evidence.diagnosticItems.map { ($0.itemStableID, $0) },
                                        uniquingKeysWith: { first, _ in first })
        let questions = content.eligibleItems
            .filter { !excludedQuestionIDs.contains($0.stableId) }
            .map { item -> PublicPlanningQuestion in
                let attempt = latestAttempt[item.stableId]
                let diagnostic = diagnosticByID[item.stableId]
                var outcome: QuestionAttemptOutcome?
                var outcomeDate: Date?
                if let attempt {
                    outcome = attempt.isCorrect ? .correct : .incorrect
                    outcomeDate = attempt.attemptedAt
                } else if let diagnostic, let marking = diagnostic.marking, marking != .unanswered {
                    outcome = marking == .correct ? .correct : .incorrect
                    outcomeDate = evidence.diagnosticSubmittedAt[diagnostic.sectionID]
                }
                // A skipped diagnostic question is flagged for review rather
                // than recorded as an incorrect answer.
                let skipped = attempt == nil && diagnostic?.marking == .unanswered
                return PublicPlanningQuestion(
                    id: item.stableId,
                    sourceID: "revisr-bank-p\(item.paper)",
                    topic: content.syllabus.topicTitle(item.taxonomy.topic),
                    difficulty: item.difficulty,
                    diagnostic: diagnostic != nil,
                    latestOutcome: outcome,
                    latestAttemptDate: outcomeDate ?? (skipped ? evidence.diagnosticSubmittedAt[diagnostic?.sectionID ?? ""] : nil),
                    reviewFlag: evidence.flaggedStableIDs.contains(item.stableId) || skipped,
                    hasSolution: true)
            }
        var options = PublicPlanningOptions()
        options.dailyMinutesCap = settings.publicSessionMinutes
        options.paceFreshQuestions = true
        options.spacedReviewIntervalDays = spacedReviewIntervalDays
        options.maximumSpacedRepeats = maximumSpacedRepeats(questionCount: questions.count, start: start,
            examDate: examDate, weeklyMinutes: weeklyMinutes, sessionMinutes: settings.publicSessionMinutes,
            availability: settings.publicAvailability, calendar: calendar)
        options.diagnosticRefinementMinutes = refinement?.minutes
        if let refinement { options.diagnosticRefinementSourceID = refinement.sourceID }
        return PublicPlanningInput(exam: .tmua, startDate: start, examDate: examDate,
            weeklyMinutes: weeklyMinutes, availability: settings.publicAvailability,
            diagnosticSignals: report.topics, questions: questions, papers: [],
            calendar: calendar, options: options)
    }

    /// Long windows with a small bank need more revisits per question to keep
    /// later weeks useful; gaps still widen with each revisit.
    static func maximumSpacedRepeats(questionCount: Int, start: Date, examDate: Date, weeklyMinutes: Int,
                                     sessionMinutes: Int?, availability: [DayAvailability],
                                     calendar: Calendar) -> Int {
        let days = PublicPreparationService.studyDaysBeforeExam(examDate, availability: availability,
                                                                today: start, calendar: calendar)
        let studyDays = max(1, availability.filter(\.isAvailable).count)
        let perDay = min(weeklyMinutes / studyDays, sessionMinutes ?? .max)
        let slots = days * max(1, perDay / PublicPlanningPolicy.questionMinutes(for: .tmua))
        let needed = Int((Double(slots) / Double(max(1, questionCount))).rounded(.up)) - 1
        return min(6, max(2, needed))
    }

    static func gatherEvidence(settings: AppSettings, snapshot: TMUADiagnosticSnapshot,
                               in context: ModelContext) throws -> TMUAPlanningEvidence {
        let profile = settings.id
        let attempts = try context.fetch(FetchDescriptor<TMUAPracticeAttempt>(
            predicate: #Predicate { $0.profileSettingsID == profile }))
        let flags = try context.fetch(FetchDescriptor<TMUAReviewFlag>(
            predicate: #Predicate { $0.profileSettingsID == profile && $0.isFlagged }))
        let submittedAt = Dictionary(uniqueKeysWithValues: snapshot.sections.compactMap { section in
            section.submittedAt.map { (section.stableID, $0) }
        })
        return TMUAPlanningEvidence(diagnosticItems: snapshot.submittedItems,
                                    diagnosticSubmittedAt: submittedAt, attempts: attempts,
                                    flaggedStableIDs: Set(flags.map(\.itemStableID)))
    }

    /// Minutes for an optional "answer more diagnostic questions" task, or nil
    /// when the diagnostic is already full length, content is insufficient,
    /// or the student already completed that invitation.
    static func refinementMinutes(snapshot: TMUADiagnosticSnapshot, settings: AppSettings,
                                  content: TMUAContentContext, existingTasks: [PublicProgrammeTask],
                                  in context: ModelContext) -> Int? {
        let current = snapshot.diagnostic.targetLength
        guard let next = current.expansionTargets.first,
              TMUADiagnosticService.canExpand(snapshot, to: next, settings: settings,
                                              content: content, in: context) else { return nil }
        let sourceID = refinementSourceID(for: current)
        guard !existingTasks.contains(where: { $0.sourceID == sourceID && $0.completedAt != nil }) else {
            return nil
        }
        let added = TMUAPaper.allCases.reduce(0) { $0 + current.additionalQuestions(to: next, paper: $1) }
        return max(15, Int((Double(added) * 75 / 20).rounded(.up)))
    }

    // MARK: - Practice

    @discardableResult
    static func recordPractice(item: TMUAContentItem, selectedOptionID: String, seconds: Int,
                               task: PublicProgrammeTask?, settings: AppSettings,
                               at date: Date = .now, in context: ModelContext) throws -> TMUAPracticeAttempt {
        guard item.options.contains(where: { $0.id == selectedOptionID }) else {
            throw TMUADiagnosticError.invalidAnswer
        }
        if let task {
            guard task.isActive, task.completedAt == nil else { throw TMUAProgrammeError.taskAlreadyComplete }
            guard task.questionID == item.stableId else { throw TMUAProgrammeError.invalidTask }
        }
        let attempt = TMUAPracticeAttempt(profileSettingsID: settings.id, item: item,
            selectedOptionID: selectedOptionID, seconds: seconds,
            origin: task == nil ? .questionBank : .programme, programmeTaskID: task?.stableID, at: date)
        context.insert(attempt)
        if let task {
            task.completedAt = date
            task.completionAttemptID = attempt.id
            task.completionNote = attempt.isCorrect ? "Correct" : "Incorrect"
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return attempt
    }

    static func setReviewFlag(_ flagged: Bool, itemStableID: String, settings: AppSettings,
                              at date: Date = .now, in context: ModelContext) throws {
        let id = "\(settings.id.uuidString)-\(itemStableID)"
        if let existing = try context.fetch(FetchDescriptor<TMUAReviewFlag>(
            predicate: #Predicate { $0.stableID == id })).first {
            existing.isFlagged = flagged
            existing.updatedAt = date
        } else {
            context.insert(TMUAReviewFlag(profileSettingsID: settings.id, itemStableID: itemStableID,
                                          isFlagged: flagged, at: date))
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func flaggedStableIDs(settings: AppSettings, in context: ModelContext) throws -> Set<String> {
        let profile = settings.id
        return Set(try context.fetch(FetchDescriptor<TMUAReviewFlag>(
            predicate: #Predicate { $0.profileSettingsID == profile && $0.isFlagged })).map(\.itemStableID))
    }

    /// Completes outstanding invitations once the student has actually
    /// answered the extra diagnostic questions.
    static func completeRefinementTasks(settings: AppSettings, at date: Date = .now,
                                        in context: ModelContext) throws {
        for task in try tasks(settings: settings, in: context)
        where task.activity == .diagnosticRefinement && task.isActive && task.completedAt == nil {
            task.completedAt = date
            task.completionNote = "Diagnostic extended"
        }
        if context.hasChanges { try context.save() }
    }
}
