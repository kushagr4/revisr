import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import revisr

/// R5: the plan is a pure function of its explicit inputs. Each scenario pins every input (student
/// identity, dates, calendar, availability, synthetic bank and synthetic library) and compares the
/// canonical serialisation of the whole programme — dates, activities, question IDs, worksheet
/// contents, paper sessions, minutes, task IDs, order and reasons — with a golden digest recorded
/// in an earlier process. Each test run is a separate process with its own hash seed, so a match
/// is a cross-process check, not just a repeated call.
///
/// A golden digest changes only when planning rules change on purpose. Record the new value from
/// the `DETERMINISM` line and say why in docs/R5_PLANNER_DETERMINISM.md.
@MainActor
final class TMUAPlannerDeterminismTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)
    private var calendar: Calendar { TMUAFixtures.calendar }

    private struct Scenario {
        let name: String
        let days: Int
        let weekly: Int
        let weekdays: Set<Weekday>
        var library = true
        var allCorrect = false
        var history = false
    }

    static let everyDay = Set(Weekday.allCases)
    private static let scenarios: [Scenario] = [
        Scenario(name: "14d-3h-3d", days: 14, weekly: 180, weekdays: [.monday, .wednesday, .saturday]),
        Scenario(name: "14d-12h-7d-strong", days: 14, weekly: 720, weekdays: everyDay, allCorrect: true),
        Scenario(name: "30d-5h-6d-questions-only", days: 30, weekly: 300,
                 weekdays: everyDay.subtracting([.sunday]), library: false),
        Scenario(name: "120d-5h-6d", days: 120, weekly: 300, weekdays: everyDay.subtracting([.sunday])),
        Scenario(name: "180d-12h-7d", days: 180, weekly: 720, weekdays: everyDay),
        Scenario(name: "60d-5h-6d-history", days: 60, weekly: 300,
                 weekdays: everyDay.subtracting([.sunday]), history: true),
    ]

    /// Recorded from a separate process; see the type comment before changing one.
    private static let golden: [String: String] = [
        "14d-3h-3d": "a0c7aef7c5a3cc8c4460c564e3f5ac67465202f462ab0f0154161b9a1128048c",
        "14d-12h-7d-strong": "afda998cdad0a73bd220142318d22be2438253e6ad8eb83eca0edc70888145e0",
        "30d-5h-6d-questions-only": "d38ea6f6d54867ac6fcb73747def505506faddef1b5d3566d4ad1bfa965de596",
        "120d-5h-6d": "042181d3ab33b67f4751fd8ff43f1adebd2c4734346e0f6547c0ea521837db41",
        "180d-12h-7d": "7e6248fc5c25819872fdb563ff9ad94110ac3be137789c06f19580a5f654523e",
        "60d-5h-6d-history": "0f80918a7e4b5492cd09df2b73aae7d6ae3702367b8077da6928ce2aa9d741fc",
    ]

    func testPlansMatchGoldenDigestsAcrossProcesses() throws {
        var mismatches: [String] = []
        for scenario in Self.scenarios {
            let first = try canonicalProgramme(scenario)
            let second = try canonicalProgramme(scenario)
            XCTAssertEqual(first, second, "\(scenario.name): two builds in one process differ")
            let digest = Self.digest(first)
            print("DETERMINISM \(scenario.name) lines=\(first.count) digest=\(digest)")
            if Self.golden[scenario.name] != digest { mismatches.append("\(scenario.name)=\(digest)") }
        }
        XCTAssertTrue(mismatches.isEmpty, "golden digests differ: \(mismatches.joined(separator: ", "))")
    }

    /// The scenarios really exercise what they claim: worksheets, whole papers, both evidence
    /// levels, completed work kept through a refresh and a changed availability.
    func testScenariosCoverWorksheetsPapersAndHistory() throws {
        let long = try canonicalProgramme(Self.scenarios[4])
        XCTAssertTrue(long.contains { $0.contains("|topicWorksheet|") }, "long plan sets worksheets")
        XCTAssertTrue(long.contains { $0.contains("|resourcePractice|") }, "long plan sets whole papers")
        XCTAssertFalse(try canonicalProgramme(Self.scenarios[2]).contains { $0.contains("worksheet:") })
        let history = try canonicalProgramme(Self.scenarios[5])
        XCTAssertTrue(history.contains { $0.hasSuffix("|completed") }, "completed tasks are part of the record")
        XCTAssertTrue(history.contains { $0.hasSuffix("|retired") }, "the refresh retired some future tasks")
        XCTAssertNotEqual(try canonicalProgramme(Self.scenarios[0]),
                          try canonicalProgramme(Scenario(name: "variant", days: 14, weekly: 180,
                              weekdays: [.monday, .wednesday, .saturday], allCorrect: true)),
                          "different diagnostic evidence gives a different plan")
    }

    // MARK: Refresh stability

    /// An optional diagnostic invitation in the next three days stays the only one after a refresh.
    func testRefreshDoesNotAddASecondRefinementInvitation() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let content = try TMUAFixtures.standardContext()
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: 40, weeklyMinutes: 300,
                                                availability: Self.availability(Self.everyDay), id: TMUAFixtures.pinnedProfileID)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                                   calendar: calendar, in: context)
        func invitations() throws -> [PublicProgrammeTask] {
            try PublicProgrammeService.tasks(for: programme, in: context).filter { $0.isActive && $0.activity == .diagnosticRefinement }
        }
        let before = try invitations()
        XCTAssertEqual(before.count, 1, "the starter diagnostic offers one invitation")
        try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                   calendar: calendar, in: context)
        XCTAssertEqual(try invitations().map(\.stableID), before.map(\.stableID))
    }

    /// Where clocks go forward at midnight (Santiago, 6 September 2026), every task still falls at
    /// the start of its day, so day keys, library sessions and empty-day counts agree.
    func testDaysStayAtMidnightAcrossAMidnightClockChange() throws {
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        let start = santiago.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))!
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let content = try TMUAFixtures.standardContext()
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        settings.id = TMUAFixtures.pinnedProfileID
        let examDate = santiago.date(byAdding: .day, value: 21, to: santiago.startOfDay(for: start))!
        try PublicPreparationService.saveFlexibleTMUAProfile(examDate: examDate, weeklyMinutes: 300,
            availability: Self.availability(Self.everyDay), sessionMinutes: nil, today: start, calendar: santiago,
            settings: settings, in: context)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: start, in: context)
        try TMUAFixtures.completeAll(snapshot, at: start, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: start,
            calendar: santiago, resourceSessions: true, catalogue: try Self.syntheticCatalogue(content: content), in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        XCTAssertTrue(tasks.contains { $0.scheduledDate > santiago.date(from: DateComponents(year: 2026, month: 9, day: 7))! })
        for task in tasks {
            XCTAssertEqual(task.scheduledDate, santiago.startOfDay(for: task.scheduledDate), task.stableID)
        }
        let byDay = Dictionary(grouping: tasks) { TMUAProgrammeService.dayKey($0.scheduledDate, calendar: santiago) }
        XCTAssertTrue(byDay.values.allSatisfy { Set($0.map(\.scheduledDate)).count == 1 }, "one instant per day")
        let summary = TMUAProgrammeService.contentSummary(programme: programme, tasks: tasks, seenStableIDs: [],
            availability: Self.availability(Self.everyDay), today: start, calendar: santiago)
        XCTAssertEqual(summary.emptyStudyDays, 0)
    }

    /// Two attempts at the same instant read the same way whatever order they are fetched in:
    /// the incorrect one counts as the later.
    func testSameInstantAttemptsReadTheSameWayInEveryOrder() throws {
        let item = try XCTUnwrap(TMUAFixtures.standardContext().eligibleItems.first)
        let wrong = try XCTUnwrap(item.options.first { $0.id != item.correctOptionId }?.id)
        let a = TMUAPracticeAttempt(profileSettingsID: TMUAFixtures.pinnedProfileID, item: item,
                                    selectedOptionID: item.correctOptionId, seconds: 60, origin: .questionBank,
                                    programmeTaskID: nil, at: today)
        let b = TMUAPracticeAttempt(profileSettingsID: TMUAFixtures.pinnedProfileID, item: item,
                                    selectedOptionID: wrong, seconds: 60, origin: .questionBank,
                                    programmeTaskID: nil, at: today)
        XCTAssertFalse(try XCTUnwrap([a, b].max(by: TMUAPracticeAttempt.isEarlier)).isCorrect)
        XCTAssertFalse(try XCTUnwrap([b, a].max(by: TMUAPracticeAttempt.isEarlier)).isCorrect)
    }

    // MARK: Building one programme

    private func canonicalProgramme(_ scenario: Scenario) throws -> [String] {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let content = try TMUAFixtures.standardContext()
        let catalogue = try Self.syntheticCatalogue(content: content)
        let availability = Self.availability(scenario.weekdays)
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: scenario.days,
            weeklyMinutes: scenario.weekly, availability: availability, id: TMUAFixtures.pinnedProfileID)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context, allCorrect: scenario.allCorrect)
        var programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
            today: today, calendar: calendar, resourceSessions: scenario.library, catalogue: catalogue, in: context)
        if scenario.history {
            try recordHistory(settings: settings, content: content, programme: programme, in: context)
            // A week later the student drops Saturdays and the plan is refreshed.
            let later = calendar.date(byAdding: .day, value: 7, to: today)!
            try PublicPreparationService.saveFlexibleTMUAProfile(examDate: programme.examDateSnapshot,
                weeklyMinutes: scenario.weekly, availability: Self.availability(scenario.weekdays.subtracting([.saturday])),
                sessionMinutes: nil, today: later, calendar: calendar, settings: settings, in: context)
            programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                today: later, calendar: calendar, resourceSessions: true, catalogue: catalogue, in: context)
        }
        return try PublicProgrammeService.tasks(for: programme, in: context).map { task in
            let state = task.completedAt != nil ? "completed" : task.isActive ? "active" : "retired"
            return [TMUAProgrammeService.dayKey(task.scheduledDate, calendar: calendar), task.stableID,
                    task.activityRawValue, task.questionID ?? "-", task.sourceID, task.topic,
                    String(task.allocatedMinutes), task.reason, state].joined(separator: "|")
        }
    }

    /// Practice in the first week: auto-marked answers (two of them recorded at the same instant),
    /// a review flag, per-question worksheet results and one completed worksheet.
    private func recordHistory(settings: AppSettings, content: TMUAContentContext, programme: PublicProgramme,
                               in context: ModelContext) throws {
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        let questionTasks = tasks.filter { $0.questionID != nil }.prefix(4)
        for (offset, task) in questionTasks.enumerated() {
            guard let item = content.eligibleItems.first(where: { $0.stableId == task.questionID }) else { continue }
            let choice = offset % 2 == 0 ? item.correctOptionId : (item.options.first { $0.id != item.correctOptionId }?.id ?? "B")
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: choice, seconds: 120, task: task,
                                                    settings: settings, at: task.scheduledDate, in: context)
        }
        // The same question answered twice at one instant: the planner must not depend on fetch order.
        if let item = content.eligibleItems.last {
            for choice in [item.correctOptionId, "E"] where item.options.contains(where: { $0.id == choice }) {
                try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: choice, seconds: 60, task: nil,
                                                        settings: settings, at: today, in: context)
            }
        }
        if let flagged = content.eligibleItems.dropFirst(5).first {
            try TMUAProgrammeService.setReviewFlag(true, itemStableID: flagged.stableId, settings: settings,
                                                   at: today, in: context)
        }
        if let sheet = tasks.first(where: { $0.activity == .topicWorksheet }) {
            let questions = TMUAProgrammeService.worksheetQuestionIDs(sheet.sourceID)
            for (offset, id) in questions.enumerated() {
                context.insert(TMUAResourceLog(profileSettingsID: settings.id, sourceID: sheet.sourceID, questionID: id,
                    outcome: offset % 3 == 0 ? .incorrect : .correct, correctCount: nil, questionCount: nil,
                    minutes: nil, recordedAt: sheet.scheduledDate, programmeTaskID: sheet.stableID))
            }
            try TMUAProgrammeService.completeResourceSession(sheet, outcome: .partial, correct: 2,
                questionCount: questions.count, minutes: 30, settings: settings, at: sheet.scheduledDate, in: context)
        }
    }

    // MARK: Synthetic inputs

    static func availability(_ weekdays: Set<Weekday>) -> [DayAvailability] {
        AppSettings.publicDefaultAvailability.map { day -> DayAvailability in
            var day = day
            day.isAvailable = weekdays.contains(day.weekday)
            return day
        }
    }

    /// A small library of synthetic papers: an official-format pair, an independent mock, a MAT-style
    /// paper (paper fit from its index), a paper with no solutions and one only linked externally.
    static func syntheticCatalogue(content: TMUAContentContext) throws -> TMUAQuestionCatalogue {
        let registry = try XCTUnwrap(TMUAResourceRegistry.bundled())
        func provider(_ key: String) throws -> TMUAResourceProvider {
            try XCTUnwrap(registry.providers.first { $0.key == key })
        }
        let topics = content.syllabus.topics
        let solutions = [TMUAResourceSource.SolutionFile(title: "Worked solutions", resourceName: "fixture-solutions",
                                                         resourceExtension: "pdf", isVideo: false)]
        func paper(_ id: String, _ provider: TMUAResourceProvider, family: String, label: String?, count: Int,
                   fit: String?, solved: Bool = true, access: TMUAResourceAccess = .studyCopy) -> TMUAResourceSource {
            let questions = (1...count).map { number -> TMUAResourceQuestion in
                let topic = topics[(number * 7 + id.count) % topics.count]
                var question = TMUAResourceQuestion(id: "\(id)-Q\(number)", label: String(number), page: number + 1,
                    topic: "Legacy \(topic.title)", difficultyLabel: "Core", paperFit: fit, format: "Multiple choice",
                    autoMarkedItemID: nil, solutionPage: solved ? number + 1 : nil)
                question.difficulty = 1 + (number * 3 + id.count) % 5
                question.solutionResource = solved ? "fixture-solutions" : nil
                return question
            }
            return TMUAResourceSource(id: id, title: id, provider: provider, family: family, paperLabel: label,
                                      year: 2020, questions: questions, solutions: solved ? solutions : [],
                                      access: access, labelCorrection: nil)
        }
        let official = try provider("uat-uk")
        let sources = [
            paper("FX-OFF-2020-P1", official, family: "TMUA Practice", label: "Paper 1", count: 20, fit: nil),
            paper("FX-OFF-2020-P2", official, family: "TMUA Practice", label: "Paper 2", count: 20, fit: nil),
            paper("FX-MOCK-A", try provider("jzmaths"), family: "JZ Maths TMUA Mock", label: "Paper 1", count: 20, fit: nil),
            paper("FX-MAT-2019", try provider("oxford-mat"), family: "MAT", label: nil, count: 10, fit: "Both"),
            paper("FX-SMC-2018", try provider("ukmt"), family: "SMC", label: nil, count: 25, fit: "Paper 1"),
            paper("FX-NOSOL", try provider("ocr-step"), family: "STEP", label: nil, count: 6, fit: "Paper 2", solved: false),
            paper("FX-LINK", official, family: "TMUA Practice", label: "Paper 1", count: 20, fit: nil, access: .providerLink),
        ]
        let map = Dictionary(uniqueKeysWithValues: topics.map { ("Legacy \($0.title)", $0.key) })
        let reconciliation = TMUACatalogueReconciliation(version: 1, reviewedOn: "2026-10-29", legacyTopicMap: map,
            duplicates: [.init(question: "FX-MOCK-A-Q3", canonical: "FX-OFF-2020-P1-Q3", relation: .adapted,
                               evidence: "fixture")],
            documents: [])
        return TMUAQuestionCatalogue.build(sources: sources, items: content.eligibleItems,
                                           allVersions: content.bank.items, syllabus: content.syllabus,
                                           reconciliation: reconciliation, distribution: .internal)
    }

    private static func digest(_ lines: [String]) -> String {
        SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
