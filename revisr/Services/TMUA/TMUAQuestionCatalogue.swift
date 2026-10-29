import Foundation

/// R4 reconciliation data bundled with every build (`TMUACatalogueReconciliation.json`): how the
/// original library index's topics map to the syllabus, which indexed questions are the same
/// question in another paper, and the papers the bundled library lacks. Metadata only: no
/// question text, keys or Drive identifiers. The detailed evidence is in the private workspace.
struct TMUACatalogueReconciliation: Decodable, Sendable {
    struct Duplicate: Decodable, Hashable, Sendable {
        enum Relation: String, Decodable, Sendable {
            /// The same question, reprinted: merged into one identity.
            case same
            /// Derived from another question with changes: kept separate, linked as a variant.
            case adapted
        }

        /// The later appearance (a mock reprinting an official question, a reprint within a series).
        let question: String
        /// The identity kept: the official, earlier or first-listed appearance.
        let canonical: String
        let relation: Relation
        let evidence: String
    }

    struct Document: Decodable, Sendable {
        enum Holding: String, Decodable, Sendable {
            /// The question paper is in the owner's Drive but not bundled.
            case drive
            /// Only the solutions are held; the questions were identified from them.
            case none
        }

        struct Question: Decodable, Sendable {
            let questionID: String
            let label: String
            let page: Int?
            let solutionPage: Int?
            let legacyTopic: String
            let paperFit: String?
            let format: String?
            let difficulty: Int?
        }

        let documentID: String
        let family: String
        let title: String
        let year: Int?
        let paper: String?
        let questionPaper: Holding
        let solutionID: String?
        let questions: [Question]
    }

    let version: Int
    let reviewedOn: String
    /// Library index topic → syllabus topic key. Topics outside the TMUA specification
    /// ("Games, invariants & strategy", "Mixed / problem solving") are deliberately absent.
    let legacyTopicMap: [String: String]
    let duplicates: [Duplicate]
    let documents: [Document]

    static func bundled(in bundle: Bundle = .main) -> TMUACatalogueReconciliation? {
        guard let url = bundle.url(forResource: "TMUACatalogueReconciliation", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TMUACatalogueReconciliation.self, from: data)
    }
}

/// One canonical question in the unified library, whatever its origin: an original Revisr
/// question, or a question from the owner's collection (official papers, mocks, worksheets and
/// competitions). It is the same record wherever the question appears, so a reprint in another
/// paper is an alias, never a fresh question.
struct TMUACatalogueEntry: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable {
        case revisrOriginal = "revisr_original"
        case collection = "drive_collection"
    }

    /// How a student sees the question in this build.
    enum Presentation: String, Sendable {
        /// Rendered by Revisr: original text, or a verified crop of the bundled paper.
        case native
        /// The bundled paper, opened at the question's page (internal builds only).
        case document
        /// Not reproduced: the publisher's page offers the paper.
        case external
    }

    /// How an answer can be recorded. Only `automatic` produces question-level evidence.
    enum AnswerMode: String, CaseIterable, Sendable {
        /// Marked by Revisr against a key it holds for this exact version.
        case automatic
        /// The student marks it against the publisher's solution, which this build can open.
        case selfMarked
        /// No solution in this build: the student records how it went.
        case manualResult
        /// The question is only on the publisher's site; the student may record a result.
        case externalViewing

        var title: String {
            switch self {
            case .automatic: "Marked by Revisr"
            case .selfMarked: "Self-marked with solution"
            case .manualResult: "Record your own result"
            case .externalViewing: "On the publisher’s website"
            }
        }
    }

    enum PaperFit: String, Sendable {
        case paper1, paper2, both, unclassified

        func includes(_ paper: TMUAPaper) -> Bool {
            switch self {
            case .paper1: paper == .one
            case .paper2: paper == .two
            case .both: true
            case .unclassified: false
            }
        }
    }

    enum Rights: String, Sendable {
        /// Revisr's own question; publication still needs review and the owner's declaration.
        case revisrOwn
        /// Third-party question held for personal study in an internal build; never distributed.
        case personalStudyCopy
        /// Third-party question with a verified grant (none today).
        case licensed
        /// Listed and linked to the publisher; nothing reproduced.
        case linkedOnly
    }

    let id: String
    /// Other identities of this question: the study-copy item that marks it, reprints in other papers.
    let aliases: [String]
    let origin: Origin
    let sourceID: String?
    let sourceTitle: String
    let provider: TMUAResourceProvider?
    let label: String?
    let page: Int?
    let paperFit: PaperFit
    let topicKey: String?
    let legacyTopic: String?
    let difficulty: Int?
    let difficultyProvenance: String
    let format: String?
    let presentation: Presentation
    let answerMode: AnswerMode
    /// The latest version, for native questions; older versions stay resolvable in the bank.
    let item: TMUAContentItem?
    let versionKeys: [String]
    let solutionPage: Int?
    /// The solution file `solutionPage` refers to (`TMUAResourceSource.SolutionFile.resourceName`).
    let solutionResource: String?
    let hasSolution: Bool
    let rights: Rights
    let publication: TMUAPublicationState
    let reviewStatus: String
    let attribution: String
    let sourceURL: URL?
    /// Content hash material: the version key for native questions; paper checksum and location otherwise.
    let fingerprint: String
    /// Set when this question was adapted from another (both are kept).
    let variantOf: String?
    /// Other papers that reprint this question.
    let alsoAppearsIn: [String]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Can be opened and attempted inside Revisr in this build.
    var isPracticable: Bool { presentation != .external }
    /// Produces question-level evidence for topic analysis.
    var isEvidence: Bool { answerMode == .automatic }

    static func levelTitle(_ level: Int) -> String {
        switch level {
        case ...1: "Foundation"
        case 2: "Core"
        case 3: "Challenging"
        case 4: "Hard"
        default: "Stretch"
        }
    }
}

/// The unified question library: the owner's collection (every indexed question of every paper this
/// build may show) and the original Revisr questions, reconciled into one set of identities. The
/// Questions tab, the paper library, the planner's library sessions and the diagnostic's candidate
/// pool all read it; the diagnostic uses exactly its automatically marked entries.
struct TMUAQuestionCatalogue: Sendable {
    let entries: [TMUACatalogueEntry]
    let sources: [TMUAResourceSource]
    /// Merged reprint identity → canonical identity.
    let aliases: [String: String]
    private let index: [String: Int]

    init(entries: [TMUACatalogueEntry], sources: [TMUAResourceSource], aliases: [String: String]) {
        self.entries = entries
        self.sources = sources
        self.aliases = aliases
        var index: [String: Int] = [:]
        for (offset, entry) in entries.enumerated() {
            index[entry.id] = offset
            for alias in entry.aliases where index[alias] == nil { index[alias] = offset }
        }
        self.index = index
    }

    /// Resolves any identity: canonical, item stable ID or merged reprint.
    func entry(_ id: String) -> TMUACatalogueEntry? {
        (index[id] ?? aliases[id].flatMap { index[$0] }).map { entries[$0] }
    }

    func entries(inSource sourceID: String) -> [TMUACatalogueEntry] {
        entries.filter { $0.sourceID == sourceID }
    }

    var practicable: [TMUACatalogueEntry] { entries.filter(\.isPracticable) }
    var automatic: [TMUACatalogueEntry] { entries.filter { $0.answerMode == .automatic } }

    func count(_ mode: TMUACatalogueEntry.AnswerMode) -> Int { entries.filter { $0.answerMode == mode }.count }

    // MARK: Assembly

    /// Pure assembly, testable without bundle files.
    /// - Parameters:
    ///   - sources: the paper library for this build (`TMUAResourceCatalogue`).
    ///   - items: the eligible bank items (latest versions) for this build.
    ///   - allVersions: every version in the bank, so entries can list superseded versions.
    nonisolated static func build(sources: [TMUAResourceSource], items: [TMUAContentItem],
                                  allVersions: [TMUAContentItem], syllabus: TMUASyllabus,
                                  reconciliation: TMUACatalogueReconciliation?,
                                  distribution: TMUAContentDistribution) -> TMUAQuestionCatalogue {
        let versions = Dictionary(grouping: allVersions, by: \.stableId)
            .mapValues { $0.sorted { $0.version < $1.version }.map(\.versionKey) }
        let itemsByStableID = Dictionary(items.map { ($0.stableId, $0) }, uniquingKeysWith: { first, _ in first })
        let indexed = Set(sources.flatMap { $0.questions.map(\.id) })
        // A reprint merges only when both appearances are in this build.
        var merged: [String: String] = [:]
        var variants: [String: String] = [:]
        for duplicate in reconciliation?.duplicates ?? []
        where indexed.contains(duplicate.canonical) && indexed.contains(duplicate.question) {
            switch duplicate.relation {
            case .same: merged[duplicate.question] = duplicate.canonical
            case .adapted: variants[duplicate.question] = duplicate.canonical
            }
        }
        var reprints: [String: [(id: String, title: String)]] = [:]
        for source in sources {
            for question in source.questions {
                if let canonical = merged[question.id] {
                    reprints[canonical, default: []].append((question.id, "\(source.title) · Q\(question.label)"))
                }
            }
        }
        let topicMap = reconciliation?.legacyTopicMap ?? [:]
        var entries: [TMUACatalogueEntry] = []
        var covered = Set<String>()
        for source in sources {
            for question in source.questions where merged[question.id] == nil {
                let item = question.autoMarkedItemID.flatMap { itemsByStableID[$0] }
                if let item { covered.insert(item.stableId) }
                let extra = reprints[question.id] ?? []
                entries.append(entry(question: question, source: source, item: item,
                                     versions: item.flatMap { versions[$0.stableId] } ?? [],
                                     aliases: (item.map { [$0.stableId] } ?? []) + extra.map(\.id),
                                     alsoAppearsIn: extra.map(\.title), variantOf: variants[question.id],
                                     topicMap: topicMap, syllabus: syllabus, distribution: distribution))
            }
        }
        // Originals, and any eligible item whose paper is not in this build's library.
        for item in items where !covered.contains(item.stableId) {
            entries.append(entry(item: item, versions: versions[item.stableId] ?? [item.versionKey]))
        }
        return TMUAQuestionCatalogue(entries: entries, sources: sources, aliases: merged)
    }

    private static func entry(question: TMUAResourceQuestion, source: TMUAResourceSource, item: TMUAContentItem?,
                              versions: [String], aliases: [String], alsoAppearsIn: [String], variantOf: String?,
                              topicMap: [String: String], syllabus: TMUASyllabus,
                              distribution: TMUAContentDistribution) -> TMUACatalogueEntry {
        let presentation: TMUACatalogueEntry.Presentation
        let mode: TMUACatalogueEntry.AnswerMode
        // Only solutions this build can open count; a public build lists none.
        let hasSolution = !source.solutions.isEmpty
        if item != nil {
            presentation = .native
            mode = .automatic
        } else if source.access == .studyCopy {
            presentation = .document
            mode = hasSolution ? .selfMarked : .manualResult
        } else {
            presentation = .external
            mode = .externalViewing
        }
        let topic = item?.taxonomy.topic ?? topicMap[question.topic].flatMap { syllabus.topic($0)?.key }
        let review: String
        if let item {
            review = item.keyProvenance.map { "Answer key: \($0). Not checked by a person." }
                ?? "Answer key not checked by a person."
        } else {
            review = hasSolution
                ? "The publisher’s solutions are available. Revisr holds no answer key, so you mark it yourself."
                : "Revisr holds no answer key or solution for this question in this build."
        }
        return TMUACatalogueEntry(
            id: question.id, aliases: aliases, origin: .collection, sourceID: source.id, sourceTitle: source.title,
            provider: source.provider, label: question.label, page: question.page,
            paperFit: item.map { $0.paper == 1 ? .paper1 : .paper2 } ?? paperFit(question, source: source),
            topicKey: topic, legacyTopic: question.topic,
            difficulty: item?.difficulty ?? question.difficulty,
            difficultyProvenance: item?.difficultyProvenance
                ?? (source.holdingNote != nil || question.difficulty == nil
                    ? "AI estimate made while indexing; not calibrated"
                    : "Estimated in the original Revisr library index; not calibrated"),
            format: question.format, presentation: presentation, answerMode: mode, item: item,
            versionKeys: versions, solutionPage: hasSolution ? question.solutionPage : nil,
            solutionResource: hasSolution ? question.solutionResource : nil, hasSolution: hasSolution,
            rights: source.access == .studyCopy ? .personalStudyCopy : .linkedOnly,
            publication: item?.review.publication ?? .notApproved, reviewStatus: review,
            attribution: "Source: \(source.provider.credit) · \(source.title) · Q\(question.label)",
            sourceURL: source.provider.link,
            fingerprint: source.checksum.map { "\($0)#p\(question.page ?? 0)#q\(question.label)" }
                ?? "\(source.id)#q\(question.label)",
            variantOf: variantOf, alsoAppearsIn: alsoAppearsIn)
    }

    private static func entry(item: TMUAContentItem, versions: [String]) -> TMUACatalogueEntry {
        let original = item.category == .revisrOriginal
        let review: String
        switch (item.review.publication, item.review.mathematical) {
        case (.approved, _): review = "Reviewed and approved for publication."
        case (_, .aiDerivationOnly): review = "Unreviewed draft: checked with AI assistance, not yet reviewed by a person."
        default: review = "Not yet reviewed by a person."
        }
        return TMUACatalogueEntry(
            id: item.stableId, aliases: [], origin: original ? .revisrOriginal : .collection,
            sourceID: nil, sourceTitle: original ? "Original Revisr questions" : (item.source?.examination ?? item.title),
            provider: nil, label: item.source?.questionNumber.map(String.init), page: nil,
            paperFit: item.paper == 1 ? .paper1 : .paper2, topicKey: item.taxonomy.topic, legacyTopic: nil,
            difficulty: item.difficulty,
            difficultyProvenance: item.difficultyProvenance ?? "Author’s estimate; not calibrated",
            format: "Multiple choice", presentation: .native, answerMode: .automatic, item: item,
            versionKeys: versions, solutionPage: nil, solutionResource: nil, hasSolution: !item.solution.isEmpty,
            rights: original ? .revisrOwn : item.category.isLicensedThirdParty ? .licensed : .personalStudyCopy,
            publication: item.review.publication, reviewStatus: review, attribution: item.creditLine,
            sourceURL: item.source?.url.flatMap(URL.init(string:)), fingerprint: item.versionKey,
            variantOf: nil, alsoAppearsIn: [])
    }

    /// TMUA-format papers name their paper; other papers carry the library index's fit judgement.
    nonisolated static func paperFit(_ question: TMUAResourceQuestion, source: TMUAResourceSource) -> TMUACatalogueEntry.PaperFit {
        if source.kind == .officialTMUA || source.kind == .independentMock, let label = source.paperLabel {
            if label.contains("Paper 1") { return .paper1 }
            if label.contains("Paper 2") { return .paper2 }
        }
        switch question.paperFit {
        case "Paper 1", "Paper 1 / Both": return .paper1
        case "Paper 2", "Paper 2 / Both": return .paper2
        case "Both": return .both
        default: return .unclassified
        }
    }
}

/// The catalogue for this launch's content context.
@MainActor
enum TMUACatalogueStore {
    private static var cached: (key: String, catalogue: TMUAQuestionCatalogue)?

    static func catalogue(_ content: TMUAContentContext?, bundle: Bundle = .main) -> TMUAQuestionCatalogue {
        guard let content else { return TMUAQuestionCatalogue(entries: [], sources: [], aliases: [:]) }
        let key = "\(content.distribution.rawValue)#\(content.bank.bankVersion)#\(content.eligibleItems.count)"
        if let cached, cached.key == key { return cached.catalogue }
        let sources = TMUAResourceCatalogue.sources(distribution: content.distribution, items: content.eligibleItems,
                                                    bundle: bundle)
        let built = TMUAQuestionCatalogue.build(sources: sources, items: content.eligibleItems,
                                                allVersions: content.bank.items, syllabus: content.syllabus,
                                                reconciliation: TMUACatalogueReconciliation.bundled(in: bundle),
                                                distribution: content.distribution)
        cached = (key, built)
        return built
    }
}
