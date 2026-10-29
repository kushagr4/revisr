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

    /// - Parameters:
    ///   - resourceSessions: also fill study days the question bank cannot fill with
    ///     self-marked papers from the library (`TMUAResourcePlanning`). The app passes true.
    ///   - catalogue: the library to plan from; nil uses this build's (`TMUACatalogueStore`).
    @discardableResult
    static func generateOrRefresh(settings: AppSettings, content: TMUAContentContext,
                                  today: Date = .now, calendar: Calendar = DateUtilities.appCalendar(),
                                  resourceSessions: Bool = false, catalogue: TMUAQuestionCatalogue? = nil,
                                  in context: ModelContext) throws -> PublicProgramme {
        let catalogue = catalogue ?? TMUACatalogueStore.catalogue(content)
        guard let examDate = settings.publicExamDate, let weekly = settings.publicWeeklyTargetMinutes,
              let snapshot = try TMUADiagnosticService.load(settings: settings, in: context),
              snapshot.isInitialComplete else {
            throw TMUAProgrammeError.diagnosticIncomplete
        }
        let evidence = try gatherEvidence(settings: settings, snapshot: snapshot, in: context)
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        let existingTasks = try tasks(settings: settings, in: context)
        let windowStart = calendar.startOfDay(for: today)
        let windowEnd = calendar.date(byAdding: .day, value: 3, to: windowStart) ?? windowStart
        let hadProgramme = try load(settings: settings, in: context) != nil
        let keepsWindow = (try load(settings: settings, in: context)).map {
            !settingsChanged($0, settings: settings, calendar: calendar)
        } == true
        // Read before anything is retired. Library sessions are planned after the engine's tasks, so the
        // summary is taken over everything a refresh could change: incomplete work outside the kept window.
        let unchanged = keepsWindow
        func changeable(_ task: PublicProgrammeTask) -> Bool {
            task.isActive && task.completedAt == nil
                && !(unchanged && task.scheduledDate >= windowStart && task.scheduledDate < windowEnd)
        }
        let beforeTopics = existingTasks.filter(changeable).map(\.topic)
        let kept = existingTasks.filter { $0.isActive && $0.completedAt == nil && !changeable($0) }.count
        // Questions in an unsubmitted diagnostic round leave the plan, so
        // practice can never show their solutions before they are answered.
        let reserved = reservedStableIDs(snapshot: snapshot)
        // A kept paper session holding such a question leaves too, so the paper is not sat first.
        let reservedPapers = Set(catalogue.sources.filter { source in
            source.questions.contains { $0.autoMarkedItemID.map(reserved.contains) == true }
        }.map(\.id))
        for task in existingTasks where task.isActive && task.completedAt == nil
            && (task.questionID.map(reserved.contains) == true
                || (task.activity == .resourcePractice && reservedPapers.contains(task.sourceID))) {
            task.isActive = false
        }
        // An invitation already in the next three days stays there through an unchanged refresh,
        // so the plan does not gain a second one further on.
        let keepsInvitation = keepsWindow && existingTasks.contains {
            $0.activity == .diagnosticRefinement && $0.isActive && $0.completedAt == nil
                && $0.scheduledDate >= windowStart && $0.scheduledDate < windowEnd
        }
        let refinement = keepsInvitation ? nil : refinementMinutes(snapshot: snapshot, settings: settings,
                                                                   content: content, existingTasks: existingTasks, in: context)
        // R4: when the library can supply fresh self-marked worksheets, a question is revisited once
        // rather than drilled a third or fourth time; the days that frees go to the library.
        let preferLibrary = resourceSessions && catalogue.practicable.contains { $0.answerMode == .selfMarked }
        // A worksheet the student has started keeps its day, so its minutes are booked before the
        // engine plans that day.
        var booked: [Date: Int] = [:]
        if resourceSessions {
            let profile = settings.id
            let started = startedWorksheetTaskIDs(try context.fetch(FetchDescriptor<TMUAResourceLog>(
                predicate: #Predicate { $0.profileSettingsID == profile })))
            for task in existingTasks where task.completedAt == nil && started.contains(task.stableID) {
                booked[calendar.startOfDay(for: task.scheduledDate), default: 0] += task.allocatedMinutes
            }
        }
        let programme = try PublicProgrammeService.applyPlan(
            programmeID: programmeID(settings: settings), settings: settings, examDate: examDate,
            weeklyMinutes: weekly, today: today, calendar: calendar,
            changed: { settingsChanged($0, settings: settings, calendar: calendar) },
            in: context) { start, excluded in
            planningInput(settings: settings, content: content, report: report, evidence: evidence,
                          start: start, examDate: examDate, weeklyMinutes: weekly,
                          excludedQuestionIDs: reserved, plannedElsewhere: excluded, refinement: refinement.map {
                              ($0, refinementSourceID(for: snapshot.diagnostic.targetLength)) },
                          calendar: calendar, preferLibraryOverRepeats: preferLibrary, bookedMinutes: booked)
        }
        if resourceSessions {
            try scheduleResourceSessions(programme: programme, settings: settings, content: content,
                                         today: today, calendar: calendar, report: report, catalogue: catalogue,
                                         reserved: reserved, in: context)
        }
        if hadProgramme {
            let after = try tasks(settings: settings, in: context).filter(changeable)
            programme.refreshSummary = PublicProgrammeService.refreshSummary(before: beforeTopics, after: after.map(\.topic),
                completed: programme.completedCountAtRefresh, frozen: kept)
            try context.save()
        }
        return programme
    }

    /// Question identities waiting in an unsubmitted diagnostic section.
    static func reservedStableIDs(snapshot: TMUADiagnosticSnapshot) -> Set<String> {
        let open = Set(snapshot.openSections.map(\.stableID))
        return Set(snapshot.items.filter { open.contains($0.sectionID) }.map(\.itemStableID))
    }

    /// Adds diagnostic questions and, when a plan exists, refreshes it at once
    /// so planned practice of the newly reserved questions is retired.
    @discardableResult
    static func expandDiagnostic(_ snapshot: TMUADiagnosticSnapshot, to target: TMUADiagnosticLength,
                                 settings: AppSettings, content: TMUAContentContext, today: Date = .now,
                                 calendar: Calendar = DateUtilities.appCalendar(),
                                 resourceSessions: Bool = false,
                                 in context: ModelContext) throws -> TMUADiagnosticSnapshot {
        let expanded = try TMUADiagnosticService.expand(snapshot, to: target, settings: settings,
                                                        content: content, in: context)
        if try load(settings: settings, in: context) != nil {
            try generateOrRefresh(settings: settings, content: content, today: today, calendar: calendar,
                                  resourceSessions: resourceSessions, in: context)
        }
        return expanded
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
        plannedElsewhere: Set<String> = [],
        refinement: (minutes: Int, sourceID: String)?,
        calendar: Calendar,
        preferLibraryOverRepeats: Bool = false,
        bookedMinutes: [Date: Int] = [:]
    ) -> PublicPlanningInput {
        // Two attempts at the same instant are told apart by what they record, never by fetch order
        // or random record IDs, so the same history always gives the same plan.
        let latestAttempt = Dictionary(grouping: evidence.attempts, by: \.itemStableID)
            .compactMapValues { $0.max(by: TMUAPracticeAttempt.isEarlier) }
        let diagnosticByID = Dictionary(evidence.diagnosticItems
            .sorted { ($0.sectionID, $0.ordinal) < ($1.sectionID, $1.ordinal) }.map { ($0.itemStableID, $0) },
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
                    hasSolution: true, outcomeFromPractice: attempt != nil)
            }
        var options = PublicPlanningOptions()
        options.dailyMinutesCap = settings.publicSessionMinutes
        options.paceFreshQuestions = true
        options.balanceFallbackTopics = true
        options.minimumOneTaskPerStudyDay = true
        options.calendarDayRotation = true
        options.recentRankFromPracticeOnly = true
        options.plannedElsewhereQuestionIDs = plannedElsewhere
        options.bookedMinutesByDay = bookedMinutes
        options.spacedReviewIntervalDays = spacedReviewIntervalDays
        options.maximumSpacedRepeats = maximumSpacedRepeats(questionCount: questions.count, start: start,
            examDate: examDate, weeklyMinutes: weeklyMinutes, sessionMinutes: settings.publicSessionMinutes,
            availability: settings.publicAvailability, calendar: calendar)
        if preferLibraryOverRepeats { options.maximumSpacedRepeats = libraryRevisitLimit }
        options.diagnosticRefinementMinutes = refinement?.minutes
        if let refinement { options.diagnosticRefinementSourceID = refinement.sourceID }
        return PublicPlanningInput(exam: .tmua, startDate: start, examDate: examDate,
            weeklyMinutes: weeklyMinutes, availability: settings.publicAvailability,
            diagnosticSignals: report.topics, questions: questions, papers: [],
            calendar: calendar, options: options)
    }

    /// Revisits per question: two, or three when the window has room. More
    /// repeats of the same multiple-choice question add little, so a small
    /// bank leaves honest gaps (reported by `contentSummary`) instead.
    static let spacedRepeatLimit = 3
    /// Revisits per question when fresh library worksheets can fill the days instead (R4).
    static let libraryRevisitLimit = 1

    static func maximumSpacedRepeats(questionCount: Int, start: Date, examDate: Date, weeklyMinutes: Int,
                                     sessionMinutes: Int?, availability: [DayAvailability],
                                     calendar: Calendar) -> Int {
        let days = PublicPreparationService.studyDaysBeforeExam(examDate, availability: availability,
                                                                today: start, calendar: calendar)
        let studyDays = max(1, availability.filter(\.isAvailable).count)
        let perDay = min(weeklyMinutes / studyDays, sessionMinutes ?? .max)
        let slots = days * max(1, perDay / PublicPlanningPolicy.questionMinutes(for: .tmua))
        let needed = Int((Double(slots) / Double(max(1, questionCount))).rounded(.up)) - 1
        return min(spacedRepeatLimit, max(2, needed))
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
        let previous = task.map { ($0.completedAt, $0.completionAttemptID, $0.completionNote) }
        let attempt = TMUAPracticeAttempt(profileSettingsID: settings.id, item: item,
            selectedOptionID: selectedOptionID, seconds: seconds,
            origin: task == nil ? .questionBank : .programme, programmeTaskID: task?.stableID, at: date)
        context.insert(attempt)
        if let task {
            task.completedAt = date
            task.completionAttemptID = attempt.id
            task.completionNote = attempt.isCorrect ? "Correct" : "Incorrect"
        }
        do { try context.save() } catch {
            // Rollback leaves model properties as set, so restore the task.
            context.rollback()
            if let task, let previous {
                (task.completedAt, task.completionAttemptID, task.completionNote) = previous
            }
            throw error
        }
        return attempt
    }

    static func setReviewFlag(_ flagged: Bool, itemStableID: String, settings: AppSettings,
                              at date: Date = .now, in context: ModelContext) throws {
        let id = "\(settings.id.uuidString)-\(itemStableID)"
        let existing = try context.fetch(FetchDescriptor<TMUAReviewFlag>(
            predicate: #Predicate { $0.stableID == id })).first
        let previous = existing.map { ($0.isFlagged, $0.updatedAt) }
        if let existing {
            existing.isFlagged = flagged
            existing.updatedAt = date
        } else {
            context.insert(TMUAReviewFlag(profileSettingsID: settings.id, itemStableID: itemStableID,
                                          isFlagged: flagged, at: date))
        }
        do { try context.save() } catch {
            context.rollback()
            if let existing, let previous { (existing.isFlagged, existing.updatedAt) = previous }
            throw error
        }
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

/// What the current bank can honestly support in the remaining plan: how
/// many study days have work and when previously unseen questions run out.
struct TMUAPlanContentSummary: Equatable {
    let studyDays: Int
    let emptyStudyDays: Int
    let distinctQuestions: Int
    /// Remaining study days given a self-marked paper session because the bank cannot fill them.
    var paperSessionDays = 0
    /// Remaining study days with a self-marked topic worksheet from the library (R4).
    var worksheetDays = 0
    let lastNewQuestionDate: Date?
    /// Days between the last newly introduced question and the exam.
    let daysWithoutNewQuestions: Int

    /// Unseen questions run out more than two weeks before the exam.
    var newQuestionsRunOutEarly: Bool { daysWithoutNewQuestions > 14 }

    var isContentLimited: Bool { emptyStudyDays > 0 || newQuestionsRunOutEarly }

    var message: String? {
        guard isContentLimited else { return nil }
        var parts: [String] = []
        if newQuestionsRunOutEarly {
            // With library sessions a question marked by Revisr returns once, and the library fills
            // the days; without them it returns up to three times at widening gaps.
            let after = worksheetDays > 0
                ? "your plan returns to earlier questions less often and fills the other days with self-marked worksheets from your library"
                : paperSessionDays > 0
                    ? "your plan revisits earlier questions with widening gaps, and some days use a self-marked paper instead"
                    : "your plan revisits earlier questions with widening gaps"
            parts.append(lastNewQuestionDate.map {
                "Questions marked by Revisr that you have not seen before run out on \($0.formatted(date: .abbreviated, time: .omitted)). After that, \(after)."
            } ?? "There are no questions marked by Revisr that you have not seen before left in this build, so \(after).")
        }
        if worksheetDays > 0 {
            parts.append("\(worksheetDays) study day\(worksheetDays == 1 ? "" : "s") include a self-marked topic worksheet from your library.")
        }
        if paperSessionDays > 0 {
            parts.append("\(paperSessionDays) study day\(paperSessionDays == 1 ? "" : "s") use a self-marked paper from your library instead.")
        }
        if emptyStudyDays > 0 {
            parts.append("\(emptyStudyDays) of your \(studyDays) remaining study days have no task because this build does not yet have enough questions to fill them.")
        }
        return parts.joined(separator: " ")
    }
}

extension TMUAProgrammeService {
    static func contentSummary(programme: PublicProgramme, tasks: [PublicProgrammeTask],
                               seenStableIDs: Set<String>, availability: [DayAvailability],
                               today: Date = .now, calendar: Calendar = DateUtilities.appCalendar()) -> TMUAPlanContentSummary {
        let start = calendar.startOfDay(for: today)
        let examDay = calendar.startOfDay(for: programme.examDateSnapshot)
        let future = tasks.filter { $0.isActive && $0.scheduledDate >= start && $0.scheduledDate < examDay }
            .sorted { $0.scheduledDate < $1.scheduledDate }
        let busyDays = Set(future.map { calendar.startOfDay(for: $0.scheduledDate) })
        var studyDays = 0
        var empty = 0
        var date = start
        while date < examDay {
            if PublicProgrammeAvailability.isAvailable(on: date, schedule: availability, calendar: calendar) == true {
                studyDays += 1
                if !busyDays.contains(date) { empty += 1 }
            }
            date = PublicPlanningEngine.nextDay(after: date, calendar: calendar, limit: examDay)
        }
        var seen = seenStableIDs
        var lastNew: Date?
        for task in future {
            guard let id = task.questionID, !seen.contains(id) else { continue }
            seen.insert(id)
            lastNew = calendar.startOfDay(for: task.scheduledDate)
        }
        let gap = calendar.dateComponents([.day], from: lastNew ?? start, to: examDay).day ?? 0
        let paperDays = Set(future.filter { $0.activity == .resourcePractice }.map { calendar.startOfDay(for: $0.scheduledDate) })
        let worksheetDays = Set(future.filter { $0.activity == .topicWorksheet }.map { calendar.startOfDay(for: $0.scheduledDate) })
        return TMUAPlanContentSummary(studyDays: studyDays, emptyStudyDays: empty,
                                      distinctQuestions: Set(future.compactMap(\.questionID)).count,
                                      paperSessionDays: paperDays.count, worksheetDays: worksheetDays.count,
                                      lastNewQuestionDate: lastNew, daysWithoutNewQuestions: gap)
    }

    /// Questions the student has met in a submitted diagnostic or in practice.
    static func seenStableIDs(settings: AppSettings, in context: ModelContext) -> Set<String> {
        let profile = settings.id
        let attempts = (try? context.fetch(FetchDescriptor<TMUAPracticeAttempt>(
            predicate: #Predicate { $0.profileSettingsID == profile }))) ?? []
        let diagnostic = (try? TMUADiagnosticService.load(settings: settings, in: context))?.submittedItems ?? []
        return Set(attempts.map(\.itemStableID)).union(diagnostic.map(\.itemStableID))
    }
}
