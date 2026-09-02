import SwiftUI

struct PlannedBlockRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let block: PlannedStudyBlock
    let isNext: Bool
    let calendar: Calendar
    let interactionHint: String

    init(
        block: PlannedStudyBlock,
        isNext: Bool,
        calendar: Calendar,
        interactionHint: String = "Double tap for study block actions"
    ) {
        self.block = block
        self.isNext = isNext
        self.calendar = calendar
        self.interactionHint = interactionHint
    }

    private var accent: Color {
        RevisrColors.subjectAccent(block.subject?.accentIdentifier)
    }

    private var timeText: String {
        guard let start = block.scheduledStart(using: calendar) else { return "Any time" }
        return start.formatted(date: .omitted, time: .shortened)
    }

    private var subjectLine: String {
        [block.subject?.name, block.module?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var detailLine: String {
        [block.topic?.name, block.activity.title]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleLayout
            } else {
                compactLayout
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .opacity(block.status == .planned ? 1 : 0.62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(interactionHint)
    }

    private var compactLayout: some View {
        HStack(spacing: RevisrSpacing.compact) {
            Capsule()
                .fill(accent)
                .frame(width: 3, height: 52)
                .accessibilityHidden(true)

            Text(timeText)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(block.status == .planned ? .primary : .secondary)
                .frame(width: 68, alignment: .leading)

            mainContent

            trailingContent
        }
    }

    private var accessibleLayout: some View {
        HStack(alignment: .top, spacing: RevisrSpacing.compact) {
            Capsule()
                .fill(accent)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                HStack {
                    Text(timeText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    trailingContent
                }
                mainContent
            }
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
            if isNext && block.status == .planned {
                Text("NEXT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(RevisrColors.accentTeal)
            }

            Text(subjectLine.isEmpty ? "Study" : subjectLine)
                .font(.body.weight(isNext ? .semibold : .medium))
                .foregroundStyle(block.status == .planned ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailingContent: some View {
        VStack(alignment: .trailing, spacing: RevisrSpacing.xSmall) {
            Text(DateUtilities.durationText(block.duration))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            switch block.status {
            case .planned:
                EmptyView()
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(RevisrColors.accentTeal)
                    .accessibilityHidden(true)
            case .skipped:
                Text("Skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityDescription: String {
        let nextPrefix = isNext && block.status == .planned ? "Next. " : ""
        return "\(nextPrefix)\(timeText). \(subjectLine). \(detailLine). \(DateUtilities.durationText(block.duration)). \(block.status.accessibilityTitle)."
    }
}

private extension PlannedBlockStatus {
    var accessibilityTitle: String {
        switch self {
        case .planned: "Planned"
        case .completed: "Completed"
        case .skipped: "Skipped"
        }
    }
}
