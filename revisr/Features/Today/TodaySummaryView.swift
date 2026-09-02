import SwiftUI

struct TodaySummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let date: Date
    let completedDuration: TimeInterval
    let plannedDuration: TimeInterval
    let isPlanComplete: Bool

    private var completionFraction: Double {
        StudyAnalytics.completionFraction(
            planned: plannedDuration,
            actual: completedDuration
        )
    }

    private var percentageText: String {
        "\(Int((completionFraction * 100).rounded()))% complete"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(RevisrTypography.sectionTitle)
                .foregroundStyle(.secondary)

            if plannedDuration > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: RevisrSpacing.small) {
                        completedText
                        Text("of \(DateUtilities.durationText(plannedDuration)) planned")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                        completedText
                        Text("of \(DateUtilities.durationText(plannedDuration)) planned")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                        progressBar
                        percentageLabel
                    }
                } else {
                    HStack(spacing: RevisrSpacing.compact) {
                        progressBar
                        percentageLabel
                    }
                }

                if isPlanComplete {
                    Label("Today’s plan is complete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RevisrColors.accentTeal)
                        .transition(.opacity)
                }
            } else {
                completedText
                Text(completedDuration > 0 ? "studied today" : "No study logged yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, RevisrSpacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var completedText: some View {
        Text(DateUtilities.durationText(completedDuration))
            .font(RevisrTypography.metric)
            .fontWeight(.semibold)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var progressBar: some View {
        ProgressView(value: completionFraction)
            .tint(RevisrColors.accentTeal)
    }

    private var percentageLabel: some View {
        Text(percentageText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var accessibilitySummary: String {
        if plannedDuration > 0 {
            return "\(DateUtilities.durationText(completedDuration)) completed of \(DateUtilities.durationText(plannedDuration)) planned. \(percentageText)."
        }
        return "\(DateUtilities.durationText(completedDuration)) studied today. Nothing planned."
    }
}
