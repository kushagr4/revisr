import SwiftData
import XCTest
@testable import revisr

/// R2: student-specific deterministic selection (`tmua-selector-v3`), policy pinning for existing
/// diagnostics, and the difficulty and source-diversity objectives on the bundled bank.
@MainActor
final class TMUASelectionPolicyTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 27)

    /// A deterministic student identity, as `TMUADiagnosticService.diagnosticID` builds it.
    private func student(_ number: Int) -> String {
        let profile = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
        return TMUADiagnosticService.diagnosticID(profileID: profile)
    }

    /// One initial round, as the service selects it: Paper 1, then Paper 2 after it.
    private func round(_ length: TMUADiagnosticLength, _ content: TMUAContentContext, assessment: String,
                       policy: TMUASelectionPolicy = .v3) throws -> (one: [TMUAContentItem], two: [TMUAContentItem]) {
        let seed = TMUADiagnosticSelector.seed(assessmentID: assessment, policy: policy)
        let one = try TMUADiagnosticSelector.select(paper: .one, count: length.paperOneQuestions,
            candidates: content.eligibleItems, policy: policy, seed: seed)
        let two = try TMUADiagnosticSelector.select(paper: .two, count: length.paperTwoQuestions,
            candidates: content.eligibleItems, prior: one, policy: policy, seed: seed)
        return (one, two)
    }

    private func ordered(_ snapshot: TMUADiagnosticSnapshot, round: Int) -> [String] {
        snapshot.sections.filter { $0.round == round }.sorted { $0.paperRawValue < $1.paperRawValue }
            .flatMap { snapshot.items(in: $0) }.map(\.versionKey)
    }

    // MARK: Policy versions and determinism

    func testPolicyVersionsAndRecordedPolicies() {
        XCTAssertEqual(TMUASelectionPolicy.current, .v3)
        XCTAssertEqual(TMUADiagnosticSelector.version, "tmua-selector-v3")
        XCTAssertEqual(TMUASelectionPolicy(recorded: "tmua-selector-v2"), .v2)
        XCTAssertEqual(TMUASelectionPolicy(recorded: "tmua-selector-v3"), .v3)
        XCTAssertEqual(TMUASelectionPolicy(recorded: "tmua-selector-v1"), .v2,
                       "retired v1 diagnostics already expanded with v2 rules before R2")
    }

    func testSameAssessmentAndPolicyAlwaysGiveTheSameSelection() throws {
        let content = try TMUAFixtures.standardContext()
        let seed = TMUADiagnosticSelector.seed(assessmentID: student(1), policy: .v3)
        XCTAssertEqual(seed, TMUADiagnosticSelector.seed(assessmentID: student(1), policy: .v3))
        XCTAssertNotEqual(seed, TMUADiagnosticSelector.seed(assessmentID: student(2), policy: .v3))
        XCTAssertNotEqual(seed, TMUADiagnosticSelector.seed(assessmentID: student(1), policy: .v2),
                          "a new policy starts a new sequence")
        let first = try TMUADiagnosticSelector.select(paper: .two, count: 10, candidates: content.eligibleItems,
                                                      seed: seed)
        let again = try TMUADiagnosticSelector.select(paper: .two, count: 10,
                                                      candidates: content.eligibleItems.reversed(), seed: seed)
        XCTAssertEqual(first.map(\.versionKey), again.map(\.versionKey), "independent of candidate order")
    }

    /// v2 is frozen: diagnostics created under it reselect exactly as before R2, whatever the seed.
    func testV2SelectionIsFrozenAndIgnoresTheSeed() throws {
        let content = try TMUAFixtures.standardContext()
        let one = try TMUADiagnosticSelector.select(paper: .one, count: 10, candidates: content.eligibleItems,
                                                    policy: .v2)
        let two = try TMUADiagnosticSelector.select(paper: .two, count: 10, candidates: content.eligibleItems,
                                                    prior: one, policy: .v2)
        let seeded = try TMUADiagnosticSelector.select(paper: .one, count: 10, candidates: content.eligibleItems,
                                                       policy: .v2, seed: 0xDEAD_BEEF)
        XCTAssertEqual(seeded.map(\.versionKey), one.map(\.versionKey))
        XCTAssertEqual(one.map(\.stableId), Self.goldenV2PaperOne)
        XCTAssertEqual(two.map(\.stableId), Self.goldenV2PaperTwo)
    }

    /// v3's own expected selection for one student on the standard fixtures. A deliberate change
    /// to v3 needs a new policy version, not a new golden list.
    func testV3SelectionMatchesItsGoldenFixture() throws {
        let content = try TMUAFixtures.standardContext()
        let (one, two) = try round(.balanced, content, assessment: student(7))
        XCTAssertEqual(one.map(\.stableId), Self.goldenV3PaperOne)
        XCTAssertEqual(two.map(\.stableId), Self.goldenV3PaperTwo)
    }

    // MARK: Pinning through the service

    func testNewDiagnosticRecordsV3AndIsReproducibleFromItsIdentity() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: today, in: context)
        XCTAssertEqual(snapshot.diagnostic.selectorVersion, "tmua-selector-v3")
        XCTAssertEqual(snapshot.diagnostic.selectionPolicy, .v3)
        let expected = try round(.balanced, content, assessment: snapshot.diagnostic.stableID)
        XCTAssertEqual(ordered(snapshot, round: 0), (expected.one + expected.two).map(\.versionKey))
    }

    func testExistingV2DiagnosticKeepsItsPolicyAndQuestionsWhenExpanded() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let initial = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content,
                                                       policy: .v2, at: today, in: context)
        XCTAssertEqual(initial.diagnostic.selectorVersion, "tmua-selector-v2")
        let v2 = try round(.starter, content, assessment: initial.diagnostic.stableID, policy: .v2)
        XCTAssertEqual(ordered(initial, round: 0), (v2.one + v2.two).map(\.versionKey))

        try TMUAFixtures.completeAll(initial, at: today, in: context)
        let before = initial.items.map { ($0.stableID, $0.selectedOptionID, $0.markingRawValue, $0.contentSnapshot) }
        let expanded = try TMUADiagnosticService.expand(initial, to: .balanced, settings: settings,
                                                        content: content, in: context)
        XCTAssertEqual(expanded.diagnostic.selectorVersion, "tmua-selector-v2", "the policy is never upgraded")
        let prior = v2.one + v2.two
        let exposed = Set(prior.map(\.stableId))
        let addOne = try TMUADiagnosticSelector.select(paper: .one, count: 5, candidates: content.eligibleItems,
                                                       prior: prior, excludedStableIDs: exposed, policy: .v2)
        let addTwo = try TMUADiagnosticSelector.select(paper: .two, count: 5, candidates: content.eligibleItems,
                                                       prior: prior + addOne, excludedStableIDs: exposed, policy: .v2)
        XCTAssertEqual(ordered(expanded, round: 1), (addOne + addTwo).map(\.versionKey),
                       "added questions follow the recorded v2 rules")
        for (id, option, marking, data) in before {
            let item = try XCTUnwrap(expanded.items.first { $0.stableID == id })
            XCTAssertEqual(item.selectedOptionID, option)
            XCTAssertEqual(item.markingRawValue, marking)
            XCTAssertEqual(item.contentSnapshot, data)
        }
    }

    func testRelaunchReproducesOrderSnapshotsAndPolicy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Revisr-R2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")
        let content = try TMUAFixtures.standardContext()
        var saved: [(String, Data)] = []
        do {
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try TMUAFixtures.profile(in: context, today: today)
            let snapshot = try TMUADiagnosticService.create(settings: settings, length: .comprehensive,
                                                            content: content, at: today, in: context)
            saved = snapshot.sections.sorted { $0.paperRawValue < $1.paperRawValue }
                .flatMap { snapshot.items(in: $0) }.map { ($0.versionKey, $0.contentSnapshot) }
        }
        let reopened = try AppContainer.make(storeURL: store)
        let context = reopened.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        let snapshot = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
        let again = snapshot.sections.sorted { $0.paperRawValue < $1.paperRawValue }
            .flatMap { snapshot.items(in: $0) }.map { ($0.versionKey, $0.contentSnapshot) }
        XCTAssertEqual(again.map(\.0), saved.map(\.0), "same questions in the same order")
        XCTAssertEqual(again.map(\.1), saved.map(\.1), "same pinned content")
        XCTAssertEqual(snapshot.diagnostic.selectorVersion, "tmua-selector-v3")
    }

    func testNewerContentVersionLeavesAPinnedDiagnosticUnchanged() throws {
        let items = try TMUAFixtures.items(paperOne: 40, paperTwo: 40)
        let content = try TMUAFixtures.context(items)
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let initial = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content,
                                                       at: today, in: context)
        let pinned = try XCTUnwrap(initial.items.first)
        let original = try XCTUnwrap(pinned.content)
        // The bank later publishes version 2 of that question with a different key.
        let revised = TMUAFixtures.item(original.stableId, paper: original.paper, topic: original.taxonomy.topic,
                                        strand: original.taxonomy.strand, difficulty: original.difficulty,
                                        version: 2, key: original.correctOptionId == "B" ? "C" : "B")
        let updated = try TMUAFixtures.context(items + [revised])
        XCTAssertTrue(updated.eligibleItems.contains { $0.versionKey == revised.versionKey })

        try TMUAFixtures.completeAll(initial, at: today, in: context)
        let expanded = try TMUADiagnosticService.expand(initial, to: .quick, settings: settings,
                                                        content: updated, in: context)
        let stillPinned = try XCTUnwrap(expanded.items.first { $0.stableID == pinned.stableID })
        XCTAssertEqual(stillPinned.versionKey, original.versionKey)
        XCTAssertEqual(stillPinned.content?.correctOptionId, original.correctOptionId)
        XCTAssertEqual(expanded.items.filter { $0.itemStableID == original.stableId }.count, 1,
                       "the revised version is not added as new evidence")
    }

    // MARK: The bundled bank

    private func bundled() throws -> TMUAContentContext {
        guard let content = TMUAContentStore.context(), content.studyCopyItemCount > 0 else {
            throw XCTSkip("No official study copies bundled in this build")
        }
        return content
    }

    private static let students = 0..<24

    func testStudentsReceiveMeaningfullyDifferentSetsWithoutLosingCoverage() throws {
        let content = try bundled()
        for length in TMUADiagnosticLength.allCases {
            let v2 = try round(length, content, assessment: "", policy: .v2)
            let v2Topics = Set((v2.one + v2.two).map(\.taxonomy.topic)).count
            var sets: [Set<String>] = []
            for number in Self.students {
                let (one, two) = try round(length, content, assessment: student(number))
                let all = one + two
                XCTAssertEqual(one.count, length.paperOneQuestions)
                XCTAssertEqual(two.count, length.paperTwoQuestions)
                XCTAssertTrue(one.allSatisfy { $0.paper == 1 } && two.allSatisfy { $0.paper == 2 })
                XCTAssertEqual(Set(all.map(\.stableId)).count, all.count, "no question twice")
                XCTAssertEqual(Set(one.map(\.taxonomy.topic)).count, min(one.count, 14), "Paper 1 topics")
                XCTAssertGreaterThanOrEqual(Set(all.map(\.taxonomy.topic)).count, v2Topics, "coverage never below v2")
                XCTAssertTrue(all.contains { $0.category == .revisrOriginal }, "originals included")
                XCTAssertTrue(all.contains { $0.category.isPastOrMock }, "official questions included")
                XCTAssertTrue(all.allSatisfy { content.eligibleItems.contains($0) }, "only eligible questions")
                sets.append(Set(all.map(\.stableId)))
            }
            XCTAssertEqual(Set(sets).count, sets.count, "\(length.title): every student gets a different set")
            var overlaps: [Double] = []
            for (index, lhs) in sets.enumerated() {
                for rhs in sets[(index + 1)...] {
                    overlaps.append(Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count))
                }
            }
            let mean = overlaps.reduce(0, +) / Double(overlaps.count)
            XCTAssertLessThan(mean, 0.35, "\(length.title): sets differ substantially, not by one question")
            print(String(format: "VARIETY %@: %d students, %d distinct sets, mean overlap %.2f, %d questions used",
                         length.title, sets.count, Set(sets).count, mean, sets.reduce(Set<String>()) { $0.union($1) }.count))
        }
    }

    /// Source spread is a soft objective: it decides only between questions of comparable coverage
    /// and difficulty, so a section may use fewer papers than the ideal when spreading would cost
    /// coverage or difficulty balance. No paper may dominate a section, and under-spread sections
    /// must stay rare.
    func testOfficialQuestionsSpreadAcrossPapersAndYears() throws {
        let content = try bundled()
        var sections = 0
        var underSpread = 0
        for length in TMUADiagnosticLength.allCases {
            for number in Self.students {
                let (one, two) = try round(length, content, assessment: student(number))
                for picks in [one, two] {
                    let section = picks[0].paper
                    let official = picks.filter(\.category.isPastOrMock)
                    guard !official.isEmpty else { continue }
                    let available = Set(content.eligibleItems.filter { $0.paper == section && $0.category.isPastOrMock }
                        .compactMap(TMUADiagnosticSelector.sourcePaperKey)).count
                    let perPaper = Dictionary(grouping: official, by: { TMUADiagnosticSelector.sourcePaperKey($0) ?? "" })
                    let fairShare = (official.count + available - 1) / available
                    XCTAssertLessThanOrEqual(perPaper.values.map(\.count).max() ?? 0, fairShare + 1,
                                             "\(length.title) P\(section): no paper dominates")
                    sections += 1
                    if perPaper.count < min(official.count, available) - 1 { underSpread += 1 }
                }
                let years = Set((one + two).compactMap(TMUADiagnosticSelector.sourceYearKey))
                let officialCount = (one + two).filter(\.category.isPastOrMock).count
                XCTAssertGreaterThanOrEqual(years.count, min(4, officialCount), "\(length.title): several sitting years")
            }
        }
        XCTAssertLessThanOrEqual(underSpread * 20, sections, "at most 5% of sections use fewer papers than they could")
        print("SPREAD \(underSpread) of \(sections) sections use fewer papers than they could")
    }

    /// The profiles are soft: coverage comes first, so one student's section can fall short of its
    /// target. Every section still has a demanding question, the average meets the target within
    /// one question, and no section is padded with easy questions.
    func testDifficultyFollowsTheProfileForEachLength() throws {
        let content = try bundled()
        for length in TMUADiagnosticLength.allCases {
            var harder: [TMUAPaper: [Int]] = [:]
            for number in Self.students {
                let (one, two) = try round(length, content, assessment: student(number))
                for (paper, picks) in [(TMUAPaper.one, one), (.two, two)] {
                    let profile = TMUADiagnosticSelector.difficultyProfile(sectionSize: picks.count)
                    let demanding = picks.filter { $0.difficulty >= 4 }.count
                    let easier = picks.filter { $0.difficulty <= 2 }.count
                    let label = "\(length.title) \(paper.title)"
                    XCTAssertGreaterThanOrEqual(demanding, 1, "\(label): a demanding question in every section")
                    XCTAssertLessThanOrEqual(easier, TMUADiagnosticSelector.percent(profile.easier, of: picks.count) + 1,
                                             "\(label): not padded with easy questions")
                    XCTAssertEqual(picks.map(\.difficulty), picks.map(\.difficulty).sorted(), "presented easiest first")
                    harder[paper, default: []].append(demanding)
                }
            }
            for (paper, counts) in harder {
                let size = length.questions(for: paper)
                let target = TMUADiagnosticSelector.percent(TMUADiagnosticSelector.difficultyProfile(sectionSize: size).harder,
                                                            of: size)
                let mean = Double(counts.reduce(0, +)) / Double(counts.count)
                XCTAssertGreaterThanOrEqual(mean, Double(target) - 1, "\(length.title) \(paper.title): demanding share")
                print(String(format: "DIFFICULTY %@ %@: level 4+ per student mean %.2f (target %d), range %d-%d",
                             length.title, paper.title, mean, target, counts.min() ?? 0, counts.max() ?? 0))
            }
        }
    }

    func testEveryExpansionPathAddsUnseenQuestionsUnderV3() throws {
        let content = try bundled()
        let pairs: [(TMUADiagnosticLength, TMUADiagnosticLength)] = [
            (.starter, .quick), (.starter, .balanced), (.starter, .comprehensive),
            (.quick, .balanced), (.quick, .comprehensive), (.balanced, .comprehensive)
        ]
        for (from, to) in pairs {
            for number in Self.students.prefix(6) {
                let assessment = student(number)
                let seed = TMUADiagnosticSelector.seed(assessmentID: assessment, policy: .v3)
                let initial = try round(from, content, assessment: assessment)
                let prior = initial.one + initial.two
                let exposed = Set(prior.map(\.stableId))
                let addOne = try TMUADiagnosticSelector.select(paper: .one, count: from.additionalQuestions(to: to, paper: .one),
                    candidates: content.eligibleItems, prior: prior, excludedStableIDs: exposed, seed: seed)
                let addTwo = try TMUADiagnosticSelector.select(paper: .two, count: from.additionalQuestions(to: to, paper: .two),
                    candidates: content.eligibleItems, prior: prior + addOne, excludedStableIDs: exposed, seed: seed)
                let all = prior + addOne + addTwo
                XCTAssertEqual(all.count, to.totalQuestions)
                XCTAssertEqual(Set(all.map(\.stableId)).count, all.count, "\(from.title)→\(to.title): no repeats")
                XCTAssertEqual(all.filter { $0.paper == 1 }.count, to.paperOneQuestions)
                XCTAssertGreaterThanOrEqual(Set(all.map(\.taxonomy.topic)).count, Set(prior.map(\.taxonomy.topic)).count)
                XCTAssertGreaterThan(Set(all.map(\.taxonomy.strand)).count, Set(prior.map(\.taxonomy.strand)).count,
                                     "\(from.title)→\(to.title): added questions reach new strands")
            }
        }
    }

    /// Composition per student for the R2 documents (identities only, no keys or question text).
    func testSelectionAuditOnBundledBank() throws {
        let content = try bundled()
        for policy in TMUASelectionPolicy.allCases {
            for length in TMUADiagnosticLength.allCases {
                for number in (policy == .v2 ? 0..<1 : Self.students) {
                    let (one, two) = try round(length, content, assessment: policy == .v2 ? "" : student(number),
                                               policy: policy)
                    func describe(_ picks: [TMUAContentItem]) -> String {
                        let official = picks.filter(\.category.isPastOrMock)
                        let papers = Set(official.compactMap(TMUADiagnosticSelector.sourcePaperKey)).count
                        let maxPaper = Dictionary(grouping: official) { TMUADiagnosticSelector.sourcePaperKey($0) ?? "" }
                            .values.map(\.count).max() ?? 0
                        let skills = Set(picks.compactMap(\.taxonomy.skill)).count
                        return "official=\(official.count) original=\(picks.count - official.count) papers=\(papers) "
                            + "maxPerPaper=\(maxPaper) topics=\(Set(picks.map(\.taxonomy.topic)).count) skills=\(skills) "
                            + "levels=\(picks.map(\.difficulty).map(String.init).joined(separator: ","))"
                    }
                    let all = one + two
                    print("SELECTION \(policy.rawValue) \(length.title) student=\(number) | P1 \(describe(one)) | P2 \(describe(two)) "
                        + "| years=\(Set(all.compactMap(TMUADiagnosticSelector.sourceYearKey)).count) "
                        + "topics=\(Set(all.map(\.taxonomy.topic)).count) strands=\(Set(all.map(\.taxonomy.strand)).count) "
                        + "| ids=\(all.map(\.stableId).joined(separator: " "))")
                }
            }
        }
    }

    // MARK: Golden fixtures (standard fixtures, Balanced)

    static let goldenV2PaperOne = ["fx-p1-025", "fx-p1-019", "fx-p1-004", "fx-p1-014", "fx-p1-002", "fx-p1-016", "fx-p1-026", "fx-p1-007", "fx-p1-006", "fx-p1-023"]
    static let goldenV2PaperTwo = ["fx-p2-019", "fx-p2-000", "fx-p2-009", "fx-p2-014", "fx-p2-029", "fx-p2-001", "fx-p2-007", "fx-p2-017", "fx-p2-021", "fx-p2-026"]
    static let goldenV3PaperOne = ["fx-p1-030", "fx-p1-024", "fx-p1-026", "fx-p1-022", "fx-p1-032", "fx-p1-002", "fx-p1-017", "fx-p1-033", "fx-p1-003", "fx-p1-013"]
    static let goldenV3PaperTwo = ["fx-p2-004", "fx-p2-000", "fx-p2-015", "fx-p2-025", "fx-p2-016", "fx-p2-027", "fx-p2-008", "fx-p2-018", "fx-p2-023", "fx-p2-013"]
}
