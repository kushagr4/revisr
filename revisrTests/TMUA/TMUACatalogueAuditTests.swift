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
                                                weeklyMinutes: capacity.weekly, availability: availability,
                                                id: TMUAFixtures.pinnedProfileID)
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
        let worksheets = tasks.filter { $0.activity == .topicWorksheet }
        let catalogue = TMUACatalogueStore.catalogue(content)
        let worksheetQuestions = worksheets.flatMap { TMUAProgrammeService.worksheetQuestionIDs($0.sourceID) }
        // R4: every library session names a real paper or real catalogue questions in this build.
        XCTAssertTrue(paperSessions.allSatisfy { task in catalogue.sources.contains { $0.id == task.sourceID } })
        XCTAssertTrue(worksheetQuestions.allSatisfy { catalogue.entry($0)?.answerMode == .selfMarked })
        XCTAssertEqual(Set(worksheetQuestions).count, worksheetQuestions.count, "no worksheet question repeats")
        let wholePapers = Set(paperSessions.map(\.sourceID))
        XCTAssertTrue(worksheetQuestions.allSatisfy { !wholePapers.contains(catalogue.entry($0)?.sourceID ?? "") },
                      "a question is never fresh twice: in a worksheet and in a paper set whole")
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
        print(String(format: "AUDIT library %@ studyDays=%d questionTasks=%d distinct=%d official=%.0f%% maxUses=%d paperSessions=%d worksheets=%d worksheetQuestions=%d emptyDays=%d freshUntil=%d",
                     label, summary.studyDays, questionTasks.count, uses.count,
                     questionTasks.isEmpty ? 0 : Double(official) / Double(questionTasks.count) * 100,
                     uses.values.max() ?? 0, paperSessions.count, worksheets.count, worksheetQuestions.count,
                     summary.emptyStudyDays, summary.daysWithoutNewQuestions))
        // R5 realism: time per question, source concentration, difficulty, paper balance, topic spread,
        // solution pages, near-duplicates and the share of worksheets on weak topics.
        let sheetEntries = worksheetQuestions.compactMap(catalogue.entry)
        XCTAssertFalse(sheetEntries.contains { entry in entry.variantOf.map(worksheetQuestions.contains) == true },
                       "\(label): a question and its adaptation are never both set")
        XCTAssertTrue(sheetEntries.allSatisfy { $0.topicKey != nil && $0.topicBasis != .outsideSpecification })
        let providers = Dictionary(grouping: sheetEntries, by: { $0.provider?.key ?? "revisr" }).mapValues(\.count)
        let levels = (1...5).map { level in sheetEntries.filter { $0.difficulty == level }.count }
        let fits = Dictionary(grouping: sheetEntries, by: \.paperFit.rawValue).mapValues(\.count)
        let weak = TMUAProgrammeService.worksheetWeakTopics(
            report: TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus), syllabus: content.syllabus)
        let weakSheets = worksheets.filter { TMUAProgrammeService.worksheetTopic($0.sourceID).map(weak.contains) == true }.count
        let sheetMinutes = worksheets.reduce(0) { $0 + $1.allocatedMinutes }
        let maxDay = byDay.values.map { $0.reduce(0) { $0 + $1.allocatedMinutes } }.max() ?? 0
        if !worksheets.isEmpty {
            print(String(format: "REALISM %@ minPerQ=%.1f topProvider=%@ %.0f%% levels=%@ fit=%@ topics=%d drafts=%d solutionPages=%.0f%% weakTopics=%d weakSheets=%.0f%% maxDay=%d cap=%d",
                         label, Double(sheetMinutes) / Double(max(1, sheetEntries.count)),
                         providers.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? "-",
                         Double(providers.values.max() ?? 0) / Double(max(1, sheetEntries.count)) * 100,
                         levels.map(String.init).joined(separator: "/"),
                         ["paper1", "paper2", "both", "unclassified"].map { "\(fits[$0] ?? 0)" }.joined(separator: "/"),
                         Set(sheetEntries.compactMap(\.topicKey)).count,
                         sheetEntries.filter { $0.topicBasis == .provisionalDraft }.count,
                         Double(sheetEntries.filter { $0.solutionPage != nil }.count) / Double(max(1, sheetEntries.count)) * 100,
                         weak.count, Double(weakSheets) / Double(max(1, worksheets.count)) * 100, maxDay, max(perDay, 20)))
        }
    }
}
