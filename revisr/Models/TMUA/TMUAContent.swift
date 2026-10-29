import Foundation

/// Where a question came from. Rights gates differ by category; a development
/// fixture can never enter a public build.
enum TMUAContentCategory: String, Codable, CaseIterable, Sendable {
    case revisrOriginal = "revisr_original"
    case licensedPastPaper = "licensed_past_paper"
    case licensedMock = "licensed_mock"
    /// An official past-paper question held for personal study in an internal build. It is
    /// shown from the bundled paper and never distributed: it fails the public gate.
    case pastPaperStudyCopy = "past_paper_study_copy"
    case developmentFixture = "development_fixture"

    var attributionTitle: String {
        switch self {
        case .revisrOriginal: "Original Revisr question"
        case .licensedPastPaper: "Licensed past examination question"
        case .licensedMock: "Licensed mock paper question"
        case .pastPaperStudyCopy: "Official past paper · personal study copy"
        case .developmentFixture: "Development fixture"
        }
    }

    var isLicensedThirdParty: Bool { self == .licensedPastPaper || self == .licensedMock }
    /// Real examination or mock questions, licensed or held as a personal study copy.
    var isPastOrMock: Bool { isLicensedThirdParty || self == .pastPaperStudyCopy }
}

enum TMUARightsState: String, Codable, Sendable {
    case cleared
    case pendingReview = "pending_review"
    case notPermitted = "not_permitted"
    case notApplicable = "not_applicable"
}

enum TMUAMathematicalReview: String, Codable, Sendable {
    case none
    case aiDerivationOnly = "ai_derivation_only"
    case humanApproved = "human_approved"
    case rejected
}

enum TMUAOriginalityReview: String, Codable, Sendable {
    case pending
    case humanApproved = "human_approved"
    case rejected
    case notApplicable = "not_applicable"
}

enum TMUAPublicationState: String, Codable, Sendable {
    case notApproved = "not_approved"
    case approved
    case withdrawn
}

enum TMUAContentDistribution: String, Codable, Sendable {
    case `internal`
    case `public`
}

struct TMUAOption: Codable, Hashable, Sendable {
    let id: String
    let text: String
}

struct TMUATaxonomyMapping: Codable, Hashable, Sendable {
    let topic: String
    let strand: String
    let skill: String?
}

struct TMUAContentSource: Codable, Hashable, Sendable {
    let organisation: String?
    let examination: String?
    let year: Int?
    let paperNumber: Int?
    let questionNumber: Int?
    let url: String?
    let attribution: String?
}

/// A question shown from its original paper rather than as Revisr text: the regions of the
/// bundled PDF (`AdmissionsPapers/<document>`) that make up the question, in reading order.
struct TMUAItemPresentation: Codable, Hashable, Sendable {
    struct Region: Codable, Hashable, Sendable {
        /// Zero-based page index.
        let page: Int
        /// PDF points, origin at the bottom-left of the media box.
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let document: String
    let regions: [Region]

    var aspectRatio: Double {
        let width = regions.map(\.width).max() ?? 1
        let height = regions.reduce(0) { $0 + $1.height }
        return height > 0 ? width / height : 1
    }
}

/// Where the official worked solution for a question is: a bundled PDF
/// (`AdmissionsSolutions/<document>`) and its one-based first page.
struct TMUASolutionReference: Codable, Hashable, Sendable {
    let document: String
    let page: Int
    let publisher: String
}

struct TMUAContentRights: Codable, Hashable, Sendable {
    let copyrightHolder: String
    let licence: String
    let inAppUse: TMUARightsState
    let redistribution: TMUARightsState
    let commercialUse: TMUARightsState
    let answerKey: TMUARightsState
    let solution: TMUARightsState
    let attribution: String
}

/// Present only on items in a public bank: the approved-content manifest entry the build
/// assembler checked against the human review register (and, for third-party items, a verified
/// rights grant). It names the stages passed, never the reviewers.
struct TMUAApprovalRecord: Codable, Hashable, Sendable {
    let manifestRevision: Int?
    let policyVersion: String
    let approvedOn: String?
    let contentHash: String
    let stages: [String]
    let rightsGrant: String?
}

struct TMUAContentReview: Codable, Hashable, Sendable {
    let mathematical: TMUAMathematicalReview
    let originality: TMUAOriginalityReview
    let publication: TMUAPublicationState
    let editorialStatus: String?
}

/// One immutable version of a question. Content, key or taxonomy changes
/// require a new version; saved diagnostics pin `versionKey`.
struct TMUAContentItem: Codable, Hashable, Identifiable, Sendable {
    let stableId: String
    let version: Int
    let paper: Int
    let category: TMUAContentCategory
    let title: String
    let stem: String
    let options: [TMUAOption]
    let correctOptionId: String
    let solution: String
    let taxonomy: TMUATaxonomyMapping
    let difficulty: Int
    let estimatedMinutes: Int
    let source: TMUAContentSource?
    let rights: TMUAContentRights
    let review: TMUAContentReview
    /// Set for questions shown from their original paper; the stem is then empty and the
    /// options carry letters only.
    var presentation: TMUAItemPresentation? = nil
    var solutionReference: TMUASolutionReference? = nil
    /// How the answer key was established, e.g. "UAT-UK official answer key".
    var keyProvenance: String? = nil
    /// How topic and difficulty were assigned when they are estimates, not reviewed values.
    var taxonomyProvenance: String? = nil
    var difficultyProvenance: String? = nil
    /// The question's identity in the original Revisr library index (`AdmissionsManifest`).
    var libraryQuestionID: String? = nil
    /// Set by the build assembler for approved items in a public bank only.
    var approval: TMUAApprovalRecord? = nil

    var id: String { versionKey }
    var versionKey: String { "\(stableId)@v\(version)" }
    var paperKind: TMUAPaper { TMUAPaper(rawValue: paper) ?? .one }

    /// The short source credit shown under a question, e.g. "Original Revisr question · draft"
    /// or "Source: UAT-UK · TMUA 2019 Paper 1 · Q12". It never implies endorsement.
    var creditLine: String {
        switch category {
        case .revisrOriginal:
            return review.publication == .approved ? "Original Revisr question" : "Original Revisr question · draft, not yet reviewed"
        case .developmentFixture:
            return category.attributionTitle
        case .pastPaperStudyCopy, .licensedPastPaper, .licensedMock:
            guard let source else { return category.attributionTitle }
            if let attribution = source.attribution, !attribution.isEmpty { return attribution }
            let paper = [source.examination, source.year.map(String.init), source.paperNumber.map { "Paper \($0)" }]
                .compactMap { $0 }.joined(separator: " ")
            let parts = [source.organisation, paper.isEmpty ? nil : paper, source.questionNumber.map { "Q\($0)" }]
                .compactMap { $0 }
            let credit = "Source: " + parts.joined(separator: " · ")
            return category == .pastPaperStudyCopy ? credit + " · personal study copy" : credit
        }
    }
}

struct TMUAContentBank: Codable, Sendable {
    let schemaVersion: Int
    let bankVersion: String
    let distribution: TMUAContentDistribution
    let taxonomyVersion: String
    let contentPolicyVersion: String
    let excludedItemCount: Int
    let items: [TMUAContentItem]
    /// The approved-content manifest revision a public bank was assembled from; nil for
    /// internal banks and for public banks built without a manifest.
    var approvedManifestRevision: Int? = nil

    static let empty = TMUAContentBank(schemaVersion: 1, bankVersion: "empty", distribution: .public,
        taxonomyVersion: TMUASyllabus.currentVersion, contentPolicyVersion: TMUAContentPolicy.version,
        excludedItemCount: 0, items: [])

    /// Highest version per stable identity; older versions stay resolvable for
    /// pinned drafts but are never selected for new work.
    var latestItems: [TMUAContentItem] {
        Dictionary(grouping: items, by: \.stableId).values
            .compactMap { $0.max { $0.version < $1.version } }
            .sorted { $0.versionKey < $1.versionKey }
    }

    func item(versionKey: String) -> TMUAContentItem? {
        items.first { $0.versionKey == versionKey }
    }
}

enum TMUAPaper: Int, CaseIterable, Codable, Identifiable, Sendable {
    case one = 1
    case two = 2

    var id: Int { rawValue }
    var title: String { "Paper \(rawValue)" }
    var subtitle: String {
        switch self {
        case .one: "Applications of mathematical knowledge"
        case .two: "Mathematical reasoning"
        }
    }
}

// MARK: - Syllabus taxonomy

struct TMUASyllabus: Decodable, Sendable {
    struct Specification: Decodable, Sendable {
        let title: String
        let assessmentWindow: String
        let publisher: String
        let url: String
    }

    struct Strand: Decodable, Hashable, Sendable {
        let key: String
        let title: String
        let specRefs: [String]
    }

    struct Topic: Decodable, Hashable, Sendable {
        let key: String
        let title: String
        let papers: [Int]
        let strands: [Strand]
    }

    struct Skill: Decodable, Hashable, Sendable {
        let key: String
        let title: String
    }

    static let currentVersion = "tmua-syllabus-v1"

    let taxonomyVersion: String
    let specification: Specification
    let legacyTopicKeyMap: [String: String]
    let topics: [Topic]
    let skills: [Skill]

    func topic(_ key: String) -> Topic? { topics.first { $0.key == key } }
    func topicTitle(_ key: String) -> String { topic(key)?.title ?? key }

    func strandTitle(_ key: String) -> String {
        topics.lazy.flatMap(\.strands).first { $0.key == key }?.title ?? key
    }

    func skillTitle(_ key: String) -> String {
        skills.first { $0.key == key }?.title ?? key
    }

    func topics(for paper: TMUAPaper) -> [Topic] {
        topics.filter { $0.papers.contains(paper.rawValue) }
    }

    static func load(bundle: Bundle = .main) -> TMUASyllabus? {
        guard let url = bundle.url(forResource: "TMUASyllabus.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TMUASyllabus.self, from: data)
    }
}
