import Foundation
import SwiftData
import XCTest
@testable import revisr

/// Synthetic content for tests only. Items are `development_fixture` unless a
/// test asks for a licensed category, and their "cleared" rights are fixture
/// values — they are not real permissions.
@MainActor
enum TMUAFixtures {
    static var syllabus: TMUASyllabus {
        get throws { try XCTUnwrap(TMUASyllabus.load(), "TMUASyllabus.v1.json must be bundled") }
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func item(_ id: String, paper: Int, topic: String, strand: String, skill: String? = nil,
                     difficulty: Int = 3, category: TMUAContentCategory = .developmentFixture,
                     cleared: Bool = true, version: Int = 1, key: String = "A") -> TMUAContentItem {
        let state: TMUARightsState = cleared ? .cleared : .pendingReview
        let source = category.isLicensedThirdParty
            ? TMUAContentSource(organisation: "Fixture Board", examination: "Fixture Exam", year: 2020,
                                paperNumber: paper, questionNumber: 1, url: "https://example.invalid/fixture",
                                attribution: "Fixture attribution")
            : nil
        return TMUAContentItem(
            stableId: id, version: version, paper: paper, category: category,
            title: "Fixture \(id)", stem: "Synthetic fixture \(id): choose option \(key).",
            options: ["A", "B", "C", "D", "E"].map { TMUAOption(id: $0, text: "Option \($0) for \(id)") },
            correctOptionId: key, solution: "Fixture solution: \(key).",
            taxonomy: TMUATaxonomyMapping(topic: topic, strand: strand, skill: skill),
            difficulty: difficulty, estimatedMinutes: 4, source: source,
            rights: TMUAContentRights(copyrightHolder: "Fixture", licence: "fixture", inAppUse: state,
                redistribution: state, commercialUse: state, answerKey: state, solution: state,
                attribution: category.attributionTitle),
            review: TMUAContentReview(mathematical: cleared ? .humanApproved : .aiDerivationOnly,
                originality: cleared ? .humanApproved : .pending,
                publication: cleared ? .approved : .notApproved, editorialStatus: "fixture"))
    }

    /// Spreads `count` items per paper across every applicable strand.
    static func items(paperOne: Int, paperTwo: Int, licensedEvery: Int? = nil,
                      prefix: String = "fx") throws -> [TMUAContentItem] {
        let syllabus = try syllabus
        var result: [TMUAContentItem] = []
        for (paper, count) in [(1, paperOne), (2, paperTwo)] {
            let strands = syllabus.topics
                .filter { paper == 1 ? $0.papers == [1, 2] : $0.papers.contains(2) }
                .sorted { lhs, rhs in
                    // Paper 2 fixtures lean on reasoning topics, like the real paper.
                    paper == 2 ? (lhs.papers.count, lhs.key) < (rhs.papers.count, rhs.key) : lhs.key < rhs.key
                }
                .flatMap { topic in topic.strands.map { (topic.key, $0.key) } }
            for index in 0..<count {
                let (topic, strand) = strands[index % strands.count]
                let licensed = licensedEvery.map { index % $0 == 0 } ?? false
                result.append(item("\(prefix)-p\(paper)-\(String(format: "%03d", index))", paper: paper,
                    topic: topic, strand: strand,
                    skill: paper == 2 && topic == "logic" ? "conditional-reasoning" : nil,
                    difficulty: [2, 3, 3, 4, 2][index % 5],
                    category: licensed ? (index % 2 == 0 ? .licensedPastPaper : .licensedMock) : .developmentFixture))
            }
        }
        return result
    }

    static func bank(_ items: [TMUAContentItem], distribution: TMUAContentDistribution = .internal) -> TMUAContentBank {
        TMUAContentBank(schemaVersion: 1, bankVersion: "fixture-\(items.count)", distribution: distribution,
            taxonomyVersion: TMUASyllabus.currentVersion, contentPolicyVersion: TMUAContentPolicy.version,
            excludedItemCount: 0, items: items)
    }

    static func context(_ items: [TMUAContentItem], distribution: TMUAContentDistribution = .internal,
                        allowsInternal: Bool = true) throws -> TMUAContentContext {
        TMUAContentContext(bank: bank(items, distribution: distribution), syllabus: try syllabus,
                           allowsInternalContent: allowsInternal, allowsDevelopmentFixtures: true)
    }

    static func standardContext() throws -> TMUAContentContext {
        try context(items(paperOne: 34, paperTwo: 30))
    }

    /// A clean public profile with the flexible TMUA flow and a saved setup.
    static func profile(in context: ModelContext, today: Date, examInDays days: Int = 60,
                        weeklyMinutes: Int = 300, availability: [DayAvailability] = AppSettings.publicDefaultAvailability,
                        session: Int? = nil) throws -> AppSettings {
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let examDate = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today))!
        try PublicPreparationService.saveFlexibleTMUAProfile(examDate: examDate, weeklyMinutes: weeklyMinutes,
            availability: availability, sessionMinutes: session, today: today, calendar: calendar,
            settings: settings, in: context)
        return settings
    }

    static func memoryContainer() throws -> ModelContainer {
        try AppContainer.make(isStoredInMemoryOnly: true)
    }

    /// Answers every question in a section: correct on even ordinals,
    /// incorrect on odd ones, and leaves `skip` questions unanswered.
    static func answerAndSubmit(_ section: TMUADiagnosticSection, snapshot: TMUADiagnosticSnapshot,
                                skip: Int = 0, allCorrect: Bool = false, at date: Date,
                                in context: ModelContext) throws {
        if section.status == .notStarted { try TMUADiagnosticService.start(section, in: snapshot, at: date, in: context) }
        for item in snapshot.items(in: section).dropLast(skip) {
            let key = try XCTUnwrap(item.content?.correctOptionId)
            let wrong = key == "A" ? "B" : "A"
            try TMUADiagnosticService.select(allCorrect || item.ordinal % 2 == 0 ? key : wrong,
                                             for: item, in: section, at: date, in: context)
        }
        try TMUADiagnosticService.submit(section, in: snapshot, at: date.addingTimeInterval(600), in: context)
    }

    static func completeAll(_ snapshot: TMUADiagnosticSnapshot, at date: Date, in context: ModelContext,
                            allCorrect: Bool = false) throws {
        for section in snapshot.sections.sorted(by: { ($0.round, $0.paperRawValue) < ($1.round, $1.paperRawValue) })
        where section.status != .submitted {
            try answerAndSubmit(section, snapshot: snapshot, allCorrect: allCorrect, at: date, in: context)
        }
    }
}
