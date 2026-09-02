import Foundation

struct AdmissionsSolutionsManifest: Decodable {
    let formatVersion: Int
    let importRevision: String
    let documents: [Document]
    let links: [Link]

    struct Document: Decodable {
        let stableSolutionID: String
        let displayName: String
        let solutionType: SolutionDocumentType
        let resourceName: String
        let resourceExtension: String
        let resourceContainer: SolutionResourceContainer
        let family: String
        let year: Int?
        let paper: String?
        let provenanceOrganization: String
        let provenanceTitle: String
        let originalFilename: String
        let pageCount: Int?
        let sha256: String?
        let availability: SolutionAvailability
        let isVerified: Bool
        let sourceID: String?
        let importRevision: String
        let mediaKind: SolutionMediaKind?
        let additionalSourceIDs: [String]?
        let normalizedTextChecksum: String?
        let semanticDocumentIdentity: String?
        let duplicateReviewState: DuplicateReviewState?
        let possibleDuplicateSolutionIDs: [String]?
    }

    struct Link: Decodable {
        let stableLinkID: String
        let solutionID: String
        let questionID: String
        let startPage: Int?
        let endPage: Int?
        let startTimeSeconds: Double?
        let endTimeSeconds: Double?
        let problemLabel: String?
        let mappingConfidence: SolutionMappingConfidence
        let importRevision: String
    }

    static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(
            forResource: "AdmissionsSolutionsManifest",
            withExtension: "json"
        ) else {
            throw AdmissionsSolutionsImportError.missingBundledManifest
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

enum AdmissionsSolutionsImportError: LocalizedError {
    case missingBundledManifest
    case unsupportedFormat(Int)
    case duplicateSolutionID(String)
    case duplicateLinkID(String)
    case unresolvedSource(String)
    case unresolvedSolution(String)
    case unresolvedQuestion(String)
    case missingResourceFilename(String)
    case invalidPageRange(String)
    case invalidTimeRange(String)
    case invalidMediaMapping(String)
    case contradictoryDuplicateMetadata(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledManifest:
            "The local Solution Bank manifest is missing from this build."
        case let .unsupportedFormat(version):
            "Solution Bank manifest format \(version) is not supported."
        case let .duplicateSolutionID(identifier):
            "The Solution Bank has a duplicate document ID: \(identifier)."
        case let .duplicateLinkID(identifier):
            "The Solution Bank has a duplicate question link ID: \(identifier)."
        case let .unresolvedSource(identifier):
            "A Solution Bank document references missing source \(identifier)."
        case let .unresolvedSolution(identifier):
            "A Solution Bank link references missing solution \(identifier)."
        case let .unresolvedQuestion(identifier):
            "A Solution Bank link references missing question \(identifier)."
        case let .missingResourceFilename(identifier):
            "Solution document \(identifier) has no bundled-resource filename."
        case let .invalidPageRange(identifier):
            "Solution link \(identifier) has an invalid PDF page range."
        case let .invalidTimeRange(identifier):
            "Solution link \(identifier) has an invalid video time range."
        case let .invalidMediaMapping(identifier):
            "Solution link \(identifier) mixes incompatible PDF/video mapping metadata."
        case let .contradictoryDuplicateMetadata(identifier):
            "Solution document \(identifier) contains contradictory duplicate metadata."
        }
    }
}
