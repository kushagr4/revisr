import Foundation

enum TMUASelectionError: LocalizedError, Equatable {
    case insufficientContent(paper: TMUAPaper, needed: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case let .insufficientContent(paper, needed, available):
            "\(paper.title) needs \(needed) more approved questions, but only \(available) unseen questions are available."
        }
    }
}

/// The rules a diagnostic was selected under. A diagnostic records its policy when it is created
/// and keeps it for every later selection (a length change before starting, or an expansion), so
/// an assessment is never reshuffled by a newer policy.
enum TMUASelectionPolicy: String, CaseIterable, Sendable {
    /// One selection for every student. The section's target size is fixed before selection
    /// starts (v1 recomputed it after every pick, inflating the difficulty and past/mock targets),
    /// and equal scores are broken by a fixed hash of the question identity.
    case v2 = "tmua-selector-v2"
    /// Student-specific and still deterministic: equal scores are broken by a hash of the
    /// question identity mixed with a seed derived from the assessment's identity. Adds difficulty
    /// profiles by section size, a balance between official and original questions, a soft
    /// penalty for repeating a source paper or year, and a bonus for topics only this paper can
    /// cover. See docs/R2_DIFFICULTY_AND_SOURCE_DIVERSITY.md.
    case v3 = "tmua-selector-v3"

    static let current: TMUASelectionPolicy = .v3

    /// The policy a stored diagnostic was created under. v1 was retired before v3 existed and
    /// such diagnostics already expanded with v2 rules, so unknown versions keep doing so.
    init(recorded version: String) {
        self = TMUASelectionPolicy(rawValue: version) ?? .v2
    }
}

/// Deterministic, coverage-aware greedy selection. Identical inputs (candidates, prior questions,
/// exposure, policy and seed) always produce the same ordered questions.
enum TMUADiagnosticSelector {
    static let version = TMUASelectionPolicy.current.rawValue

    private struct Coverage {
        var topics: [String: Int] = [:]
        var strands: [String: Int] = [:]
        var skills: [String: Int] = [:]
        var difficultyBands: [Int: Int] = [:]
        var licensedTopics: Set<String> = []
        var licensed = 0
        var total = 0
        // v3 only
        var levelFive = 0
        var originals = 0
        var originalTopics: Set<String> = []
        var sourcePapers: [String: Int] = [:]
        var sourceYears: [String: Int] = [:]

        mutating func add(_ item: TMUAContentItem) {
            topics[item.taxonomy.topic, default: 0] += 1
            strands[item.taxonomy.strand, default: 0] += 1
            if let skill = item.taxonomy.skill { skills[skill, default: 0] += 1 }
            difficultyBands[TMUADiagnosticSelector.band(item.difficulty), default: 0] += 1
            if item.category.isPastOrMock {
                licensed += 1
                licensedTopics.insert(item.taxonomy.topic)
            } else {
                originals += 1
                originalTopics.insert(item.taxonomy.topic)
            }
            if item.difficulty >= 5 { levelFive += 1 }
            if let key = TMUADiagnosticSelector.sourcePaperKey(item) { sourcePapers[key, default: 0] += 1 }
            if let key = TMUADiagnosticSelector.sourceYearKey(item) { sourceYears[key, default: 0] += 1 }
            total += 1
        }
    }

    /// Target share of easier, standard and harder questions.
    private static let bandTargets: [Int: Double] = [0: 0.35, 1: 0.45, 2: 0.20]

    /// The v2 ordering key: FNV-1a over the version key, the same for every student.
    static func tieBreak(_ item: TMUAContentItem) -> (UInt64, String) {
        (fnv1a(item.versionKey), item.versionKey)
    }

    static func band(_ difficulty: Int) -> Int {
        difficulty <= 2 ? 0 : difficulty == 3 ? 1 : 2
    }

    /// The seed for one assessment: its stable identity mixed with the policy version, so the
    /// same assessment always reselects the same questions and a new policy starts a new sequence.
    static func seed(assessmentID: String, policy: TMUASelectionPolicy) -> UInt64 {
        fnv1a("\(assessmentID)|\(policy.rawValue)")
    }

    /// Questions from the same published paper (official and licensed items only).
    static func sourcePaperKey(_ item: TMUAContentItem) -> String? {
        guard item.category.isPastOrMock, let source = item.source else { return nil }
        return "\(source.examination ?? "-")|\(source.year.map(String.init) ?? "-")|P\(source.paperNumber.map(String.init) ?? "-")"
    }

    /// Questions from the same sitting year; an undated paper (a specimen) is its own group.
    static func sourceYearKey(_ item: TMUAContentItem) -> String? {
        guard item.category.isPastOrMock, let source = item.source else { return nil }
        return source.year.map(String.init) ?? source.examination ?? "-"
    }

    /// - Parameters:
    ///   - prior: questions already in this diagnostic (any paper). Their
    ///     coverage steers the new picks so an expansion fills gaps.
    ///   - excludedStableIDs: identities the student has already seen; a
    ///     question is never reassigned in another version.
    ///   - policy: the policy the diagnostic was created under.
    ///   - seed: from `seed(assessmentID:policy:)`; ignored by v2.
    static func select(
        paper: TMUAPaper,
        count: Int,
        candidates: [TMUAContentItem],
        prior: [TMUAContentItem] = [],
        excludedStableIDs: Set<String> = [],
        policy: TMUASelectionPolicy = .current,
        seed: UInt64 = 0,
        preferredLicensedShare: Double = TMUAContentPolicy.preferredLicensedShare
    ) throws -> [TMUAContentItem] {
        guard count > 0 else { return [] }
        let excluded = excludedStableIDs.union(prior.map(\.stableId))
        var pool = candidates.filter { $0.paper == paper.rawValue && !excluded.contains($0.stableId) }
        var seen = Set<String>()
        pool = pool.sorted { $0.versionKey < $1.versionKey }.filter { seen.insert($0.stableId).inserted }
        guard pool.count >= count else {
            throw TMUASelectionError.insufficientContent(paper: paper, needed: count, available: pool.count)
        }

        var paperCoverage = Coverage()
        var diagnosticCoverage = Coverage()
        for item in prior {
            diagnosticCoverage.add(item)
            if item.paper == paper.rawValue { paperCoverage.add(item) }
        }
        let shortSection = count + paperCoverage.total <= 8
        let targetTotal = paperCoverage.total + count
        // v3: topics the other paper can still cover; the rest can only be covered here.
        let elsewhere = Set(candidates.filter { $0.paper != paper.rawValue && !excluded.contains($0.stableId) }
            .map(\.taxonomy.topic))
        var chosen: [TMUAContentItem] = []
        while chosen.count < count {
            var best: (score: Int, key: UInt64, item: TMUAContentItem)?
            for item in pool {
                let value: Int
                let key: UInt64
                switch policy {
                case .v2:
                    value = score(item, paper: paperCoverage, diagnostic: diagnosticCoverage,
                                  targetTotal: targetTotal,
                                  shortSection: shortSection, preferredLicensedShare: preferredLicensedShare)
                    key = tieBreak(item).0
                case .v3:
                    value = scoreV3(item, section: paper, paper: paperCoverage, diagnostic: diagnosticCoverage,
                                    targetTotal: targetTotal, onlyHere: !elsewhere.contains(item.taxonomy.topic),
                                    preferredLicensedShare: preferredLicensedShare)
                    key = mix(fnv1a(item.versionKey) ^ seed)
                }
                if let current = best {
                    if value > current.score
                        || (value == current.score && (key, item.versionKey) < (current.key, current.item.versionKey)) {
                        best = (value, key, item)
                    }
                } else {
                    best = (value, key, item)
                }
            }
            guard let pick = best?.item else { break }
            chosen.append(pick)
            paperCoverage.add(pick)
            diagnosticCoverage.add(pick)
            pool.removeAll { $0.stableId == pick.stableId }
        }
        // Present in a gentle difficulty progression, keeping selection order
        // as the tie-break so the result stays deterministic.
        return chosen.enumerated().sorted { lhs, rhs in
            lhs.element.difficulty != rhs.element.difficulty
                ? lhs.element.difficulty < rhs.element.difficulty : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func score(
        _ item: TMUAContentItem,
        paper: Coverage,
        diagnostic: Coverage,
        targetTotal: Int,
        shortSection: Bool,
        preferredLicensedShare: Double
    ) -> Int {
        var value = 0
        let topicCount = diagnostic.topics[item.taxonomy.topic, default: 0]
        if topicCount == 0 { value += 1_000 }
        value -= 120 * paper.topics[item.taxonomy.topic, default: 0]
        value -= 40 * topicCount
        if diagnostic.strands[item.taxonomy.strand, default: 0] == 0 { value += 200 }
        if let skill = item.taxonomy.skill, diagnostic.skills[skill, default: 0] == 0 { value += 80 }
        let band = band(item.difficulty)
        let target = Int((Double(targetTotal) * (bandTargets[band] ?? 0)).rounded(.up))
        if paper.difficultyBands[band, default: 0] < target { value += 60 }
        if shortSection && (2...3).contains(item.difficulty) { value += 15 }
        if item.category.isPastOrMock,
           Double(paper.licensed) < Double(targetTotal) * preferredLicensedShare,
           !paper.licensedTopics.contains(item.taxonomy.topic) {
            value += 50
        }
        return value
    }

    // MARK: - v3

    /// Percentage targets for easier (≤ 2), standard (3) and harder (≥ 4) questions, and for
    /// level 5 within the harder share, by the section's size. Short sections favour standard
    /// questions, which tell students apart best; longer ones progress to demanding questions.
    /// Levels are estimates (see docs/QUESTION_DIFFICULTY_AUDIT.md), not calibrated difficulty.
    static func difficultyProfile(sectionSize: Int) -> (easier: Int, standard: Int, harder: Int, levelFive: Int) {
        switch sectionSize {
        case ...5: (20, 60, 20, 0)
        case ...8: (20, 50, 30, 0)
        case ...15: (20, 45, 35, 10)
        default: (20, 40, 40, 10)
        }
    }

    /// Score weights. Coverage dominates (a new topic outweighs everything else together), then
    /// difficulty, then the source balance and diversity terms, which only decide between
    /// questions of comparable coverage and difficulty.
    enum Weight {
        static let newTopic = 1_000
        static let topicOnlyInThisPaper = 100
        static let repeatTopicInPaper = 200
        static let repeatTopicInDiagnostic = 40
        static let newStrand = 200
        static let newSkill = 80
        static let difficultyUnderTarget = 60
        static let difficultyAtTarget = 40
        static let levelFiveUnderTarget = 40
        /// Each source is preferred until it holds its share of the section (half each by
        /// default), so neither fills a section when the other covers the same ground.
        static let officialUnderShare = 50
        static let originalUnderShare = 50
        static let repeatSourcePaper = 25
        static let repeatSourceYear = 10
    }

    private static func scoreV3(
        _ item: TMUAContentItem,
        section: TMUAPaper,
        paper: Coverage,
        diagnostic: Coverage,
        targetTotal: Int,
        onlyHere: Bool,
        preferredLicensedShare: Double
    ) -> Int {
        var value = 0
        let topic = item.taxonomy.topic
        let topicCount = diagnostic.topics[topic, default: 0]
        if topicCount == 0 {
            value += Weight.newTopic
            if onlyHere { value += Weight.topicOnlyInThisPaper }
        }
        value -= Weight.repeatTopicInPaper * paper.topics[topic, default: 0]
        value -= Weight.repeatTopicInDiagnostic * topicCount
        if diagnostic.strands[item.taxonomy.strand, default: 0] == 0 { value += Weight.newStrand }
        // Reasoning skills are classified for Paper 2; Paper 1 tags are incomplete.
        if section == .two, let skill = item.taxonomy.skill, diagnostic.skills[skill, default: 0] == 0 {
            value += Weight.newSkill
        }

        let profile = difficultyProfile(sectionSize: targetTotal)
        let band = band(item.difficulty)
        let share = band == 0 ? profile.easier : band == 1 ? profile.standard : profile.harder
        if paper.difficultyBands[band, default: 0] < percent(share, of: targetTotal) {
            value += Weight.difficultyUnderTarget
        } else {
            value -= Weight.difficultyAtTarget
        }
        if profile.levelFive > 0, item.difficulty >= 5, paper.levelFive < percent(profile.levelFive, of: targetTotal) {
            value += Weight.levelFiveUnderTarget
        }

        let officialTarget = percent(Int((preferredLicensedShare * 100).rounded()), of: targetTotal)
        if item.category.isPastOrMock {
            if paper.licensed < officialTarget, !paper.licensedTopics.contains(topic) {
                value += Weight.officialUnderShare
            }
        } else if paper.originals < targetTotal - officialTarget, !paper.originalTopics.contains(topic) {
            value += Weight.originalUnderShare
        }
        if let key = sourcePaperKey(item) { value -= Weight.repeatSourcePaper * diagnostic.sourcePapers[key, default: 0] }
        if let key = sourceYearKey(item) { value -= Weight.repeatSourceYear * diagnostic.sourceYears[key, default: 0] }
        return value
    }

    /// `percentage` of `total`, rounded up, in exact integer arithmetic.
    static func percent(_ percentage: Int, of total: Int) -> Int {
        (total * percentage + 99) / 100
    }

    // MARK: - Hashing

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// SplitMix64's finaliser: spreads a seed change across every bit of the ordering key.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
