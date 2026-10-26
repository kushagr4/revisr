import Foundation

/// The student's chosen diagnostic size. Counts are cumulative targets, so an
/// expansion only adds the difference for each paper.
enum TMUADiagnosticLength: String, CaseIterable, Codable, Identifiable, Sendable {
    case starter
    case quick
    case balanced
    case comprehensive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starter: "Starter"
        case .quick: "Quick"
        case .balanced: "Balanced"
        case .comprehensive: "Comprehensive"
        }
    }

    var totalQuestions: Int { paperOneQuestions + paperTwoQuestions }

    var paperOneQuestions: Int {
        switch self {
        case .starter: 5
        case .quick: 8
        case .balanced: 10
        case .comprehensive: 20
        }
    }

    var paperTwoQuestions: Int {
        switch self {
        case .starter: 5
        case .quick: 7
        case .balanced: 10
        case .comprehensive: 20
        }
    }

    func questions(for paper: TMUAPaper) -> Int {
        paper == .one ? paperOneQuestions : paperTwoQuestions
    }

    /// Official sections are 20 questions in 75 minutes; shorter sections get a
    /// proportional advisory time. Nothing expires or auto-submits.
    func advisoryMinutes(for paper: TMUAPaper) -> Int {
        let count = questions(for: paper)
        return count == 20 ? 75 : Int((Double(count) * 75 / 20).rounded(.up))
    }

    var isFullLengthSections: Bool { self == .comprehensive }

    var summary: String {
        switch self {
        case .starter: "A quick first look. Limited evidence, broad uncertainty."
        case .quick: "Somewhat broader coverage while staying short."
        case .balanced: "A more substantial sample of knowledge and reasoning."
        case .comprehensive: "Two full-length sections with the widest coverage."
        }
    }

    var confidenceTitle: String {
        switch self {
        case .starter: "Provisional"
        case .quick: "Screening"
        case .balanced: "Developing"
        case .comprehensive: "Broadest available"
        }
    }

    var confidenceExplanation: String {
        switch self {
        case .starter:
            "Ten questions give a provisional starting point. Many syllabus areas were not sampled, so your plan keeps broad coverage and treats every finding as tentative."
        case .quick:
            "Fifteen questions give a broader screening. Topic findings remain conservative because most topics were sampled only once or twice."
        case .balanced:
            "Twenty questions sample more of the syllabus, so priorities are clearer where the evidence supports them. Several areas still have little evidence."
        case .comprehensive:
            "Forty questions give the broadest evidence Revisr collects. Topics with few questions are still labelled as having insufficient evidence; no single question measures mastery of a topic."
        }
    }

    var isRecommended: Bool { self == .comprehensive }

    /// Lengths this one can grow into without discarding any submitted work.
    var expansionTargets: [TMUADiagnosticLength] {
        Self.allCases.filter { $0.totalQuestions > totalQuestions }
    }

    func additionalQuestions(to target: TMUADiagnosticLength, paper: TMUAPaper) -> Int {
        max(0, target.questions(for: paper) - questions(for: paper))
    }
}
