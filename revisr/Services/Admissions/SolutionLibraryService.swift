import Foundation

struct QuestionSolutionResolution: Identifiable {
    let link: QuestionSolutionLink
    let document: SolutionDocument
    let url: URL

    var id: String { link.stableLinkID }
}

struct SolutionLibraryAudit: Equatable {
    let expectedCount: Int
    let resolvedCount: Int
    let missingSolutionIDs: [String]

    var isComplete: Bool {
        expectedCount == resolvedCount && missingSolutionIDs.isEmpty
    }
}

/// A render-time index for the question bank. Building it is linear in the
/// imported solution library; lookups while SwiftUI creates rows are constant
/// time and do not repeatedly fault every QuestionSolutionLink relationship.
struct QuestionBankSolutionIndex {
    private let linksByQuestionID: [String: [QuestionSolutionLink]]
    private let documentsBySourceID: [String: [SolutionDocument]]
    private let resolvedDocumentIDs: Set<String>
    private let verifiedQuestionIDsByDocumentID: [String: Set<String>]

    init(
        documents: [SolutionDocument],
        links: [QuestionSolutionLink],
        bundle: Bundle = .main
    ) {
        var linksByQuestionID: [String: [QuestionSolutionLink]] = [:]
        var verifiedQuestionIDsByDocumentID: [String: Set<String>] = [:]

        for link in links where link.isImportedActive {
            guard let questionID = link.question?.externalQuestionID else { continue }
            linksByQuestionID[questionID, default: []].append(link)
            if link.mappingConfidence == .verifiedPage,
               let documentID = link.solutionDocument?.stableSolutionID {
                verifiedQuestionIDsByDocumentID[documentID, default: []].insert(questionID)
            }
        }

        var documentsBySourceID: [String: [SolutionDocument]] = [:]
        var resolvedDocumentIDs: Set<String> = []
        for document in documents where document.isImportedActive {
            for sourceID in document.effectiveRelatedSourceIDs {
                documentsBySourceID[sourceID, default: []].append(document)
            }
            if SolutionLibraryService.bundledURL(for: document, in: bundle) != nil {
                resolvedDocumentIDs.insert(document.stableSolutionID)
            }
        }

        self.linksByQuestionID = linksByQuestionID
        self.documentsBySourceID = documentsBySourceID
        self.resolvedDocumentIDs = resolvedDocumentIDs
        self.verifiedQuestionIDsByDocumentID = verifiedQuestionIDsByDocumentID
    }

    func links(for question: AdmissionsQuestion) -> [QuestionSolutionLink] {
        linksByQuestionID[question.externalQuestionID] ?? []
    }

    func availability(for source: SourceDocument) -> SolutionAvailability {
        guard let documents = documentsBySourceID[source.stableSourceID],
              !documents.isEmpty else { return .pendingSource }
        guard documents.contains(where: { resolvedDocumentIDs.contains($0.stableSolutionID) }) else {
            return .unavailable
        }

        let directlyMappedQuestionIDs = documents.reduce(into: Set<String>()) { result, document in
            result.formUnion(verifiedQuestionIDsByDocumentID[document.stableSolutionID] ?? [])
        }
        return directlyMappedQuestionIDs.count == source.questionUnitCount ? .available : .partial
    }
}

enum SolutionLibraryService {
    static let bundleSubdirectory = "AdmissionsSolutions"

    static func bundledURL(
        for document: SolutionDocument,
        in bundle: Bundle = .main
    ) -> URL? {
        switch document.resourceContainer {
        case .solutionBundle:
            bundle.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension,
                subdirectory: bundleSubdirectory
            ) ?? bundle.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension
            )
        case .sourcePaperBundle:
            bundle.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension,
                subdirectory: SourceLibraryService.bundleSubdirectory
            ) ?? bundle.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension
            )
        case .videoBundle:
            bundle.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension,
                subdirectory: "AdmissionsVideos"
            ) ?? bundle.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension
            )
        }
    }

    static func resolutions(
        for question: AdmissionsQuestion,
        links: [QuestionSolutionLink],
        in bundle: Bundle = .main
    ) -> [QuestionSolutionResolution] {
        links.compactMap { link in
            guard link.isImportedActive,
                  link.question?.externalQuestionID == question.externalQuestionID,
                  let document = link.solutionDocument,
                  document.isImportedActive,
                  let url = bundledURL(for: document, in: bundle) else { return nil }
            return QuestionSolutionResolution(link: link, document: document, url: url)
        }
        .sorted {
            if $0.document.solutionType.preferenceOrder != $1.document.solutionType.preferenceOrder {
                return $0.document.solutionType.preferenceOrder < $1.document.solutionType.preferenceOrder
            }
            return $0.document.displayName < $1.document.displayName
        }
    }

    static func availability(
        for source: SourceDocument,
        documents: [SolutionDocument],
        links: [QuestionSolutionLink],
        in bundle: Bundle = .main
    ) -> SolutionAvailability {
        let sourceDocuments = documents.filter {
            $0.isImportedActive && $0.effectiveRelatedSourceIDs.contains(source.stableSourceID)
        }
        guard !sourceDocuments.isEmpty else { return .pendingSource }
        guard sourceDocuments.contains(where: { bundledURL(for: $0, in: bundle) != nil }) else {
            return .unavailable
        }
        let documentIDs = Set(sourceDocuments.map(\.stableSolutionID))
        let directQuestionIDs = Set(links.compactMap { link -> String? in
            guard link.isImportedActive,
                  link.mappingConfidence == .verifiedPage,
                  let documentID = link.solutionDocument?.stableSolutionID,
                  documentIDs.contains(documentID) else { return nil }
            return link.question?.externalQuestionID
        })
        return directQuestionIDs.count == source.questionUnitCount ? .available : .partial
    }

    static func revealRequirement(
        for question: AdmissionsQuestion,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SolutionRevealRequirement {
        if question.protection != .none || isFutureOfficialBenchmark(
            question,
            now: now,
            calendar: calendar
        ) {
            return .protectedQuestion
        }
        return question.attempts.isEmpty ? .unattempted : .none
    }

    private static func isFutureOfficialBenchmark(
        _ question: AdmissionsQuestion,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard question.family == "TMUA Actual" else { return false }
        return question.programmeAssignments.contains { assignment in
            guard assignment.isImportedActive,
                  let day = assignment.programmeDay,
                  let programme = day.programme else { return false }
            let scheduledDate = programme.date(for: day.dayNumber, calendar: calendar)
            return calendar.startOfDay(for: scheduledDate) > calendar.startOfDay(for: now)
        }
    }

    static func audit(
        documents: [SolutionDocument],
        in bundle: Bundle = .main
    ) -> SolutionLibraryAudit {
        let active = documents.filter(\.isImportedActive)
        let missing = active.filter { bundledURL(for: $0, in: bundle) == nil }
            .map(\.stableSolutionID).sorted()
        return SolutionLibraryAudit(
            expectedCount: active.count,
            resolvedCount: active.count - missing.count,
            missingSolutionIDs: missing
        )
    }
}
