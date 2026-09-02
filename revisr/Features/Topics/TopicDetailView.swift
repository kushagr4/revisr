import SwiftData
import SwiftUI

struct TopicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var sessions: [StudySession]

    let topic: Topic
    @State private var notes: String
    @State private var isEditing = false
    @State private var issue: TopicViewIssue?

    init(topic: Topic) {
        self.topic = topic
        _notes = State(initialValue: topic.notes)
        let topicID = topic.id
        _sessions = Query(
            filter: #Predicate<StudySession> { $0.topic?.id == topicID },
            sort: [SortDescriptor(\StudySession.date, order: .reverse)]
        )
    }

    private var totalDuration: TimeInterval {
        TopicAnalytics.totalDuration(for: topic, sessions: sessions)
    }

    private var lastStudied: Date? {
        TopicAnalytics.lastStudied(for: topic, sessions: sessions)
    }

    private var recentSessions: [StudySession] {
        TopicAnalytics.recentSessions(for: topic, sessions: sessions)
    }

    private var hierarchy: String {
        [topic.module?.subject?.name, topic.module?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Text(topic.name)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if !hierarchy.isEmpty {
                        Text(hierarchy)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, RevisrSpacing.small)
            }

            Section("Topic") {
                Menu {
                    ForEach(TopicStatus.allCases) { status in
                        Button {
                            setStatus(status)
                        } label: {
                            Label(status.title, systemImage: status == topic.status ? "checkmark" : status.systemImage)
                        }
                    }
                } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                            Text("Status")
                            TopicStatusLabel(status: topic.status)
                        }
                    } else {
                        HStack {
                            Text("Status")
                            Spacer()
                            TopicStatusLabel(status: topic.status)
                        }
                    }
                }
                .accessibilityLabel("Status, \(topic.status.title)")
                .accessibilityHint("Double tap to change status.")

                Toggle(isOn: reviewBinding) {
                    Label("Needs Review", systemImage: topic.needsReview ? "bookmark.fill" : "bookmark")
                }
            }

            Section("Study") {
                TopicMetricRow(label: "Total study", value: DateUtilities.durationText(totalDuration))
                TopicMetricRow(
                    label: "Last studied",
                    value: lastStudied.map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? "Never"
                )
            }

            Section("Recent Study") {
                if recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                        Text("No study logged for this topic yet")
                            .font(.body.weight(.medium))
                        Text("Use Quick Add or include it in your Plan when you revise it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, RevisrSpacing.small)
                } else {
                    ForEach(recentSessions) { session in
                        TopicSessionRow(session: session)
                    }
                }
            }

            Section {
                TextField("Short reminders for this topic", text: $notes, axis: .vertical)
                    .lineLimit(4...8)
                if notes != topic.notes {
                    Button("Save Notes", action: saveNotes)
                        .fontWeight(.semibold)
                }
            } header: {
                Text("Notes")
            } footer: {
                Text("Results are omitted because Revisr does not currently store a reliable topic-level result relationship.")
            }
        }
        .navigationTitle("Topic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            TopicEditorView(topic: topic) {
                dismiss()
            }
        }
        .alert(item: $issue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .tint(RevisrColors.accentTeal)
    }

    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { topic.needsReview },
            set: { setNeedsReview($0) }
        )
    }

    private func setStatus(_ status: TopicStatus) {
        do {
            try TopicService.setStatus(status, for: topic, in: modelContext)
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Update Status", message: error.localizedDescription)
        }
    }

    private func setNeedsReview(_ value: Bool) {
        do {
            try TopicService.setNeedsReview(value, for: topic, in: modelContext)
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Update Topic", message: error.localizedDescription)
        }
    }

    private func saveNotes() {
        topic.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            notes = topic.notes
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Save Notes", message: error.localizedDescription)
        }
    }
}

private struct TopicSessionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let session: StudySession

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.date.formatted(.dateTime.day().month(.abbreviated)))
                    Text("\(session.activity.title) · \(DateUtilities.durationText(session.duration))")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text(session.date.formatted(.dateTime.day().month(.abbreviated)))
                    Spacer()
                    Text("\(session.activity.title) · \(DateUtilities.durationText(session.duration))")
                        .foregroundStyle(.secondary)
                }
            }
            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .font(.subheadline)
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}

private struct TopicMetricRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: String
    let value: String

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                Text(label)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(label) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        }
    }
}
