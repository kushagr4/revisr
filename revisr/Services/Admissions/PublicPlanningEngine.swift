import Foundation

/// A value-only planning snapshot. SwiftData and PDF resolution happen before
/// this point so identical inputs always produce identical dated assignments.
struct PublicPlanningInput {
    let exam: PublicExamKind
    let startDate: Date
    let examDate: Date
    let weeklyMinutes: Int
    let availability: [DayAvailability]
    let diagnosticSignals: [DiagnosticTopicResult]
    let questions: [PublicPlanningQuestion]
    let papers: [PublicPlanningPaper]
    let calendar: Calendar
    /// Defaults reproduce the original planner exactly (and its TypeScript
    /// parity fixtures). The flexible TMUA programme opts into the extras.
    var options: PublicPlanningOptions = .legacy
}

struct PublicPlanningOptions: Equatable {
    /// Upper bound on minutes planned for any one study day.
    var dailyMinutesCap: Int?
    /// Spread unseen questions across the remaining window instead of
    /// front-loading them, so later weeks are not left empty.
    var paceFreshQuestions = false
    /// Allows re-scheduling a question already attempted or planned earlier,
    /// as spaced review. The required gap grows with each repeat (interval,
    /// then twice the interval, ...).
    var spacedReviewIntervalDays: Int?
    var maximumSpacedRepeats = 2
    /// Schedules one optional task inviting the student to answer more
    /// diagnostic questions, with this many minutes.
    var diagnosticRefinementMinutes: Int?
    var diagnosticRefinementSourceID = "diagnostic-expansion"
    /// Questions per task for this programme; nil keeps the exam default.
    var questionMinutes: Int?
    /// When the preferred topic has nothing suitable, take the fallback from
    /// the least-practised high-priority topic rather than always the top
    /// one, so a small bank does not concentrate a short plan on one topic.
    var balanceFallbackTopics = false
    /// While unseen questions remain, pacing never leaves a study day empty:
    /// one unseen question may be introduced early instead.
    var minimumOneTaskPerStudyDay = false

    static let legacy = PublicPlanningOptions()
}

struct PublicPlanningQuestion: Equatable {
    let id: String
    let sourceID: String
    let topic: String
    let difficulty: Int
    let diagnostic: Bool
    let latestOutcome: QuestionAttemptOutcome?
    let latestAttemptDate: Date?
    let reviewFlag: Bool
    let hasSolution: Bool
}

struct PublicPlanningPaper: Equatable {
    let sourceID: String
    let questionIDs: [String]
    let durationMinutes: Int
}

enum PublicPlanningActivity: String, CaseIterable {
    case targeted
    case consolidation
    case errorReview
    case mixed
    case timed
    case fullPaper
    case finalReview
    case spacedReview
    case diagnosticRefinement
    /// A self-marked paper from the library, scheduled only on days the question bank cannot fill.
    case resourcePractice

    var title: String {
        switch self {
        case .targeted: "Targeted practice"
        case .consolidation: "Consolidation"
        case .errorReview: "Error review"
        case .mixed: "Mixed practice"
        case .timed: "Timed practice"
        case .fullPaper: "Full paper"
        case .finalReview: "Final review"
        case .spacedReview: "Spaced review"
        case .diagnosticRefinement: "Refine your diagnostic"
        case .resourcePractice: "Paper practice (self-marked)"
        }
    }
}

struct PublicPlannedTask: Equatable {
    let date: Date
    let questionID: String?
    let sourceID: String
    let topic: String
    let minutes: Int
    let activity: PublicPlanningActivity
    let reason: String
}

struct PublicTopicPriority: Equatable {
    let topic: String
    let rank: Int
    let reason: String
}

struct PublicPlanningResult {
    let tasks: [PublicPlannedTask]
    let priorities: [PublicTopicPriority]
    let availableDays: Int
    let unfilledDays: Int
}

enum PublicPlanningError: LocalizedError, Equatable {
    case examDatePassed
    case noAvailableDays
    case insufficientDailyCapacity
    case noEligibleQuestions

    var errorDescription: String? {
        switch self {
        case .examDatePassed: "Choose a future examination date before generating a programme."
        case .noAvailableDays: "Make at least one weekday available for study."
        case .insufficientDailyCapacity: "The weekly target is too short for a useful session on any available day. Increase it in preparation settings."
        case .noEligibleQuestions: "No suitable unprotected questions are available for this examination. Your diagnostics are saved; review the local content."
        }
    }
}

enum PublicPlanningPolicy {
    // Conservative planning caps, not claims about official expected solution time.
    static func questionMinutes(for exam: PublicExamKind) -> Int {
        switch exam {
        case .tmua: 15
        case .smc: 12
        case .bmo: 45
        }
    }

    static func paperMinutes(for exam: PublicExamKind) -> Int {
        DiagnosticPaperPolicy.forExam(exam).durationMinutes
    }

    static func paperQuestionCount(for exam: PublicExamKind) -> Int {
        DiagnosticPaperPolicy.forExam(exam).questionCount
    }
}

enum PublicPlanningEngine {
    static func generate(_ input: PublicPlanningInput) throws -> PublicPlanningResult {
        let calendar = input.calendar
        let start = calendar.startOfDay(for: input.startDate)
        let examDay = calendar.startOfDay(for: input.examDate)
        guard start < examDay else { throw PublicPlanningError.examDatePassed }
        let available = input.availability.filter(\.isAvailable)
        guard !available.isEmpty else { throw PublicPlanningError.noAvailableDays }
        let options = input.options
        let minutes = options.questionMinutes ?? PublicPlanningPolicy.questionMinutes(for: input.exam)
        guard input.weeklyMinutes / available.count >= minutes,
              (options.dailyMinutesCap ?? minutes) >= minutes else {
            throw PublicPlanningError.insufficientDailyCapacity
        }
        guard !input.questions.isEmpty else { throw PublicPlanningError.noEligibleQuestions }

        let signals = Dictionary(uniqueKeysWithValues: input.diagnosticSignals.map { ($0.name, $0) })
        let groups = Dictionary(grouping: input.questions, by: \.topic)
        var priorities: [PublicTopicPriority] = []
        for topic in groups.keys {
            let signal = signals[topic]
            let recent = groups[topic, default: []].filter { question in
                guard let date = question.latestAttemptDate else { return false }
                guard let days = calendar.dateComponents([.day], from: date, to: start).day else { return false }
                return (0...21).contains(days)
            }
            let misses = recent.filter { $0.latestOutcome == .incorrect || $0.latestOutcome == .partial }.count
            let successes = recent.filter { $0.latestOutcome == .correct }.count
            let evidenceRank: Int
            let reason: String
            switch signal?.level {
            case .strongDifficulty?:
                evidenceRank = 40
                reason = "Several assessed diagnostic questions in \(topic) were missed across both papers."
            case .possibleImprovement?:
                evidenceRank = 30
                reason = "Your diagnostic suggests \(topic) may need more practice."
            case .relativeStrength?:
                evidenceRank = 10
                reason = "Your diagnostic showed relative strength in \(topic); occasional practice will maintain it."
            case .insufficient?, nil:
                evidenceRank = 20
                reason = "\(topic) had too little assessed diagnostic evidence, so this is exploratory practice."
            }
            let recentRank = min(8, misses * 3) - min(4, successes * 2)
            let combinedRank = evidenceRank + recentRank
            priorities.append(PublicTopicPriority(topic: topic, rank: combinedRank, reason: reason))
        }
        priorities.sort { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.topic < rhs.topic : lhs.rank > rhs.rank
        }

        let questionByID = Dictionary(uniqueKeysWithValues: input.questions.map { ($0.id, $0) })
        let questionOrder: (PublicPlanningQuestion, PublicPlanningQuestion) -> Bool = { lhs, rhs in
            if lhs.difficulty != rhs.difficulty { return lhs.difficulty < rhs.difficulty }
            return lhs.id < rhs.id
        }
        var used = Set<String>()
        var usedPapers = Set<String>()
        var topicCounts: [String: Int] = [:]
        var tasks: [PublicPlannedTask] = []
        var availableDays = 0
        var unfilledDays = 0
        var lastPlanned: [String: Date] = [:]
        var spacedRepeats: [String: Int] = [:]
        var refinementPlaced = options.diagnosticRefinementMinutes == nil
        let freshTotal = input.questions.filter { !$0.diagnostic && $0.latestOutcome == nil }.count
        var freshPlacedTotal = 0
        var studyDayIndex = 0
        var totalStudyDays = 0
        var cursor = start
        while cursor < examDay {
            if let weekday = Weekday(rawValue: calendar.component(.weekday, from: cursor)),
               available.contains(where: { $0.weekday == weekday }) { totalStudyDays += 1 }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? examDay
        }
        var date = start
        while date < examDay {
            defer { date = calendar.date(byAdding: .day, value: 1, to: date) ?? examDay }
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)),
                  let day = available.first(where: { $0.weekday == weekday }) else { continue }
            availableDays += 1
            let orderedWeekdays = Weekday.displayOrder.filter { value in
                available.contains(where: { $0.weekday == value })
            }
            let dailyIndex = orderedWeekdays.firstIndex(of: weekday) ?? 0
            let baseCapacity = input.weeklyMinutes / available.count
                + (dailyIndex < input.weeklyMinutes % available.count ? 1 : 0)
            let capacity = options.dailyMinutesCap.map { min($0, baseCapacity) } ?? baseCapacity
            let daysRemaining = calendar.dateComponents([.day], from: date, to: examDay).day ?? 0
            let finalWindow = daysRemaining <= 3
            let usableCapacity = finalWindow ? max(minutes, capacity / 2) : capacity
            var remaining = min(capacity, usableCapacity)
            var placed = 0
            // Cumulative pacing: by each study day, roughly that share of the
            // window's unseen questions has been introduced.
            let freshTarget = Int((Double(freshTotal) * Double(studyDayIndex + 1)
                / Double(max(1, totalStudyDays))).rounded(.up))
            let freshAllowance = options.paceFreshQuestions ? max(0, freshTarget - freshPlacedTotal) : Int.max
            var freshPlacedToday = 0
            studyDayIndex += 1

            if !refinementPlaced, !finalWindow, availableDays >= 3,
               let refinement = options.diagnosticRefinementMinutes, refinement <= remaining {
                tasks.append(PublicPlannedTask(date: date, questionID: nil, sourceID: options.diagnosticRefinementSourceID,
                    topic: "Diagnostic", minutes: refinement, activity: .diagnosticRefinement,
                    reason: "Optional: answer more diagnostic questions to sharpen your topic priorities."))
                refinementPlaced = true
                remaining -= refinement
                placed += 1
            }

            // Full papers are optional and only use a complete, unattempted,
            // non-diagnostic source that fits within this day's actual budget.
            if availableDays % 10 == 0 && !finalWindow {
                let paper = input.papers.sorted { $0.sourceID < $1.sourceID }.first { paper in
                    !usedPapers.contains(paper.sourceID)
                        && paper.durationMinutes <= remaining
                        && paper.questionIDs.count == PublicPlanningPolicy.paperQuestionCount(for: input.exam)
                        && paper.questionIDs.allSatisfy { id in
                            questionByID[id] != nil && !used.contains(id)
                                && questionByID[id]?.latestOutcome == nil
                                && questionByID[id]?.diagnostic == false
                        }
                }
                if let paper {
                    tasks.append(PublicPlannedTask(date: date, questionID: nil, sourceID: paper.sourceID,
                        topic: "Mixed topics", minutes: paper.durationMinutes, activity: .fullPaper,
                        reason: "A complete unused \(input.exam.title) paper fits your available time today."))
                    usedPapers.insert(paper.sourceID)
                    used.formUnion(paper.questionIDs)
                    remaining -= paper.durationMinutes
                    placed += 1
                }
            }

            while remaining >= minutes && placed < 6 {
                let slot = placed
                let ranked = priorities.sorted { lhs, rhs in
                    let left = lhs.rank * (topicCounts[rhs.topic, default: 0] + 1)
                    let right = rhs.rank * (topicCounts[lhs.topic, default: 0] + 1)
                    return left == right ? lhs.topic < rhs.topic : left > right
                }
                let previousTopic = tasks.last(where: { calendar.isDate($0.date, inSameDayAs: date) })?.topic
                let preferred = slot == 1
                    ? (ranked.first(where: { $0.topic != previousTopic }) ?? ranked[0])
                    : ranked[0]
                let activity: PublicPlanningActivity = finalWindow ? .finalReview
                    : slot == 0 ? .targeted
                    : slot == 1 && availableDays % 3 == 0 ? .timed
                    : slot == 1 ? .mixed : .consolidation
                let reviewPool = input.questions.filter { question in
                    guard !used.contains(question.id), question.topic == preferred.topic else { return false }
                    let failed = question.latestOutcome == .incorrect || question.latestOutcome == .partial
                    guard failed || question.reviewFlag else { return false }
                    guard let last = question.latestAttemptDate else { return true }
                    return (calendar.dateComponents([.day], from: last, to: date).day ?? 0) >= 3
                }.sorted(by: questionOrder)
                let freshPool = input.questions.filter {
                    !used.contains($0.id) && !$0.diagnostic && $0.latestOutcome == nil
                        && $0.topic == preferred.topic
                }.sorted(by: questionOrder)
                let fallbackOrder = options.balanceFallbackTopics ? ranked : priorities
                let anyFresh = input.questions.filter {
                    !used.contains($0.id) && !$0.diagnostic && $0.latestOutcome == nil
                }.sorted { lhs, rhs in
                    let left = fallbackOrder.firstIndex(where: { $0.topic == lhs.topic }) ?? 0
                    let right = fallbackOrder.firstIndex(where: { $0.topic == rhs.topic }) ?? 0
                    if left != right { return left < right }
                    return questionOrder(lhs, rhs)
                }
                let preferredReview = slot == 0 ? reviewPool.first : nil
                let freshAllowed = freshPlacedToday < freshAllowance
                var selectedQuestion = preferredReview ?? (freshAllowed ? freshPool.first : nil)
                    ?? reviewPool.first ?? (freshAllowed ? anyFresh.first : nil)
                var isSpaced = false
                if selectedQuestion == nil, let interval = options.spacedReviewIntervalDays {
                    let placedToday = Set(tasks.filter { calendar.isDate($0.date, inSameDayAs: date) }
                        .compactMap(\.questionID))
                    let spaced = input.questions.filter { question in
                        guard !placedToday.contains(question.id),
                              spacedRepeats[question.id, default: 0] < options.maximumSpacedRepeats,
                              let last = lastPlanned[question.id] ?? question.latestAttemptDate,
                              let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: date).day
                        else { return false }
                        return gap >= interval * (spacedRepeats[question.id, default: 0] + 1)
                    }.sorted { lhs, rhs in
                        let leftMissed = lhs.latestOutcome == .incorrect || lhs.latestOutcome == .partial || lhs.reviewFlag
                        let rightMissed = rhs.latestOutcome == .incorrect || rhs.latestOutcome == .partial || rhs.reviewFlag
                        if leftMissed != rightMissed { return leftMissed }
                        let left = priorities.firstIndex(where: { $0.topic == lhs.topic }) ?? 0
                        let right = priorities.firstIndex(where: { $0.topic == rhs.topic }) ?? 0
                        if left != right { return left < right }
                        let leftDate = lastPlanned[lhs.id] ?? lhs.latestAttemptDate ?? start
                        let rightDate = lastPlanned[rhs.id] ?? rhs.latestAttemptDate ?? start
                        if leftDate != rightDate { return leftDate < rightDate }
                        return lhs.id < rhs.id
                    }
                    selectedQuestion = spaced.first
                    // Nothing is due for review: borrow up to a week ahead of
                    // the fresh-question pace rather than leave time unused.
                    if selectedQuestion == nil, options.paceFreshQuestions {
                        let ahead = Int((Double(freshTotal) * Double(min(totalStudyDays, studyDayIndex + 6))
                            / Double(max(1, totalStudyDays))).rounded(.up))
                        if freshPlacedTotal < ahead { selectedQuestion = freshPool.first ?? anyFresh.first }
                    }
                    if selectedQuestion == nil, placed == 0, options.minimumOneTaskPerStudyDay {
                        selectedQuestion = freshPool.first ?? anyFresh.first
                    }
                    // A missed or flagged question meeting its first revisit
                    // in this plan is error review; later revisits are spaced.
                    if let pick = selectedQuestion,
                       pick.latestOutcome != nil || pick.diagnostic || pick.reviewFlag || lastPlanned[pick.id] != nil {
                        let missed = pick.latestOutcome == .incorrect || pick.latestOutcome == .partial || pick.reviewFlag
                        isSpaced = !(missed && lastPlanned[pick.id] == nil && !used.contains(pick.id))
                    }
                }
                guard let selected = selectedQuestion else { break }
                let isReview = selected.latestOutcome != nil || selected.diagnostic || selected.reviewFlag
                let effectiveActivity: PublicPlanningActivity = isSpaced ? .spacedReview
                    : isReview ? .errorReview : activity
                let reason: String
                if isSpaced {
                    reason = "Return to this \(selected.topic) question after a gap to strengthen recall."
                } else if isReview {
                    reason = "Revisit \(selected.topic) after an earlier result or review flag."
                } else if activity == .mixed {
                    reason = "Practise \(selected.topic) alongside other topics to build flexibility."
                } else if activity == .timed {
                    reason = "Try a timed \(selected.topic) question within today's study budget."
                } else if activity == .finalReview {
                    reason = "Light \(selected.topic) practice before the examination."
                } else {
                    reason = priorities.first(where: { $0.topic == selected.topic })?.reason ?? preferred.reason
                }
                tasks.append(PublicPlannedTask(date: date, questionID: selected.id,
                    sourceID: selected.sourceID, topic: selected.topic, minutes: minutes,
                    activity: effectiveActivity, reason: reason))
                if isSpaced {
                    spacedRepeats[selected.id, default: 0] += 1
                } else {
                    if !isReview && !used.contains(selected.id) {
                        freshPlacedToday += 1
                        freshPlacedTotal += 1
                    }
                    used.insert(selected.id)
                }
                lastPlanned[selected.id] = date
                topicCounts[selected.topic, default: 0] += 1
                remaining -= minutes
                placed += 1
            }
            if placed == 0 { unfilledDays += 1 }
            _ = day.startMinute // Availability timing is retained for the UI; no invented time of day.
        }
        guard !tasks.isEmpty else { throw PublicPlanningError.noEligibleQuestions }
        return PublicPlanningResult(tasks: tasks, priorities: priorities,
            availableDays: availableDays, unfilledDays: unfilledDays)
    }
}
