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
    /// R5: `weakTopics` (assessed weaknesses from the diagnostic) get two worksheets in each round
    /// instead of one, and `revisits` (questions the student marked wrong earlier) may come back once,
    /// first in their topic's queue.
    nonisolated static func worksheetCandidates(_ entries: [TMUACatalogueEntry], topicOrder: [String],
                                                excluded: Set<String>, excludedSources: Set<String>,
                                                size: Int, weakTopics: Set<String> = [],
                                                revisits: Set<String> = []) -> [(topic: String, questions: [String])] {
        func rank(_ entry: TMUACatalogueEntry) -> Int {
            switch entry.provider?.kind {
            case .officialTMUA?: 0
            case .independentMock?: 1
            case .otherAdmissionsTest?: 2
            default: 3
            }
        }
        var used = excluded.subtracting(revisits)
        // Adaptations are blocked by everything already practised, revisits included.
        var practised = excluded
        // A syllabus topic is required (a question outside the specification or not yet classified is
        // never set as topic practice); paper fit is not, since worksheets are grouped by topic only.
        let usable = entries.filter { entry in
            entry.presentation == .document && entry.answerMode == .selfMarked
                && entry.topicKey != nil && !excludedSources.contains(entry.sourceID ?? "")
                && !used.contains(entry.id) && entry.format == "Multiple choice"
        }
        // Adaptations in both directions: an original is skipped once one of its adaptations is set.
        let adaptations = Dictionary(grouping: entries.filter { $0.variantOf != nil }, by: { $0.variantOf ?? "" })
            .mapValues { $0.map(\.id) }
        // Within a topic: revisits first, then official papers, mocks, other admissions tests and
        // competitions. Inside each of those tiers, publishers take turns (each easiest first), so a
        // worksheet is not drawn from one topic bank and its easiest questions alone.
        func queue(_ topicEntries: [TMUACatalogueEntry]) -> [TMUACatalogueEntry] {
            let tiers = Dictionary(grouping: topicEntries) { (revisits.contains($0.id) ? 0 : 1) * 10 + rank($0) }
            return tiers.keys.sorted().flatMap { tier -> [TMUACatalogueEntry] in
                let byProvider = Dictionary(grouping: tiers[tier] ?? [], by: { $0.provider?.key ?? "" })
                    .mapValues { $0.sorted { ($0.difficulty ?? 3, $0.id) < ($1.difficulty ?? 3, $1.id) } }
                let lists = byProvider.keys.sorted().compactMap { byProvider[$0] }
                return (0..<(lists.map(\.count).max() ?? 0)).flatMap { index in lists.compactMap { index < $0.count ? $0[index] : nil } }
            }
        }
        let byTopic = Dictionary(grouping: usable, by: { $0.topicKey ?? "" }).mapValues(queue)
        let level = Dictionary(usable.map { ($0.id, $0.difficulty ?? 3) }, uniquingKeysWith: { first, _ in first })
        var queues = byTopic.mapValues { $0[...] }
        var result: [(String, [String])] = []
        var progressed = true
        // Round-robin over topics in priority order: one worksheet per topic per round, two for a weak topic.
        while progressed {
            progressed = false
            for topic in topicOrder.flatMap({ weakTopics.contains($0) ? [$0, $0] : [$0] }) {
                var picked: [String] = []
                while picked.count < size, let entry = queues[topic]?.popFirst() {
                    if used.contains(entry.id) || entry.variantOf.map(practised.contains) == true
                        || adaptations[entry.id]?.contains(where: practised.contains) == true { continue }
                    picked.append(entry.id)
                    used.insert(entry.id)
                    practised.insert(entry.id)
                }
                if picked.count >= max(2, size / 2) {
                    // Easier questions first within the worksheet, then harder ones.
                    let ramp = picked.enumerated().sorted { (level[$0.element] ?? 3, $0.offset) < (level[$1.element] ?? 3, $1.offset) }
                    result.append((topic, ramp.map(\.element)))
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

    /// Topics the diagnostic assessed as weak (clear difficulty or possible improvement): verified
    /// evidence only, so self-marked results never add worksheets to a topic.
    nonisolated static func worksheetWeakTopics(report: TMUADiagnosticReport?, syllabus: TMUASyllabus) -> Set<String> {
        let weak = Set((report?.topics ?? []).filter { $0.level == .strongDifficulty || $0.level == .possibleImprovement }.map(\.name))
        return Set(syllabus.topics.filter { weak.contains($0.title) }.map(\.key))
    }

    /// R5: a planning estimate for one self-marked worksheet question, including marking it against
    /// the solution: 5 minutes at levels 1–2, 6 at level 3 or unknown, 8 at level 4 and 10 at level 5.
    /// The TMUA allows 75 minutes for 20 questions (3¾ each); these leave time to mark. They are
    /// conservative estimates, not measured timings, and levels are themselves estimates.
    nonisolated static func worksheetQuestionMinutes(difficulty: Int?) -> Int {
        switch difficulty {
        case let level? where level <= 2: 5
        case 4?: 8
        case let level? where level >= 5: 10
        default: 6
        }
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

    /// A library session's length on an empty study day: the day's share of the week, capped by the
    /// session length the student set and by the 75 minutes of a full paper. Never more than the day holds.
    nonisolated static func resourceSessionMinutes(weeklyMinutes: Int, availability: [DayAvailability],
                                                   sessionCap: Int? = nil) -> Int {
        let days = max(1, availability.filter(\.isAvailable).count)
        return min(75, weeklyMinutes / days, sessionCap ?? .max)
    }

    nonisolated static func resourceReason(_ source: TMUAResourceSource, minutes: Int) -> String {
        let scope = minutes >= 75 ? "Sit the paper in 75 minutes" : "Work through as much of the paper as fits in \(minutes) minutes"
        let access = source.access == .studyCopy ? "from your library" : "on \(source.provider.name)’s website"
        return "\(scope) \(access), then mark it with its solutions. New Revisr questions do not fill this day; your result is recorded for progress, not as evidence of topic mastery."
    }

    static func scheduleResourceSessions(programme: PublicProgramme, settings: AppSettings,
                                         content: TMUAContentContext, today: Date, calendar: Calendar,
                                         report: TMUADiagnosticReport? = nil, catalogue: TMUAQuestionCatalogue? = nil,
                                         reserved: Set<String> = [], in context: ModelContext) throws {
        let catalogue = catalogue ?? TMUACatalogueStore.catalogue(content)
        let sources = catalogue.sources
        let all = try PublicProgrammeService.tasks(for: programme, in: context)
        let profile = settings.id
        let logs = try context.fetch(FetchDescriptor<TMUAResourceLog>(predicate: #Predicate { $0.profileSettingsID == profile }))
        let resourceTasks = all.filter { $0.stableID.contains(resourceTaskMarker) }
        // R5: a worksheet with recorded results is the student's work in progress. A refresh keeps it,
        // with its questions and on its day, rather than retiring it or reusing its day for other work.
        let started = startedWorksheetTaskIDs(logs)
        for task in resourceTasks where task.completedAt == nil && !task.isActive && started.contains(task.stableID) {
            task.isActive = true
        }
        var completed = Set(logs.filter { $0.questionID == nil }.map(\.sourceID))
        completed.formUnion(resourceTasks.filter { $0.completedAt != nil }.map(\.sourceID))
        // Sessions inside the frozen window stay as they are; their papers are not offered twice.
        let kept = resourceTasks.filter { $0.isActive && $0.completedAt == nil }
        // A paper holding a question from an open diagnostic round is never set whole, so the paper
        // cannot show that question before it is answered.
        let papers = resourceCandidates(sources, completed: completed.union(kept.map(\.sourceID)))
            .filter { paper in !paper.questions.contains { $0.autoMarkedItemID.map(reserved.contains) == true } }
        let minutes = resourceSessionMinutes(weeklyMinutes: programme.weeklyMinutesSnapshot,
                                             availability: settings.publicAvailability, sessionCap: settings.publicSessionMinutes)
        // Questions already recorded or in another worksheet are not offered again. A paper the plan
        // sets whole keeps its questions for that session, and a paper with a question in a worksheet
        // is not then set whole; papers merely eligible for a session reserve nothing.
        let sheetTasks = resourceTasks.filter { ($0.isActive || $0.completedAt != nil) && $0.activity == .topicWorksheet }
        let worksheetQuestions = sheetTasks.flatMap { worksheetQuestionIDs($0.sourceID) }
        let revisits = worksheetRevisits(logs: logs, worksheets: sheetTasks.map {
            (questions: worksheetQuestionIDs($0.sourceID), date: $0.scheduledDate, active: $0.completedAt == nil)
        }, today: today, calendar: calendar)
        let weak = worksheetWeakTopics(report: report, syllabus: content.syllabus)
        let worksheets = worksheetCandidates(
            catalogue.entries, topicOrder: worksheetTopicOrder(report: report, syllabus: content.syllabus),
            excluded: Set(logs.compactMap(\.questionID) + worksheetQuestions),
            excludedSources: completed.union(kept.map(\.sourceID)),
            size: 8, weakTopics: weak, revisits: revisits)
        var paperQueue = papers[...]
        var sheetQueue = worksheets[...]
        var wholePapers = Set<String>()
        var worksheetPapers = Set(worksheetQuestions.compactMap { catalogue.entry($0)?.sourceID })
        typealias Session = (sourceID: String, topic: String, activity: PublicPlanningActivity, reason: String, minutes: Int)
        // A worksheet takes its next questions while their estimated time fits the room, up to eight.
        // A sheet too long for a short room waits for a later day rather than being cut to one question.
        let sessionMinutes = minutes
        func worksheet(minutes: Int) -> Session? {
            while let sheet = sheetQueue.first {
                var questions: [String] = []
                var total = 0
                for id in sheet.questions where !wholePapers.contains(catalogue.entry(id)?.sourceID ?? "") {
                    let cost = worksheetQuestionMinutes(difficulty: catalogue.entry(id)?.difficulty)
                    guard questions.count < 8, total + cost <= minutes else { break }
                    questions.append(id)
                    total += cost
                }
                let available = sheet.questions.filter { !wholePapers.contains(catalogue.entry($0)?.sourceID ?? "") }.count
                // Too long for this room: wait for a longer one, unless even a full session is too short.
                if questions.count < 2 && available >= 2 && minutes < sessionMinutes { return nil }
                sheetQueue.removeFirst()
                guard questions.count >= 2 else { continue }
                worksheetPapers.formUnion(questions.compactMap { catalogue.entry($0)?.sourceID })
                let title = content.syllabus.topicTitle(sheet.topic)
                return (worksheetSourceID(topic: sheet.topic, questions: questions), title, .topicWorksheet,
                        worksheetReason(topic: title, count: questions.count, revisits: questions.filter(revisits.contains).count,
                                        weak: weak.contains(sheet.topic)), total)
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
        // A day too short for any library session (under 15 minutes) gets none.
        while date < examDay, minutes >= 15, !paperQueue.isEmpty || !sheetQueue.isEmpty {
            defer { date = PublicPlanningEngine.nextDay(after: date, calendar: calendar, limit: examDay) }
            guard PublicProgrammeAvailability.isAvailable(on: date, schedule: settings.publicAvailability,
                                                          calendar: calendar) == true,
                  !sessionDays.contains(date) else { continue }
            let id = "\(programme.stableID)\(resourceTaskMarker)\(Self.dayKey(date, calendar: calendar))"
            // A completed, kept or started session is never rewritten, whatever happened to its date.
            if let existing = byID[id], existing.completedAt != nil || existing.isActive { continue }
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

    /// Questions the student marked incorrect or partly right at least a week ago that have not come
    /// back since their first such result and are not planned now: each may come back once. Self-marked
    /// results only decide which questions return; they never change topic priorities.
    static func worksheetRevisits(logs: [TMUAResourceLog], worksheets: [(questions: [String], date: Date, active: Bool)],
                                  today: Date, calendar: Calendar) -> Set<String> {
        let active = Set(worksheets.filter(\.active).flatMap(\.questions))
        let byQuestion = Dictionary(grouping: logs.filter { $0.questionID != nil }, by: { $0.questionID ?? "" })
        return Set(byQuestion.compactMap { id, rows -> String? in
            guard let latest = rows.max(by: TMUAResourceLog.isEarlier),
                  latest.outcome == .incorrect || latest.outcome == .partial, !active.contains(id),
                  let firstMiss = rows.filter({ $0.outcome == .incorrect || $0.outcome == .partial })
                    .min(by: TMUAResourceLog.isEarlier),
                  (calendar.dateComponents([.day], from: calendar.startOfDay(for: latest.recordedAt),
                                           to: calendar.startOfDay(for: today)).day ?? 0) >= 7 else { return nil }
            // A return is a worksheet holding the question on a later day than its first miss.
            let missDay = calendar.startOfDay(for: firstMiss.recordedAt)
            let returns = worksheets.filter { $0.questions.contains(id) && calendar.startOfDay(for: $0.date) > missDay }
            return returns.isEmpty ? id : nil
        })
    }

    nonisolated static func worksheetReason(topic: String, count: Int, revisits: Int = 0, weak: Bool = false) -> String {
        var text = "\(count) questions on \(topic.lowercased()) from papers in your library, which Revisr cannot mark."
        if weak { text += " Your diagnostic showed this topic needs more practice, so it gets extra worksheets." }
        if revisits > 0 {
            text += " \(revisits == 1 ? "One question" : "\(revisits) questions") you marked incorrect or partly right before \(revisits == 1 ? "comes" : "come") back once."
        }
        return text + " Open each at its page, mark it against the publisher’s solution and record how it went. Your results decide which questions come back for review; they never count as evidence of topic mastery."
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
