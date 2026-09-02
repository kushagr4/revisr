import Foundation
import SwiftData

@MainActor
enum AdmissionsSolutionsImportService {
    static let supportedFormatVersions = 1...2

    static func seedBundledManifestIfNeeded(in context: ModelContext) throws {
        let manifest = try AdmissionsSolutionsManifest.bundled()
        try upsert(manifest, in: context)
    }

    static func upsert(
        _ manifest: AdmissionsSolutionsManifest,
        in context: ModelContext
    ) throws {
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsSolutionsImportError.unsupportedFormat(manifest.formatVersion)
        }
        let sourceIDs = Set(try context.fetch(FetchDescriptor<SourceDocument>()).map(\.stableSourceID))
        let questionIDs = Set(try context.fetch(FetchDescriptor<AdmissionsQuestion>()).map(\.externalQuestionID))
        try validate(manifest, sourceIDs: sourceIDs, questionIDs: questionIDs)
        do {
            try performUpsert(manifest, in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func performUpsert(
        _ manifest: AdmissionsSolutionsManifest,
        in context: ModelContext
    ) throws {

        let sources = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<SourceDocument>())
                .map { ($0.stableSourceID, $0) }
        )
        let questions = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<AdmissionsQuestion>())
                .map { ($0.externalQuestionID, $0) }
        )
        var documents = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<SolutionDocument>())
                .map { ($0.stableSolutionID, $0) }
        )
        var links = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<QuestionSolutionLink>())
                .map { ($0.stableLinkID, $0) }
        )

        if documents.count == manifest.documents.count,
           links.count == manifest.links.count,
           documents.values.allSatisfy({
               $0.isImportedActive && $0.importRevision == manifest.importRevision
           }),
           links.values.allSatisfy({
               $0.isImportedActive && $0.importRevision == manifest.importRevision
           }) {
            return
        }

        let activeDocumentIDs = Set(manifest.documents.map(\.stableSolutionID))
        let activeLinkIDs = Set(manifest.links.map(\.stableLinkID))

        for record in manifest.documents {
            let source: SourceDocument?
            if let sourceID = record.sourceID {
                guard let resolved = sources[sourceID] else {
                    throw AdmissionsSolutionsImportError.unresolvedSource(sourceID)
                }
                source = resolved
            } else {
                source = nil
            }
            let document = documents[record.stableSolutionID] ?? SolutionDocument(
                stableSolutionID: record.stableSolutionID,
                displayName: record.displayName,
                solutionType: record.solutionType,
                resourceName: record.resourceName,
                resourceExtension: record.resourceExtension,
                resourceContainer: record.resourceContainer,
                family: record.family,
                provenanceOrganization: record.provenanceOrganization,
                provenanceTitle: record.provenanceTitle,
                originalFilename: record.originalFilename,
                availability: record.availability,
                isVerified: record.isVerified,
                importRevision: manifest.importRevision
            )
            if documents[record.stableSolutionID] == nil {
                context.insert(document)
                documents[record.stableSolutionID] = document
            }
            document.displayName = record.displayName
            document.solutionType = record.solutionType
            document.resourceName = record.resourceName
            document.resourceExtension = record.resourceExtension
            document.resourceContainer = record.resourceContainer
            document.family = record.family
            document.year = record.year
            document.paper = record.paper
            document.provenanceOrganization = record.provenanceOrganization
            document.provenanceTitle = record.provenanceTitle
            document.originalFilename = record.originalFilename
            document.pageCount = record.pageCount
            document.checksum = record.sha256
            if let value = record.mediaKind { document.mediaKind = value }
            if let values = record.additionalSourceIDs { document.additionalRelatedSourceIDs = values }
            if let value = record.normalizedTextChecksum { document.normalizedTextChecksum = value }
            if let value = record.semanticDocumentIdentity { document.semanticDocumentIdentity = value }
            if let value = record.duplicateReviewState { document.duplicateReviewState = value }
            if let values = record.possibleDuplicateSolutionIDs { document.possibleDuplicateSolutionIDs = values }
            document.availability = record.availability
            document.isVerified = record.isVerified
            document.importRevision = manifest.importRevision
            document.isImportedActive = true
            document.relatedSource = source
        }

        for record in manifest.links {
            guard let document = documents[record.solutionID] else {
                throw AdmissionsSolutionsImportError.unresolvedSolution(record.solutionID)
            }
            guard let question = questions[record.questionID] else {
                throw AdmissionsSolutionsImportError.unresolvedQuestion(record.questionID)
            }
            let link = links[record.stableLinkID] ?? QuestionSolutionLink(
                stableLinkID: record.stableLinkID,
                startPage: record.startPage,
                startTimeSeconds: record.startTimeSeconds,
                endTimeSeconds: record.endTimeSeconds,
                mappingConfidence: record.mappingConfidence,
                importRevision: manifest.importRevision
            )
            if links[record.stableLinkID] == nil {
                context.insert(link)
                links[record.stableLinkID] = link
            }
            link.startPage = record.startPage
            link.endPage = record.endPage
            link.startTimeSeconds = record.startTimeSeconds
            link.endTimeSeconds = record.endTimeSeconds
            link.problemLabel = record.problemLabel
            link.mappingConfidence = record.mappingConfidence
            link.importRevision = manifest.importRevision
            link.isImportedActive = true
            link.question = question
            link.solutionDocument = document
        }

        for (identifier, link) in links where !activeLinkIDs.contains(identifier) {
            link.isImportedActive = false
        }
        for (identifier, document) in documents where !activeDocumentIDs.contains(identifier) {
            document.isImportedActive = false
        }
        if context.hasChanges { try context.save() }
    }

    static func validate(
        _ manifest: AdmissionsSolutionsManifest,
        sourceIDs: Set<String>,
        questionIDs: Set<String>
    ) throws {
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsSolutionsImportError.unsupportedFormat(manifest.formatVersion)
        }
        var documentIDs = Set<String>()
        for document in manifest.documents where !documentIDs.insert(document.stableSolutionID).inserted {
            throw AdmissionsSolutionsImportError.duplicateSolutionID(document.stableSolutionID)
        }
        var linkIDs = Set<String>()
        for link in manifest.links where !linkIDs.insert(link.stableLinkID).inserted {
            throw AdmissionsSolutionsImportError.duplicateLinkID(link.stableLinkID)
        }

        let documentsByID = Dictionary(uniqueKeysWithValues: manifest.documents.map {
            ($0.stableSolutionID, $0)
        })
        for document in manifest.documents {
            guard !document.resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !document.resourceExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AdmissionsSolutionsImportError.missingResourceFilename(document.stableSolutionID)
            }
            if let sourceID = document.sourceID, !sourceIDs.contains(sourceID) {
                throw AdmissionsSolutionsImportError.unresolvedSource(sourceID)
            }
            if let additional = document.additionalSourceIDs {
                guard Set(additional).count == additional.count,
                      additional.allSatisfy({ sourceIDs.contains($0) && $0 != document.sourceID }) else {
                    throw AdmissionsSolutionsImportError.unresolvedSource(
                        additional.first(where: { !sourceIDs.contains($0) || $0 == document.sourceID })
                            ?? document.stableSolutionID
                    )
                }
            }
            if let possible = document.possibleDuplicateSolutionIDs {
                guard Set(possible).count == possible.count,
                      possible.allSatisfy({ documentIDs.contains($0) && $0 != document.stableSolutionID }) else {
                    throw AdmissionsSolutionsImportError.contradictoryDuplicateMetadata(document.stableSolutionID)
                }
            }
        }

        for link in manifest.links {
            guard let document = documentsByID[link.solutionID] else {
                throw AdmissionsSolutionsImportError.unresolvedSolution(link.solutionID)
            }
            guard questionIDs.contains(link.questionID) else {
                throw AdmissionsSolutionsImportError.unresolvedQuestion(link.questionID)
            }
            let mediaKind = document.mediaKind
                ?? (document.resourceExtension.lowercased() == "mp4" ? .video : .pdf)
            switch mediaKind {
            case .pdf:
                guard let startPage = link.startPage, startPage >= 1,
                      link.endPage.map({ $0 >= startPage }) ?? true else {
                    throw AdmissionsSolutionsImportError.invalidPageRange(link.stableLinkID)
                }
                guard link.startTimeSeconds == nil, link.endTimeSeconds == nil else {
                    throw AdmissionsSolutionsImportError.invalidMediaMapping(link.stableLinkID)
                }
            case .video:
                guard link.startPage == nil, link.endPage == nil,
                      link.mappingConfidence != .verifiedPage else {
                    throw AdmissionsSolutionsImportError.invalidMediaMapping(link.stableLinkID)
                }
                guard link.startTimeSeconds.map({ $0 >= 0 }) ?? true,
                      link.endTimeSeconds.map({ end in
                          end >= 0 && end >= (link.startTimeSeconds ?? 0)
                      }) ?? true else {
                    throw AdmissionsSolutionsImportError.invalidTimeRange(link.stableLinkID)
                }
            }
        }
    }
}
