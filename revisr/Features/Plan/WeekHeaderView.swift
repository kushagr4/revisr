import SwiftUI

struct WeekHeaderView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let weekStart: Date
    let plannedDuration: TimeInterval
    let isCurrentWeek: Bool
    let isComplete: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCurrentWeek: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            if dynamicTypeSize.isAccessibilitySize {
                weekSummary

                HStack(spacing: RevisrSpacing.compact) {
                    weekNavigationButtons
                    Spacer(minLength: RevisrSpacing.small)
                    if !isCurrentWeek {
                        Button("Current Week", action: onCurrentWeek)
                            .font(.subheadline.weight(.medium))
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    weekSummary
                    Spacer()
                    weekNavigationButtons
                }
            }

            HStack {
                if isComplete {
                    Label("All planned blocks completed", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(RevisrColors.accentTeal)
                }
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize, !isCurrentWeek {
                    Button("Current Week", action: onCurrentWeek)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .contain)
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
            Text(DateUtilities.weekRangeTitle(containing: weekStart))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(
                plannedDuration > 0
                    ? "\(DateUtilities.durationText(plannedDuration)) planned"
                    : "No blocks planned this week"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var weekNavigationButtons: some View {
        HStack(spacing: RevisrSpacing.xSmall) {
            Button("Previous week", systemImage: "chevron.left", action: onPrevious)
                .labelStyle(.iconOnly)
                .frame(minWidth: RevisrMetrics.minimumTapTarget, minHeight: RevisrMetrics.minimumTapTarget)
            Button("Next week", systemImage: "chevron.right", action: onNext)
                .labelStyle(.iconOnly)
                .frame(minWidth: RevisrMetrics.minimumTapTarget, minHeight: RevisrMetrics.minimumTapTarget)
        }
        .buttonStyle(.borderless)
    }
}
