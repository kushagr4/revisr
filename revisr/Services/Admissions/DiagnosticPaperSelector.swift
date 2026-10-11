import Foundation

struct DiagnosticPaperPolicy {
    let sourceIDs: [String]
    let questionCount: Int
    let durationMinutes: Int
    let maximumMarksPerQuestion: Int?
    let requiresPDFSolutions: Bool
    let creatorCredit: String?

    static func forExam(_ exam: PublicExamKind) -> DiagnosticPaperPolicy {
        switch exam {
        case .tmua:
            // Audited third-party Paper 1/Paper 2 pair; no official benchmark.
            DiagnosticPaperPolicy(
                sourceIDs: ["SRC-E29687FAAA262C5F", "SRC-D475EB66A3CA6BF0"],
                questionCount: 20,
                durationMinutes: 75,
                maximumMarksPerQuestion: nil,
                requiresPDFSolutions: true,
                creatorCredit: nil
            )
        case .smc:
            DiagnosticPaperPolicy(
                sourceIDs: ["SRC-802E1A98D14C82D9", "SRC-EB34C15CFA44A832"],
                questionCount: 25,
                durationMinutes: 90,
                maximumMarksPerQuestion: nil,
                requiresPDFSolutions: true,
                creatorCredit: "United Kingdom Mathematics Trust"
            )
        case .bmo:
            DiagnosticPaperPolicy(
                sourceIDs: ["SRC-8C463E1A9E242017", "SRC-385D3DE51F5BA6A6"],
                questionCount: 6,
                durationMinutes: 210,
                maximumMarksPerQuestion: 10,
                requiresPDFSolutions: false,
                creatorCredit: "United Kingdom Mathematics Trust"
            )
        }
    }
}

struct DiagnosticPaperSelection {
    let source: SourceDocument
    let questions: [AdmissionsQuestion]
    let solution: SolutionDocument?
    let policy: DiagnosticPaperPolicy
    let ordinal: Int

    var displayName: String {
        switch source.stableSourceID {
        case "SRC-802E1A98D14C82D9": "SMC 2023 paper"
        case "SRC-EB34C15CFA44A832": "SMC 2024 paper"
        case "SRC-8C463E1A9E242017": "BMO1 November 2022 paper"
        case "SRC-385D3DE51F5BA6A6": "BMO1 November 2023 paper"
        default: source.displayName
        }
    }
}

enum DiagnosticSelectionError: LocalizedError, Equatable {
    case unavailablePaper(String)
    case incompleteQuestions(String)
    case ineligibleQuestion(String)
    case duplicateQuestion(String)
    case missingSolution(String)

    var errorDescription: String? {
        switch self {
        case let .unavailablePaper(id): "Diagnostic paper \(id) is unavailable locally."
        case let .incompleteQuestions(id): "Diagnostic paper \(id) has incomplete question references."
        case let .ineligibleQuestion(id): "Diagnostic question \(id) is protected or not eligible."
        case let .duplicateQuestion(id): "Diagnostic question \(id) appears in both papers."
        case let .missingSolution(id): "Diagnostic paper \(id) lacks a verified local PDF solution."
        }
    }
}

enum DiagnosticPaperSelector {
    static func select(
        exam: PublicExamKind,
        sources: [SourceDocument],
        questions: [AdmissionsQuestion],
        solutions: [SolutionDocument],
        links: [QuestionSolutionLink],
        bundle: Bundle = .main
    ) throws -> [DiagnosticPaperSelection] {
        let policy = DiagnosticPaperPolicy.forExam(exam)
        var seenQuestionIDs = Set<String>()
        return try policy.sourceIDs.enumerated().map { offset, sourceID in
            guard let source = sources.first(where: {
                $0.stableSourceID == sourceID && $0.isImportedActive
            }), SourceLibraryService.bundledURL(for: source, in: bundle) != nil else {
                throw DiagnosticSelectionError.unavailablePaper(sourceID)
            }
            let paperQuestions = questions.filter {
                $0.sourceDocument?.stableSourceID == sourceID && $0.isImportedActive
            }.sorted {
                ($0.questionNumber ?? 0, $0.externalQuestionID)
                    < ($1.questionNumber ?? 0, $1.externalQuestionID)
            }
            guard paperQuestions.count == policy.questionCount,
                  Set(paperQuestions.compactMap(\.questionNumber)) == Set(1...policy.questionCount),
                  paperQuestions.allSatisfy({
                      guard let page = $0.page else { return false }
                      return page >= 1 && page <= (source.pageCount ?? 0)
                  }) else {
                throw DiagnosticSelectionError.incompleteQuestions(sourceID)
            }
            for question in paperQuestions {
                guard question.scheduleEligible,
                      question.protection == .none,
                      question.validityState == .usable,
                      question.duplicateReviewState != .confirmedDuplicate,
                      question.duplicateReviewState != .possibleDuplicate,
                      question.possibleDuplicateQuestionIDs.isEmpty,
                      question.isUsefulFor(exam.preparationStream),
                      !(exam == .tmua && question.family == "TMUA Actual") else {
                    throw DiagnosticSelectionError.ineligibleQuestion(question.externalQuestionID)
                }
                guard seenQuestionIDs.insert(question.externalQuestionID).inserted else {
                    throw DiagnosticSelectionError.duplicateQuestion(question.externalQuestionID)
                }
            }
            let solution = solutions.first { document in
                document.isImportedActive && document.isVerified
                    && document.mediaKind == .pdf
                    && document.effectiveRelatedSourceIDs.contains(sourceID)
                    && SolutionLibraryService.bundledURL(for: document, in: bundle) != nil
            }
            if policy.requiresPDFSolutions {
                guard let solution else { throw DiagnosticSelectionError.missingSolution(sourceID) }
                let mapped = Set(links.compactMap { link -> String? in
                    guard link.isImportedActive,
                          link.solutionDocument?.stableSolutionID == solution.stableSolutionID else { return nil }
                    return link.question?.externalQuestionID
                })
                guard Set(paperQuestions.map(\.externalQuestionID)).isSubset(of: mapped) else {
                    throw DiagnosticSelectionError.missingSolution(sourceID)
                }
            }
            return DiagnosticPaperSelection(
                source: source,
                questions: paperQuestions,
                solution: solution,
                policy: policy,
                ordinal: offset + 1
            )
        }
    }
}
