import Foundation

/// Where a question came from. Rights gates differ by category; a development
/// fixture can never enter a public build.
enum TMUAContentCategory: String, Codable, CaseIterable, Sendable {
    case revisrOriginal = "revisr_original"
    case licensedPastPaper = "licensed_past_paper"
    case licensedMock = "licensed_mock"
    case developmentFixture = "development_fixture"

    var attributionTitle: String {
        switch self {
        case .revisrOriginal: "Original Revisr question"
        case .licensedPastPaper: "Licensed past examination question"
        case .licensedMock: "Licensed mock paper question"
        case .developmentFixture: "Development fixture"
        }
    }

    var isLicensedThirdParty: Bool { self == .licensedPastPaper || self == .licensedMock }
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

    var id: String { versionKey }
    var versionKey: String { "\(stableId)@v\(version)" }
    var paperKind: TMUAPaper { TMUAPaper(rawValue: paper) ?? .one }
}

struct TMUAContentBank: Codable, Sendable {
    let schemaVersion: Int
    let bankVersion: String
    let distribution: TMUAContentDistribution
    let taxonomyVersion: String
    let contentPolicyVersion: String
    let excludedItemCount: Int
    let items: [TMUAContentItem]

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
