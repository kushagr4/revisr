import Foundation
import SwiftData

struct QuestionPerformanceSummary: Equatable {
    let attemptCount: Int
    let uniqueQuestionCount: Int
    let correctCount: Int
    let partialCount: Int
    let incorrectCount: Int
    let skippedCount: Int
    let accuracy: Double?
    let averageSeconds: Double?
}

enum AdmissionsAnalytics {
    /// Attempt-level semantics: Partial is in the denominator but is not fully
    /// correct; Skipped is counted as an attempt but excluded from accuracy.
    static func attemptSummary(_ attempts: [QuestionAttempt]) -> QuestionPerformanceSummary {
        summary(attempts: attempts, uniqueQuestionCount: Set(attempts.compactMap {
            $0.question?.externalQuestionID
        }).count)
    }

    /// Unique/latest semantics use the most recent non-skipped result per Question.
    static func latestQuestionSummary(_ questions: [AdmissionsQuestion]) -> QuestionPerformanceSummary {
        let latest = questions.compactMap(latestMeaningfulAttempt(for:))
        return summary(attempts: latest, uniqueQuestionCount: latest.count)
    }

    static func latestMeaningfulAttempt(for question: AdmissionsQuestion) -> QuestionAttempt? {
        question.attempts
            .filter { $0.outcome != .skipped }
            .max(by: { $0.attemptedAt < $1.attemptedAt })
    }

    static func topicSummary(
        topic: String,
        questions: [AdmissionsQuestion]
    ) -> QuestionPerformanceSummary {
        latestQuestionSummary(questions.filter { $0.primaryTopic == topic })
    }

    static func errorDistribution(_ attempts: [QuestionAttempt]) -> [QuestionErrorType: Int] {
        Dictionary(grouping: attempts.compactMap(\.errorType), by: { $0 })
            .mapValues(\.count)
    }

    private static func summary(
        attempts: [QuestionAttempt],
        uniqueQuestionCount: Int
    ) -> QuestionPerformanceSummary {
        let correct = attempts.filter { $0.outcome == .correct }.count
        let partial = attempts.filter { $0.outcome == .partial }.count
        let incorrect = attempts.filter { $0.outcome == .incorrect }.count
        let skipped = attempts.filter { $0.outcome == .skipped }.count
        let denominator = correct + partial + incorrect
        let timed = attempts.map(\.timeTakenSeconds).filter { $0 > 0 }
        return QuestionPerformanceSummary(
            attemptCount: attempts.count,
            uniqueQuestionCount: uniqueQuestionCount,
            correctCount: correct,
            partialCount: partial,
            incorrectCount: incorrect,
            skippedCount: skipped,
            accuracy: denominator > 0 ? Double(correct) / Double(denominator) : nil,
            averageSeconds: timed.isEmpty ? nil : Double(timed.reduce(0, +)) / Double(timed.count)
        )
    }
}

struct ExtraPracticeFilter: Equatable, Sendable {
    var primaryTopic: String?
    var difficulty: Int?
    var tmuaPaperFit: String?
    var reasoningSkill: String?
    var family: String?
    var needsReviewOnly = false
}

enum ExtraPracticeSelector {
    static func select(
        from questions: [AdmissionsQuestion],
        filter: ExtraPracticeFilter,
        programme: AdmissionsProgramme?,
        on date: Date = .now,
        limit: Int = 10,
        allowsProtectedQuestions: Bool = false,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AdmissionsQuestion] {
        return questions
            .filter { question in
                guard question.isTMUAPracticeEligible else { return false }
                if !allowsProtectedQuestions && question.protection != .none { return false }
                if isFutureBenchmark(question, after: date, calendar: calendar) { return false }
                if let topic = filter.primaryTopic, question.primaryTopic != topic { return false }
                if let difficulty = filter.difficulty, question.difficulty != difficulty { return false }
                if let fit = filter.tmuaPaperFit,
                   !(question.tmuaPaperFit ?? "").localizedCaseInsensitiveContains(fit) { return false }
                if let skill = filter.reasoningSkill, question.reasoningSkill != skill { return false }
                if let family = filter.family, question.family != family { return false }
                if filter.needsReviewOnly, question.reviewState == .none { return false }
                return true
            }
            .sorted { lhs, rhs in
                let lhsUnattempted = lhs.attempts.isEmpty
                let rhsUnattempted = rhs.attempts.isEmpty
                if lhsUnattempted != rhsUnattempted { return lhsUnattempted }
                return lhs.externalQuestionID < rhs.externalQuestionID
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func isFutureBenchmark(
        _ question: AdmissionsQuestion,
        after date: Date,
        calendar: Calendar
    ) -> Bool {
        guard question.family == "TMUA Actual" else { return false }
        return question.programmeAssignments.contains { assignment in
            guard assignment.isImportedActive,
                  let day = assignment.programmeDay,
                  let programme = day.programme else { return false }
            return calendar.startOfDay(for: programme.date(for: day.dayNumber, calendar: calendar))
                > calendar.startOfDay(for: date)
        }
    }
}

@MainActor
enum QuestionAttemptService {
    static func record(
        question: AdmissionsQuestion,
        assignment: ProgrammeAssignment?,
        outcome: QuestionAttemptOutcome,
        seconds: Int,
        errorType: QuestionErrorType?,
        notes: String,
        origin: QuestionAttemptOrigin,
        in context: ModelContext
    ) throws -> QuestionAttempt {
        let effectiveError = outcome == .correct ? nil : errorType
        let attempt = QuestionAttempt(
            outcome: outcome,
            timeTakenSeconds: seconds,
            errorType: effectiveError,
            notes: notes,
            origin: origin,
            question: question,
            programmeAssignment: assignment
        )
        context.insert(attempt)
        try context.save()
        return attempt
    }
}

struct SourceLibraryAudit: Equatable {
    let expectedCount: Int
    let resolvedCount: Int
    let missingSourceIDs: [String]
    let duplicateResourceURLs: [URL]

    var isComplete: Bool {
        resolvedCount == expectedCount
            && missingSourceIDs.isEmpty
            && duplicateResourceURLs.isEmpty
    }
}

enum SourceLibraryService {
    static let bundleSubdirectory = "AdmissionsPapers"

    /// Stable bundled lookup. No path is persisted and no model value is changed.
    static func bundledURL(for source: SourceDocument, in bundle: Bundle = .main) -> URL? {
        let name = source.stableSourceID
        return bundle.url(
            forResource: name,
            withExtension: "pdf",
            subdirectory: bundleSubdirectory
        ) ?? bundle.url(forResource: name, withExtension: "pdf")
    }

    /// Bundled resources are authoritative. The legacy app-managed copy remains
    /// a migration fallback for an older installed container only.
    static func resolvedURL(for source: SourceDocument, in bundle: Bundle = .main) -> URL? {
        bundledURL(for: source, in: bundle) ?? legacyLocalURL(for: source)
    }

    static func audit(
        sources: [SourceDocument],
        in bundle: Bundle = .main
    ) -> SourceLibraryAudit {
        let resolved = sources.compactMap { source in
            bundledURL(for: source, in: bundle).map { (source.stableSourceID, $0) }
        }
        let resolvedIDs = Set(resolved.map(\.0))
        let duplicateURLs = Dictionary(grouping: resolved.map(\.1), by: \.standardizedFileURL)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted { $0.path < $1.path }
        return SourceLibraryAudit(
            expectedCount: sources.count,
            resolvedCount: resolved.count,
            missingSourceIDs: sources
                .map(\.stableSourceID)
                .filter { !resolvedIDs.contains($0) }
                .sorted(),
            duplicateResourceURLs: duplicateURLs
        )
    }

    /// Workbook pages are one-based; PDFKit indices are zero-based.
    static func pdfPageIndex(for workbookPage: Int?, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let oneBasedPage = max(1, workbookPage ?? 1)
        return min(oneBasedPage - 1, pageCount - 1)
    }

    private static func legacyLocalURL(for source: SourceDocument) -> URL? {
        guard let localFilename = source.localFilename else { return nil }
        let url = sourceDirectory.appendingPathComponent(localFilename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static let sourceDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Revisr Source Papers", isDirectory: true)
    }()

}
