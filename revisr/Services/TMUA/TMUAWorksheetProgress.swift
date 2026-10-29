import Foundation
import SwiftData

/// R5: a topic worksheet's question-level progress, read from the results the student records
/// against each of its questions (`TMUAResourceLog` rows carrying the worksheet's task ID). These
/// are self-reports on questions Revisr cannot mark, so none of them is verified evidence.
struct TMUAWorksheetProgress: Equatable {
    enum State: Equatable {
        case notStarted
        case inProgress
        /// Every question has a result; the student has not yet finished the worksheet.
        case readyToFinish
        case completed
        /// Finished with some questions skipped or never recorded.
        case completedWithGaps
    }

    let questionIDs: [String]
    /// The latest result recorded in this worksheet for each of its questions.
    let results: [String: TMUAResourceOutcome]
    let isFinished: Bool

    func count(_ outcome: TMUAResourceOutcome) -> Int {
        questionIDs.filter { results[$0] == outcome }.count
    }

    var recorded: Int { questionIDs.filter { results[$0] != nil }.count }
    /// Recorded with something other than "Skipped".
    var worked: Int { recorded - count(.skipped) }
    var unrecorded: Int { questionIDs.count - recorded }
    /// The first question without a result: where the student picks up again.
    var nextQuestionID: String? { questionIDs.first { results[$0] == nil } }
    /// Finishing needs at least one question actually worked; skipping everything finishes nothing.
    var canFinish: Bool { !isFinished && worked > 0 }

    var state: State {
        if isFinished { return worked == questionIDs.count ? .completed : .completedWithGaps }
        if recorded == 0 { return .notStarted }
        return unrecorded == 0 ? .readyToFinish : .inProgress
    }

    /// "3 of 8 recorded" while working; the tally once finished or fully recorded.
    var summary: String {
        switch state {
        case .notStarted: "\(questionIDs.count) question\(questionIDs.count == 1 ? "" : "s") · not started"
        case .inProgress: "\(recorded) of \(questionIDs.count) recorded"
        case .readyToFinish, .completed, .completedWithGaps: tally
        }
    }

    /// "5 correct · 2 incorrect · 1 skipped", in a fixed order, omitting zeros.
    var tally: String {
        var parts = [TMUAResourceOutcome.correct, .partial, .incorrect, .attempted, .skipped].compactMap { outcome in
            count(outcome) > 0 ? "\(count(outcome)) \(outcome.title.lowercased())" : nil
        }
        if unrecorded > 0 { parts.append("\(unrecorded) not recorded") }
        return parts.joined(separator: " · ")
    }

    /// The whole worksheet's self-marked result, for its completion record.
    var overallOutcome: TMUAResourceOutcome {
        let wrong = count(.incorrect) + count(.partial)
        if count(.correct) == questionIDs.count { return .correct }
        if wrong > 0 { return count(.correct) == 0 && count(.partial) == 0 && count(.attempted) == 0 ? .incorrect : .partial }
        return .attempted
    }
}

extension TMUAProgrammeService {
    /// Progress of one worksheet task from the student's recorded results. Only rows recorded in
    /// this worksheet count; a result for the same question elsewhere in the app does not.
    static func worksheetProgress(questionIDs: [String], taskID: String, isFinished: Bool,
                                  logs: [TMUAResourceLog]) -> TMUAWorksheetProgress {
        var latest: [String: TMUAResourceLog] = [:]
        for log in logs where log.programmeTaskID == taskID {
            guard let id = log.questionID else { continue }
            if let current = latest[id], !TMUAResourceLog.isEarlier(current, log) { continue }
            latest[id] = log
        }
        return TMUAWorksheetProgress(questionIDs: questionIDs, results: latest.mapValues(\.outcome), isFinished: isFinished)
    }

    static func worksheetProgress(_ task: PublicProgrammeTask, logs: [TMUAResourceLog]) -> TMUAWorksheetProgress {
        worksheetProgress(questionIDs: worksheetQuestionIDs(task.sourceID), taskID: task.stableID,
                          isFinished: task.completedAt != nil, logs: logs)
    }

    /// Worksheet tasks with at least one recorded result: work in progress that a refresh keeps.
    static func startedWorksheetTaskIDs(_ logs: [TMUAResourceLog]) -> Set<String> {
        Set(logs.filter { $0.questionID != nil }.compactMap(\.programmeTaskID))
    }

    /// Records the student's own result for one worksheet question. A later result replaces the
    /// earlier one in the worksheet's tally; both stay in the question's history.
    static func recordWorksheetResult(_ outcome: TMUAResourceOutcome, questionID: String, paperSourceID: String,
                                      task: PublicProgrammeTask, minutes: Int? = nil, settings: AppSettings,
                                      at date: Date = .now, in context: ModelContext) throws {
        guard task.activity == .topicWorksheet, worksheetQuestionIDs(task.sourceID).contains(questionID) else {
            throw TMUAProgrammeError.invalidTask
        }
        guard task.completedAt == nil else { throw TMUAProgrammeError.taskAlreadyComplete }
        context.insert(TMUAResourceLog(profileSettingsID: settings.id, sourceID: paperSourceID, questionID: questionID,
                                       outcome: outcome, minutes: minutes, recordedAt: date,
                                       programmeTaskID: task.stableID))
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Finishes a worksheet from its question-level results. Questions without a result stay
    /// unrecorded (never counted as correct), and a worksheet with nothing worked cannot finish.
    static func finishWorksheet(_ task: PublicProgrammeTask, settings: AppSettings, at date: Date = .now,
                                in context: ModelContext) throws {
        guard task.activity == .topicWorksheet else { throw TMUAProgrammeError.invalidTask }
        guard task.completedAt == nil else { throw TMUAProgrammeError.taskAlreadyComplete }
        let profile = settings.id
        let logs = try context.fetch(FetchDescriptor<TMUAResourceLog>(predicate: #Predicate { $0.profileSettingsID == profile }))
        let progress = worksheetProgress(task, logs: logs)
        guard progress.canFinish else { throw TMUAProgrammeError.invalidTask }
        let minutes = logs.filter { $0.programmeTaskID == task.stableID && $0.questionID != nil }.compactMap(\.minutes)
        context.insert(TMUAResourceLog(profileSettingsID: settings.id, sourceID: task.sourceID, questionID: nil,
            outcome: progress.overallOutcome, correctCount: progress.count(.correct),
            questionCount: progress.questionIDs.count, minutes: minutes.isEmpty ? nil : minutes.reduce(0, +),
            recordedAt: date, programmeTaskID: task.stableID))
        task.completedAt = date
        task.completionNote = "Self-marked: " + progress.tally
        do { try context.save() } catch {
            context.rollback()
            task.completedAt = nil
            task.completionNote = ""
            throw error
        }
    }
}
