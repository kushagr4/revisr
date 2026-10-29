import Foundation
import SwiftData

/// Self-marked paper sessions for study days that Revisr's question bank cannot fill. They come
/// from the unified library (bundled personal study copies in internal builds, papers on the
/// provider's own site otherwise), never add question-level evidence, and are rebuilt with the
/// plan on every refresh. Days the bank can fill are never displaced.
extension TMUAProgrammeService {
    static let resourceTaskMarker = "-resource-"
    /// A topic worksheet's source ID names its questions: "worksheet:<topic key>:<id>,<id>,…".
    static let worksheetMarker = "worksheet:"

    nonisolated static func worksheetSourceID(topic: String, questions: [String]) -> String {
        worksheetMarker + topic + ":" + questions.joined(separator: ",")
    }

    /// The catalogue question IDs of a worksheet task, in order; empty for any other source ID.
    nonisolated static func worksheetQuestionIDs(_ sourceID: String) -> [String] {
        guard sourceID.hasPrefix(worksheetMarker) else { return [] }
        let parts = sourceID.dropFirst(worksheetMarker.count).split(separator: ":", maxSplits: 1)
        return parts.count == 2 ? parts[1].split(separator: ",").map(String.init) : []
    }

    nonisolated static func worksheetTopic(_ sourceID: String) -> String? {
        guard sourceID.hasPrefix(worksheetMarker) else { return nil }
        return sourceID.dropFirst(worksheetMarker.count).split(separator: ":", maxSplits: 1).first.map(String.init)
    }

    /// R4: topic worksheets from the unified catalogue. Questions from papers in the library that the
    /// student opens at their page and marks against the publisher's solution, grouped by syllabus
    /// topic in `topicOrder` (weakest diagnostic evidence first). TMUA-format papers come first, then
    /// other admissions tests, then competitions; a question already recorded, already in a worksheet,
    /// in a paper the plan uses whole, or adapted from one already chosen is never offered again.
    nonisolated static func worksheetCandidates(_ entries: [TMUACatalogueEntry], topicOrder: [String],
                                                excluded: Set<String>, excludedSources: Set<String>,
                                                size: Int) -> [(topic: String, questions: [String])] {
        func rank(_ entry: TMUACatalogueEntry) -> Int {
            switch entry.provider?.kind {
            case .officialTMUA?: 0
            case .independentMock?: 1
            case .otherAdmissionsTest?: 2
            default: 3
            }
        }
        var used = excluded
        let usable = entries.filter { entry in
            entry.presentation == .document && entry.answerMode == .selfMarked && entry.paperFit != .unclassified
                && entry.topicKey != nil && !excludedSources.contains(entry.sourceID ?? "")
                && !used.contains(entry.id) && entry.format == "Multiple choice"
        }
        let byTopic = Dictionary(grouping: usable, by: { $0.topicKey ?? "" })
            .mapValues { $0.sorted { (rank($0), $0.difficulty ?? 3, $0.id) < (rank($1), $1.difficulty ?? 3, $1.id) } }
        var queues = byTopic.mapValues { $0[...] }
        var result: [(String, [String])] = []
        var progressed = true
        // Round-robin over topics in priority order, one worksheet per topic per round.
        while progressed {
            progressed = false
            for topic in topicOrder {
                var picked: [String] = []
                while picked.count < size, let entry = queues[topic]?.popFirst() {
                    if used.contains(entry.id) || entry.variantOf.map(used.contains) == true { continue }
                    picked.append(entry.id)
                    used.insert(entry.id)
                }
                if picked.count >= max(2, size / 2) {
                    result.append((topic, picked))
                    progressed = true
                }
            }
        }
        return result
    }

    /// Syllabus topic keys, weakest diagnostic evidence first, then every other topic.
    nonisolated static func worksheetTopicOrder(report: TMUADiagnosticReport?, syllabus: TMUASyllabus) -> [String] {
        func weight(_ level: DiagnosticEvidenceLevel?) -> Int {
            switch level {
            case .strongDifficulty?: 0
            case .possibleImprovement?: 1
            case .insufficient?, nil: 2
            case .relativeStrength?: 3
            }
        }
        let levels = Dictionary((report?.topics ?? []).map { ($0.name, $0.level) }, uniquingKeysWith: { first, _ in first })
        return syllabus.topics.enumerated()
            .sorted { (weight(levels[$0.element.title]), $0.offset) < (weight(levels[$1.element.title]), $1.offset) }
            .map(\.element.key)
    }

    /// Sources worth a TMUA student's practice time, in the order they are offered: official TMUA
    /// papers that Revisr cannot auto-mark, then TMUA-format mocks, MAT, the Senior Mathematical
    /// Challenge, then STEP. Papers already finished, and papers whose every question is
    /// auto-marked in this build (those already feed the plan question by question), are skipped.
    nonisolated static func resourceCandidates(_ sources: [TMUAResourceSource],
                                               completed: Set<String>) -> [TMUAResourceSource] {
        func rank(_ source: TMUAResourceSource) -> Int? {
            guard !source.questions.isEmpty, source.autoMarkedCount < source.questions.count,
                  !completed.contains(source.id) else { return nil }
            switch source.kind {
            case .officialTMUA: return 0
            case .independentMock: return 1
            case .otherAdmissionsTest: return source.family == "MAT" ? 2 : source.family == "STEP" ? 4 : nil
            case .competition: return source.family == "SMC" ? 3 : nil
            case .reference: return nil
            }
        }
        var ranked: [(source: TMUAResourceSource, rank: Int, order: Int)] = []
        for (order, source) in sources.enumerated() {
            if let value = rank(source) { ranked.append((source, value, order)) }
        }
        ranked.sort { lhs, rhs in lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.order < rhs.order }
        return ranked.map(\.source)
    }

    nonisolated static func resourceSessionMinutes(weeklyMinutes: Int, availability: [DayAvailability]) -> Int {
        let days = max(1, availability.filter(\.isAvailable).count)
        return min(75, max(20, weeklyMinutes / days))
    }

    nonisolated static func resourceReason(_ source: TMUAResourceSource, minutes: Int) -> String {
        let scope = minutes >= 75 ? "Sit the paper in 75 minutes" : "Work through as much of the paper as fits in \(minutes) minutes"
        let access = source.access == .studyCopy ? "from your library" : "on \(source.provider.name)’s website"
        return "\(scope) \(access), then mark it with its solutions. New Revisr questions do not fill this day; your result is recorded for progress, not as evidence of topic mastery."
    }

    static func scheduleResourceSessions(programme: PublicProgramme, settings: AppSettings,
                                         content: TMUAContentContext, today: Date, calendar: Calendar,
                                         report: TMUADiagnosticReport? = nil,
                                         in context: ModelContext) throws {
        let catalogue = TMUACatalogueStore.catalogue(content)
        let sources = catalogue.sources
        let all = try PublicProgrammeService.tasks(for: programme, in: context)
        let profile = settings.id
        let logs = try context.fetch(FetchDescriptor<TMUAResourceLog>(predicate: #Predicate { $0.profileSettingsID == profile }))
        let resourceTasks = all.filter { $0.stableID.contains(resourceTaskMarker) }
        var completed = Set(logs.filter { $0.questionID == nil }.map(\.sourceID))
        completed.formUnion(resourceTasks.filter { $0.completedAt != nil }.map(\.sourceID))
        // Sessions inside the frozen window stay as they are; their papers are not offered twice.
        let kept = resourceTasks.filter { $0.isActive && $0.completedAt == nil }
        let papers = resourceCandidates(sources, completed: completed.union(kept.map(\.sourceID)))
        let minutes = resourceSessionMinutes(weeklyMinutes: programme.weeklyMinutesSnapshot,
                                             availability: settings.publicAvailability)
        // Questions already recorded or in another worksheet are not offered again. A paper the plan
        // sets whole keeps its questions for that session, and a paper with a question in a worksheet
        // is not then set whole; papers merely eligible for a session reserve nothing.
        let worksheetQuestions = resourceTasks.filter { $0.isActive || $0.completedAt != nil }
            .flatMap { worksheetQuestionIDs($0.sourceID) }
        let worksheets = worksheetCandidates(
            catalogue.entries, topicOrder: worksheetTopicOrder(report: report, syllabus: content.syllabus),
            excluded: Set(logs.compactMap(\.questionID) + worksheetQuestions),
            excludedSources: completed.union(kept.map(\.sourceID)),
            size: worksheetSize(minutes: minutes))
        var paperQueue = papers[...]
        var sheetQueue = worksheets[...]
        var wholePapers = Set<String>()
        var worksheetPapers = Set(worksheetQuestions.compactMap { catalogue.entry($0)?.sourceID })
        typealias Session = (sourceID: String, topic: String, activity: PublicPlanningActivity, reason: String, minutes: Int)
        func worksheet(minutes: Int) -> Session? {
            while let sheet = sheetQueue.popFirst() {
                let questions = Array(sheet.questions
                    .filter { !wholePapers.contains(catalogue.entry($0)?.sourceID ?? "") }
                    .prefix(worksheetSize(minutes: minutes)))
                guard questions.count >= 2 else { continue }
                worksheetPapers.formUnion(questions.compactMap { catalogue.entry($0)?.sourceID })
                let title = content.syllabus.topicTitle(sheet.topic)
                return (worksheetSourceID(topic: sheet.topic, questions: questions), title, .topicWorksheet,
                        worksheetReason(topic: title, count: questions.count), minutes)
            }
            return nil
        }
        func wholePaper() -> Session? {
            while let paper = paperQueue.popFirst() {
                guard !worksheetPapers.contains(paper.id) else { continue }
                wholePapers.insert(paper.id)
                return (paper.id, "Mixed practice", .resourcePractice, resourceReason(paper, minutes: minutes), minutes)
            }
            return nil
        }
        let byID = Dictionary(resourceTasks.map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
        // Minutes already planned per day: a day the bank fills is never displaced, and a day it leaves
        // with room for at least a short worksheet takes one sized to that room.
        var planned: [Date: Int] = [:]
        for task in all where task.isActive || task.completedAt != nil {
            planned[calendar.startOfDay(for: task.scheduledDate), default: 0] += task.allocatedMinutes
        }
        // One library session per day: a kept or completed one is never replaced.
        let sessionDays = Set(resourceTasks.filter { $0.isActive || $0.completedAt != nil }
            .map { calendar.startOfDay(for: $0.scheduledDate) })
        let dayCapacity = min(settings.publicSessionMinutes ?? .max,
                              programme.weeklyMinutesSnapshot / max(1, settings.publicAvailability.filter(\.isAvailable).count))
        let examDay = calendar.startOfDay(for: programme.examDateSnapshot)
        var date = calendar.startOfDay(for: today)
        var nextIsWorksheet = true
        while date < examDay, !paperQueue.isEmpty || !sheetQueue.isEmpty {
            defer { date = calendar.date(byAdding: .day, value: 1, to: date) ?? examDay }
            guard PublicProgrammeAvailability.isAvailable(on: date, schedule: settings.publicAvailability,
                                                          calendar: calendar) == true,
                  !sessionDays.contains(date) else { continue }
            let used = planned[date] ?? 0
            let session: Session
            if used == 0 {
                // An empty day alternates a topic worksheet with a whole paper, worksheet first.
                if nextIsWorksheet || paperQueue.isEmpty, let sheet = worksheet(minutes: minutes) {
                    session = sheet
                    nextIsWorksheet = false
                } else if let paper = wholePaper() {
                    session = paper
                    nextIsWorksheet = true
                } else if let sheet = worksheet(minutes: minutes) {
                    session = sheet
                } else { continue }
            } else if dayCapacity - used >= minimumWorksheetMinutes, let sheet = worksheet(minutes: dayCapacity - used) {
                session = sheet
            } else {
                continue
            }
            planned[date, default: 0] += session.minutes
            let id = "\(programme.stableID)\(resourceTaskMarker)\(Self.dayKey(date, calendar: calendar))"
            let task = PublicPlannedTask(date: date, questionID: nil, sourceID: session.sourceID, topic: session.topic,
                                         minutes: session.minutes, activity: session.activity, reason: session.reason)
            if let existing = byID[id] {
                existing.isActive = true
                existing.scheduledDate = date
                existing.sourceID = session.sourceID
                existing.topic = session.topic
                existing.activityRawValue = session.activity.rawValue
                existing.allocatedMinutes = session.minutes
                existing.reason = task.reason
            } else {
                context.insert(PublicProgrammeTask(stableID: id, programmeID: programme.stableID, task: task))
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Shortest room on a planned day worth a worksheet: three questions at about six minutes each.
    static let minimumWorksheetMinutes = 18

    nonisolated static func worksheetSize(minutes: Int) -> Int { min(8, max(3, minutes / 6)) }

    nonisolated static func worksheetReason(topic: String, count: Int) -> String {
        "\(count) questions on \(topic.lowercased()) from papers in your library, which Revisr cannot mark. Open each at its page, mark it against the publisher’s solution and record how it went. Your results count towards your progress and plan, not as evidence of topic mastery."
    }

    /// Completes a resource session with the student's own result.
    static func completeResourceSession(_ task: PublicProgrammeTask, outcome: TMUAResourceOutcome, correct: Int?,
                                        questionCount: Int?, minutes: Int?, settings: AppSettings,
                                        at date: Date = .now, in context: ModelContext) throws {
        guard task.activity == .resourcePractice || task.activity == .topicWorksheet else { throw TMUAProgrammeError.invalidTask }
        guard task.completedAt == nil else { throw TMUAProgrammeError.taskAlreadyComplete }
        let log = TMUAResourceLog(profileSettingsID: settings.id, sourceID: task.sourceID, questionID: nil,
                                  outcome: outcome, correctCount: correct, questionCount: questionCount,
                                  minutes: minutes, recordedAt: date, programmeTaskID: task.stableID)
        context.insert(log)
        task.completedAt = date
        task.completionNote = "Self-recorded: \(outcome.title)" + (correct.map { c in questionCount.map { " \(c)/\($0)" } ?? "" } ?? "")
        do { try context.save() } catch {
            context.rollback()
            task.completedAt = nil
            task.completionNote = ""
            throw error
        }
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
