import SwiftData
import XCTest
@testable import revisr

/// The original Revisr library reconnected to the TMUA journey: catalogue access rules,
/// attribution, official past-paper study copies, mixed selection and paper sessions.
@MainActor
final class TMUAQuestionBankIntegrationTests: XCTestCase {
    private var manifest: AdmissionsManifest { get throws { try AdmissionsManifest.bundled() } }
    private var registry: TMUAResourceRegistry { get throws { try XCTUnwrap(TMUAResourceRegistry.bundled()) } }

    // MARK: Catalogue

    func testEveryLibraryFamilyHasAProviderWithCredit() throws {
        let manifest = try manifest, registry = try registry
        for source in manifest.sources {
            let provider = registry.provider(family: source.family, sourceID: source.stableSourceID)
            XCTAssertNotNil(provider, "no provider for \(source.family) \(source.displayName)")
            XCTAssertFalse(provider?.credit.isEmpty ?? true)
        }
        XCTAssertEqual(manifest.sources.count, 136)
        XCTAssertEqual(manifest.questions.count, 2_600)
    }

    func testInternalBuildShowsEveryBundledSourceAsAStudyCopy() throws {
        let sources = TMUAResourceCatalogue.build(manifest: try manifest, solutions: nil, registry: try registry,
                                                  distribution: .internal, items: [], isBundled: { _ in true })
        XCTAssertEqual(sources.count, 136)
        XCTAssertTrue(sources.allSatisfy { $0.access == .studyCopy })
        XCTAssertEqual(sources.reduce(0) { $0 + $1.questions.count }, 2_600, "no indexed question is dropped")
    }

    func testPublicBuildListsOnlyProvidersWhoseOwnPagesOfferThePapers() throws {
        let sources = TMUAResourceCatalogue.build(manifest: try manifest, solutions: nil, registry: try registry,
                                                  distribution: .public, items: [], isBundled: { _ in true })
        XCTAssertFalse(sources.isEmpty)
        for source in sources {
            XCTAssertEqual(source.access, .providerLink, source.title)
            XCTAssertEqual(source.provider.publicAccess, .listed, source.title)
            XCTAssertEqual(source.provider.link?.scheme, "https", source.title)
            XCTAssertTrue(source.solutions.isEmpty, "public builds never offer bundled solutions")
        }
        let shownProviders = Set(sources.map(\.provider.key))
        XCTAssertEqual(shownProviders, ["uat-uk", "oxford-mat", "ocr-step", "ukmt"])
        for restricted in ["TMUA.fyi Challenge", "Beyond Horizon TMUA Mock", "Tyler Topic Bank", "CSAT", "JZ Maths TMUA Mock"] {
            XCTAssertFalse(sources.contains { $0.family == restricted }, "\(restricted) is not listed publicly")
        }
    }

    func testOriginalIndexLabelErrorsAreCorrectedInTheCatalogue() throws {
        let sources = TMUAResourceCatalogue.build(manifest: try manifest, solutions: nil, registry: try registry,
                                                  distribution: .internal, items: [], isBundled: { _ in true })
        let mocks = sources.filter { $0.family == "TMUA Mock" && $0.provider.key == "tyler-tutoring" }
            .sorted { $0.title < $1.title }
        XCTAssertEqual(mocks.compactMap(\.paperLabel), ["Set A", "Set B", "Set C", "Set D"])
        XCTAssertEqual(mocks.filter { $0.labelCorrection != nil }.count, 3)
        XCTAssertTrue(sources.allSatisfy { !$0.title.contains("_") }, "filenames are not shown as titles")
    }

    func testAutoMarkedQuestionsLinkToTheirBankItems() throws {
        let item = studyCopy("tmua-2019-p1-q11", libraryID: "TMUA-2019-P1-Q11", paper: 1)
        let sources = TMUAResourceCatalogue.build(manifest: try manifest, solutions: nil, registry: try registry,
                                                  distribution: .internal, items: [item], isBundled: { _ in true })
        let paper = try XCTUnwrap(sources.first { $0.title == "TMUA 2019 Paper 1" })
        XCTAssertEqual(paper.questions.first { $0.id == "TMUA-2019-P1-Q11" }?.autoMarkedItemID, "tmua-2019-p1-q11")
        XCTAssertEqual(paper.autoMarkedCount, 1)
    }

    // MARK: Study copies and rights

    func testStudyCopiesNeverPassThePublicGateEvenWithClearedFields() throws {
        let item = studyCopy("tmua-2020-p2-q01", libraryID: "TMUA-2020-P2-Q01", paper: 2, cleared: true)
        XCTAssertTrue(TMUAContentPolicy.publicGateFailures(item).contains { $0.contains("Personal study copy") })
        let content = try TMUAFixtures.context(try TMUAFixtures.items(paperOne: 20, paperTwo: 20) + [item],
                                               distribution: .internal, allowsInternal: false)
        XCTAssertEqual(content.distribution, .public)
        XCTAssertFalse(content.eligibleItems.contains { $0.category == .pastPaperStudyCopy })
    }

    func testCreditLineNamesThePublisherAndThePersonalStudyCopy() {
        let item = studyCopy("tmua-2019-p1-q11", libraryID: "TMUA-2019-P1-Q11", paper: 1)
        XCTAssertEqual(item.creditLine, "Source: UAT-UK (© UCLES) · TMUA 2019 Paper 1 · Q11 · personal study copy")
        XCTAssertFalse(item.creditLine.localizedCaseInsensitiveContains("endorse"))
    }

    func testInternalContextReportsTheMixAndLabelsIt() throws {
        let originals = try TMUAFixtures.items(paperOne: 20, paperTwo: 20).map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              difficulty: 2, category: .revisrOriginal, cleared: false)
        }
        let content = try TMUAFixtures.context(originals + studyCopies(perPaper: 20))
        XCTAssertEqual(content.sourceMix, .mixedStudyCopies)
        XCTAssertNotNil(content.sourceMix.studentNotice)
        XCTAssertEqual(content.studyCopyItemCount, 40)
        XCTAssertEqual(content.licensedItemCount, 0, "a study copy is not licensed content")
    }

    // MARK: Selection

    func testDiagnosticMixesOriginalAndOfficialQuestionsAcrossDifficulty() throws {
        // Originals are all easy here; a selector that picked the easiest questions would use only them.
        let originals = try TMUAFixtures.items(paperOne: 30, paperTwo: 30).map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              skill: $0.taxonomy.skill, difficulty: 2, category: .revisrOriginal, cleared: false)
        }
        let content = try TMUAFixtures.context(originals + studyCopies(perPaper: 30))
        for paper in TMUAPaper.allCases {
            let chosen = try TMUADiagnosticSelector.select(paper: paper, count: 10, candidates: content.eligibleItems)
            let official = chosen.filter { $0.category == .pastPaperStudyCopy }
            XCTAssertGreaterThan(official.count, 0, "\(paper.title) includes official questions")
            XCTAssertGreaterThan(chosen.count - official.count, 0, "\(paper.title) is not forced all-official")
            XCTAssertTrue(chosen.contains { $0.difficulty >= 4 }, "\(paper.title) includes harder questions")
            XCTAssertEqual(Set(chosen.map(\.stableId)).count, chosen.count)
            let note = TMUADiagnosticService.compositionNote(chosen, sourceMix: content.sourceMix)
            XCTAssertTrue(note.contains("official past-paper"), note)
        }
    }

    // MARK: Planning

    func testPlanAssignsOfficialQuestionsAsAutoMarkedPractice() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let today = TMUAFixtures.date(2026, 9, 1)
        let content = try TMUAFixtures.context(try TMUAFixtures.items(paperOne: 12, paperTwo: 12) + studyCopies(perPaper: 40))
        TMUAContentStore.install(content)
        defer { TMUAContentStore.install(nil) }
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: 45)
        try completeDiagnostic(settings: settings, content: content, today: today, in: context)
        try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                   calendar: TMUAFixtures.calendar, in: context)
        let tasks = try TMUAProgrammeService.tasks(settings: settings, in: context).filter(\.isActive)
        let official = Set(content.eligibleItems.filter { $0.category == .pastPaperStudyCopy }.map(\.stableId))
        XCTAssertTrue(tasks.contains { $0.questionID.map(official.contains) == true },
                      "official study copies are scheduled as ordinary auto-marked practice")
        XCTAssertFalse(tasks.contains { $0.activity == .resourcePractice }, "paper sessions are opt-in")
    }

    func testPaperSessionsFillOnlyEmptyDaysAndNeverCreateEvidence() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let today = TMUAFixtures.date(2026, 6, 1)
        // A small bank and a long window leave empty study days.
        let content = try TMUAFixtures.context(try TMUAFixtures.items(paperOne: 12, paperTwo: 12))
        TMUAContentStore.install(content)
        defer { TMUAContentStore.install(nil) }
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: 120, weeklyMinutes: 420)
        try completeDiagnostic(settings: settings, content: content, today: today, in: context)
        let calendar = TMUAFixtures.calendar
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                                   calendar: calendar, in: context)
        let before = try TMUAProgrammeService.tasks(settings: settings, in: context).filter(\.isActive)
        let emptyBefore = TMUAProgrammeService.contentSummary(programme: programme, tasks: before, seenStableIDs: [],
            availability: settings.publicAvailability, today: today, calendar: calendar).emptyStudyDays
        XCTAssertGreaterThan(emptyBefore, 0, "fixture leaves empty days")

        try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                   calendar: calendar, resourceSessions: true, in: context)
        let after = try TMUAProgrammeService.tasks(settings: settings, in: context).filter(\.isActive)
        let sessions = after.filter { $0.activity == .resourcePractice }
        let questionDays = Set(after.filter { $0.activity != .resourcePractice }.map { calendar.startOfDay(for: $0.scheduledDate) })
        XCTAssertFalse(sessions.isEmpty)
        for session in sessions {
            XCTAssertNil(session.questionID)
            XCTAssertFalse(questionDays.contains(calendar.startOfDay(for: session.scheduledDate)),
                           "a paper session never displaces question practice")
        }
        XCTAssertEqual(Set(sessions.map(\.sourceID)).count, sessions.count, "no paper is assigned twice")
        let summary = TMUAProgrammeService.contentSummary(programme: programme, tasks: after, seenStableIDs: [],
            availability: settings.publicAvailability, today: today, calendar: calendar)
        XCTAssertEqual(summary.paperSessionDays, sessions.count)
        XCTAssertLessThan(summary.emptyStudyDays, emptyBefore)

        let session = try XCTUnwrap(sessions.min { $0.scheduledDate < $1.scheduledDate })
        let attemptsBefore = try context.fetchCount(FetchDescriptor<TMUAPracticeAttempt>())
        try TMUAProgrammeService.completeResourceSession(session, outcome: .partial, correct: 11, questionCount: 20,
                                                         minutes: 75, settings: settings, in: context)
        XCTAssertNotNil(session.completedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TMUAResourceLog>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TMUAPracticeAttempt>()), attemptsBefore,
                       "a self-marked paper never becomes question-level evidence")
        XCTAssertThrowsError(try TMUAProgrammeService.completeResourceSession(session, outcome: .correct, correct: nil,
            questionCount: nil, minutes: nil, settings: settings, in: context))

        // A refresh keeps the completed session and does not offer that paper again.
        try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
                                                   calendar: calendar, resourceSessions: true, in: context)
        let refreshed = try TMUAProgrammeService.tasks(settings: settings, in: context)
        XCTAssertFalse(refreshed.contains { $0.isActive && $0.completedAt == nil && $0.sourceID == session.sourceID
                                            && $0.activity == .resourcePractice })
    }

    func testPaperSessionCandidatesPreferTMUAFormatAndSkipFinishedOrAutoMarkedPapers() throws {
        let sources = TMUAResourceCatalogue.build(manifest: try manifest, solutions: nil, registry: try registry,
                                                  distribution: .internal,
                                                  items: [studyCopy("tmua-2019-p1-q01", libraryID: "TMUA-2019-P1-Q01", paper: 1)],
                                                  isBundled: { _ in true })
        let candidates = TMUAProgrammeService.resourceCandidates(sources, completed: [])
        XCTAssertEqual(candidates.first?.kind, .officialTMUA)
        XCTAssertFalse(candidates.contains { $0.kind == .reference || $0.family == "CSAT" || $0.family == "BMO" })
        let firstMock = try XCTUnwrap(candidates.firstIndex { $0.kind == .independentMock })
        let firstMAT = try XCTUnwrap(candidates.firstIndex { $0.family == "MAT" })
        XCTAssertLessThan(firstMock, firstMAT)
        let skipped = try XCTUnwrap(candidates.first)
        XCTAssertFalse(TMUAProgrammeService.resourceCandidates(sources, completed: [skipped.id]).contains { $0.id == skipped.id })
    }

    // MARK: The bundled bank

    /// Runs against the bank this build bundled; skipped in builds without the private workspace.
    func testBundledStudyCopiesAreCompleteAndUnique() throws {
        guard let content = TMUAContentStore.context(), content.studyCopyItemCount > 0 else {
            throw XCTSkip("No official study copies bundled in this build")
        }
        let copies = content.eligibleItems.filter { $0.category == .pastPaperStudyCopy }
        var libraryIDs = Set<String>()
        for item in copies {
            XCTAssertTrue(item.stem.isEmpty && item.options.allSatisfy { $0.text.isEmpty }, item.versionKey)
            XCTAssertTrue(item.options.contains { $0.id == item.correctOptionId }, "key is one of the printed options")
            XCTAssertNotNil(item.keyProvenance, item.versionKey)
            XCTAssertNotNil(item.taxonomyProvenance, item.versionKey)
            XCTAssertNotNil(item.difficultyProvenance, item.versionKey)
            XCTAssertFalse([item.rights.inAppUse, item.rights.redistribution, item.rights.answerKey].contains(.cleared))
            let presentation = try XCTUnwrap(item.presentation)
            XCTAssertNotNil(TMUAPaperFiles.paperURL(presentation.document), "\(item.versionKey) paper is bundled")
            let solution = try XCTUnwrap(item.solutionReference)
            XCTAssertNotNil(TMUAPaperFiles.solutionURL(solution.document), "\(item.versionKey) solution is bundled")
            let libraryID = try XCTUnwrap(item.libraryQuestionID)
            XCTAssertTrue(libraryIDs.insert(libraryID).inserted, "\(libraryID) appears once")
        }
        XCTAssertFalse(libraryIDs.contains("TMUA-2020-P1-Q02"), "the question reused from 2019 Paper 2 appears once")
        print("BANK study copies \(copies.count), originals \(content.originalItemCount)")
    }

    func testBundledDiagnosticDrawsOfficialQuestionsFromSeveralPapers() throws {
        guard let content = TMUAContentStore.context(), content.studyCopyItemCount > 0 else {
            throw XCTSkip("No official study copies bundled in this build")
        }
        for paper in TMUAPaper.allCases {
            let chosen = try TMUADiagnosticSelector.select(paper: paper, count: 20, candidates: content.eligibleItems)
            let official = chosen.filter { $0.category == .pastPaperStudyCopy }
            let papers = Set(official.compactMap { $0.source.map { "\($0.year ?? 0)-\($0.paperNumber ?? 0)" } })
            XCTAssertGreaterThanOrEqual(papers.count, 3, "\(paper.title): official picks spread across papers")
            XCTAssertGreaterThan(chosen.count - official.count, 0, "\(paper.title): originals still included")
            XCTAssertEqual(Set(chosen.map(\.taxonomy.topic)).count, Set(chosen.map(\.taxonomy.topic)).count)
            print("MIX \(paper.title): \(official.count) official from \(papers.count) papers, \(chosen.count - official.count) original; topics \(Set(chosen.map(\.taxonomy.topic)).count); difficulty \(chosen.map(\.difficulty).sorted())")
        }
    }

    // MARK: Helpers

    private func studyCopy(_ id: String, libraryID: String, paper: Int, topic: String = "algebra",
                           strand: String = "polynomials", difficulty: Int = 4, cleared: Bool = false) -> TMUAContentItem {
        let parts = libraryID.split(separator: "-")
        let state: TMUARightsState = cleared ? .cleared : .notPermitted
        var item = TMUAContentItem(
            stableId: id, version: 1, paper: paper, category: .pastPaperStudyCopy,
            title: "TMUA \(parts[1]) Paper \(paper) · Q\(Int(parts[3].dropFirst()) ?? 0)", stem: "",
            options: ["A", "B", "C", "D", "E", "F"].map { TMUAOption(id: $0, text: "") },
            correctOptionId: "C", solution: "Official worked solution.",
            taxonomy: TMUATaxonomyMapping(topic: topic, strand: strand, skill: nil),
            difficulty: difficulty, estimatedMinutes: 4,
            source: TMUAContentSource(organisation: "UAT-UK (© UCLES)", examination: "TMUA", year: Int(parts[1]),
                                      paperNumber: paper, questionNumber: Int(parts[3].dropFirst()),
                                      url: "https://esat-tmua.ac.uk/tmua-preparation-materials/", attribution: nil),
            rights: TMUAContentRights(copyrightHolder: "UCLES", licence: "none", inAppUse: state, redistribution: state,
                                      commercialUse: state, answerKey: state, solution: state, attribution: "UAT-UK (© UCLES)"),
            review: TMUAContentReview(mathematical: cleared ? .humanApproved : .none, originality: .notApplicable,
                                      publication: cleared ? .approved : .notApproved, editorialStatus: "fixture"))
        item.presentation = TMUAItemPresentation(document: "fixture.pdf",
            regions: [.init(page: 0, x: 0, y: 0, width: 400, height: 300)])
        item.keyProvenance = "fixture"
        item.libraryQuestionID = libraryID
        return item
    }

    /// Official-style study copies spread over the syllabus, harder than the fixture originals.
    private func studyCopies(perPaper: Int) throws -> [TMUAContentItem] {
        try TMUAFixtures.items(paperOne: perPaper, paperTwo: perPaper, prefix: "oc").enumerated().map { offset, base in
            var item = studyCopy(base.stableId, libraryID: "TMUA-20\(17 + offset % 6)-P\(base.paper)-Q\(String(format: "%02d", offset % 20 + 1))",
                                 paper: base.paper, topic: base.taxonomy.topic, strand: base.taxonomy.strand,
                                 difficulty: [3, 4, 5, 3, 4][offset % 5])
            item = TMUAContentItem(stableId: item.stableId, version: 1, paper: item.paper, category: item.category,
                                   title: item.title, stem: item.stem, options: item.options,
                                   correctOptionId: item.correctOptionId, solution: item.solution,
                                   taxonomy: TMUATaxonomyMapping(topic: base.taxonomy.topic, strand: base.taxonomy.strand,
                                                                 skill: base.taxonomy.skill),
                                   difficulty: item.difficulty, estimatedMinutes: 4, source: item.source,
                                   rights: item.rights, review: item.review, presentation: item.presentation,
                                   keyProvenance: "fixture", libraryQuestionID: item.libraryQuestionID)
            return item
        }
    }

    private func completeDiagnostic(settings: AppSettings, content: TMUAContentContext, today: Date,
                                    in context: ModelContext) throws {
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content,
                                                        at: today, in: context)
        for section in snapshot.sections.sorted(by: { $0.paperRawValue < $1.paperRawValue }) {
            try TMUAFixtures.answerAndSubmit(section, snapshot: snapshot, at: today, in: context)
        }
    }
}
