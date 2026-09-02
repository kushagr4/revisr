import Foundation

struct AdmissionsManifest: Decodable {
    let formatVersion: Int
    let importRevision: String
    let profiles: [Profile]
    let sources: [Source]
    let questions: [Question]
    let topics: [Topic]
    let programme: Programme

    struct Profile: Decodable {
        let kind: AdmissionsTestKind
        let displayName: String
        let isActive: Bool
    }

    struct Source: Decodable {
        let stableSourceID: String
        let displayName: String
        let expectedFilename: String
        let family: String
        let year: Int?
        let paper: String?
        let pageCount: Int?
        let questionUnitCount: Int
        let useRule: String?
        let inventoryStatus: String?
        let checksum: String?
        let mediaKind: SolutionMediaKind?
        let normalizedTextChecksum: String?
        let semanticDocumentIdentity: String?
        let duplicateReviewState: DuplicateReviewState?
        let possibleDuplicateSourceIDs: [String]?
    }

    struct Question: Decodable {
        let externalQuestionID: String
        let admissionsTest: AdmissionsTestKind
        let family: String
        let year: Int?
        let paper: String?
        let section: String?
        let questionLabel: String
        let page: Int?
        let primaryTopic: String
        let secondaryTopic: String?
        let reasoningSkill: String?
        let tmuaPaperFit: String?
        let difficulty: Int
        let difficultyLabel: String
        let tmuaRelevance: Double?
        let format: String?
        let recommendedUse: String?
        let scheduleEligible: Bool
        let classificationConfidence: String?
        let descriptor: String?
        let protection: QuestionProtection
        let sourceID: String?
        let importRevision: String
        let primaryPreparationStream: PreparationStreamKind?
        let intendedUses: [PreparationStreamKind]?
        let questionNumber: Int?
        let subpart: String?
        let difficultyProvenance: DifficultyProvenance?
        let validityState: QuestionValidityState?
        let validityReason: String?
        let duplicateReviewState: DuplicateReviewState?
        let possibleDuplicateQuestionIDs: [String]?
        let verifiedCanonicalQuestionID: String?
    }

    struct Topic: Decodable {
        let stableTopicID: String
        let name: String
        let displayOrder: Int
    }

    struct Programme: Decodable {
        let externalProgrammeID: String
        let admissionsTest: AdmissionsTestKind
        let name: String
        let startDate: String
        let importRevision: String
        let days: [Day]
        let assignments: [Assignment]
    }

    struct Day: Decodable {
        let dayNumber: Int
        let focus: String
        let studyBrief: String
        let allocatedQuestionCount: Int
        let expectedQuestionMinutes: Int
        let expectedReviewMinutes: Int
        let dailyTarget: String?
        let notes: String?
        let scheduleOffsetDays: Int?
        let earliestStartMinute: Int?
    }

    struct Assignment: Decodable {
        let externalAssignmentID: String
        let dayNumber: Int
        let questionID: String
        let block: String?
        let purpose: String?
        let suggestedTimeCapMinutes: Int?
        let displayOrder: Int
    }
}

extension AdmissionsManifest {
    static func bundled() throws -> AdmissionsManifest {
        guard let url = Bundle.main.url(forResource: "AdmissionsManifest", withExtension: "json") else {
            throw AdmissionsImportError.missingBundledManifest
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AdmissionsManifest.self, from: data)
    }
}

enum AdmissionsImportError: LocalizedError {
    case missingBundledManifest
    case unsupportedFormat(Int)
    case invalidStartDate(String)
    case duplicateQuestionID(String)
    case duplicateProfileID(String)
    case duplicateSourceID(String)
    case duplicateTopicID(String)
    case duplicateProgrammeDay(Int)
    case duplicateAssignmentID(String)
    case unresolvedQuestionSource(questionID: String, sourceID: String)
    case unresolvedAssignment(String)
    case unresolvedProgrammeDay(Int)
    case missingResourceFilename(String)
    case invalidQuestionPage(String)
    case invalidPreparationClassification(String)
    case contradictoryQuestionMetadata(String)
    case invalidProgrammeDay(Int)

    var errorDescription: String? {
        switch self {
        case .missingBundledManifest:
            "The admissions metadata manifest is missing from this build."
        case let .unsupportedFormat(version):
            "Admissions manifest format \(version) is not supported."
        case let .invalidStartDate(value):
            "The admissions programme start date is invalid: \(value)."
        case let .duplicateQuestionID(identifier):
            "The admissions manifest contains a duplicate Question ID: \(identifier)."
        case let .duplicateProfileID(identifier):
            "The admissions manifest contains a duplicate profile ID: \(identifier)."
        case let .duplicateSourceID(identifier):
            "The admissions manifest contains a duplicate source ID: \(identifier)."
        case let .duplicateTopicID(identifier):
            "The admissions manifest contains a duplicate topic ID: \(identifier)."
        case let .duplicateProgrammeDay(day):
            "The admissions manifest contains duplicate Day \(day)."
        case let .duplicateAssignmentID(identifier):
            "The admissions manifest contains a duplicate assignment ID: \(identifier)."
        case let .unresolvedQuestionSource(questionID, sourceID):
            "Question \(questionID) references missing source \(sourceID)."
        case let .unresolvedAssignment(identifier):
            "Programme assignment \(identifier) does not resolve to a Question."
        case let .unresolvedProgrammeDay(day):
            "Programme assignment references missing Day \(day)."
        case let .missingResourceFilename(identifier):
            "Source \(identifier) has no bundled-resource filename."
        case let .invalidQuestionPage(identifier):
            "Question \(identifier) has an invalid page reference."
        case let .invalidPreparationClassification(identifier):
            "Question \(identifier) contains invalid canonical preparation-stream metadata."
        case let .contradictoryQuestionMetadata(identifier):
            "Question \(identifier) contains contradictory validity or protection metadata."
        case let .invalidProgrammeDay(day):
            "Programme Day \(day) contains invalid schedule metadata."
        }
    }
}
