import SwiftData
import SwiftUI

struct TopicRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let topic: Topic
    let lastStudied: Date?
    let includesHierarchy: Bool

    private var hierarchy: String {
        [topic.module?.name, topic.module?.subject?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: RevisrSpacing.compact) {
            VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                Text(topic.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if includesHierarchy, !hierarchy.isEmpty {
                    Text(hierarchy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            TopicStatusLabel(status: topic.status)
                            Text(DateUtilities.relativeStudyText(lastStudied))
                                .foregroundStyle(.secondary)
                            if topic.needsReview {
                                Label("Needs Review", systemImage: "bookmark.fill")
                                    .foregroundStyle(RevisrColors.accentTeal)
                            }
                        }
                    } else {
                        HStack(spacing: RevisrSpacing.xSmall) {
                            TopicStatusLabel(status: topic.status)
                            Text("·").foregroundStyle(.tertiary)
                            Text(DateUtilities.relativeStudyText(lastStudied))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: RevisrSpacing.small)
                if topic.needsReview {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(RevisrColors.accentTeal)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens topic details. Touch and hold for quick actions.")
    }

    private var accessibilityLabel: String {
        [
            topic.name,
            hierarchy,
            topic.status.title,
            topic.needsReview ? "Needs Review" : nil,
            DateUtilities.relativeStudyText(lastStudied)
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct TopicStatusLabel: View {
    let status: TopicStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status == .strong ? RevisrColors.accentTeal : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TopicContextActions: View {
    @Environment(\.modelContext) private var modelContext

    let topic: Topic
    let onIssue: (TopicViewIssue) -> Void

    var body: some View {
        Menu("Set Status", systemImage: "slider.horizontal.3") {
            ForEach(TopicStatus.allCases) { status in
                Button {
                    updateStatus(status)
                } label: {
                    Label(status.title, systemImage: status == topic.status ? "checkmark" : status.systemImage)
                }
            }
        }
        Button {
            updateReview(!topic.needsReview)
        } label: {
            Label(topic.needsReview ? "Remove Needs Review" : "Mark Needs Review", systemImage: topic.needsReview ? "bookmark.slash" : "bookmark")
        }
    }

    private func updateStatus(_ status: TopicStatus) {
        do {
            try TopicService.setStatus(status, for: topic, in: modelContext)
        } catch {
            onIssue(TopicViewIssue(title: "Couldn’t Update Status", message: error.localizedDescription))
        }
    }

    private func updateReview(_ value: Bool) {
        do {
            try TopicService.setNeedsReview(value, for: topic, in: modelContext)
        } catch {
            onIssue(TopicViewIssue(title: "Couldn’t Update Topic", message: error.localizedDescription))
        }
    }
}
