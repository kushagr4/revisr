import Charts
import SwiftUI

struct ResultProgressSection: View {
    let kind: StudyResultKind
    let results: [StudyResult]
    let onAdd: () -> Void
    let onEdit: (StudyResult) -> Void
    let onViewHistory: () -> Void

    private var sortedResults: [StudyResult] {
        results.sorted { $0.date > $1.date }
    }

    var body: some View {
        Section {
            if results.isEmpty {
                ProgressEmptyRow(
                    title: kind == .tmua ? "No TMUA results" : "No A-Level results",
                    message: kind == .tmua
                        ? "Add a paper result to begin a consistent score trend."
                        : "Add a Mathematics or Further Mathematics result to track percentages.",
                    systemImage: kind == .tmua ? "doc.text" : "function"
                )
            } else {
                if kind == .tmua {
                    TMUAChart(results: results)
                } else {
                    ALevelChart(results: results)
                }

                ForEach(sortedResults.prefix(5)) { result in
                    Button {
                        onEdit(result)
                    } label: {
                        StudyResultRow(result: result, kind: kind)
                    }
                    .buttonStyle(.plain)
                }

                if results.count > 5 {
                    Button("View All Results", action: onViewHistory)
                }
            }
        } header: {
            HStack {
                Text(kind == .tmua ? "TMUA results" : "A-Level results")
                Spacer()
                Button("Add", action: onAdd)
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .accessibilityLabel("Add \(kind.title)")
            }
        }
    }
}

private struct TMUAChart: View {
    let results: [StudyResult]

    private var metric: TMUAMetric? { ProgressAnalytics.tmuaMetric(for: results) }
    private var points: [ComparableResultPoint] {
        guard let metric else { return [] }
        return ProgressAnalytics.tmuaPoints(from: results, metric: metric)
    }
    private var averages: [ResultAverage] { ProgressAnalytics.averages(for: points) }
    private var trend: TMUATrend? { ProgressAnalytics.trend(for: points) }

    private var yDomain: ClosedRange<Double> {
        guard metric == .scaled, let minimum = points.map(\.value).min(), let maximum = points.map(\.value).max() else {
            return 0...100
        }
        return max(0, minimum - 1)...min(20, max(maximum + 1, minimum + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
            if let metric, !points.isEmpty {
                Text(metric.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(metric.title, point.value),
                        series: .value("Paper", point.label)
                    )
                    .foregroundStyle(by: .value("Paper", point.label))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(metric.title, point.value)
                    )
                    .foregroundStyle(by: .value("Paper", point.label))
                    .symbol(by: .value("Paper", point.label))
                }
                .chartYScale(domain: yDomain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("TMUA \(metric.title) trend")
                .accessibilityValue(chartAccessibilityValue(metric: metric))

                if !averages.isEmpty {
                    Text(averages.map { "\($0.label) avg \(format($0.value, metric: metric))" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let trend {
                    Label(trendText(trend, metric: metric), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressEmptyRow(
                    title: "No comparable scores",
                    message: "Add raw marks or scaled scores to create a trend. Revisr never combines the two units.",
                    systemImage: "chart.xyaxis.line"
                )
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
    }

    private func format(_ value: Double, metric: TMUAMetric) -> String {
        metric == .percentage
            ? value.formatted(.number.precision(.fractionLength(0))) + "%"
            : value.formatted(.number.precision(.fractionLength(1)))
    }

    private func trendText(_ trend: TMUATrend, metric: TMUAMetric) -> String {
        switch trend {
        case .recentAverage(let value):
            return "Recent 3 average: \(format(value, metric: metric))"
        case .change(let value):
            let formatted = format(abs(value), metric: metric)
            if abs(value) < 0.05 { return "Recent results are steady" }
            return value > 0 ? "Recent average up \(formatted)" : "Recent average down \(formatted)"
        }
    }

    private func chartAccessibilityValue(metric: TMUAMetric) -> String {
        let values = points
            .sorted { $0.date < $1.date }
            .map {
                "\($0.label), \(format($0.value, metric: metric)), \($0.date.formatted(date: .abbreviated, time: .omitted))"
            }
            .joined(separator: "; ")
        let trendSummary = trend.map { trendText($0, metric: metric) }
        return ["\(points.count) result\(points.count == 1 ? "" : "s")", values, trendSummary]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

private struct ALevelChart: View {
    let results: [StudyResult]

    private var points: [ComparableResultPoint] {
        ProgressAnalytics.aLevelPoints(from: results)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
            if points.isEmpty {
                ProgressEmptyRow(
                    title: "No comparable scores",
                    message: "A-Level trends use raw marks as a percentage.",
                    systemImage: "chart.xyaxis.line"
                )
            } else {
                Text("Raw percentage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Percentage", point.value),
                        series: .value("Subject", point.subjectName)
                    )
                    .foregroundStyle(by: .value("Subject", point.subjectName))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Percentage", point.value)
                    )
                    .foregroundStyle(by: .value("Subject", point.subjectName))
                    .symbol(by: .value("Subject", point.subjectName))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("A-Level percentage trend")
                .accessibilityValue(chartAccessibilityValue)
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
    }

    private var chartAccessibilityValue: String {
        let values = points
            .sorted { $0.date < $1.date }
            .map {
                let percentage = $0.value.formatted(.number.precision(.fractionLength(0)))
                return "\($0.subjectName), \(percentage) percent, \($0.date.formatted(date: .abbreviated, time: .omitted))"
            }
            .joined(separator: "; ")
        return "\(points.count) result\(points.count == 1 ? "" : "s"). \(values)"
    }
}

struct StudyResultRow: View {
    let result: StudyResult
    let kind: StudyResultKind

    private var scoreText: String {
        if kind == .tmua, let scaled = result.scaledScore {
            return "Scaled \(scaled.formatted(.number.precision(.fractionLength(1))))"
        }
        if let raw = result.rawScore, let maximum = result.maximumScore {
            return "\(raw.formatted(.number.precision(.fractionLength(0...1))))/\(maximum.formatted(.number.precision(.fractionLength(0...1)))) · \((result.percentage * 100).formatted(.number.precision(.fractionLength(0))))%"
        }
        return "Score unavailable"
    }

    var body: some View {
        HStack(spacing: RevisrSpacing.compact) {
            VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                Text(result.paperOrModuleLabel)
                    .font(.body.weight(.medium))
                Text("\(result.subjectNameSnapshot) · \(result.date.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: RevisrSpacing.small)
            Text(scoreText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .contentShape(Rectangle())
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.subjectNameSnapshot), \(result.paperOrModuleLabel), \(scoreText), \(result.date.formatted(date: .abbreviated, time: .omitted)).")
        .accessibilityHint("Double tap to edit this result.")
    }
}
