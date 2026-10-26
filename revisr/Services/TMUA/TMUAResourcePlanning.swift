import Foundation
import SwiftData

/// Self-marked paper sessions for study days that Revisr's question bank cannot fill. They come
/// from the unified library (bundled personal study copies in internal builds, papers on the
/// provider's own site otherwise), never add question-level evidence, and are rebuilt with the
/// plan on every refresh. Days the bank can fill are never displaced.
extension TMUAProgrammeService {
    static let resourceTaskMarker = "-resource-"

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
                                         in context: ModelContext) throws {
        let sources = TMUAResourceCatalogue.sources(distribution: content.distribution, items: content.eligibleItems)
        let all = try PublicProgrammeService.tasks(for: programme, in: context)
        let profile = settings.id
        let logs = try context.fetch(FetchDescriptor<TMUAResourceLog>(predicate: #Predicate { $0.profileSettingsID == profile }))
        let resourceTasks = all.filter { $0.stableID.contains(resourceTaskMarker) }
        var completed = Set(logs.filter { $0.questionID == nil }.map(\.sourceID))
        completed.formUnion(resourceTasks.filter { $0.completedAt != nil }.map(\.sourceID))
        // Sessions inside the frozen window stay as they are; their papers are not offered twice.
        let kept = resourceTasks.filter { $0.isActive && $0.completedAt == nil }
        var queue = resourceCandidates(sources, completed: completed.union(kept.map(\.sourceID)))[...]
        let byID = Dictionary(resourceTasks.map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
        let busy = Set(all.filter { $0.isActive || $0.completedAt != nil }.map { calendar.startOfDay(for: $0.scheduledDate) })
        let minutes = resourceSessionMinutes(weeklyMinutes: programme.weeklyMinutesSnapshot,
                                             availability: settings.publicAvailability)
        let examDay = calendar.startOfDay(for: programme.examDateSnapshot)
        var date = calendar.startOfDay(for: today)
        while date < examDay, !queue.isEmpty {
            defer { date = calendar.date(byAdding: .day, value: 1, to: date) ?? examDay }
            guard PublicProgrammeAvailability.isAvailable(on: date, schedule: settings.publicAvailability,
                                                          calendar: calendar) == true,
                  !busy.contains(date), let source = queue.popFirst() else { continue }
            let id = "\(programme.stableID)\(resourceTaskMarker)\(Self.dayKey(date, calendar: calendar))"
            let planned = PublicPlannedTask(date: date, questionID: nil, sourceID: source.id, topic: "Mixed practice",
                                            minutes: minutes, activity: .resourcePractice,
                                            reason: resourceReason(source, minutes: minutes))
            if let existing = byID[id] {
                existing.isActive = true
                existing.scheduledDate = date
                existing.sourceID = source.id
                existing.allocatedMinutes = minutes
                existing.reason = planned.reason
            } else {
                context.insert(PublicProgrammeTask(stableID: id, programmeID: programme.stableID, task: planned))
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Completes a resource session with the student's own result.
    static func completeResourceSession(_ task: PublicProgrammeTask, outcome: TMUAResourceOutcome, correct: Int?,
                                        questionCount: Int?, minutes: Int?, settings: AppSettings,
                                        at date: Date = .now, in context: ModelContext) throws {
        guard task.activity == .resourcePractice else { throw TMUAProgrammeError.invalidTask }
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
