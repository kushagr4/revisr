import SwiftData
import XCTest
@testable import revisr

/// R1 planner audit: generates plans across horizons, capacities and banks,
/// checks invariants and prints `AUDIT` lines that the R1 audit document
/// summarises. The bundled-bank run uses the development bank when present.
@MainActor
final class TMUAPlannerAuditTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)
    private var calendar: Calendar { TMUAFixtures.calendar }

    struct Capacity {
        let name: String
        let weekly: Int
        let days: Set<Weekday>
        let session: Int?
    }

    private let capacities = [
        Capacity(name: "3h/3d", weekly: 180, days: [.monday, .wednesday, .saturday], session: nil),
        Capacity(name: "5h/6d", weekly: 300, days: Set(Weekday.allCases).subtracting([.sunday]), session: nil),
        Capacity(name: "8h/5d cap60", weekly: 480, days: [.monday, .tuesday, .wednesday, .thursday, .friday], session: 60),
        Capacity(name: "12h/7d", weekly: 720, days: Set(Weekday.allCases), session: nil)
    ]

    private func availability(_ days: Set<Weekday>) -> [DayAvailability] {
        AppSettings.publicDefaultAvailability.map { day in
            var day = day
            day.isAvailable = days.contains(day.weekday)
            return day
        }
    }

    struct Metrics {
        var studyDays = 0, daysWithTasks = 0, emptyStudyDays = 0, emptyFinalHalf = 0
        var tasks = 0, questionTasks = 0, distinctQuestions = 0, maxUses = 0
        var fresh = 0, errorReview = 0, spaced = 0, finalReview = 0
        var plannedMinutes = 0, capacityMinutes = 0, maxDayMinutes = 0, maxTopicShare = 0.0
        var lastFreshDaysBeforeExam: Int?
        var firstEmptyStudyDay: Int?
    }

    private func audit(content: TMUAContentContext, label: String, days: Int, capacity: Capacity,
                       length: TMUADiagnosticLength) throws -> Metrics? {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days,
            weeklyMinutes: capacity.weekly, availability: availability(capacity.days), session: capacity.session)
        guard content.availability(for: length).isAvailable else { return nil }
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: length, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                   today: today, calendar: calendar, in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        let examDay = calendar.startOfDay(for: try XCTUnwrap(settings.publicExamDate))
        let diagnosticIDs = Set(snapshot.items.map(\.itemStableID))
        let eligibleIDs = Set(content.eligibleItems.map(\.stableId))
        let perDayCapacity = min(capacity.weekly / capacity.days.count, capacity.session ?? .max)
        let scenario = "\(label) \(days)d \(capacity.name) \(length.rawValue)"

        var metrics = Metrics()
        let byDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.scheduledDate) }
        var date = calendar.startOfDay(for: today)
        var index = 0
        while date < examDay {
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: date))!
            if capacity.days.contains(weekday) {
                metrics.studyDays += 1
                let dayTasks = byDay[date] ?? []
                let minutes = dayTasks.reduce(0) { $0 + $1.allocatedMinutes }
                metrics.capacityMinutes += perDayCapacity
                metrics.maxDayMinutes = max(metrics.maxDayMinutes, minutes)
                XCTAssertLessThanOrEqual(minutes, perDayCapacity + 1, "\(scenario): day over capacity")
                if dayTasks.isEmpty {
                    metrics.emptyStudyDays += 1
                    metrics.firstEmptyStudyDay = metrics.firstEmptyStudyDay ?? index
                    if index * 2 >= days { metrics.emptyFinalHalf += 1 }
                } else {
                    metrics.daysWithTasks += 1
                }
                let ids = dayTasks.compactMap(\.questionID)
                XCTAssertEqual(Set(ids).count, ids.count, "\(scenario): same question twice on one day")
            } else {
                XCTAssertNil(byDay[date], "\(scenario): task on a rest day")
            }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
            index += 1
        }
        XCTAssertTrue(tasks.allSatisfy { $0.scheduledDate < examDay && $0.scheduledDate >= calendar.startOfDay(for: today) },
                      "\(scenario): task outside the window")

        let questionTasks = tasks.filter { $0.questionID != nil }.sorted { $0.scheduledDate < $1.scheduledDate }
        var seen = diagnosticIDs
        var uses: [String: Int] = [:]
        for task in questionTasks {
            let id = task.questionID!
            XCTAssertTrue(eligibleIDs.contains(id), "\(scenario): unknown question")
            uses[id, default: 0] += 1
            switch task.activity {
            case .spacedReview:
                metrics.spaced += 1
                XCTAssertTrue(seen.contains(id), "\(scenario): spaced review of a question never seen")
            case .errorReview:
                metrics.errorReview += 1
                XCTAssertTrue(seen.contains(id), "\(scenario): error review of a question never seen")
            case .finalReview:
                metrics.finalReview += 1
                if !seen.contains(id) {
                    metrics.lastFreshDaysBeforeExam = calendar.dateComponents([.day], from: task.scheduledDate, to: examDay).day
                }
            default:
                XCTAssertFalse(seen.contains(id), "\(scenario): \(task.activity.rawValue) labels a question the student has already seen")
                metrics.fresh += 1
                metrics.lastFreshDaysBeforeExam = calendar.dateComponents([.day], from: task.scheduledDate, to: examDay).day
            }
            seen.insert(id)
        }
        metrics.tasks = tasks.count
        metrics.questionTasks = questionTasks.count
        metrics.distinctQuestions = uses.count
        metrics.maxUses = uses.values.max() ?? 0
        metrics.plannedMinutes = tasks.reduce(0) { $0 + $1.allocatedMinutes }
        let topics = Dictionary(grouping: questionTasks, by: \.topic).mapValues(\.count)
        metrics.maxTopicShare = Double(topics.values.max() ?? 0) / Double(max(1, questionTasks.count))
        XCTAssertLessThanOrEqual(metrics.maxUses, 1 + 6, "\(scenario): a question is scheduled too often")
        for (_, minutes) in Dictionary(grouping: tasks, by: { calendar.dateInterval(of: .weekOfYear, for: $0.scheduledDate)!.start })
            .mapValues({ $0.reduce(0) { $0 + $1.allocatedMinutes } }) {
            XCTAssertLessThanOrEqual(minutes, capacity.weekly, "\(scenario): week over capacity")
        }
        print(String(format: "AUDIT %@ | study %d | empty %d (final half %d, first #%@) | tasks %d | distinct %d | max uses %d | fresh %d err %d spaced %d final %d | util %.0f%% | top topic %.0f%% | last new %@d before exam",
                     scenario, metrics.studyDays, metrics.emptyStudyDays, metrics.emptyFinalHalf,
                     metrics.firstEmptyStudyDay.map(String.init) ?? "-", metrics.tasks, metrics.distinctQuestions,
                     metrics.maxUses, metrics.fresh, metrics.errorReview, metrics.spaced, metrics.finalReview,
                     100 * Double(metrics.plannedMinutes) / Double(max(1, metrics.capacityMinutes)),
                     100 * metrics.maxTopicShare, metrics.lastFreshDaysBeforeExam.map(String.init) ?? "-"))
        return metrics
    }

    /// Long windows on a small bank must say when new questions run out
    /// instead of implying months of varied practice.
    func testContentSummaryIsHonestAboutLongWindows() throws {
        let content = try TMUAFixtures.standardContext()
        for (days, limited) in [(14, false), (180, true)] {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days)
            let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content,
                                                            at: today, in: context)
            try TMUAFixtures.completeAll(snapshot, at: today, in: context)
            let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                       today: today, calendar: calendar, in: context)
            let summary = TMUAProgrammeService.contentSummary(programme: programme,
                tasks: try PublicProgrammeService.tasks(for: programme, in: context),
                seenStableIDs: TMUAProgrammeService.seenStableIDs(settings: settings, in: context),
                availability: settings.publicAvailability, today: today, calendar: calendar)
            print("CONTENT \(days)d: study \(summary.studyDays), empty \(summary.emptyStudyDays), distinct \(summary.distinctQuestions), no new for last \(summary.daysWithoutNewQuestions)d — \(summary.message ?? "no notice")")
            XCTAssertEqual(summary.isContentLimited, limited, "\(days)-day window")
            XCTAssertEqual(summary.message != nil, limited)
        }
    }

    func testPlannerAuditOnSyntheticBank() throws {
        let content = try TMUAFixtures.standardContext()
        for days in [3, 7, 14, 30, 60, 90, 120, 180] {
            for capacity in capacities {
                for length in [TMUADiagnosticLength.starter, .comprehensive] {
                    _ = try audit(content: content, label: "fixture64", days: days, capacity: capacity, length: length)
                }
            }
        }
    }

    func testPlannerAuditOnBundledDevelopmentBank() throws {
        guard let content = TMUAContentStore.context(), content.eligibleItems.count >= 40 else {
            throw XCTSkip("Bundled development bank not present in this build")
        }
        for days in [3, 7, 14, 30, 60, 90, 120, 180] {
            for capacity in capacities {
                for length in [TMUADiagnosticLength.starter, .comprehensive] {
                    _ = try audit(content: content, label: "bank\(content.eligibleItems.count)", days: days,
                                  capacity: capacity, length: length)
                }
            }
        }
    }
}
