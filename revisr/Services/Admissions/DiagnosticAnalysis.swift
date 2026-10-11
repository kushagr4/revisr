import Foundation

enum DiagnosticEvidenceLevel: String {
    case strongDifficulty
    case possibleImprovement
    case relativeStrength
    case insufficient

    var title: String {
        switch self {
        case .strongDifficulty: "Strong evidence of difficulty"
        case .possibleImprovement: "Possible area for improvement"
        case .relativeStrength: "Relative strength"
        case .insufficient: "Insufficient evidence"
        }
    }
}

struct DiagnosticTopicResult {
    let name: String
    let assessedCount: Int
    let unansweredCount: Int
    let unassessedCount: Int
    let level: DiagnosticEvidenceLevel
    let explanation: String
}

struct DiagnosticPaperResult {
    let ordinal: Int
    let sourceID: String
    let questionCount: Int
    let answeredCount: Int
    let assessedCount: Int
    let correctCount: Int
    let incorrectCount: Int
    let elapsedSeconds: Int
    let displayScore: String
    let provenance: String
}

struct DiagnosticReport {
    let papers: [DiagnosticPaperResult]
    let topics: [DiagnosticTopicResult]
    let skills: [DiagnosticTopicResult]
}

enum DiagnosticAnalysis {
    static func report(
        exam: PublicExamKind,
        papers: [DiagnosticPaperRecord],
        responses: [DiagnosticResponse],
        questions: [AdmissionsQuestion]
    ) -> DiagnosticReport {
        let questionByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.externalQuestionID, $0) })
        let responsesByPaper = Dictionary(grouping: responses, by: \.paperID)
        let paperResults = papers.sorted { $0.ordinal < $1.ordinal }.map { paper in
            paperResult(exam: exam, paper: paper, responses: responsesByPaper[paper.stableID] ?? [])
        }
        let activePapers = Set(papers.map(\.stableID))
        let evidence = responses.compactMap { response -> Evidence? in
            guard activePapers.contains(response.paperID),
                  let question = questionByID[response.questionID] else { return nil }
            let answered = exam == .bmo ? response.wasAttempted : response.selectedOption != nil
            let value: Double?
            if exam == .bmo {
                value = response.selfEstimatedMarks.map { Double($0) / 10 }
            } else {
                switch response.marking {
                case .correct: value = 1
                case .incorrect: value = 0
                case .unassessed: value = nil
                }
            }
            return Evidence(
                topic: question.primaryTopic,
                skill: question.reasoningSkill,
                paperID: response.paperID,
                difficulty: question.difficulty,
                answered: answered,
                value: value
            )
        }
        return DiagnosticReport(
            papers: paperResults,
            topics: aggregate(evidence, exam: exam, key: \.topic),
            skills: aggregate(evidence.filter { $0.skill != nil }, exam: exam, key: \.skill)
        )
    }

    private struct Evidence {
        let topic: String?
        let skill: String?
        let paperID: String
        let difficulty: Int
        let answered: Bool
        let value: Double?
    }

    private static func paperResult(
        exam: PublicExamKind,
        paper: DiagnosticPaperRecord,
        responses: [DiagnosticResponse]
    ) -> DiagnosticPaperResult {
        let answered = responses.filter { exam == .bmo ? $0.wasAttempted : $0.selectedOption != nil }.count
        let assessed = responses.filter {
            exam == .bmo ? $0.selfEstimatedMarks != nil : $0.marking != .unassessed
        }.count
        let correct = responses.filter { $0.marking == .correct }.count
        let incorrect = responses.filter { $0.marking == .incorrect }.count
        let score: String
        let provenance: String
        switch exam {
        case .tmua:
            score = "\(correct) correct of \(assessed) assessed (\(responses.count) questions)"
            provenance = "Self-marked against the local PDF mark scheme; no scaled TMUA score."
        case .smc:
            if assessed == answered {
                score = "\(25 + 4 * correct - incorrect) / 125 self-marked SMC points"
            } else {
                score = "\(correct) correct, \(incorrect) incorrect; \(answered - assessed) unassessed"
            }
            provenance = "Official paper rule: 25 starting points, +4 correct, −1 incorrect, 0 unanswered. Correctness is reported by you."
        case .bmo:
            let marks = responses.compactMap(\.selfEstimatedMarks).reduce(0, +)
            if answered == 0 {
                score = "No proofs attempted"
            } else if assessed == answered {
                score = "\(marks) / \(responses.count * 10) self-estimated marks"
            } else {
                score = "\(marks) self-estimated marks recorded; \(answered - assessed) proofs unassessed"
            }
            provenance = "Self-estimate only; no bundled examiner mark scheme. Each question carries 10 marks."
        }
        return DiagnosticPaperResult(
            ordinal: paper.ordinal,
            sourceID: paper.sourceID,
            questionCount: responses.count,
            answeredCount: answered,
            assessedCount: assessed,
            correctCount: correct,
            incorrectCount: incorrect,
            elapsedSeconds: Int(paper.accumulatedSeconds),
            displayScore: score,
            provenance: provenance
        )
    }

    private static func aggregate(
        _ evidence: [Evidence],
        exam: PublicExamKind,
        key: KeyPath<Evidence, String?>
    ) -> [DiagnosticTopicResult] {
        let groups = Dictionary(grouping: evidence) { $0[keyPath: key] ?? "" }
        return groups.compactMap { name, rows -> DiagnosticTopicResult? in
            guard !name.isEmpty else { return nil }
            let assessed = rows.compactMap(\.value)
            let unanswered = rows.filter { !$0.answered }.count
            let unassessed = rows.filter { $0.answered && $0.value == nil }.count
            let sourceCount = Set(rows.filter { $0.value != nil }.map(\.paperID)).count
            let low = assessed.filter { $0 <= 0.4 }.count
            let high = assessed.filter { $0 >= 0.8 }.count
            let missedOrdinary = rows.contains { $0.value.map { $0 <= 0.4 } == true && $0.difficulty <= 3 }
            let level: DiagnosticEvidenceLevel
            let explanation: String
            if exam != .bmo && assessed.count >= 4 && sourceCount == 2
                && low >= 3 && missedOrdinary {
                level = .strongDifficulty
                explanation = "\(low) of \(assessed.count) assessed questions were missed across both papers, including an ordinary-difficulty question."
            } else if assessed.count >= 2 && low >= 2 && low * 2 >= assessed.count {
                level = .possibleImprovement
                explanation = exam == .bmo
                    ? "Low self-estimated marks on \(low) proofs; no examiner scheme is available."
                    : "\(low) of \(assessed.count) assessed questions were missed; more evidence is needed for a firm conclusion."
            } else if assessed.count >= 4 && sourceCount == 2 && high >= 4
                        && high * 4 >= assessed.count * 3 {
                level = .relativeStrength
                explanation = exam == .bmo
                    ? "High self-estimated marks across both papers; this is not examiner-verified."
                    : "\(high) of \(assessed.count) assessed questions were correct across both papers."
            } else {
                level = .insufficient
                explanation = "\(assessed.count) assessed question\(assessed.count == 1 ? "" : "s"); more evidence is needed."
            }
            return DiagnosticTopicResult(
                name: name,
                assessedCount: assessed.count,
                unansweredCount: unanswered,
                unassessedCount: unassessed,
                level: level,
                explanation: explanation
            )
        }.sorted {
            let priority: [DiagnosticEvidenceLevel: Int] = [
                .strongDifficulty: 0, .possibleImprovement: 1,
                .relativeStrength: 2, .insufficient: 3
            ]
            if priority[$0.level] != priority[$1.level] {
                return (priority[$0.level] ?? 4) < (priority[$1.level] ?? 4)
            }
            return $0.name < $1.name
        }
    }

}
