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

    var title: String {
        switch self {
        case .targeted: "Targeted practice"
        case .consolidation: "Consolidation"
        case .errorReview: "Error review"
        case .mixed: "Mixed practice"
        case .timed: "Timed practice"
        case .fullPaper: "Full paper"
        case .finalReview: "Final review"
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
        let minutes = PublicPlanningPolicy.questionMinutes(for: input.exam)
        guard input.weeklyMinutes / available.count >= minutes else {
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
            let capacity = input.weeklyMinutes / available.count
                + (dailyIndex < input.weeklyMinutes % available.count ? 1 : 0)
            let daysRemaining = calendar.dateComponents([.day], from: date, to: examDay).day ?? 0
            let finalWindow = daysRemaining <= 3
            let usableCapacity = finalWindow ? max(minutes, capacity / 2) : capacity
            var remaining = min(capacity, usableCapacity)
            var placed = 0

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
                let anyFresh = input.questions.filter {
                    !used.contains($0.id) && !$0.diagnostic && $0.latestOutcome == nil
                }.sorted { lhs, rhs in
                    let left = priorities.firstIndex(where: { $0.topic == lhs.topic }) ?? 0
                    let right = priorities.firstIndex(where: { $0.topic == rhs.topic }) ?? 0
                    if left != right { return left < right }
                    return questionOrder(lhs, rhs)
                }
                let preferredReview = slot == 0 ? reviewPool.first : nil
                let selectedQuestion = preferredReview ?? freshPool.first
                    ?? reviewPool.first ?? anyFresh.first
                guard let selected = selectedQuestion else { break }
                let isReview = selected.latestOutcome != nil || selected.diagnostic || selected.reviewFlag
                let effectiveActivity: PublicPlanningActivity = isReview ? .errorReview : activity
                let reason: String
                if isReview {
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
                used.insert(selected.id)
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
