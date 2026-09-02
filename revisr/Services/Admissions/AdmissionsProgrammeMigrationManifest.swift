import Foundation

struct AdmissionsProgrammeMigrationManifest: Decodable {
    let formatVersion: Int
    let migrationRevision: String
    let programmeID: String
    let baseProgrammeImportRevision: String
    let preserveHistoryThroughDay: Int
    let examDate: String
    let flexDates: [String]
    let unavailableWeekdays: [String]
    let days: [AdmissionsManifest.Day]
    let assignments: [AdmissionsManifest.Assignment]

    static func bundled() throws -> AdmissionsProgrammeMigrationManifest {
        guard let url = Bundle.main.url(
            forResource: "AdmissionsProgrammeMigration",
            withExtension: "json"
        ) else {
            throw AdmissionsProgrammeMigrationError.missingBundledManifest
        }
        return try JSONDecoder().decode(
            AdmissionsProgrammeMigrationManifest.self,
            from: Data(contentsOf: url)
        )
    }
}

enum AdmissionsProgrammeMigrationError: LocalizedError {
    case missingBundledManifest
    case unsupportedFormat(Int)
    case unresolvedProgramme(String)
    case duplicateDay(Int)
    case duplicateAssignment(String)
    case unresolvedDay(Int)
    case unresolvedQuestion(String)
    case invalidDay(Int)
    case protectedQuestion(String)
    case historicalAssignmentConflict(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledManifest:
            "The bundled programme migration is missing."
        case let .unsupportedFormat(version):
            "Programme migration format \(version) is unsupported."
        case let .unresolvedProgramme(identifier):
            "Programme migration cannot resolve programme \(identifier)."
        case let .duplicateDay(number):
            "Programme migration contains duplicate Day \(number)."
        case let .duplicateAssignment(identifier):
            "Programme migration contains duplicate assignment \(identifier)."
        case let .unresolvedDay(number):
            "Programme migration references missing Day \(number)."
        case let .unresolvedQuestion(identifier):
            "Programme migration references missing question \(identifier)."
        case let .invalidDay(number):
            "Programme migration contains invalid schedule data for Day \(number)."
        case let .protectedQuestion(identifier):
            "Programme migration attempts to schedule protected question \(identifier)."
        case let .historicalAssignmentConflict(identifier):
            "Programme migration conflicts with historical assignment \(identifier)."
        }
    }
}
