import Foundation

/// Versioned rules deciding which bank items a build may use. The assembler
/// script applies the same public gate before content is bundled; this check
/// repeats it at runtime so a mislabelled bank cannot widen eligibility.
enum TMUAContentPolicy {
    static let version = "tmua-content-policy-v1"

    /// A soft preference for licensed past/mock questions when they are
    /// available. Coverage always outranks source mix; there is no fixed ratio.
    static let preferredLicensedShare = 0.3

    /// Product decision: a public diagnostic must not silently become
    /// original-only. Changing this requires an explicit product decision.
    static let publicAllowsOriginalOnlyDiagnostic = false

    static func publicGateFailures(_ item: TMUAContentItem) -> [String] {
        var failures: [String] = []
        if item.category == .developmentFixture { failures.append("Development fixture") }
        let rights = item.rights
        let states: [(String, TMUARightsState)] = [
            ("In-app use", rights.inAppUse), ("Redistribution", rights.redistribution),
            ("Commercial use", rights.commercialUse), ("Answer key", rights.answerKey),
            ("Solution", rights.solution)
        ]
        for (name, state) in states where state != .cleared {
            failures.append("\(name) not cleared")
        }
        if item.review.mathematical != .humanApproved { failures.append("Mathematical review outstanding") }
        if item.category == .revisrOriginal && item.review.originality != .humanApproved {
            failures.append("Originality review outstanding")
        }
        if item.review.publication != .approved { failures.append("Publication not approved") }
        if item.category.isLicensedThirdParty && item.source?.url == nil {
            failures.append("Source attribution incomplete")
        }
        return failures
    }

    static func isStructurallyUsable(_ item: TMUAContentItem, syllabus: TMUASyllabus) -> Bool {
        guard let topic = syllabus.topic(item.taxonomy.topic),
              topic.strands.contains(where: { $0.key == item.taxonomy.strand }),
              topic.papers.contains(item.paper),
              (4...8).contains(item.options.count),
              item.options.contains(where: { $0.id == item.correctOptionId }),
              Set(item.options.map(\.id)).count == item.options.count,
              !item.solution.isEmpty, (1...5).contains(item.difficulty) else { return false }
        return true
    }
}

/// The effective content environment for this build and bank.
struct TMUAContentContext: Sendable {
    let bank: TMUAContentBank
    let syllabus: TMUASyllabus
    let distribution: TMUAContentDistribution
    let eligibleItems: [TMUAContentItem]

    /// - Parameter allowsInternalContent: false in release builds, so an
    ///   internal bank is still judged by the public gate.
    /// - Parameter allowsDevelopmentFixtures: only test code passes true.
    init(bank: TMUAContentBank, syllabus: TMUASyllabus,
         allowsInternalContent: Bool = TMUAContentContext.buildAllowsInternalContent,
         allowsDevelopmentFixtures: Bool = false) {
        self.bank = bank
        self.syllabus = syllabus
        let distribution: TMUAContentDistribution = bank.distribution == .internal && allowsInternalContent
            ? .internal : .public
        self.distribution = distribution
        eligibleItems = bank.latestItems.filter { item in
            guard TMUAContentPolicy.isStructurallyUsable(item, syllabus: syllabus) else { return false }
            if item.category == .developmentFixture { return allowsDevelopmentFixtures }
            return distribution == .internal || TMUAContentPolicy.publicGateFailures(item).isEmpty
        }
    }

    static var buildAllowsInternalContent: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    func eligibleItems(for paper: TMUAPaper) -> [TMUAContentItem] {
        eligibleItems.filter { $0.paper == paper.rawValue }
    }

    var licensedItemCount: Int { eligibleItems.filter(\.category.isLicensedThirdParty).count }
    var originalItemCount: Int { eligibleItems.filter { $0.category == .revisrOriginal }.count }
    var unreviewedItemCount: Int {
        eligibleItems.filter { !TMUAContentPolicy.publicGateFailures($0).isEmpty }.count
    }

    var sourceMix: TMUASourceMixStatus {
        if licensedItemCount > 0 { return .mixedAvailable }
        if distribution == .internal { return .originalOnlyDevelopment }
        return TMUAContentPolicy.publicAllowsOriginalOnlyDiagnostic ? .originalOnlyApproved : .blocked
    }

    func availability(for length: TMUADiagnosticLength,
                      excluding exposed: Set<String> = []) -> TMUADiagnosticAvailability {
        if sourceMix == .blocked {
            return .blocked("No rights-cleared past or mock questions are available, so the mixed-source diagnostic cannot be offered in this build.")
        }
        for paper in TMUAPaper.allCases {
            let available = eligibleItems(for: paper).filter { !exposed.contains($0.stableId) }.count
            let needed = length.questions(for: paper)
            if available < needed {
                return .insufficientContent(paper: paper, needed: needed, available: available)
            }
        }
        return .available
    }
}

enum TMUASourceMixStatus: Equatable, Sendable {
    case mixedAvailable
    case originalOnlyDevelopment
    case originalOnlyApproved
    case blocked

    var studentNotice: String? {
        switch self {
        case .mixedAvailable: nil
        case .originalOnlyDevelopment:
            "Development build: no past or mock questions are cleared for use yet, so this diagnostic uses unreviewed original Revisr questions only."
        case .originalOnlyApproved: "This diagnostic uses original Revisr questions."
        case .blocked: "The diagnostic is not available in this build."
        }
    }
}

enum TMUADiagnosticAvailability: Equatable, Sendable {
    case available
    case insufficientContent(paper: TMUAPaper, needed: Int, available: Int)
    case blocked(String)

    var isAvailable: Bool { self == .available }

    var message: String? {
        switch self {
        case .available: nil
        case let .insufficientContent(paper, needed, available):
            "\(paper.title) needs \(needed) approved questions, but only \(available) are available in this build. Revisr will not pad the diagnostic with repeated or unapproved questions."
        case let .blocked(reason): reason
        }
    }
}

/// Loads the assembled bank once per launch.
@MainActor
enum TMUAContentStore {
    static let bankResourceName = "RevisrContentBank"
    private static var cached: TMUAContentContext?

    static func context(bundle: Bundle = .main) -> TMUAContentContext? {
        if let cached { return cached }
        guard let syllabus = TMUASyllabus.load(bundle: bundle) else { return nil }
        let bank: TMUAContentBank
        if let url = bundle.url(forResource: bankResourceName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(TMUAContentBank.self, from: data) {
            bank = decoded
        } else {
            bank = .empty
        }
        let context = TMUAContentContext(bank: bank, syllabus: syllabus)
        cached = context
        return context
    }

    /// Test seam: installs a specific context (for example synthetic fixtures).
    static func install(_ context: TMUAContentContext?) { cached = context }
}
