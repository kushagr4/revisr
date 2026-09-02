import SwiftData
import SwiftUI

struct SubjectTopicsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var sessions: [StudySession]

    let subject: Subject
    @State private var editorModule: StudyModule?
    @State private var issue: TopicViewIssue?

    init(subject: Subject) {
        self.subject = subject
        let subjectID = subject.id
        _sessions = Query(
            filter: #Predicate<StudySession> { $0.subject?.id == subjectID },
            sort: [SortDescriptor(\StudySession.date, order: .reverse)]
        )
    }

    private var modules: [StudyModule] {
        subject.modules.sorted { $0.displayOrder < $1.displayOrder }
    }

    private var lastStudied: [UUID: Date] {
        TopicAnalytics.lastStudiedByTopic(from: sessions)
    }

    var body: some View {
        List {
            ForEach(modules) { module in
                Section {
                    let topics = module.topics.sorted { lhs, rhs in
                        if lhs.displayOrder != rhs.displayOrder { return lhs.displayOrder < rhs.displayOrder }
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    if topics.isEmpty {
                        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                            Text("No topics yet")
                                .font(.body.weight(.medium))
                            Button("Add Topic") { editorModule = module }
                                .font(.subheadline)
                        }
                        .padding(.vertical, RevisrSpacing.small)
                    } else {
                        ForEach(topics) { topic in
                            NavigationLink {
                                TopicDetailView(topic: topic)
                            } label: {
                                TopicRow(
                                    topic: topic,
                                    lastStudied: lastStudied[topic.id],
                                    includesHierarchy: false
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
                    }
                } header: {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.name)
                            Text(moduleSummary(module))
                                .font(.caption)
                                .textCase(nil)
                            Button("Add Topic") { editorModule = module }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                                .accessibilityLabel("Add topic to \(module.name)")
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.name)
                                Text(moduleSummary(module))
                                    .font(.caption)
                                    .textCase(nil)
                            }
                            Spacer()
                            Button("Add") { editorModule = module }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                                .accessibilityLabel("Add topic to \(module.name)")
                        }
                    }
                }
            }
        }
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorModule) { module in
            TopicEditorView(preselectedModule: module)
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

    private func moduleSummary(_ module: StudyModule) -> String {
        let count = module.topics.count
        let reviewCount = module.topics.filter(\.needsReview).count
        var values = ["\(count) topic\(count == 1 ? "" : "s")"]
        if reviewCount > 0 { values.append("\(reviewCount) need review") }
        return values.joined(separator: " · ")
    }

    private func setNeedsReview(_ value: Bool, for topic: Topic) {
        do {
            try TopicService.setNeedsReview(value, for: topic, in: modelContext)
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Update Topic", message: error.localizedDescription)
        }
    }
}
