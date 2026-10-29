import SwiftData
import XCTest
@testable import revisr

/// R3: what a public build may show. Only items carrying an approved-content manifest record
/// (set by the build assembler) are eligible, plans assign only eligible material, and an
/// empty public bank produces honest unavailable states instead of padding.
@MainActor
final class TMUAPublicContentTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 28)
    private var calendar: Calendar { TMUAFixtures.calendar }

    // MARK: Approval gate

    func testPublicBuildNeedsTheManifestRecordEvenWhenFieldsClaimApproval() throws {
        var claimed = TMUAFixtures.item("claimed", paper: 1, topic: "algebra", strand: "polynomials",
                                        category: .revisrOriginal, cleared: true)
        claimed.approval = nil
        let approved = TMUAFixtures.item("approved", paper: 1, topic: "algebra", strand: "polynomials",
                                         category: .revisrOriginal, cleared: true)
        XCTAssertTrue(TMUAContentPolicy.publicGateFailures(claimed).isEmpty, "its own fields claim every clearance")
        XCTAssertEqual(TMUAContentPolicy.approvalFailures(claimed), ["Not in the approved-content manifest"])
        let syllabus = try TMUAFixtures.syllabus
        let publicContext = TMUAContentContext(bank: TMUAFixtures.bank([claimed, approved], distribution: .public),
                                               syllabus: syllabus, allowsInternalContent: true)
        XCTAssertEqual(publicContext.eligibleItems.map(\.stableId), ["approved"])
        let internalContext = TMUAContentContext(bank: TMUAFixtures.bank([claimed, approved]),
                                                 syllabus: syllabus, allowsInternalContent: true)
        XCTAssertEqual(internalContext.eligibleItems.count, 2, "development builds keep every draft")
    }

    func testApprovalRecordMustNameThePolicyContentAndGrant() throws {
        var item = TMUAFixtures.item("x", paper: 1, topic: "algebra", strand: "polynomials",
                                     category: .licensedPastPaper, cleared: true)
        XCTAssertTrue(TMUAContentPolicy.approvalFailures(item).isEmpty)
        item.approval = TMUAApprovalRecord(manifestRevision: 1, policyVersion: "something-else", approvedOn: nil,
                                           contentHash: "short", stages: [], rightsGrant: nil)
        let failures = TMUAContentPolicy.approvalFailures(item)
        XCTAssertEqual(failures.count, 3, failures.joined(separator: "; "))
    }

    func testPublicBankDecodesApprovalAndManifestRevision() throws {
        let json = """
        {"schemaVersion":1,"bankVersion":"b","distribution":"public","taxonomyVersion":"\(TMUASyllabus.currentVersion)",
         "contentPolicyVersion":"\(TMUAContentPolicy.version)","approvedManifestRevision":3,"excludedItemCount":0,"items":[]}
        """
        let bank = try JSONDecoder().decode(TMUAContentBank.self, from: Data(json.utf8))
        XCTAssertEqual(bank.approvedManifestRevision, 3)
        let older = json.replacingOccurrences(of: "\"approvedManifestRevision\":3,", with: "")
        XCTAssertNil(try JSONDecoder().decode(TMUAContentBank.self, from: Data(older.utf8)).approvedManifestRevision,
                     "banks from before R3 still decode")
    }

    // MARK: Honest unavailable states

    func testEmptyPublicBankIsUnavailableAtEveryLengthWithAnHonestReason() throws {
        let context = try TMUAFixtures.context([], distribution: .public)
        XCTAssertEqual(context.sourceMix, .blocked)
        for length in TMUADiagnosticLength.allCases {
            guard case let .blocked(reason) = context.availability(for: length) else {
                return XCTFail("\(length) must be unavailable with no approved questions")
            }
            XCTAssertTrue(reason.contains("independent review"), reason)
            XCTAssertTrue(reason.contains("publishers"), "points to the external library: \(reason)")
        }
    }

    func testOriginalOnlyPublicDiagnosticNeedsTheProductDecisionAndEnoughQuestions() throws {
        let originals = try TMUAFixtures.items(paperOne: 12, paperTwo: 12).map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              category: .revisrOriginal, cleared: true)
        }
        let bank = TMUAFixtures.bank(originals, distribution: .public)
        let syllabus = try TMUAFixtures.syllabus
        XCTAssertTrue(TMUAContentPolicy.publicAllowsOriginalOnlyDiagnostic, "the owner's R4 product decision")
        let withheld = TMUAContentContext(bank: bank, syllabus: syllabus, allowsInternalContent: true,
                                          allowsOriginalOnlyPublicDiagnostic: false)
        XCTAssertEqual(withheld.sourceMix, .blocked, "the switch still withholds it when turned off")
        let decided = TMUAContentContext(bank: bank, syllabus: syllabus, allowsInternalContent: true)
        XCTAssertEqual(decided.sourceMix, .originalOnlyApproved)
        XCTAssertTrue(decided.availability(for: .starter).isAvailable)
        XCTAssertTrue(decided.availability(for: .balanced).isAvailable)
        XCTAssertEqual(decided.availability(for: .comprehensive),
                       .insufficientContent(paper: .one, needed: 20, available: 12),
                       "a length the approved set cannot fill stays unavailable, with the exact gap")
    }

    func testReleaseBuildOfTheBundledBankHasNoPublicQuestionsToday() throws {
        guard let bundled = TMUAContentStore.context() else { throw XCTSkip("no bundled bank") }
        let asPublic = TMUAContentContext(bank: bundled.bank, syllabus: bundled.syllabus, allowsInternalContent: false)
        XCTAssertEqual(asPublic.distribution, .public)
        XCTAssertEqual(asPublic.eligibleItems.count, 0, "nothing has completed human review and rights clearance")
        XCTAssertFalse(asPublic.availability(for: .starter).isAvailable)
        let sources = TMUAResourceCatalogue.sources(distribution: .public, items: asPublic.eligibleItems)
        XCTAssertFalse(sources.isEmpty, "the external library stays available")
        XCTAssertTrue(sources.allSatisfy { $0.access == .providerLink && $0.provider.link?.scheme == "https" })
        XCTAssertTrue(sources.allSatisfy { $0.autoMarkedCount == 0 && $0.solutions.isEmpty })
    }

    func testOtherPreparationSitesAreCreditedLinksWithoutPapers() throws {
        let registry = try XCTUnwrap(TMUAResourceRegistry.bundled())
        let sites = TMUAResourceCatalogue.linkedProviders(registry)
        XCTAssertEqual(Set(sites.map(\.key)), ["jzmaths", "tmua-co-uk", "tmua-euclid", "tyler-tutoring"])
        XCTAssertTrue(sites.allSatisfy { $0.link?.scheme == "https" && $0.permission == "none" })
        let restricted = Set(registry.providers.filter { $0.publicAccess == .restricted }.map(\.key))
        XCTAssertTrue(restricted.isDisjoint(with: sites.map(\.key)), "restricted providers are never linked")
        XCTAssertTrue(restricted.contains("miomath") && restricted.contains("yotta"))
        let sources = TMUAResourceCatalogue.sources(distribution: .public, items: [])
        XCTAssertFalse(sources.contains { sites.map(\.key).contains($0.provider.key) },
                       "a linked site's papers are not listed individually")
    }

    // MARK: Plans use only what the build may show

    func testPublicPlanAssignsOnlyApprovedQuestionsAndLinkedPapers() throws {
        let approved = try TMUAFixtures.items(paperOne: 34, paperTwo: 30, licensedEvery: 3)
        let drafts = try TMUAFixtures.items(paperOne: 15, paperTwo: 15, prefix: "draft").map {
            TMUAFixtures.item($0.stableId, paper: $0.paper, topic: $0.taxonomy.topic, strand: $0.taxonomy.strand,
                              category: .revisrOriginal, cleared: false)
        }
        let content = try TMUAFixtures.context(approved + drafts, distribution: .public)
        let draftIDs = Set(drafts.map(\.stableId))
        XCTAssertTrue(Set(content.eligibleItems.map(\.stableId)).isDisjoint(with: draftIDs))
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: 90, weeklyMinutes: 720)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: today, in: context)
        XCTAssertTrue(Set(snapshot.items.map(\.itemStableID)).isDisjoint(with: draftIDs))
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
            calendar: calendar, resourceSessions: true, in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        let eligible = Set(content.eligibleItems.map(\.stableId))
        XCTAssertTrue(tasks.compactMap(\.questionID).allSatisfy { eligible.contains($0) },
                      "no plan task points at a question this build cannot show")
        let sources = Dictionary(TMUAResourceCatalogue.sources(distribution: .public, items: content.eligibleItems)
            .map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in tasks where task.activity == .resourcePractice {
            let source = try XCTUnwrap(sources[task.sourceID], "a paper session names a listed source")
            XCTAssertEqual(source.access, .providerLink, "public paper sessions open on the publisher's site")
            XCTAssertTrue(task.reason.contains(source.provider.name), task.reason)
        }
    }

    // MARK: Capacity of a public build (audit, prints CAPACITY lines)

    /// What a public build could support if a set of the bundled originals passed every review:
    /// all current originals, and the private review queue's first waves when that file is
    /// present. Approvals here are stamped in memory only; nothing is approved.
    func testPublicCapacityIfOriginalsPassedReview() throws {
        guard let bundled = TMUAContentStore.context(), bundled.originalItemCount > 0 else {
            throw XCTSkip("no original drafts bundled in this build")
        }
        let originals = bundled.bank.latestItems.filter { $0.category == .revisrOriginal }
        var scenarios: [(String, [TMUAContentItem])] = [("all-originals", originals)]
        if let waves = Self.queueWaves() {
            for upTo in [1, 2] {
                let wanted = Set(waves.filter { $0.value <= upTo }.map(\.key))
                scenarios.append(("queue-waves-1-\(upTo)", originals.filter { wanted.contains($0.versionKey) }))
            }
        }
        for (name, set) in scenarios {
            let stamped = set.map(Self.stampedApproved)
            let content = TMUAContentContext(bank: TMUAFixtures.bank(stamped, distribution: .public),
                                             syllabus: bundled.syllabus, allowsInternalContent: false,
                                             allowsOriginalOnlyPublicDiagnostic: true)
            XCTAssertEqual(content.eligibleItems.count, set.count)
            let lengths = TMUADiagnosticLength.allCases.map { length -> String in
                switch content.availability(for: length) {
                case .available: "\(length.rawValue)=yes"
                case let .insufficientContent(paper, needed, available): "\(length.rawValue)=no(P\(paper.rawValue) \(available)/\(needed))"
                case .blocked: "\(length.rawValue)=blocked"
                }
            }
            let topics = TMUAPaper.allCases.map { paper in
                "P\(paper.rawValue)topics=\(Set(content.eligibleItems(for: paper).map(\.taxonomy.topic)).count)"
            }
            print("CAPACITY \(name) P1=\(content.eligibleItems(for: .one).count) P2=\(content.eligibleItems(for: .two).count) \(topics.joined(separator: " ")) \(lengths.joined(separator: " "))")
            guard content.availability(for: .balanced).isAvailable else { continue }
            for days in [14, 30, 60, 90, 120, 180] {
                try planAudit(content: content, name: name, days: days)
            }
        }
    }

    private func planAudit(content: TMUAContentContext, name: String, days: Int) throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let availability = AppSettings.publicDefaultAvailability.map { day -> DayAvailability in
            var day = day
            day.isAvailable = day.weekday != .sunday
            return day
        }
        let settings = try TMUAFixtures.profile(in: context, today: today, examInDays: days, weeklyMinutes: 300,
                                                availability: availability)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .balanced, content: content,
                                                        at: today, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        let programme = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: today,
            calendar: calendar, resourceSessions: true, in: context)
        let tasks = try PublicProgrammeService.tasks(for: programme, in: context).filter(\.isActive)
        let questionTasks = tasks.filter { $0.questionID != nil }
        let uses = Dictionary(grouping: questionTasks.compactMap(\.questionID), by: { $0 }).mapValues(\.count)
        let summary = TMUAProgrammeService.contentSummary(programme: programme, tasks: tasks,
            seenStableIDs: Set(snapshot.items.map(\.itemStableID)), availability: availability,
            today: today, calendar: calendar)
        XCTAssertLessThanOrEqual(uses.values.max() ?? 0, TMUAProgrammeService.spacedRepeatLimit + 1)
        print("CAPACITY plan \(name) \(days)d 5h/6d studyDays=\(summary.studyDays) questionTasks=\(questionTasks.count) distinct=\(uses.count) maxUses=\(uses.values.max() ?? 0) paperSessions=\(tasks.filter { $0.activity == .resourcePractice }.count) emptyDays=\(summary.emptyStudyDays) daysWithoutNew=\(summary.daysWithoutNewQuestions)")
    }

    private static func stampedApproved(_ item: TMUAContentItem) -> TMUAContentItem {
        var copy = TMUAContentItem(
            stableId: item.stableId, version: item.version, paper: item.paper, category: item.category,
            title: item.title, stem: item.stem, options: item.options, correctOptionId: item.correctOptionId,
            solution: item.solution, taxonomy: item.taxonomy, difficulty: item.difficulty,
            estimatedMinutes: item.estimatedMinutes, source: item.source,
            rights: TMUAContentRights(copyrightHolder: item.rights.copyrightHolder, licence: "audit", inAppUse: .cleared,
                                      redistribution: .cleared, commercialUse: .cleared, answerKey: .cleared,
                                      solution: .cleared, attribution: "Original Revisr question"),
            review: TMUAContentReview(mathematical: .humanApproved, originality: .humanApproved, publication: .approved,
                                      editorialStatus: "audit-only"))
        copy.approval = TMUAFixtures.approval(category: item.category)
        return copy
    }

    /// Wave of each version in the private review queue, if the private workspace sits beside
    /// this repository (the assembler's default). Only identities and wave numbers are read.
    private static func queueWaves() -> [String: Int]? {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repo.deletingLastPathComponent().appendingPathComponent("revisr-content-private/review/queue.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["queue"] as? [[String: Any]] else { return nil }
        var waves: [String: Int] = [:]
        for row in rows {
            if let key = row["versionKey"] as? String, let wave = row["wave"] as? Int { waves[key] = wave }
        }
        return waves
    }
}
