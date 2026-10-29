import Foundation

/// Provider-level credit, verified link and access decision (`TMUAResourceProviders.json`).
struct TMUAResourceProvider: Decodable, Hashable, Sendable {
    enum Kind: String, Decodable, CaseIterable, Sendable {
        case officialTMUA = "official_tmua"
        case otherAdmissionsTest = "other_admissions_test"
        case independentMock = "independent_mock"
        case competition
        case reference

        var title: String {
            switch self {
            case .officialTMUA: "Official TMUA papers"
            case .otherAdmissionsTest: "Other admissions tests"
            case .independentMock: "Independent TMUA mocks"
            case .competition: "Mathematics competitions"
            case .reference: "Reference"
            }
        }
    }

    /// What a public build may show: papers listed and linked, the provider credited and
    /// linked without listing papers, or nothing.
    enum PublicAccess: String, Decodable, Sendable {
        case listed
        case provider
        case restricted
    }

    let key: String
    let name: String
    let credit: String
    let kind: Kind
    let families: [String]
    let url: String?
    let linkTitle: String?
    let publicAccess: PublicAccess
    let permission: String
    let terms: String

    var link: URL? { url.flatMap(URL.init(string:)) }
}

struct TMUAResourceRegistry: Decodable, Sendable {
    struct Override: Decodable, Sendable {
        let sourceID: String
        let provider: String
        let paper: String?
        let note: String?
    }

    let version: Int
    let checkedOn: String
    let providers: [TMUAResourceProvider]
    let sourceOverrides: [Override]

    static func bundled(in bundle: Bundle = .main) -> TMUAResourceRegistry? {
        guard let url = bundle.url(forResource: "TMUAResourceProviders", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TMUAResourceRegistry.self, from: data)
    }

    func provider(family: String, sourceID: String) -> TMUAResourceProvider? {
        if let override = sourceOverrides.first(where: { $0.sourceID == sourceID }) {
            return providers.first { $0.key == override.provider }
        }
        return providers.first { $0.families.contains(family) }
    }
}

/// How a student reaches a resource in this build.
enum TMUAResourceAccess: Equatable, Sendable {
    /// The paper is bundled: internal builds only, as the owner's personal study copy.
    case studyCopy
    /// Listed and linked to the provider's own page, which offers it.
    case providerLink
}

/// One indexed question in a source, from the original Revisr library index.
struct TMUAResourceQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let page: Int?
    let topic: String
    let difficultyLabel: String
    let paperFit: String?
    let format: String?
    /// The bank item that auto-marks this question in this build, when one exists.
    let autoMarkedItemID: String?
    let solutionPage: Int?
    /// The library index's estimate (1–5), or the indexer's for papers added in R4.
    var difficulty: Int? = nil
    /// The solution file (`SolutionFile.resourceName`) that `solutionPage` refers to.
    var solutionResource: String? = nil
}

/// A paper, mock, worksheet or reference document in the unified library.
struct TMUAResourceSource: Identifiable, Hashable, Sendable {
    struct SolutionFile: Hashable, Sendable {
        let title: String
        let resourceName: String
        let resourceExtension: String
        let isVideo: Bool
    }

    let id: String
    let title: String
    let provider: TMUAResourceProvider
    let family: String
    let paperLabel: String?
    let year: Int?
    let questions: [TMUAResourceQuestion]
    let solutions: [SolutionFile]
    let access: TMUAResourceAccess
    let labelCorrection: String?
    /// The paper file's SHA-256, when Revisr holds the file; with a page it fingerprints a question.
    var checksum: String? = nil
    /// Internal builds: where the owner's copy is when the paper is not bundled (R4 supplement).
    var holdingNote: String? = nil

    var kind: TMUAResourceProvider.Kind {
        if family == "Reference" || family == "Specification" { return .reference }
        return provider.kind
    }

    var autoMarkedCount: Int { questions.filter { $0.autoMarkedItemID != nil }.count }

    var subtitle: String {
        var parts = [provider.credit]
        if !questions.isEmpty { parts.append("\(questions.count) question\(questions.count == 1 ? "" : "s")") }
        if !solutions.isEmpty { parts.append(Set(solutions.map(\.title)).sorted().joined(separator: ", ").lowercased()) }
        return parts.joined(separator: " · ")
    }
}

/// The unified library: Revisr's bank plus the original Revisr source collection, labelled with
/// what this build may show. Public builds list only providers whose own pages offer the papers;
/// internal builds add the owner's bundled papers as personal study copies.
@MainActor
enum TMUAResourceCatalogue {
    private static var cached: (key: String, sources: [TMUAResourceSource])?

    static func sources(distribution: TMUAContentDistribution, items: [TMUAContentItem],
                        bundle: Bundle = .main) -> [TMUAResourceSource] {
        // Keyed by the items themselves and the bundle, not just their number, so a different bank
        // of the same size (in tests) never reuses another's library.
        let key = "\(distribution.rawValue)#\(items.count)#\(items.first?.versionKey ?? "")#\(items.last?.versionKey ?? "")#\(bundle.bundlePath)"
        if let cached, cached.key == key { return cached.sources }
        guard let manifest = try? AdmissionsManifest.bundled(),
              let registry = TMUAResourceRegistry.bundled(in: bundle) else { return [] }
        let solutions = try? AdmissionsSolutionsManifest.bundled(in: bundle)
        let built = build(manifest: manifest, solutions: solutions, registry: registry, distribution: distribution,
                          items: items, isBundled: { SourceLibraryServiceLookup.paperExists($0, bundle: bundle) },
                          supplement: TMUACatalogueReconciliation.bundled(in: bundle))
        cached = (key, built)
        return built
    }

    /// Independent providers credited and linked to their own sites without listing their papers
    /// (`publicAccess: provider`), so students can find them in any build.
    nonisolated static func linkedProviders(_ registry: TMUAResourceRegistry?) -> [TMUAResourceProvider] {
        (registry?.providers ?? []).filter { $0.publicAccess == .provider && $0.link?.scheme == "https" }
            .sorted { $0.name < $1.name }
    }

    /// Pure assembly, testable without bundle files.
    nonisolated static func build(manifest: AdmissionsManifest, solutions: AdmissionsSolutionsManifest?,
                                  registry: TMUAResourceRegistry, distribution: TMUAContentDistribution,
                                  items: [TMUAContentItem], isBundled: (String) -> Bool,
                                  supplement: TMUACatalogueReconciliation? = nil) -> [TMUAResourceSource] {
        let autoMarked = Dictionary(items.compactMap { item in item.libraryQuestionID.map { ($0, item.stableId) } },
                                    uniquingKeysWith: { first, _ in first })
        // A verified crop's page corrects the original index (Specimen Paper 1 Q5 is on page 5, not 4).
        let verifiedPages = Dictionary(items.compactMap { item -> (String, Int)? in
            guard let id = item.libraryQuestionID, let page = item.presentation?.regions.first?.page else { return nil }
            return (id, page + 1)
        }, uniquingKeysWith: { first, _ in first })
        let questionsBySource = Dictionary(grouping: manifest.questions, by: { $0.sourceID ?? "" })
        var solutionPages: [String: (page: Int, resource: String?)] = [:]
        let resourceNames = Dictionary((solutions?.documents ?? []).map { ($0.stableSolutionID, $0.resourceName) },
                                       uniquingKeysWith: { first, _ in first })
        for link in solutions?.links ?? [] where link.mappingConfidence == .verifiedPage {
            if let page = link.startPage, solutionPages[link.questionID] == nil {
                solutionPages[link.questionID] = (page, resourceNames[link.solutionID])
            }
        }
        let documentsBySource = Dictionary(grouping: (solutions?.documents ?? []).filter { $0.sourceID != nil },
                                           by: { $0.sourceID ?? "" })
        var result: [TMUAResourceSource] = []
        for source in manifest.sources {
            guard let provider = registry.provider(family: source.family, sourceID: source.stableSourceID) else { continue }
            let bundled = distribution == .internal && isBundled(source.stableSourceID)
            let access: TMUAResourceAccess
            if bundled {
                access = .studyCopy
            } else if provider.publicAccess == .listed, provider.link != nil {
                access = .providerLink
            } else {
                continue
            }
            let override = registry.sourceOverrides.first { $0.sourceID == source.stableSourceID }
            let paperLabel = override?.paper ?? source.paper
            let questions = (questionsBySource[source.stableSourceID] ?? [])
                // Paper part first, so a combined Paper 1 + Paper 2 file lists each paper in order; the
                // question ID settles the rest, so the order never depends on the manifest's.
                .sorted { ($0.paper ?? "", $0.questionNumber ?? Int($0.questionLabel) ?? 0, $0.questionLabel, $0.externalQuestionID)
                    < ($1.paper ?? "", $1.questionNumber ?? Int($1.questionLabel) ?? 0, $1.questionLabel, $1.externalQuestionID) }
                .map { question in
                    TMUAResourceQuestion(
                        id: question.externalQuestionID, label: question.questionLabel,
                        page: verifiedPages[question.externalQuestionID] ?? question.page,
                        topic: question.primaryTopic, difficultyLabel: question.difficultyLabel,
                        paperFit: question.tmuaPaperFit, format: question.format,
                        autoMarkedItemID: autoMarked[question.externalQuestionID],
                        solutionPage: solutionPages[question.externalQuestionID]?.page, difficulty: question.difficulty,
                        solutionResource: solutionPages[question.externalQuestionID]?.resource)
                }
            // Solution videos were saved with a YouTube downloader; they are not surfaced (R1 licensing plan).
            let files = (documentsBySource[source.stableSourceID] ?? [])
                .filter { bundled && $0.availability != .unavailable && $0.resourceExtension != "mp4" }
                .map { TMUAResourceSource.SolutionFile(title: $0.solutionType.title, resourceName: $0.resourceName,
                                                       resourceExtension: $0.resourceExtension,
                                                       isVideo: $0.resourceExtension == "mp4") }
            result.append(TMUAResourceSource(
                id: source.stableSourceID, title: displayTitle(source, paperLabel: paperLabel, provider: provider),
                provider: provider, family: source.family, paperLabel: paperLabel, year: source.year,
                questions: questions, solutions: files, access: access,
                labelCorrection: override?.paper != nil && override?.paper != source.paper ? override?.note : nil,
                checksum: bundled ? source.checksum : nil))
        }
        result += supplementSources(supplement, solutions: solutions, registry: registry, distribution: distribution)
        return result.sorted { lhs, rhs in
            let order = TMUAResourceProvider.Kind.allCases
            let left = order.firstIndex(of: lhs.kind) ?? 0, right = order.firstIndex(of: rhs.kind) ?? 0
            if left != right { return left < right }
            if lhs.provider.name != rhs.provider.name { return lhs.provider.name < rhs.provider.name }
            if lhs.year != rhs.year { return (lhs.year ?? 0) > (rhs.year ?? 0) }
            return (lhs.title, lhs.id) < (rhs.title, rhs.id)
        }
    }

    /// R4: papers the bundled library lacks: question papers held only in the owner's Drive, and
    /// papers Revisr's collection knows only from their solutions. They come only from providers
    /// whose own pages offer the papers, so every build lists them with the publisher's link;
    /// internal builds add the bundled solutions and say where the owner's copy is.
    nonisolated static func supplementSources(_ supplement: TMUACatalogueReconciliation?,
                                              solutions: AdmissionsSolutionsManifest?,
                                              registry: TMUAResourceRegistry,
                                              distribution: TMUAContentDistribution) -> [TMUAResourceSource] {
        let documents = Dictionary((solutions?.documents ?? []).map { ($0.stableSolutionID, $0) },
                                   uniquingKeysWith: { first, _ in first })
        return (supplement?.documents ?? []).compactMap { document in
            guard let provider = registry.provider(family: document.family, sourceID: document.documentID),
                  provider.publicAccess == .listed, provider.link != nil else { return nil }
            let solution = document.solutionID.flatMap { documents[$0] }
            let files = [solution].compactMap { $0 }
                .filter { distribution == .internal && $0.availability != .unavailable && $0.resourceExtension != "mp4" }
                .map { TMUAResourceSource.SolutionFile(title: $0.solutionType.title, resourceName: $0.resourceName,
                                                       resourceExtension: $0.resourceExtension, isVideo: false) }
            let questions = document.questions.map { question in
                TMUAResourceQuestion(id: question.questionID, label: question.label, page: question.page,
                                     topic: question.legacyTopic,
                                     difficultyLabel: question.difficulty.map(TMUACatalogueEntry.levelTitle) ?? "Not rated",
                                     paperFit: question.paperFit, format: question.format, autoMarkedItemID: nil,
                                     solutionPage: files.isEmpty ? nil : question.solutionPage,
                                     difficulty: question.difficulty, solutionResource: files.first?.resourceName)
            }
            let note: String? = distribution == .internal ? (document.questionPaper == .drive
                ? "Your copy of this paper is in your Google Drive and is not bundled in this build; the publisher’s page offers it too."
                : "Your collection holds only the solutions to this paper; the question paper is on the publisher’s page.") : nil
            return TMUAResourceSource(id: document.documentID, title: document.title, provider: provider,
                                      family: document.family, paperLabel: document.paper, year: document.year,
                                      questions: questions, solutions: files, access: .providerLink,
                                      labelCorrection: nil, checksum: nil, holdingNote: note)
        }
    }

    /// Readable titles: the original index sometimes holds a filename ("Yotta_P2_QP").
    nonisolated static func displayTitle(_ source: AdmissionsManifest.Source, paperLabel: String?,
                                         provider: TMUAResourceProvider) -> String {
        let name = source.displayName.replacingOccurrences(of: "_", with: " ")
        switch source.family {
        case "TMUA Actual":
            return "TMUA \(source.year.map(String.init) ?? "") \(paperLabel ?? "")".trimmingCharacters(in: .whitespaces)
        case "TMUA Mock":
            return "\(provider.name) TMUA mock \(paperLabel ?? "")".trimmingCharacters(in: .whitespaces)
        default:
            return name
        }
    }
}

/// Bundled paper lookup by stable source ID, mirroring `SourceLibraryService.bundledURL`.
enum SourceLibraryServiceLookup {
    static func paperURL(_ sourceID: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: sourceID, withExtension: "pdf", subdirectory: SourceLibraryService.bundleSubdirectory)
            ?? bundle.url(forResource: sourceID, withExtension: "pdf")
    }

    static func paperExists(_ sourceID: String, bundle: Bundle = .main) -> Bool {
        paperURL(sourceID, bundle: bundle) != nil
    }

    static func solutionURL(_ file: TMUAResourceSource.SolutionFile, bundle: Bundle = .main) -> URL? {
        let subdirectory = file.isVideo ? "AdmissionsVideos" : SolutionLibraryService.bundleSubdirectory
        return bundle.url(forResource: file.resourceName, withExtension: file.resourceExtension, subdirectory: subdirectory)
            ?? bundle.url(forResource: file.resourceName, withExtension: file.resourceExtension,
                          subdirectory: SourceLibraryService.bundleSubdirectory)
            ?? bundle.url(forResource: file.resourceName, withExtension: file.resourceExtension)
    }
}
