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
        let key = "\(distribution.rawValue)#\(items.count)"
        if let cached, cached.key == key { return cached.sources }
        guard let manifest = try? AdmissionsManifest.bundled(),
              let registry = TMUAResourceRegistry.bundled(in: bundle) else { return [] }
        let solutions = try? AdmissionsSolutionsManifest.bundled(in: bundle)
        let built = build(manifest: manifest, solutions: solutions, registry: registry, distribution: distribution,
                          items: items, isBundled: { SourceLibraryServiceLookup.paperExists($0, bundle: bundle) })
        cached = (key, built)
        return built
    }

    /// Pure assembly, testable without bundle files.
    nonisolated static func build(manifest: AdmissionsManifest, solutions: AdmissionsSolutionsManifest?,
                                  registry: TMUAResourceRegistry, distribution: TMUAContentDistribution,
                                  items: [TMUAContentItem], isBundled: (String) -> Bool) -> [TMUAResourceSource] {
        let autoMarked = Dictionary(items.compactMap { item in item.libraryQuestionID.map { ($0, item.stableId) } },
                                    uniquingKeysWith: { first, _ in first })
        // A verified crop's page corrects the original index (Specimen Paper 1 Q5 is on page 5, not 4).
        let verifiedPages = Dictionary(items.compactMap { item -> (String, Int)? in
            guard let id = item.libraryQuestionID, let page = item.presentation?.regions.first?.page else { return nil }
            return (id, page + 1)
        }, uniquingKeysWith: { first, _ in first })
        let questionsBySource = Dictionary(grouping: manifest.questions, by: { $0.sourceID ?? "" })
        var solutionPages: [String: Int] = [:]
        for link in solutions?.links ?? [] where link.mappingConfidence == .verifiedPage {
            if let page = link.startPage, solutionPages[link.questionID] == nil { solutionPages[link.questionID] = page }
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
                .sorted { ($0.questionNumber ?? Int($0.questionLabel) ?? 0, $0.questionLabel) < ($1.questionNumber ?? Int($1.questionLabel) ?? 0, $1.questionLabel) }
                .map { question in
                    TMUAResourceQuestion(
                        id: question.externalQuestionID, label: question.questionLabel,
                        page: verifiedPages[question.externalQuestionID] ?? question.page,
                        topic: question.primaryTopic, difficultyLabel: question.difficultyLabel,
                        paperFit: question.tmuaPaperFit, format: question.format,
                        autoMarkedItemID: autoMarked[question.externalQuestionID],
                        solutionPage: solutionPages[question.externalQuestionID])
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
                labelCorrection: override?.paper != nil && override?.paper != source.paper ? override?.note : nil))
        }
        return result.sorted { lhs, rhs in
            let order = TMUAResourceProvider.Kind.allCases
            let left = order.firstIndex(of: lhs.kind) ?? 0, right = order.firstIndex(of: rhs.kind) ?? 0
            if left != right { return left < right }
            if lhs.provider.name != rhs.provider.name { return lhs.provider.name < rhs.provider.name }
            if lhs.year != rhs.year { return (lhs.year ?? 0) > (rhs.year ?? 0) }
            return lhs.title < rhs.title
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
