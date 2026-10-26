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

/// Deterministic, coverage-aware greedy selection. Identical inputs always
/// produce the same ordered questions, so an assessment version can be
/// reproduced from its bank version, length and prior exposure.
enum TMUADiagnosticSelector {
    static let version = "tmua-selector-v1"

    private struct Coverage {
        var topics: [String: Int] = [:]
        var strands: [String: Int] = [:]
        var skills: [String: Int] = [:]
        var difficultyBands: [Int: Int] = [:]
        var licensedTopics: Set<String> = []
        var licensed = 0
        var total = 0

        mutating func add(_ item: TMUAContentItem) {
            topics[item.taxonomy.topic, default: 0] += 1
            strands[item.taxonomy.strand, default: 0] += 1
            if let skill = item.taxonomy.skill { skills[skill, default: 0] += 1 }
            difficultyBands[TMUADiagnosticSelector.band(item.difficulty), default: 0] += 1
            if item.category.isLicensedThirdParty {
                licensed += 1
                licensedTopics.insert(item.taxonomy.topic)
            }
            total += 1
        }
    }

    /// Target share of easier, standard and harder questions.
    private static let bandTargets: [Int: Double] = [0: 0.35, 1: 0.45, 2: 0.20]

    static func band(_ difficulty: Int) -> Int {
        difficulty <= 2 ? 0 : difficulty == 3 ? 1 : 2
    }

    /// - Parameters:
    ///   - prior: questions already in this diagnostic (any paper). Their
    ///     coverage steers the new picks so an expansion fills gaps.
    ///   - excludedStableIDs: identities the student has already seen; a
    ///     question is never reassigned in another version.
    static func select(
        paper: TMUAPaper,
        count: Int,
        candidates: [TMUAContentItem],
        prior: [TMUAContentItem] = [],
        excludedStableIDs: Set<String> = [],
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
        var chosen: [TMUAContentItem] = []
        while chosen.count < count {
            var best: (score: Int, item: TMUAContentItem)?
            for item in pool {
                let value = score(item, paper: paperCoverage, diagnostic: diagnosticCoverage,
                                  targetTotal: paperCoverage.total + count,
                                  shortSection: shortSection, preferredLicensedShare: preferredLicensedShare)
                if let current = best {
                    if value > current.score || (value == current.score && item.versionKey < current.item.versionKey) {
                        best = (value, item)
                    }
                } else {
                    best = (value, item)
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
        if item.category.isLicensedThirdParty,
           Double(paper.licensed) < Double(targetTotal) * preferredLicensedShare,
           !paper.licensedTopics.contains(item.taxonomy.topic) {
            value += 50
        }
        return value
    }
}
