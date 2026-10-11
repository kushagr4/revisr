import Foundation

enum DiagnosticPaperMarking: Equatable {
    case correct
    case incorrect
    case unassessed
}

struct DiagnosticPaperRecord {
    let stableID: String
    let ordinal: Int
    let sourceID: String
    let accumulatedSeconds: Double
}

struct DiagnosticResponse {
    let paperID: String
    let questionID: String
    let wasAttempted: Bool
    let selectedOption: String?
    let selfEstimatedMarks: Int?
    let marking: DiagnosticPaperMarking
}

struct AdmissionsQuestion {
    let externalQuestionID: String
    let primaryTopic: String?
    let reasoningSkill: String?
    let difficulty: Int
}

struct DiagnosticPaperPolicy {
    let questionCount: Int
    let durationMinutes: Int

    static func forExam(_ exam: PublicExamKind) -> DiagnosticPaperPolicy {
        switch exam {
        case .tmua: DiagnosticPaperPolicy(questionCount: 20, durationMinutes: 75)
        case .smc: DiagnosticPaperPolicy(questionCount: 25, durationMinutes: 90)
        case .bmo: DiagnosticPaperPolicy(questionCount: 6, durationMinutes: 210)
        }
    }
}

@main
struct ProductionEngineSmoke {
    static func main() throws {
        try testAvailabilityAndPlanner()
        testDiagnosticAnalysis()
        try testPlanningBoundariesAndEligibility()
        testLowDiagnosticEvidence()
    }

    static func testAvailabilityAndPlanner() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }

        let schedule = [
            DayAvailability(weekday: .monday, isAvailable: true),
            DayAvailability(weekday: .wednesday, isAvailable: true)
        ]
        precondition(PublicProgrammeAvailability.isAvailable(on: date(2026, 10, 12), schedule: schedule, calendar: calendar) == true)
        precondition(PublicProgrammeAvailability.isAvailable(on: date(2026, 10, 13), schedule: schedule, calendar: calendar) == nil)
        precondition(PublicProgrammeAvailability.isAvailable(on: date(2026, 10, 14), schedule: schedule, calendar: calendar) == true)
        let restSchedule = [DayAvailability(weekday: .sunday, isAvailable: false)]
        precondition(PublicProgrammeAvailability.isAvailable(on: date(2026, 10, 18), schedule: restSchedule, calendar: calendar) == false)

        let questions = [
            PublicPlanningQuestion(id: "A-1", sourceID: "SRC-A", topic: "Algebra", difficulty: 2,
                diagnostic: false, latestOutcome: nil, latestAttemptDate: nil, reviewFlag: false, hasSolution: true),
            PublicPlanningQuestion(id: "G-1", sourceID: "SRC-G", topic: "Geometry", difficulty: 2,
                diagnostic: false, latestOutcome: nil, latestAttemptDate: nil, reviewFlag: false, hasSolution: true),
            PublicPlanningQuestion(id: "G-2", sourceID: "SRC-G", topic: "Geometry", difficulty: 3,
                diagnostic: false, latestOutcome: nil, latestAttemptDate: nil, reviewFlag: false, hasSolution: true)
        ]
        let signals = [
            DiagnosticTopicResult(name: "Geometry", assessedCount: 5, unansweredCount: 0,
                unassessedCount: 0, level: .strongDifficulty, explanation: "Fixture input"),
            DiagnosticTopicResult(name: "Algebra", assessedCount: 1, unansweredCount: 0,
                unassessedCount: 0, level: .insufficient, explanation: "Fixture input")
        ]
        let input = PublicPlanningInput(exam: .tmua, startDate: date(2026, 10, 12),
            examDate: date(2026, 10, 15), weeklyMinutes: 30, availability: schedule,
            diagnosticSignals: signals, questions: questions, papers: [], calendar: calendar)
        let result = try PublicPlanningEngine.generate(input)
        let repeatedResult = try PublicPlanningEngine.generate(input)

        precondition(result.tasks == repeatedResult.tasks)
        precondition(result.priorities == repeatedResult.priorities)
        precondition(result.priorities.map(\.topic) == ["Geometry", "Algebra"])
        precondition(result.tasks.map(\.topic) == ["Geometry", "Algebra"])
        precondition(result.tasks.map(\.questionID) == ["G-1", "A-1"])
        precondition(result.tasks.map(\.sourceID) == ["SRC-G", "SRC-A"])
        let taskDates = result.tasks.map {
            [calendar.component(.year, from: $0.date), calendar.component(.month, from: $0.date), calendar.component(.day, from: $0.date)]
        }
        precondition(taskDates == [[2026, 10, 12], [2026, 10, 14]])
        precondition(result.tasks.map(\.activity) == [.finalReview, .finalReview])
        precondition(result.tasks.map(\.reason) == [
            "Light Geometry practice before the examination.",
            "Light Algebra practice before the examination."
        ])
        precondition(result.tasks.allSatisfy { $0.minutes == 15 })
        precondition(Set(result.tasks.compactMap(\.questionID)).count == result.tasks.count)
        precondition(result.tasks.allSatisfy { [2, 4].contains(calendar.component(.weekday, from: $0.date)) })
        precondition(result.availableDays == 2)
        precondition(result.unfilledDays == 0)

        print("availability helper: available days, rest days, and missing schedule entries distinguished")
        print("production PublicPlanningEngine: priority, task allocation, eligible dates, duration, and uniqueness assertions passed")
    }

    static func testDiagnosticAnalysis() {
        let twoPapers = [
            DiagnosticPaperRecord(stableID: "tmua-1", ordinal: 1, sourceID: "S1", accumulatedSeconds: 1_200),
            DiagnosticPaperRecord(stableID: "tmua-2", ordinal: 2, sourceID: "S2", accumulatedSeconds: 1_300)
        ]
        let tmuaResponses = (1...4).map { index in
            DiagnosticResponse(paperID: index <= 2 ? "tmua-1" : "tmua-2", questionID: "T-\(index)",
                wasAttempted: true, selectedOption: "A", selfEstimatedMarks: nil, marking: .incorrect)
        }
        let tmuaQuestions = (1...4).map { index in
            AdmissionsQuestion(externalQuestionID: "T-\(index)", primaryTopic: "Algebra",
                reasoningSkill: nil, difficulty: 3)
        }
        let tmua = DiagnosticAnalysis.report(exam: .tmua, papers: twoPapers,
            responses: tmuaResponses, questions: tmuaQuestions)
        precondition(tmua.papers.map(\.displayScore) == [
            "0 correct of 2 assessed (2 questions)", "0 correct of 2 assessed (2 questions)"
        ])
        precondition(tmua.topics.first?.level == .strongDifficulty)

        let smcPaper = [DiagnosticPaperRecord(stableID: "smc-1", ordinal: 1,
            sourceID: "S3", accumulatedSeconds: 1_000)]
        let smcResponses = [
            DiagnosticResponse(paperID: "smc-1", questionID: "S-C1", wasAttempted: true,
                selectedOption: "A", selfEstimatedMarks: nil, marking: .correct),
            DiagnosticResponse(paperID: "smc-1", questionID: "S-C2", wasAttempted: true,
                selectedOption: "B", selfEstimatedMarks: nil, marking: .correct),
            DiagnosticResponse(paperID: "smc-1", questionID: "S-I", wasAttempted: true,
                selectedOption: "C", selfEstimatedMarks: nil, marking: .incorrect),
            DiagnosticResponse(paperID: "smc-1", questionID: "S-U", wasAttempted: false,
                selectedOption: nil, selfEstimatedMarks: nil, marking: .unassessed)
        ]
        let smcQuestions = ["S-C1", "S-C2", "S-I", "S-U"].map {
            AdmissionsQuestion(externalQuestionID: $0, primaryTopic: "Number",
                reasoningSkill: nil, difficulty: 2)
        }
        let smc = DiagnosticAnalysis.report(exam: .smc, papers: smcPaper,
            responses: smcResponses, questions: smcQuestions)
        precondition(smc.papers.first?.displayScore == "32 / 125 self-marked SMC points")
        precondition(smc.papers.first?.provenance.contains("Correctness is reported by you.") == true)

        let bmoPapers = [
            DiagnosticPaperRecord(stableID: "bmo-1", ordinal: 1, sourceID: "S4", accumulatedSeconds: 4_000),
            DiagnosticPaperRecord(stableID: "bmo-2", ordinal: 2, sourceID: "S5", accumulatedSeconds: 4_000)
        ]
        let bmoResponses = [
            DiagnosticResponse(paperID: "bmo-1", questionID: "B-1", wasAttempted: true,
                selectedOption: nil, selfEstimatedMarks: 3, marking: .unassessed),
            DiagnosticResponse(paperID: "bmo-2", questionID: "B-2", wasAttempted: true,
                selectedOption: nil, selfEstimatedMarks: 4, marking: .unassessed)
        ]
        let bmoQuestions = ["B-1", "B-2"].map {
            AdmissionsQuestion(externalQuestionID: $0, primaryTopic: "Proof",
                reasoningSkill: nil, difficulty: 4)
        }
        let bmo = DiagnosticAnalysis.report(exam: .bmo, papers: bmoPapers,
            responses: bmoResponses, questions: bmoQuestions)
        precondition(bmo.papers.map(\.displayScore) == ["3 / 10 self-estimated marks", "4 / 10 self-estimated marks"])
        precondition(bmo.papers.allSatisfy {
            $0.provenance == "Self-estimate only; no bundled examiner mark scheme. Each question carries 10 marks."
        })
        precondition(bmo.topics.first?.level == .possibleImprovement)
        precondition(bmo.topics.first?.explanation == "Low self-estimated marks on 2 proofs; no examiner scheme is available.")

        print("production DiagnosticAnalysis: TMUA evidence classification, SMC scoring, and BMO self-assessment assertions passed")
    }

    static func testPlanningBoundariesAndEligibility() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        func plannerInput(examDay: Int, availability: [DayAvailability], questions: [PublicPlanningQuestion]) -> PublicPlanningInput {
            PublicPlanningInput(exam: .tmua, startDate: start,
                examDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: examDay))!,
                weeklyMinutes: 30, availability: availability, diagnosticSignals: [],
                questions: questions, papers: [], calendar: calendar)
        }
        let fresh = PublicPlanningQuestion(id: "fresh-short", sourceID: "SRC", topic: "Algebra", difficulty: 2,
            diagnostic: false, latestOutcome: nil, latestAttemptDate: nil, reviewFlag: false, hasSolution: true)
        let oneDay = try PublicPlanningEngine.generate(plannerInput(examDay: 13,
            availability: [DayAvailability(weekday: .monday, isAvailable: true)], questions: [fresh]))
        precondition(oneDay.tasks.count == 1)
        precondition(oneDay.tasks[0].date == start && oneDay.tasks[0].minutes == 15)
        precondition(oneDay.tasks[0].activity == .finalReview)
        precondition(oneDay.tasks[0].reason == "Light Algebra practice before the examination.")
        precondition(oneDay.availableDays == 1 && oneDay.unfilledDays == 0)

        let none = Weekday.displayOrder.map { DayAvailability(weekday: $0, isAvailable: false) }
        do {
            _ = try PublicPlanningEngine.generate(plannerInput(examDay: 15, availability: none, questions: [fresh]))
            preconditionFailure("Expected noAvailableDays")
        } catch let error as PublicPlanningError {
            precondition(error == .noAvailableDays)
        }

        let review = PublicPlanningQuestion(id: "diagnostic-wrong", sourceID: "SRC", topic: "Algebra", difficulty: 2,
            diagnostic: true, latestOutcome: .incorrect, latestAttemptDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)),
            reviewFlag: false, hasSolution: true)
        let unassessed = PublicPlanningQuestion(id: "diagnostic-unassessed", sourceID: "SRC", topic: "Algebra", difficulty: 2,
            diagnostic: true, latestOutcome: nil, latestAttemptDate: nil, reviewFlag: false, hasSolution: true)
        let eligibility = try PublicPlanningEngine.generate(plannerInput(examDay: 19,
            availability: [DayAvailability(weekday: .monday, isAvailable: true)],
            questions: [review, unassessed]))
        precondition(eligibility.tasks.contains { $0.questionID == "diagnostic-wrong" && $0.activity == .errorReview })
        precondition(!eligibility.tasks.contains { $0.questionID == "diagnostic-unassessed" })
        precondition(eligibility.tasks.first?.reason == "Revisit Algebra after an earlier result or review flag.")
        print("production PublicPlanningEngine boundaries: zero available days, one-day final-review allocation, and diagnostic question eligibility passed")
    }

    static func testLowDiagnosticEvidence() {
        let paper = DiagnosticPaperRecord(stableID: "low-1", ordinal: 1, sourceID: "SRC", accumulatedSeconds: 0)
        let response = DiagnosticResponse(paperID: "low-1", questionID: "LOW-1", wasAttempted: true,
            selectedOption: "A", selfEstimatedMarks: nil, marking: .incorrect)
        let question = AdmissionsQuestion(externalQuestionID: "LOW-1", primaryTopic: "Algebra",
            reasoningSkill: nil, difficulty: 2)
        let report = DiagnosticAnalysis.report(exam: .tmua, papers: [paper], responses: [response], questions: [question])
        precondition(report.topics.first?.level == .insufficient)
        precondition(report.topics.first?.explanation == "1 assessed question; more evidence is needed.")
        print("production DiagnosticAnalysis low-evidence boundary: one assessed miss remains insufficient")
    }
}
