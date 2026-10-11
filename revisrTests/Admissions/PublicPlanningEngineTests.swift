import XCTest
@testable import revisr

final class PublicPlanningEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func questions(_ count: Int = 160, exam: PublicExamKind = .tmua) -> [PublicPlanningQuestion] {
        (0..<count).map { index in
            PublicPlanningQuestion(id: "Q-\(String(format: "%04d", index))",
                sourceID: "SRC-\(index / 25)",
                topic: index.isMultiple(of: 2) ? "Algebra" : "Geometry",
                difficulty: index % 5 + 1, diagnostic: false,
                latestOutcome: nil, latestAttemptDate: nil,
                reviewFlag: false, hasSolution: exam != .bmo)
        }
    }

    private func input(exam: PublicExamKind = .tmua, days: Int = 30,
                       weeklyMinutes: Int = 600,
                       availability: [DayAvailability] = AppSettings.publicDefaultAvailability,
                       questions: [PublicPlanningQuestion]? = nil,
                       signals: [DiagnosticTopicResult] = []) -> PublicPlanningInput {
        PublicPlanningInput(exam: exam, startDate: date(2026, 10, 9),
            examDate: calendar.date(byAdding: .day, value: days, to: date(2026, 10, 9))!,
            weeklyMinutes: weeklyMinutes, availability: availability,
            diagnosticSignals: signals, questions: questions ?? self.questions(exam: exam),
            papers: [], calendar: calendar)
    }

    func testDeterministicSchedulesRespectDatesDaysAndWeeklyCapacity() throws {
        for days in [7, 30, 90] {
            let source = input(days: days, questions: questions(700))
            let first = try PublicPlanningEngine.generate(source)
            let second = try PublicPlanningEngine.generate(source)
            XCTAssertEqual(first.tasks, second.tasks)
            XCTAssertFalse(first.tasks.isEmpty)
            XCTAssertTrue(first.tasks.allSatisfy { $0.date < source.examDate })
            XCTAssertEqual(Set(first.tasks.compactMap(\.questionID)).count,
                           first.tasks.compactMap(\.questionID).count)
            let weeks = Dictionary(grouping: first.tasks) { task in
                source.calendar.dateInterval(of: .weekOfYear, for: task.date)!.start
            }
            XCTAssertTrue(weeks.values.allSatisfy { $0.reduce(0) { $0 + $1.minutes } <= 600 })
        }
    }

    func testWeekendsOnlyAndNoAvailableDayOrCapacityAreActionable() throws {
        let weekends = Weekday.displayOrder.map {
            DayAvailability(weekday: $0, isAvailable: $0 == .saturday || $0 == .sunday)
        }
        let result = try PublicPlanningEngine.generate(input(availability: weekends))
        XCTAssertTrue(result.tasks.allSatisfy {
            [1, 7].contains(calendar.component(.weekday, from: $0.date))
        })
        let none = Weekday.displayOrder.map { DayAvailability(weekday: $0, isAvailable: false) }
        XCTAssertThrowsError(try PublicPlanningEngine.generate(input(availability: none))) {
            XCTAssertEqual($0 as? PublicPlanningError, .noAvailableDays)
        }
        XCTAssertThrowsError(try PublicPlanningEngine.generate(input(weeklyMinutes: 30))) {
            XCTAssertEqual($0 as? PublicPlanningError, .insufficientDailyCapacity)
        }
    }

    func testDiagnosticEvidenceChangesFirstTopicWithoutInventedStrengthForBMO() throws {
        let strong = DiagnosticTopicResult(name: "Geometry", assessedCount: 5,
            unansweredCount: 0, unassessedCount: 0, level: .strongDifficulty,
            explanation: "Recorded misses")
        let relative = DiagnosticTopicResult(name: "Algebra", assessedCount: 5,
            unansweredCount: 0, unassessedCount: 0, level: .relativeStrength,
            explanation: "Recorded successes")
        let tmua = try PublicPlanningEngine.generate(input(signals: [strong, relative]))
        XCTAssertEqual(tmua.tasks.first?.topic, "Geometry")
        XCTAssertEqual(tmua.priorities.first?.topic, "Geometry")
        XCTAssertGreaterThan(tmua.tasks.filter { $0.topic == "Geometry" }.count,
                             tmua.tasks.filter { $0.topic == "Algebra" }.count)
        let bmo = try PublicPlanningEngine.generate(input(exam: .bmo, signals: [
            DiagnosticTopicResult(name: "Geometry", assessedCount: 2,
                unansweredCount: 0, unassessedCount: 0, level: .possibleImprovement,
                explanation: "Self-estimated marks")
        ]))
        XCTAssertEqual(bmo.priorities.first?.topic, "Geometry")
        XCTAssertFalse(bmo.priorities.first?.reason.contains("across both papers") ?? true)
    }

    func testDiagnosticQuestionsOnlyReturnForGenuineReview() throws {
        let rows = [
            PublicPlanningQuestion(id: "diagnostic-wrong", sourceID: "A", topic: "Algebra",
                difficulty: 2, diagnostic: true, latestOutcome: .incorrect,
                latestAttemptDate: date(2026, 10, 1), reviewFlag: false, hasSolution: true),
            PublicPlanningQuestion(id: "diagnostic-unassessed", sourceID: "A", topic: "Algebra",
                difficulty: 2, diagnostic: true, latestOutcome: nil,
                latestAttemptDate: nil, reviewFlag: false, hasSolution: true),
            PublicPlanningQuestion(id: "fresh", sourceID: "B", topic: "Algebra",
                difficulty: 2, diagnostic: false, latestOutcome: nil,
                latestAttemptDate: nil, reviewFlag: false, hasSolution: true)
        ]
        let result = try PublicPlanningEngine.generate(input(days: 7, questions: rows))
        XCTAssertTrue(result.tasks.contains { $0.questionID == "diagnostic-wrong" && $0.activity == .errorReview })
        XCTAssertFalse(result.tasks.contains { $0.questionID == "diagnostic-unassessed" })
    }

    func testDaylightSavingUsesCalendarDays() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let start = london.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let exam = london.date(from: DateComponents(year: 2026, month: 10, day: 28))!
        let source = PublicPlanningInput(exam: .tmua, startDate: start, examDate: exam,
            weeklyMinutes: 420, availability: AppSettings.publicDefaultAvailability,
            diagnosticSignals: [], questions: questions(100), papers: [], calendar: london)
        let result = try PublicPlanningEngine.generate(source)
        XCTAssertEqual(Set(result.tasks.map { london.startOfDay(for: $0.date) }).count, 4)
        XCTAssertTrue(result.tasks.allSatisfy { $0.date < exam })
    }
}
