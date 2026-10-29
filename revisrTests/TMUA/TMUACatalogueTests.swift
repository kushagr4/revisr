import SwiftData
import XCTest
@testable import revisr

/// R4: the unified question catalogue. One identity per real question across the owner's collection
/// and the original Revisr bank; each entry says how it is presented and marked in this build; the
/// diagnostic draws exactly the automatically marked entries; reprints never count as fresh.
@MainActor
final class TMUACatalogueTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 29)
    private var calendar: Calendar { TMUAFixtures.calendar }

    private func bundled(_ distribution: TMUAContentDistribution) throws -> (TMUAContentContext, TMUAQuestionCatalogue) {
        guard let content = TMUAContentStore.context() else { throw XCTSkip("no bundled bank") }
        let context = TMUAContentContext(bank: content.bank, syllabus: content.syllabus,
                                         allowsInternalContent: distribution == .internal)
        let reconciliation = try XCTUnwrap(TMUACatalogueReconciliation.bundled(), "reconciliation file is bundled")
        let sources = TMUAResourceCatalogue.sources(distribution: context.distribution, items: context.eligibleItems)
        let catalogue = TMUAQuestionCatalogue.build(sources: sources, items: context.eligibleItems,
                                                    allVersions: context.bank.items, syllabus: context.syllabus,
                                                    reconciliation: reconciliation, distribution: context.distribution)
        return (context, catalogue)
    }

    // MARK: Identity

    func testEveryQuestionHasOneIdentityAndAliasesResolve() throws {
        let (_, catalogue) = try bundled(.internal)
        let ids = catalogue.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no question is listed twice")
        let aliases = catalogue.entries.flatMap(\.aliases)
        XCTAssertTrue(Set(aliases).isDisjoint(with: ids), "an alias is never also a separate entry")
        // The official question set twice, a mock's reprint of a MAT question and a Tyler reprint of
        // an official question all resolve to the first appearance.
        XCTAssertEqual(catalogue.entry("TMUA-2020-P1-Q02")?.id, "TMUA-2019-P2-Q02")
        XCTAssertEqual(catalogue.entry("BH-S3-P2-Q02")?.id, "MAT-2014-Q1I")
        let reprint = try XCTUnwrap(catalogue.entry("TYLER-LOGIC-Q06"))
        XCTAssertEqual(reprint.id, "TMUA-2020-P2-Q10")
        XCTAssertEqual(reprint.answerMode, .automatic, "a reprint of a marked question is marked too")
        XCTAssertTrue(reprint.alsoAppearsIn.contains { $0.contains("Q6") })
        // Adaptations stay separate questions, linked to their original.
        XCTAssertEqual(catalogue.entry("JZ-D-P2-Q17")?.variantOf, "TMUA-2019-P2-Q20")
        XCTAssertEqual(catalogue.entry("JZ-D-P2-Q17")?.id, "JZ-D-P2-Q17")
        // A study copy's item identity resolves to its paper question.
        XCTAssertEqual(catalogue.entry("tmua-2019-p1-q11")?.id, "TMUA-2019-P1-Q11")
    }

    func testDiagnosticCandidatesAreExactlyTheAutomaticallyMarkedEntries() throws {
        for distribution in [TMUAContentDistribution.internal, .public] {
            let (content, catalogue) = try bundled(distribution)
            let marked = catalogue.automatic.compactMap(\.item?.stableId)
            XCTAssertEqual(marked.count, catalogue.automatic.count, "every automatic entry has a bank item")
            XCTAssertEqual(Set(marked), Set(content.eligibleItems.map(\.stableId)),
                           "the selector's pool and the catalogue's marked questions are the same set")
            XCTAssertEqual(marked.count, content.eligibleItems.count, "no eligible item is two catalogue questions")
            XCTAssertTrue(catalogue.entries.filter { $0.item == nil }.allSatisfy { $0.answerMode != .automatic },
                          "no answer key is invented for a question Revisr holds no key for")
        }
    }

    func testLatestVersionIsUsedAndEarlierVersionsStayListed() throws {
        let (content, catalogue) = try bundled(.internal)
        let corrected = try XCTUnwrap(catalogue.entries.first { $0.versionKeys.count > 1 }, "R1 and R3 corrections exist")
        let latest = try XCTUnwrap(content.bank.latestItems.first { $0.stableId == corrected.item?.stableId })
        XCTAssertEqual(corrected.item?.versionKey, latest.versionKey)
        XCTAssertEqual(corrected.versionKeys.last, latest.versionKey)
        XCTAssertTrue(corrected.versionKeys.allSatisfy { content.bank.item(versionKey: $0) != nil },
                      "superseded versions stay resolvable for pinned diagnostics")
    }

    // MARK: Presentation, marking and rights by build

    func testInternalBuildPresentsPapersAndPublicBuildOnlyLinksThem() throws {
        let (_, internalCatalogue) = try bundled(.internal)
        let documents = internalCatalogue.entries.filter { $0.presentation == .document }
        XCTAssertFalse(documents.isEmpty)
        XCTAssertTrue(documents.allSatisfy { $0.rights == .personalStudyCopy && $0.answerMode != .automatic })
        XCTAssertTrue(documents.allSatisfy { entry in
            internalCatalogue.sources.first { $0.id == entry.sourceID }?.access == .studyCopy
        })
        let (_, publicCatalogue) = try bundled(.public)
        XCTAssertTrue(publicCatalogue.entries.allSatisfy { $0.presentation == .external && $0.rights == .linkedOnly },
                      "a public build with no approved questions presents nothing itself")
        XCTAssertTrue(publicCatalogue.entries.allSatisfy { !$0.hasSolution && $0.solutionPage == nil },
                      "no restricted solution is offered in a public build")
        XCTAssertTrue(publicCatalogue.entries.allSatisfy { $0.provider?.publicAccess == .listed && $0.sourceURL?.scheme == "https" })
        XCTAssertTrue(publicCatalogue.practicable.isEmpty)
    }

    func testPapersHeldOnlyInDriveOrAsSolutionsAreListedHonestly() throws {
        let (_, internalCatalogue) = try bundled(.internal)
        let specimen = try XCTUnwrap(internalCatalogue.entry("TSPEC-P2-Q01"))
        XCTAssertEqual(specimen.presentation, .external, "the paper is not bundled, so it is not shown as in-app")
        XCTAssertEqual(specimen.answerMode, .externalViewing)
        XCTAssertEqual(specimen.paperFit, .paper2)
        XCTAssertTrue(specimen.hasSolution, "the official worked solutions are bundled in development builds")
        XCTAssertNotNil(specimen.solutionResource)
        let source = try XCTUnwrap(internalCatalogue.sources.first { $0.id == "SUP-TSPEC-P2" })
        XCTAssertNotNil(source.holdingNote)
        XCTAssertEqual(internalCatalogue.entries(inSource: "SUP-TMUA-2023-P1").count, 20)
        let (_, publicCatalogue) = try bundled(.public)
        let linked = try XCTUnwrap(publicCatalogue.entry("TMUA-2023-P2-Q01"))
        XCTAssertFalse(linked.hasSolution)
        XCTAssertNil(publicCatalogue.sources.first { $0.id == "SUP-TMUA-2023-P2" }?.holdingNote,
                     "a public build never mentions the owner's Drive")
    }

    func testTopicsMapOnlyToSyllabusTopicsAndOfficialPapersKeepTheirPaper() throws {
        let (content, catalogue) = try bundled(.internal)
        let keys = Set(content.syllabus.topics.map(\.key))
        XCTAssertTrue(catalogue.entries.compactMap(\.topicKey).allSatisfy(keys.contains))
        let unmapped = Set(catalogue.entries.filter { $0.topicKey == nil }.compactMap(\.legacyTopic))
        XCTAssertTrue(unmapped.isSubset(of: ["Games, invariants & strategy", "Mixed / problem solving"]), "\(unmapped)")
        for entry in catalogue.entries where entry.provider?.kind == .officialTMUA {
            let label = catalogue.sources.first { $0.id == entry.sourceID }?.paperLabel ?? ""
            if label.contains("Paper 1") { XCTAssertEqual(entry.paperFit, .paper1, entry.id) }
            if label.contains("Paper 2") { XCTAssertEqual(entry.paperFit, .paper2, entry.id) }
        }
    }

    func testDifficultyIsAlwaysLabelledAsAnEstimate() throws {
        let (_, catalogue) = try bundled(.internal)
        for entry in catalogue.entries where entry.difficulty != nil {
            let provenance = entry.difficultyProvenance.lowercased()
            XCTAssertTrue(provenance.contains("estimat") || provenance.contains("not calibrated"),
                          "\(entry.id): \(entry.difficultyProvenance)")
        }
    }

    // MARK: Pure assembly

    func testReprintsMergeOnlyWhenTheirOriginalIsInTheBuild() throws {
        let syllabus = try TMUAFixtures.syllabus
        let registry = try XCTUnwrap(TMUAResourceRegistry.bundled())
        let official = try XCTUnwrap(registry.providers.first { $0.key == "uat-uk" })
        let mock = try XCTUnwrap(registry.providers.first { $0.key == "jzmaths" })
        func question(_ id: String) -> TMUAResourceQuestion {
            TMUAResourceQuestion(id: id, label: "1", page: 2, topic: "Integration", difficultyLabel: "Core",
                                 paperFit: "Paper 1", format: "Multiple choice", autoMarkedItemID: nil, solutionPage: nil)
        }
        func paper(_ id: String, _ provider: TMUAResourceProvider, _ questions: [String]) -> TMUAResourceSource {
            TMUAResourceSource(id: id, title: id, provider: provider, family: "x", paperLabel: "Paper 1", year: 2020,
                               questions: questions.map(question), solutions: [], access: .studyCopy, labelCorrection: nil)
        }
        let reconciliation = TMUACatalogueReconciliation(version: 1, reviewedOn: "2026-10-29",
            legacyTopicMap: ["Integration": "integration"],
            duplicates: [.init(question: "MOCK-Q1", canonical: "OFF-Q1", relation: .same, evidence: "fixture"),
                         .init(question: "MOCK-Q2", canonical: "OFF-Q2", relation: .adapted, evidence: "fixture")],
            documents: [])
        let both = TMUAQuestionCatalogue.build(
            sources: [paper("OFF", official, ["OFF-Q1", "OFF-Q2"]), paper("MOCK", mock, ["MOCK-Q1", "MOCK-Q2"])],
            items: [], allVersions: [], syllabus: syllabus, reconciliation: reconciliation, distribution: .internal)
        XCTAssertEqual(Set(both.entries.map(\.id)), ["OFF-Q1", "OFF-Q2", "MOCK-Q2"])
        XCTAssertEqual(both.entry("MOCK-Q1")?.id, "OFF-Q1")
        XCTAssertEqual(both.entry("MOCK-Q2")?.variantOf, "OFF-Q2")
        XCTAssertEqual(both.entry("OFF-Q1")?.topicKey, "integration")
        let mockOnly = TMUAQuestionCatalogue.build(sources: [paper("MOCK", mock, ["MOCK-Q1", "MOCK-Q2"])],
            items: [], allVersions: [], syllabus: syllabus, reconciliation: reconciliation, distribution: .internal)
        XCTAssertEqual(Set(mockOnly.entries.map(\.id)), ["MOCK-Q1", "MOCK-Q2"],
                       "with its original absent, a reprint stays available rather than disappearing")
    }

    // MARK: Diagnostics with approved sets

    func testApprovedMixedOriginalAndLicensedBankOffersTheMixedDiagnostic() throws {
        let originals = try TMUAFixtures.items(paperOne: 20, paperTwo: 20, prefix: "orig").map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              category: .revisrOriginal, cleared: true)
        }
        let licensed = try TMUAFixtures.items(paperOne: 20, paperTwo: 20, prefix: "lic").map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              category: .licensedPastPaper, cleared: true)
        }
        let content = try TMUAFixtures.context(originals + licensed, distribution: .public)
        XCTAssertEqual(content.sourceMix, .mixedAvailable)
        XCTAssertNil(content.sourceMix.studentNotice)
        let container = try TMUAFixtures.memoryContainer()
        let settings = try TMUAFixtures.profile(in: container.mainContext, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .comprehensive, content: content,
                                                        at: today, in: container.mainContext)
        let chosen = Set(snapshot.items.map(\.itemStableID))
        XCTAssertEqual(chosen.count, 40)
        let licensedChosen = licensed.filter { chosen.contains($0.stableId) }.count
        XCTAssertGreaterThan(licensedChosen, 0, "licensed questions take part")
        XCTAssertLessThan(licensedChosen, 40, "originals take part")
        for paper in TMUAPaper.allCases {
            XCTAssertEqual(snapshot.items.filter { $0.paperRawValue == paper.rawValue }.count, 20)
        }
    }

    // MARK: Worksheets

    func testWorksheetsUseSelfMarkedQuestionsByTopicPriorityWithoutRepeats() throws {
        let (content, catalogue) = try bundled(.internal)
        let order = TMUAProgrammeService.worksheetTopicOrder(report: nil, syllabus: content.syllabus)
        XCTAssertEqual(order.count, content.syllabus.topics.count)
        let sheets = TMUAProgrammeService.worksheetCandidates(catalogue.entries, topicOrder: order, excluded: [],
                                                              excludedSources: [], size: 6)
        XCTAssertFalse(sheets.isEmpty)
        let questions = sheets.flatMap(\.questions)
        XCTAssertEqual(Set(questions).count, questions.count, "a question is in at most one worksheet")
        for sheet in sheets {
            for id in sheet.questions {
                let entry = try XCTUnwrap(catalogue.entry(id))
                XCTAssertEqual(entry.topicKey, sheet.topic)
                XCTAssertEqual(entry.answerMode, .selfMarked, "worksheets need a solution to mark against")
                XCTAssertEqual(entry.presentation, .document)
            }
            let encoded = TMUAProgrammeService.worksheetSourceID(topic: sheet.topic, questions: sheet.questions)
            XCTAssertEqual(TMUAProgrammeService.worksheetQuestionIDs(encoded), sheet.questions)
            XCTAssertEqual(TMUAProgrammeService.worksheetTopic(encoded), sheet.topic)
        }
        let again = TMUAProgrammeService.worksheetCandidates(catalogue.entries, topicOrder: order,
                                                             excluded: Set(questions.prefix(10)), excludedSources: [], size: 6)
        XCTAssertTrue(Set(again.flatMap(\.questions)).isDisjoint(with: questions.prefix(10)), "recorded questions are not reissued")
    }

    /// Worksheet topics follow the diagnostic's own evidence: strong difficulty first, then possible
    /// improvement, then topics without enough evidence, and relative strengths last.
    func testWorksheetTopicsFollowDiagnosticEvidence() throws {
        let (content, _) = try bundled(.internal)
        let topics = content.syllabus.topics
        XCTAssertGreaterThan(topics.count, 6)
        func result(_ index: Int, _ level: DiagnosticEvidenceLevel) -> DiagnosticTopicResult {
            DiagnosticTopicResult(name: content.syllabus.topicTitle(topics[index].key), assessedCount: 2,
                                  unansweredCount: 0, unassessedCount: 0, level: level, explanation: "")
        }
        let report = TMUADiagnosticReport(length: .starter, initialLength: .starter, papers: [],
                                          topics: [result(0, .relativeStrength), result(3, .possibleImprovement),
                                                   result(5, .strongDifficulty)],
                                          skills: [], sampledTopicKeys: [], unassessedTopicKeys: [],
                                          sampledStrandKeys: [], compositionNote: "", wasExpanded: false)
        let order = TMUAProgrammeService.worksheetTopicOrder(report: report, syllabus: content.syllabus)
        XCTAssertEqual(order.count, topics.count)
        XCTAssertEqual(Array(order.prefix(2)), [topics[5].key, topics[3].key])
        XCTAssertEqual(order.last, topics[0].key)
        XCTAssertEqual(order[2], topics[1].key, "topics without evidence keep syllabus order")
    }

    // MARK: Reconciliation report (aggregates only, for docs/R4_GOOGLE_DRIVE_RECONCILIATION.md)

    func testPrintReconciliationCounts() throws {
        for distribution in [TMUAContentDistribution.internal, .public] {
            let (content, catalogue) = try bundled(distribution)
            let name = distribution.rawValue
            let entries = catalogue.entries
            func line(_ label: String, _ values: [String: Int]) {
                print("CATALOGUE \(name) \(label) " + values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            }
            print("CATALOGUE \(name) unique=\(entries.count) sources=\(catalogue.sources.count) mergedReprints=\(catalogue.aliases.count) variants=\(entries.filter { $0.variantOf != nil }.count) originals=\(entries.filter { $0.origin == .revisrOriginal }.count) collection=\(entries.filter { $0.origin == .collection }.count) versions=\(entries.reduce(0) { $0 + max(1, $1.versionKeys.count) }) eligibleItems=\(content.eligibleItems.count)")
            line("answerMode", Dictionary(grouping: entries, by: \.answerMode.rawValue).mapValues(\.count))
            line("presentation", Dictionary(grouping: entries, by: \.presentation.rawValue).mapValues(\.count))
            line("paper", Dictionary(grouping: entries, by: \.paperFit.rawValue).mapValues(\.count))
            line("withSolution", ["yes": entries.filter(\.hasSolution).count, "no": entries.filter { !$0.hasSolution }.count])
            line("provider", Dictionary(grouping: entries, by: { $0.provider?.key ?? "revisr" }).mapValues(\.count))
            line("topic", Dictionary(grouping: entries, by: { $0.topicKey ?? "unmapped" }).mapValues(\.count))
            line("difficulty", Dictionary(grouping: entries, by: { $0.difficulty.map(String.init) ?? "none" }).mapValues(\.count))
            line("format", Dictionary(grouping: entries, by: { $0.format ?? "unknown" }).mapValues(\.count))
            line("practicableByMode", Dictionary(grouping: catalogue.practicable, by: \.answerMode.rawValue).mapValues(\.count))
            let pool = catalogue.entries.filter { $0.presentation == .document && $0.answerMode == .selfMarked
                && $0.paperFit != .unclassified && $0.topicKey != nil && $0.format == "Multiple choice" }
            let papers = Set(TMUAProgrammeService.resourceCandidates(catalogue.sources, completed: []).map(\.id))
            // The planner keeps a paper offered whole for that session, so worksheets draw from the rest.
            let outsidePapers = pool.filter { !papers.contains($0.sourceID ?? "") }.count
            print("CATALOGUE \(name) worksheetPool=\(pool.count) worksheetPoolOutsideWholePapers=\(outsidePapers) paperCandidates=\(papers.count) questionSolutionPages=\(entries.filter { $0.solutionPage != nil }.count)")
        }
    }
}
