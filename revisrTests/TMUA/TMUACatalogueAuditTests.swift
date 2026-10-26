import SwiftData
import XCTest
@testable import revisr

/// Plans built from the bundled library (original drafts plus official past-paper study copies)
/// for 14–180 day windows, with and without self-marked paper sessions. Prints `AUDIT` lines
/// summarised in docs/RESOURCE_LIBRARY_INTEGRATION.md. Skipped in builds without study copies.
@MainActor
final class TMUACatalogueAuditTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)
    private var calendar: Calendar { TMUAFixtures.calendar }

    private let capacities: [(name: String, weekly: Int, days: Set<Weekday>)] = [
        ("3h/3d", 180, [.monday, .wednesday, .saturday]),
        ("5h/6d", 300, Set(Weekday.allCases).subtracting([.sunday])),
        ("12h/7d", 720, Set(Weekday.allCases))
    ]

    func testBundledLibraryPlansAcrossWindows() throws {
        guard let content = TMUAContentStore.context(), content.studyCopyItemCount > 0 else {
            throw XCTSkip("No official study copies bundled in this build")
        }
        for days in [14, 30, 60, 90, 120, 180] {
            for capacity in capacities {
                for sessions in [false, true] {
                    try audit(content: content, days: days, capacity: capacity, sessions: sessions)
                }
            }
        }
    }

    private func audit(content: TMUAContentContext, days: Int,
                       capacity: (name: String, weekly: Int, days: Set<Weekday>), sessions: Bool) throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let availability = AppSettings.publicDefaultAvailability.map { day -> DayAvailability in
            var day = day
            day.isAvailable = capacity.days.contains(day.weekday)
            return day
        }
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days,
                                                weeklyMinutes: capacity.weekly, availability: availability)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
            calendar: calendar, resourceSessions: sessions, in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        let itemsByID = Dictionary(content.eligibleItems.map { ($0.stableId, $0) }, uniquingKeysWith: { first, _ in first })
        let questionTasks = tasks.filter { $0.questionID != nil }
        let uses = Dictionary(grouping: questionTasks.compactMap(\.questionID), by: { $0 }).mapValues(\.count)
        let official = questionTasks.filter { $0.questionID.flatMap { itemsByID[$0] }?.category == .pastPaperStudyCopy }.count
        let paperSessions = tasks.filter { $0.activity == .resourcePractice }
        let summary = TMUAProgrammeService.contentSummary(programme: programme, tasks: tasks,
            seenStableIDs: Set(snapshot.items.map(\.itemStableID)), availability: availability,
            today: today, calendar: calendar)
        let perDay = capacity.weekly / capacity.days.count
        let byDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.scheduledDate) }
        let label = "\(days)d \(capacity.name) \(sessions ? "with-papers" : "questions-only")"
        for (day, dayTasks) in byDay {
            XCTAssertLessThanOrEqual(dayTasks.reduce(0) { $0 + $1.allocatedMinutes }, max(perDay, 20) + 1,
                                     "\(label): \(day) over capacity")
        }
        XCTAssertLessThanOrEqual(uses.values.max() ?? 0, TMUAProgrammeService.spacedRepeatLimit + 1,
                                 "\(label): a question is overused")
        if sessions {
            XCTAssertEqual(summary.emptyStudyDays, 0, "\(label): papers remain, so no study day is left empty")
        }
        print(String(format: "AUDIT library %@ studyDays=%d questionTasks=%d distinct=%d official=%.0f%% maxUses=%d paperSessions=%d emptyDays=%d freshUntil=%d",
                     label, summary.studyDays, questionTasks.count, uses.count,
                     questionTasks.isEmpty ? 0 : Double(official) / Double(questionTasks.count) * 100,
                     uses.values.max() ?? 0, paperSessions.count, summary.emptyStudyDays, summary.daysWithoutNewQuestions))
    }
}
