import SwiftData
import SwiftUI

struct TopicsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var presentation: AppPresentationState
    @Query(sort: \Subject.displayOrder) private var subjects: [Subject]
    @Query private var sessions: [StudySession]

    @State private var searchText = ""
    @State private var isAddingTopic = false
    @State private var debugTopicID: UUID?
    @State private var debugSubjectID: UUID?
    @State private var issue: TopicViewIssue?

    init(initialSearchText: String = "") {
        var resolvedSearchText = initialSearchText
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--topics-search") {
            resolvedSearchText = "complex"
        }
#endif
        _searchText = State(initialValue: resolvedSearchText)
    }

    private var topics: [Topic] {
        subjects
            .flatMap(\.modules)
            .flatMap(\.topics)
    }

    private var lastStudied: [UUID: Date] {
        TopicAnalytics.lastStudiedByTopic(from: sessions)
    }

    private var reviewTopics: [Topic] {
        TopicAnalytics.needsReview(topics: topics, lastStudied: lastStudied)
    }

    private var searchResults: [Topic] {
        TopicAnalytics.search(topics: topics, query: searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
                Section("Search Results") {
                    if searchResults.isEmpty {
                        ContentUnavailableView(
                            "No matching topics",
                            systemImage: "magnifyingglass",
                            description: Text("Try another search.")
                        )
                    } else {
                        ForEach(searchResults) { topic in
                            topicLink(topic, includesHierarchy: true)
                        }
                    }
                }
            } else {
                if !reviewTopics.isEmpty {
                    Section("Needs Review") {
                        ForEach(reviewTopics.prefix(4)) { topic in
                            topicLink(topic, includesHierarchy: true)
                        }
                        if reviewTopics.count > 4 {
                            NavigationLink("View All (\(reviewTopics.count))") {
                                NeedsReviewTopicsView()
                            }
                        }
                    }
                }

                Section("Subjects") {
                    ForEach(subjects) { subject in
                        NavigationLink {
                            SubjectTopicsView(subject: subject)
                        } label: {
                            SubjectTopicSummaryRow(subject: subject)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Topics, modules, or subjects")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    presentation.presentQuickStudyEntry()
                } label: {
                    Label("Log Study", systemImage: "stopwatch")
                }
                .accessibilityHint("Opens the quick study entry form")

                Button {
                    isAddingTopic = true
                } label: {
                    Label("Add Topic", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingTopic) {
            TopicEditorView()
        }
        .navigationDestination(item: $debugTopicID) { topicID in
            if let topic = topics.first(where: { $0.id == topicID }) {
                TopicDetailView(topic: topic)
            }
        }
        .navigationDestination(item: $debugSubjectID) { subjectID in
            if let subject = subjects.first(where: { $0.id == subjectID }) {
                SubjectTopicsView(subject: subject)
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
        .onAppear {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--topics-add") {
                isAddingTopic = true
            } else if arguments.contains("--topics-detail") {
                openDebugTopicIfAvailable()
            } else {
                openDebugSubjectIfAvailable()
            }
#endif
        }
        .onChange(of: topics.count) {
            openDebugTopicIfAvailable()
        }
        .onChange(of: subjects.count) {
            openDebugSubjectIfAvailable()
        }
    }

    private var requestedDebugSubjectName: String? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--topics-mathematics") {
            return "Mathematics"
        } else if arguments.contains("--topics-further") {
            return "Further Mathematics"
        } else if arguments.contains("--topics-tmua") {
            return "TMUA"
        }
#endif
        return nil
    }

    private func openDebugTopicIfAvailable() {
#if DEBUG
        guard debugTopicID == nil,
              ProcessInfo.processInfo.arguments.contains("--topics-detail"),
              let topic = topics.first(where: { $0.name == "Complex Numbers" }) ?? topics.first
        else { return }
        debugTopicID = topic.id
#endif
    }

    private func openDebugSubjectIfAvailable() {
#if DEBUG
        guard debugSubjectID == nil,
              let name = requestedDebugSubjectName,
              let subject = subjects.first(where: { $0.name == name })
        else { return }
        debugSubjectID = subject.id
#endif
    }

    private func topicLink(_ topic: Topic, includesHierarchy: Bool) -> some View {
        NavigationLink {
            TopicDetailView(topic: topic)
        } label: {
            TopicRow(
                topic: topic,
                lastStudied: lastStudied[topic.id],
                includesHierarchy: includesHierarchy
            )
        }
        .contextMenu {
            TopicContextActions(topic: topic) { issue = $0 }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                setNeedsReview(!topic.needsReview, for: topic)
            } label: {
                Label(topic.needsReview ? "Reviewed" : "Needs Review", systemImage: topic.needsReview ? "bookmark.slash" : "bookmark")
            }
            .tint(RevisrColors.accentTeal)
        }
    }

    private func setNeedsReview(_ value: Bool, for topic: Topic) {
        do {
            try TopicService.setNeedsReview(value, for: topic, in: modelContext)
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Update Topic", message: error.localizedDescription)
        }
    }
}

private struct NeedsReviewTopicsView: View {
    @Query private var topics: [Topic]
    @Query private var sessions: [StudySession]

    private var lastStudied: [UUID: Date] {
        TopicAnalytics.lastStudiedByTopic(from: sessions)
    }

    private var reviewTopics: [Topic] {
        TopicAnalytics.needsReview(topics: topics, lastStudied: lastStudied)
    }

    var body: some View {
        List(reviewTopics) { topic in
            NavigationLink {
                TopicDetailView(topic: topic)
            } label: {
                TopicRow(topic: topic, lastStudied: lastStudied[topic.id], includesHierarchy: true)
            }
        }
        .navigationTitle("Needs Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SubjectTopicSummaryRow: View {
    let subject: Subject

    private var modules: [StudyModule] {
        subject.modules.sorted { $0.displayOrder < $1.displayOrder }
    }
    private var topicCount: Int { modules.flatMap(\.topics).count }
    private var reviewCount: Int { modules.flatMap(\.topics).filter(\.needsReview).count }

    var body: some View {
        HStack(spacing: RevisrSpacing.compact) {
            Circle()
                .fill(RevisrColors.subjectAccent(subject.accentIdentifier))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                Text(subject.name)
                    .font(.body.weight(.medium))
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var values = ["\(modules.count) module\(modules.count == 1 ? "" : "s")", "\(topicCount) topic\(topicCount == 1 ? "" : "s")"]
        if reviewCount > 0 { values.append("\(reviewCount) need review") }
        return values.joined(separator: " · ")
    }
}

struct TopicViewIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
