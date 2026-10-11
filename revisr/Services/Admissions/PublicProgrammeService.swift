import Foundation
import SwiftData

enum PublicProgrammeError: LocalizedError {
    case diagnosticsIncomplete
    case taskAlreadyComplete
    case questionUnavailable
    case invalidTask

    var errorDescription: String? {
        switch self {
        case .diagnosticsIncomplete: "Complete both diagnostic papers before generating a programme."
        case .taskAlreadyComplete: "This task is already complete. Your earlier work is unchanged."
        case .questionUnavailable: "This question is no longer available in the local catalogue."
        case .invalidTask: "This programme task cannot be completed in its current state."
        }
    }
}

@MainActor
enum PublicProgrammeService {
    static func programmeID(settings: AppSettings) -> String {
        "public-programme-v1-\(settings.id.uuidString)-\(settings.publicExam.rawValue)"
    }

    static func load(settings: AppSettings, in context: ModelContext) throws -> PublicProgramme? {
        let id = programmeID(settings: settings)
        return try context.fetch(FetchDescriptor<PublicProgramme>()).first { $0.stableID == id }
    }

    static func tasks(for programme: PublicProgramme, in context: ModelContext) throws -> [PublicProgrammeTask] {
        try context.fetch(FetchDescriptor<PublicProgrammeTask>())
            .filter { $0.programmeID == programme.stableID }
            .sorted {
                if $0.scheduledDate != $1.scheduledDate { return $0.scheduledDate < $1.scheduledDate }
                return $0.stableID < $1.stableID
            }
    }

    static func settingsChanged(_ programme: PublicProgramme, settings: AppSettings,
                                calendar: Calendar = DateUtilities.appCalendar()) -> Bool {
        guard let date = settings.publicExamDate,
              let weekly = settings.publicWeeklyTargetMinutes else { return true }
        return !calendar.isDate(programme.examDateSnapshot, inSameDayAs: date)
            || programme.weeklyMinutesSnapshot != weekly
            || programme.availabilitySnapshot != settings.publicAvailability
    }

    static func generateIfNeeded(settings: AppSettings, today: Date = .now,
                                 calendar: Calendar = DateUtilities.appCalendar(),
                                 in context: ModelContext) throws -> PublicProgramme {
        if let existing = try load(settings: settings, in: context) { return existing }
        return try createOrRefresh(settings: settings, today: today, calendar: calendar, in: context)
    }

    static func refresh(settings: AppSettings, today: Date = .now,
                        calendar: Calendar = DateUtilities.appCalendar(),
                        in context: ModelContext) throws -> PublicProgramme {
        try createOrRefresh(settings: settings, today: today, calendar: calendar, in: context)
    }

    private static func createOrRefresh(settings: AppSettings, today: Date,
                                        calendar: Calendar, in context: ModelContext) throws -> PublicProgramme {
        guard let examDate = settings.publicExamDate,
              let weeklyMinutes = settings.publicWeeklyTargetMinutes else {
            throw PublicProgrammeError.diagnosticsIncomplete
        }
        let id = programmeID(settings: settings)
        let assessmentID = DiagnosticAssessmentService.assessmentID(profileID: settings.id, exam: settings.publicExam)
        guard let assessment = try context.fetch(FetchDescriptor<DiagnosticAssessment>()).first(where: {
            $0.stableID == assessmentID && $0.completedAt != nil
        }) else { throw PublicProgrammeError.diagnosticsIncomplete }
        let old = try load(settings: settings, in: context)
        let oldTasks = try old.map { try tasks(for: $0, in: context) } ?? []
        let changed = old.map { settingsChanged($0, settings: settings, calendar: calendar) } ?? false
        let currentDay = calendar.startOfDay(for: today)
        let stableEnd = calendar.date(byAdding: .day, value: 3, to: currentDay) ?? currentDay
        let start = old != nil && !changed ? stableEnd : currentDay
        let frozen = oldTasks.filter { task in
            task.isActive && task.completedAt == nil && task.scheduledDate >= currentDay
                && task.scheduledDate < stableEnd && !changed
        }
        let frozenQuestionIDs = Set(frozen.compactMap(\.questionID))
        let snapshot = try makeInput(settings: settings, assessment: assessment,
                                     start: start, examDate: examDate,
                                     weeklyMinutes: weeklyMinutes, excludedQuestionIDs: frozenQuestionIDs,
                                     calendar: calendar, in: context)
        let result: PublicPlanningResult
        if start >= calendar.startOfDay(for: examDate), old != nil {
            result = PublicPlanningResult(tasks: [], priorities: [], availableDays: 0, unfilledDays: 0)
        } else {
            result = try PublicPlanningEngine.generate(snapshot)
        }
        let programme = old ?? PublicProgramme(stableID: id, profileSettingsID: settings.id,
            exam: settings.publicExam, generatedAt: today, examDate: examDate,
            weeklyMinutes: weeklyMinutes, availability: settings.publicAvailability)
        if old == nil { context.insert(programme) }

        let frozenIDs = Set(frozen.map(\.stableID))
        for task in oldTasks where task.completedAt == nil && !frozenIDs.contains(task.stableID) {
            task.isActive = false
        }
        let taskByID = Dictionary(uniqueKeysWithValues: oldTasks.map { ($0.stableID, $0) })
        for planned in result.tasks {
            let taskID = stableTaskID(programmeID: id, task: planned, calendar: calendar)
            if let existing = taskByID[taskID] {
                guard existing.completedAt == nil else { continue }
                existing.isActive = true
                existing.reason = planned.reason
                existing.allocatedMinutes = planned.minutes
            } else {
                context.insert(PublicProgrammeTask(stableID: taskID, programmeID: id, task: planned))
            }
        }
        if old != nil { programme.revision += 1 }
        programme.refreshedAt = today
        programme.examDateSnapshot = examDate
        programme.weeklyMinutesSnapshot = weeklyMinutes
        programme.availabilitySnapshotData = (try? JSONEncoder().encode(settings.publicAvailability)) ?? Data()
        programme.completedCountAtRefresh = oldTasks.filter { $0.completedAt != nil }.count
        settings.publicOnboardingStage = .programme
        do { try context.save() } catch { context.rollback(); throw error }
        return programme
    }

    private static func stableTaskID(programmeID: String, task: PublicPlannedTask,
                                     calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: task.date)
        let key = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(programmeID)-\(key)-\(task.activity.rawValue)-\(task.questionID ?? task.sourceID)"
    }

    private static func makeInput(settings: AppSettings, assessment: DiagnosticAssessment,
                                  start: Date, examDate: Date, weeklyMinutes: Int,
                                  excludedQuestionIDs: Set<String>, calendar: Calendar,
                                  in context: ModelContext) throws -> PublicPlanningInput {
        let allQuestions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let allSources = try context.fetch(FetchDescriptor<SourceDocument>())
        let allLinks = try context.fetch(FetchDescriptor<QuestionSolutionLink>())
        let allAttempts = try context.fetch(FetchDescriptor<QuestionAttempt>())
        let allPapers = try context.fetch(FetchDescriptor<DiagnosticPaperRecord>())
            .filter { $0.assessmentID == assessment.stableID }
        let paperIDs = Set(allPapers.map(\.stableID))
        let diagnosticResponses = try context.fetch(FetchDescriptor<DiagnosticResponse>())
            .filter { paperIDs.contains($0.paperID) }
        let diagnosticIDs = Set(diagnosticResponses.map(\.questionID))
        let paperByID = Dictionary(uniqueKeysWithValues: allPapers.map { ($0.stableID, $0) })
        let diagnosticReview = Dictionary(uniqueKeysWithValues: diagnosticResponses.compactMap { row -> (String, Date?)? in
            let needsReview = settings.publicExam == .bmo
                ? (row.selfEstimatedMarks.map { $0 <= 4 } ?? false)
                : row.marking == .incorrect
            guard needsReview else { return nil }
            return (row.questionID, paperByID[row.paperID]?.completedAt)
        })
        let report = DiagnosticAnalysis.report(exam: settings.publicExam,
            papers: allPapers, responses: diagnosticResponses, questions: allQuestions)
        let sources = Dictionary(uniqueKeysWithValues: allSources.map { ($0.stableSourceID, $0) })
        let availableSourceIDs = Set(allSources.filter {
            $0.isImportedActive && SourceLibraryService.bundledURL(for: $0) != nil
        }.map(\.stableSourceID))
        let solvedQuestionIDs = Set(allLinks.compactMap { link -> String? in
            guard link.isImportedActive, let solution = link.solutionDocument,
                  solution.isImportedActive, solution.isVerified, solution.mediaKind == .pdf,
                  SolutionLibraryService.bundledURL(for: solution) != nil else { return nil }
            return link.question?.externalQuestionID
        })
        let latest = Dictionary(grouping: allAttempts.compactMap { attempt -> (String, QuestionAttempt)? in
            guard let id = attempt.question?.externalQuestionID else { return nil }
            return (id, attempt)
        }, by: \.0).mapValues { rows in
            rows.map(\.1).max { $0.attemptedAt < $1.attemptedAt }!
        }
        let legacyReservedIDs = Set(try context.fetch(FetchDescriptor<ProgrammeAssignment>())
            .filter(\.isImportedActive).compactMap { $0.question?.externalQuestionID })
        let eligible = allQuestions.filter { question in
            guard let sourceID = question.sourceDocument?.stableSourceID,
                  let source = sources[sourceID], availableSourceIDs.contains(sourceID),
                  let page = question.page, page > 0, page <= (source.pageCount ?? 0) else { return false }
            guard question.isImportedActive, question.scheduleEligible,
                  question.validityState == .usable, question.protection == .none,
                  question.duplicateReviewState != .confirmedDuplicate,
                  question.duplicateReviewState != .possibleDuplicate,
                  question.possibleDuplicateQuestionIDs.isEmpty,
                  question.isUsefulFor(settings.publicExam.preparationStream),
                  !excludedQuestionIDs.contains(question.externalQuestionID) else { return false }
            // The legacy fixed programme's reserved/active questions remain out
            // of public selection, including TMUA Actual benchmarks.
            guard question.family != "TMUA Actual",
                  !legacyReservedIDs.contains(question.externalQuestionID) else { return false }
            return settings.publicExam == .bmo || solvedQuestionIDs.contains(question.externalQuestionID)
        }
        let questions = eligible.compactMap { question -> PublicPlanningQuestion? in
            guard let sourceID = question.sourceDocument?.stableSourceID else { return nil }
            let attempt = latest[question.externalQuestionID]
            return PublicPlanningQuestion(id: question.externalQuestionID, sourceID: sourceID,
                topic: question.primaryTopic, difficulty: question.difficulty,
                diagnostic: diagnosticIDs.contains(question.externalQuestionID),
                latestOutcome: attempt?.outcome ?? (diagnosticReview[question.externalQuestionID] != nil ? .partial : nil),
                latestAttemptDate: attempt?.attemptedAt ?? diagnosticReview[question.externalQuestionID] ?? nil,
                reviewFlag: question.reviewState != .none,
                hasSolution: solvedQuestionIDs.contains(question.externalQuestionID))
        }
        let grouped = Dictionary(grouping: questions, by: \.sourceID)
        let completePapers = grouped.compactMap { sourceID, rows -> PublicPlanningPaper? in
            guard rows.count == PublicPlanningPolicy.paperQuestionCount(for: settings.publicExam),
                  sources[sourceID]?.questionUnitCount == rows.count,
                  rows.allSatisfy({ !$0.diagnostic && $0.latestOutcome == nil }) else { return nil }
            return PublicPlanningPaper(sourceID: sourceID,
                questionIDs: rows.map(\.id).sorted(),
                durationMinutes: PublicPlanningPolicy.paperMinutes(for: settings.publicExam))
        }
        return PublicPlanningInput(exam: settings.publicExam, startDate: start,
            examDate: examDate, weeklyMinutes: weeklyMinutes,
            availability: settings.publicAvailability,
            diagnosticSignals: report.topics, questions: questions,
            papers: completePapers, calendar: calendar)
    }

    static func completeQuestion(_ task: PublicProgrammeTask, question: AdmissionsQuestion,
                                 outcome: QuestionAttemptOutcome, seconds: Int,
                                 errorType: QuestionErrorType?, notes: String,
                                 at date: Date = .now, in context: ModelContext) throws {
        guard task.isActive, task.completedAt == nil else { throw PublicProgrammeError.taskAlreadyComplete }
        guard task.questionID == question.externalQuestionID else { throw PublicProgrammeError.invalidTask }
        guard question.isImportedActive else { throw PublicProgrammeError.questionUnavailable }
        let attempt = QuestionAttempt(attemptedAt: date, outcome: outcome,
            timeTakenSeconds: max(0, seconds),
            errorType: outcome == .correct ? nil : errorType,
            notes: notes, origin: .programme, question: question)
        context.insert(attempt)
        task.completedAt = date
        task.completionAttemptID = attempt.id
        task.completionNote = notes
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func completePaper(_ task: PublicProgrammeTask, note: String,
                              at date: Date = .now, in context: ModelContext) throws {
        guard task.isActive, task.completedAt == nil else { throw PublicProgrammeError.taskAlreadyComplete }
        guard task.activity == .fullPaper, task.questionID == nil else { throw PublicProgrammeError.invalidTask }
        task.completedAt = date
        task.completionNote = note
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
