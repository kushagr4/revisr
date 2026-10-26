import Foundation

struct TMUAPaperScore: Equatable {
    let paper: TMUAPaper
    let questionCount: Int
    let answered: Int
    let correct: Int
    let activeSeconds: Int
    let sessionCount: Int

    var skipped: Int { questionCount - answered }
    var rawScore: String { "\(correct) / \(questionCount)" }
}

struct TMUADiagnosticReport {
    let length: TMUADiagnosticLength
    let initialLength: TMUADiagnosticLength
    let papers: [TMUAPaperScore]
    let topics: [DiagnosticTopicResult]
    let skills: [DiagnosticTopicResult]
    let sampledTopicKeys: [String]
    let unassessedTopicKeys: [String]
    let sampledStrandKeys: [String]
    let compositionNote: String
    let wasExpanded: Bool

    var questionCount: Int { papers.reduce(0) { $0 + $1.questionCount } }
    var correct: Int { papers.reduce(0) { $0 + $1.correct } }
    var answered: Int { papers.reduce(0) { $0 + $1.answered } }
    var skipped: Int { questionCount - answered }
    var activeSeconds: Int { papers.reduce(0) { $0 + $1.activeSeconds } }
    var combinedScore: String { "\(correct) / \(questionCount)" }

    var scoreDisclaimer: String {
        "A raw count of correct answers out of the \(questionCount) questions in Revisr's diagnostic; skipped questions score zero. It is not a TMUA score, is not on the official 1–9 scale and cannot be converted to one."
            + (length.isFullLengthSections ? "" : " These were abbreviated sections, so the result is not comparable with a full-length paper.")
    }

    var timingNote: String {
        var note = "Recorded time counts only while a section was open and running. Pauses, time in other apps and time after the app closed are excluded."
        if wasExpanded {
            note += " Your diagnostic was extended from \(initialLength.title) to \(length.title); the additional questions were answered in separate sessions, not under one continuous timed sitting."
        }
        return note
    }
}

enum TMUADiagnosticReportBuilder {
    /// Reasoning skills that only Paper 2 assesses. Their evidence comes from a
    /// single paper by design, so the engine requires one contributing paper.
    static let paperTwoOnlySkills: Set<String> = [
        "conditional-reasoning", "necessary-sufficient", "quantifier-reasoning", "negation",
        "counterexample", "proof-structure", "error-identification", "deduction"
    ]

    static func build(snapshot: TMUADiagnosticSnapshot, syllabus: TMUASyllabus) -> TMUADiagnosticReport {
        let submittedSections = snapshot.sections.filter { $0.status == .submitted }
        let submittedIDs = Set(submittedSections.map(\.stableID))
        // One observation per question identity: a repeated identity never
        // adds independent evidence.
        var seen = Set<String>()
        let items = snapshot.items
            .filter { submittedIDs.contains($0.sectionID) }
            .sorted { ($0.sectionID, $0.ordinal) < ($1.sectionID, $1.ordinal) }
            .filter { seen.insert($0.itemStableID).inserted }

        let papers = TMUAPaper.allCases.map { paper -> TMUAPaperScore in
            let rows = items.filter { $0.paperRawValue == paper.rawValue }
            let sections = submittedSections.filter { $0.paper == paper }
            return TMUAPaperScore(
                paper: paper,
                questionCount: rows.count,
                answered: rows.filter { $0.selectedOptionID != nil }.count,
                correct: rows.filter { $0.marking == .correct }.count,
                activeSeconds: Int(sections.reduce(0) { $0 + $1.accumulatedSeconds }),
                sessionCount: sections.count)
        }

        let evidence = items.map { item -> DiagnosticEvidence in
            let value: Double? = switch item.marking {
            case .correct?: 1
            case .incorrect?: 0
            case .unanswered?, nil: nil
            }
            return DiagnosticEvidence(
                topic: syllabus.topicTitle(item.topicKey),
                skill: item.skillKey.map(syllabus.skillTitle),
                paperID: "P\(item.paperRawValue)",
                difficulty: item.difficulty,
                answered: item.selectedOptionID != nil,
                value: value)
        }
        let topicPapers = Dictionary(uniqueKeysWithValues: syllabus.topics.map { ($0.title, $0.papers.count) })
        let paperTwoSkillTitles = Set(paperTwoOnlySkills.map(syllabus.skillTitle))
        let topics = DiagnosticAnalysis.aggregate(evidence, exam: .tmua, key: \.topic) { topicPapers[$0] ?? 2 }
        let skills = DiagnosticAnalysis.aggregate(evidence.filter { $0.skill != nil }, exam: .tmua, key: \.skill) {
            paperTwoSkillTitles.contains($0) ? 1 : 2
        }

        let sampledTopics = Set(items.map(\.topicKey))
        // Label confidence by the evidence actually collected: an expansion
        // that is still open does not yet earn the longer length's wording.
        let completedRounds = Dictionary(grouping: snapshot.sections, by: \.round)
            .filter { $0.value.allSatisfy { $0.status == .submitted } }
        let evidenceLength = completedRounds.max { $0.key < $1.key }?.value.first?.roundTargetLength
            ?? snapshot.diagnostic.initialLength
        return TMUADiagnosticReport(
            length: evidenceLength,
            initialLength: snapshot.diagnostic.initialLength,
            papers: papers,
            topics: topics,
            skills: skills,
            sampledTopicKeys: syllabus.topics.map(\.key).filter(sampledTopics.contains),
            unassessedTopicKeys: syllabus.topics.map(\.key).filter { !sampledTopics.contains($0) },
            sampledStrandKeys: Array(Set(items.map(\.strandKey))).sorted(),
            compositionNote: snapshot.diagnostic.sourceCompositionNote,
            wasExpanded: completedRounds.count > 1)
    }
}
