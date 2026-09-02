import Foundation

enum StudySubjectCategory: String, CaseIterable, Identifiable, Sendable {
    case tmua
    case furtherMathematics
    case mathematics

    var id: Self { self }

    var title: String {
        switch self {
        case .tmua: "TMUA"
        case .furtherMathematics: "Further Mathematics"
        case .mathematics: "Mathematics"
        }
    }

    var accentIdentifier: SubjectAccentID {
        switch self {
        case .tmua: .tmua
        case .furtherMathematics: .furtherMathematics
        case .mathematics: .mathematics
        }
    }

    static func classify(subject: Subject?, snapshot: String) -> Self? {
        if let accent = subject?.accentIdentifier {
            return switch accent {
            case .tmua: .tmua
            case .furtherMathematics: .furtherMathematics
            case .mathematics: .mathematics
            }
        }

        let value = snapshot.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return switch value {
        case "tmua": .tmua
        case "further mathematics": .furtherMathematics
        case "mathematics": .mathematics
        default: nil
        }
    }
}

struct StudyAllocation: Identifiable, Equatable {
    let category: StudySubjectCategory
    let duration: TimeInterval
    let fraction: Double
    let targetFraction: Double

    var id: StudySubjectCategory { category }
}

enum TMUAMetric: String, Equatable, Sendable {
    case scaled
    case percentage

    var title: String {
        switch self {
        case .scaled: "Scaled score"
        case .percentage: "Raw percentage"
        }
    }
}

struct ComparableResultPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let label: String
    let subjectName: String
    let value: Double
}

struct ResultAverage: Identifiable, Equatable {
    let label: String
    let value: Double
    var id: String { label }
}

enum TMUATrend: Equatable {
    case recentAverage(Double)
    case change(Double)
}

enum ProgressAnalytics {
    static func allocations(
        sessions: [StudySession],
        settings: AppSettings?
    ) -> [StudyAllocation] {
        var durations = Dictionary(uniqueKeysWithValues: StudySubjectCategory.allCases.map { ($0, 0.0) })
        for session in sessions {
            guard let category = StudySubjectCategory.classify(
                subject: session.subject,
                snapshot: session.subjectNameSnapshot
            ) else { continue }
            durations[category, default: 0] += max(0, session.duration)
        }
        let total = durations.values.reduce(0, +)

        return StudySubjectCategory.allCases.map { category in
            let duration = durations[category, default: 0]
            let target = targetFraction(for: category, settings: settings)
            return StudyAllocation(
                category: category,
                duration: duration,
                fraction: total > 0 ? duration / total : 0,
                targetFraction: target
            )
        }
    }

    static func targetFraction(for category: StudySubjectCategory, settings: AppSettings?) -> Double {
        guard let settings else {
            return switch category {
            case .tmua: 0.55
            case .furtherMathematics: 0.27
            case .mathematics: 0.18
            }
        }
        return switch category {
        case .tmua: settings.tmuaTarget
        case .furtherMathematics: settings.furtherMathematicsTarget
        case .mathematics: settings.mathematicsTarget
        }
    }

    static func tmuaResults(from results: [StudyResult]) -> [StudyResult] {
        results.filter {
            StudySubjectCategory.classify(subject: $0.subject, snapshot: $0.subjectNameSnapshot) == .tmua
        }
    }

    static func aLevelResults(
        from results: [StudyResult],
        category: StudySubjectCategory? = nil
    ) -> [StudyResult] {
        results.filter { result in
            guard let resultCategory = StudySubjectCategory.classify(
                subject: result.subject,
                snapshot: result.subjectNameSnapshot
            ), resultCategory != .tmua else { return false }
            return category == nil || category == resultCategory
        }
    }

    /// Scaled scores are used when at least two exist. A lone scaled-only result
    /// remains chartable when no raw percentages exist; units are never combined.
    static func tmuaMetric(for results: [StudyResult]) -> TMUAMetric? {
        let tmua = tmuaResults(from: results)
        let scaledCount = tmua.compactMap(\.scaledScore).count
        let percentageCount = tmua.compactMap(\.rawPercentage).count
        if scaledCount >= 2 || (scaledCount > 0 && percentageCount == 0) { return .scaled }
        if percentageCount > 0 { return .percentage }
        return nil
    }

    static func tmuaPoints(from results: [StudyResult], metric: TMUAMetric) -> [ComparableResultPoint] {
        tmuaResults(from: results).compactMap { result in
            let value: Double?
            switch metric {
            case .scaled: value = result.scaledScore
            case .percentage: value = result.rawPercentage.map { $0 * 100 }
            }
            guard let value else { return nil }
            return ComparableResultPoint(
                id: result.id,
                date: result.date,
                label: result.paperOrModuleLabel,
                subjectName: result.subjectNameSnapshot,
                value: value
            )
        }.sorted { $0.date < $1.date }
    }

    static func aLevelPoints(from results: [StudyResult]) -> [ComparableResultPoint] {
        aLevelResults(from: results).compactMap { result in
            guard let percentage = result.rawPercentage else { return nil }
            return ComparableResultPoint(
                id: result.id,
                date: result.date,
                label: result.paperOrModuleLabel,
                subjectName: result.subjectNameSnapshot,
                value: percentage * 100
            )
        }.sorted { $0.date < $1.date }
    }

    static func averages(for points: [ComparableResultPoint]) -> [ResultAverage] {
        Dictionary(grouping: points, by: \.label)
            .map { label, values in
                ResultAverage(label: label, value: values.map(\.value).reduce(0, +) / Double(values.count))
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    static func trend(for points: [ComparableResultPoint]) -> TMUATrend? {
        let values = points.sorted { $0.date < $1.date }.map(\.value)
        guard values.count >= 3 else { return nil }
        if values.count < 5 {
            return .recentAverage(values.suffix(3).reduce(0, +) / 3)
        }
        let recent = values.suffix(2).reduce(0, +) / 2
        let previous = values.dropLast(2).suffix(2).reduce(0, +) / 2
        return .change(recent - previous)
    }
}
