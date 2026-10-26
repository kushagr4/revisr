import XCTest
@testable import revisr

@MainActor
final class TMUAContentAndSelectionTests: XCTestCase {
    func testDiagnosticLengthsHaveExactPaperCounts() {
        let expected: [TMUADiagnosticLength: (Int, Int)] = [
            .starter: (5, 5), .quick: (8, 7), .balanced: (10, 10), .comprehensive: (20, 20)
        ]
        for (length, counts) in expected {
            XCTAssertEqual(length.paperOneQuestions, counts.0, length.title)
            XCTAssertEqual(length.paperTwoQuestions, counts.1, length.title)
            XCTAssertEqual(length.totalQuestions, counts.0 + counts.1)
        }
        XCTAssertEqual(TMUADiagnosticLength.comprehensive.advisoryMinutes(for: .one), 75)
        XCTAssertEqual(TMUADiagnosticLength.starter.advisoryMinutes(for: .two), 19)
        XCTAssertTrue(TMUADiagnosticLength.comprehensive.isRecommended)
        XCTAssertFalse(TMUADiagnosticLength.balanced.isFullLengthSections)
        XCTAssertEqual(TMUADiagnosticLength.starter.expansionTargets, [.quick, .balanced, .comprehensive])
        XCTAssertEqual(TMUADiagnosticLength.starter.additionalQuestions(to: .quick, paper: .one), 3)
        XCTAssertEqual(TMUADiagnosticLength.starter.additionalQuestions(to: .quick, paper: .two), 2)
        XCTAssertTrue(TMUADiagnosticLength.comprehensive.expansionTargets.isEmpty)
    }

    func testEverySelectionHasExactCountsBothPapersAndNoDuplicates() throws {
        let content = try TMUAFixtures.standardContext()
        for length in TMUADiagnosticLength.allCases {
            let one = try TMUADiagnosticSelector.select(paper: .one, count: length.paperOneQuestions,
                                                        candidates: content.eligibleItems)
            let two = try TMUADiagnosticSelector.select(paper: .two, count: length.paperTwoQuestions,
                                                        candidates: content.eligibleItems, prior: one)
            XCTAssertEqual(one.count, length.paperOneQuestions, length.title)
            XCTAssertEqual(two.count, length.paperTwoQuestions, length.title)
            XCTAssertTrue(one.allSatisfy { $0.paper == 1 })
            XCTAssertTrue(two.allSatisfy { $0.paper == 2 })
            let ids = (one + two).map(\.stableId)
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate stable ID in \(length.title)")
            let topics = Set((one + two).map(\.taxonomy.topic))
            // Coverage-aware: each Paper 1 pick is a new topic until the 14
            // Section 1 topics run out, and Paper 2 adds all three reasoning topics.
            XCTAssertEqual(Set(one.map(\.taxonomy.topic)).count, min(length.paperOneQuestions, 14), length.title)
            XCTAssertGreaterThanOrEqual(topics.count, min(length.paperOneQuestions, 14) + 3, length.title)
            XCTAssertTrue(two.contains { ["logic", "proof", "errors-in-proofs"].contains($0.taxonomy.topic) })
        }
    }

    func testSelectionIsDeterministic() throws {
        let content = try TMUAFixtures.standardContext()
        let first = try TMUADiagnosticSelector.select(paper: .two, count: 10, candidates: content.eligibleItems)
        let second = try TMUADiagnosticSelector.select(paper: .two, count: 10,
                                                       candidates: content.eligibleItems.reversed())
        XCTAssertEqual(first.map(\.versionKey), second.map(\.versionKey))
    }

    func testDifficultyVarietyInFullSection() throws {
        let content = try TMUAFixtures.standardContext()
        let picks = try TMUADiagnosticSelector.select(paper: .one, count: 20, candidates: content.eligibleItems)
        XCTAssertGreaterThanOrEqual(Set(picks.map(\.difficulty)).count, 3)
        XCTAssertEqual(picks.map(\.difficulty), picks.map(\.difficulty).sorted(), "presented in difficulty order")
    }

    func testInsufficientContentIsRejectedNotPadded() throws {
        let content = try TMUAFixtures.context(TMUAFixtures.items(paperOne: 12, paperTwo: 6))
        XCTAssertThrowsError(try TMUADiagnosticSelector.select(paper: .two, count: 7, candidates: content.eligibleItems)) {
            XCTAssertEqual($0 as? TMUASelectionError, .insufficientContent(paper: .two, needed: 7, available: 6))
        }
        XCTAssertTrue(content.availability(for: .starter).isAvailable)
        XCTAssertEqual(content.availability(for: .quick), .insufficientContent(paper: .two, needed: 7, available: 6))
        XCTAssertNotNil(content.availability(for: .comprehensive).message)
    }

    func testExposedQuestionsAreNeverReselected() throws {
        let content = try TMUAFixtures.standardContext()
        let first = try TMUADiagnosticSelector.select(paper: .one, count: 5, candidates: content.eligibleItems)
        let more = try TMUADiagnosticSelector.select(paper: .one, count: 3, candidates: content.eligibleItems,
                                                     prior: first, excludedStableIDs: ["fx-p1-030"])
        XCTAssertTrue(Set(more.map(\.stableId)).isDisjoint(with: first.map(\.stableId)))
        XCTAssertFalse(more.contains { $0.stableId == "fx-p1-030" })
    }

    func testOnlyLatestVersionIsSelectable() throws {
        let v1 = TMUAFixtures.item("versioned", paper: 1, topic: "algebra", strand: "polynomials", version: 1)
        let v2 = TMUAFixtures.item("versioned", paper: 1, topic: "algebra", strand: "polynomials", version: 2)
        let bank = TMUAFixtures.bank([v1, v2])
        XCTAssertEqual(bank.latestItems.map(\.versionKey), ["versioned@v2"])
        XCTAssertNotNil(bank.item(versionKey: "versioned@v1"), "older versions stay resolvable for pinned drafts")
    }

    // MARK: Rights gates

    func testPublicGateRequiresEveryClearance() throws {
        let cleared = TMUAFixtures.item("ok", paper: 1, topic: "algebra", strand: "polynomials",
                                        category: .revisrOriginal, cleared: true)
        let pending = TMUAFixtures.item("pending", paper: 1, topic: "algebra", strand: "polynomials",
                                        category: .revisrOriginal, cleared: false)
        let fixture = TMUAFixtures.item("fixture", paper: 1, topic: "algebra", strand: "polynomials")
        XCTAssertTrue(TMUAContentPolicy.publicGateFailures(cleared).isEmpty)
        XCTAssertTrue(TMUAContentPolicy.publicGateFailures(pending).contains("Publication not approved"))
        XCTAssertTrue(TMUAContentPolicy.publicGateFailures(pending).contains("Originality review outstanding"))
        XCTAssertTrue(TMUAContentPolicy.publicGateFailures(fixture).contains("Development fixture"))

        let syllabus = try TMUAFixtures.syllabus
        let publicContext = TMUAContentContext(bank: TMUAFixtures.bank([cleared, pending, fixture], distribution: .public),
                                               syllabus: syllabus, allowsInternalContent: true)
        XCTAssertEqual(publicContext.eligibleItems.map(\.stableId), ["ok"])
        let internalContext = TMUAContentContext(bank: TMUAFixtures.bank([cleared, pending, fixture]),
                                                 syllabus: syllabus, allowsInternalContent: true)
        XCTAssertEqual(Set(internalContext.eligibleItems.map(\.stableId)), ["ok", "pending"],
                       "fixtures need explicit test opt-in even internally")
    }

    func testReleaseBuildTreatsInternalBankAsPublic() throws {
        let pending = TMUAFixtures.item("pending", paper: 1, topic: "algebra", strand: "polynomials",
                                        category: .revisrOriginal, cleared: false)
        let context = TMUAContentContext(bank: TMUAFixtures.bank([pending]), syllabus: try TMUAFixtures.syllabus,
                                         allowsInternalContent: false)
        XCTAssertEqual(context.distribution, .public)
        XCTAssertTrue(context.eligibleItems.isEmpty)
    }

    func testPublicOriginalOnlyDiagnosticIsBlockedNotSilentlySubstituted() throws {
        let originals = try TMUAFixtures.items(paperOne: 20, paperTwo: 20).map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              category: .revisrOriginal, cleared: true)
        }
        let publicContext = try TMUAFixtures.context(originals, distribution: .public)
        XCTAssertEqual(publicContext.sourceMix, .blocked)
        if case .blocked = publicContext.availability(for: .starter) {} else {
            XCTFail("public original-only diagnostic must be blocked")
        }
        let internalContext = try TMUAFixtures.context(originals)
        XCTAssertEqual(internalContext.sourceMix, .originalOnlyDevelopment)
        XCTAssertTrue(internalContext.availability(for: .starter).isAvailable)
        XCTAssertNotNil(internalContext.sourceMix.studentNotice)
    }

    func testMixedSourceSelectionUsesLicensedItemsWithAttributionAndSpread() throws {
        let content = try TMUAFixtures.context(TMUAFixtures.items(paperOne: 34, paperTwo: 30, licensedEvery: 3))
        XCTAssertEqual(content.sourceMix, .mixedAvailable)
        let one = try TMUADiagnosticSelector.select(paper: .one, count: 20, candidates: content.eligibleItems)
        let licensed = one.filter(\.category.isLicensedThirdParty)
        XCTAssertGreaterThan(licensed.count, 0)
        XCTAssertLessThan(licensed.count, one.count, "no forced all-licensed paper")
        XCTAssertTrue(licensed.allSatisfy { $0.source?.attribution != nil && $0.source?.url != nil })
        XCTAssertGreaterThan(Set(licensed.map(\.taxonomy.topic)).count, 1, "licensed items not concentrated in one topic")
        let note = TMUADiagnosticService.compositionNote(one, sourceMix: content.sourceMix)
        XCTAssertTrue(note.contains("licensed"), note)
    }

    func testBundledSyllabusCoversOfficialSpecificationSections() throws {
        let syllabus = try TMUAFixtures.syllabus
        let refs = Set(syllabus.topics.flatMap(\.strands).flatMap(\.specRefs))
        for ref in ["MM1.1", "MM2.4", "MM3.3", "MM4.6", "MM5.3", "MM6.3", "MM7.5", "MM8.2",
                    "M2.5", "M3.8", "M5.9", "M6.1", "M7.6", "Arg1", "Arg2", "Arg3", "Arg4",
                    "Prf1", "Prf2", "Prf3", "Prf4", "Prf5", "Err1", "Err2"] {
            XCTAssertTrue(refs.contains(ref), "missing specification reference \(ref)")
        }
        XCTAssertEqual(Set(syllabus.topics(for: .two).map(\.key)).subtracting(syllabus.topics(for: .one).map(\.key)),
                       ["logic", "proof", "errors-in-proofs"])
    }

    /// Runs against whatever bank this build bundled; skipped when no private
    /// workspace was available at build time.
    func testBundledBankIsStructurallyValidAndLabelledHonestly() throws {
        guard let content = TMUAContentStore.context(), !content.bank.items.isEmpty else {
            throw XCTSkip("No content bank bundled in this build")
        }
        for item in content.bank.items {
            XCTAssertTrue(TMUAContentPolicy.isStructurallyUsable(item, syllabus: content.syllabus), item.versionKey)
            XCTAssertNotEqual(item.category, .developmentFixture)
        }
        if content.distribution == .public {
            XCTAssertTrue(content.eligibleItems.allSatisfy { TMUAContentPolicy.publicGateFailures($0).isEmpty })
        }
        XCTAssertEqual(content.licensedItemCount, 0, "no licensed past/mock content has been cleared")
    }
}
