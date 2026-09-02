import SwiftData
import SwiftUI

struct AdmissionsProgressView: View {
    @Query(filter: #Predicate<AdmissionsQuestion> { $0.isImportedActive })
    private var questions: [AdmissionsQuestion]
    @Query(sort: \QuestionAttempt.attemptedAt, order: .reverse)
    private var attempts: [QuestionAttempt]
    @Query(sort: \StudyResult.date, order: .reverse)
    private var results: [StudyResult]
    @Query(filter: #Predicate<ProgrammeDay> { $0.isImportedActive })
    private var days: [ProgrammeDay]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        AdmissionsStatusBadge(text: "TMUA Active", systemImage: "target")
                        Spacer()
                        Text("Local only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Latest Result per Question") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: RevisrSpacing.standard) {
                        AdmissionsMetricCard(
                            title: "Unique attempted",
                            value: "\(latest.uniqueQuestionCount)",
                            detail: "of \(questions.count) questions",
                            systemImage: "checklist"
                        )
                        AdmissionsMetricCard(
                            title: "Accuracy",
                            value: latest.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                            detail: "Skipped excluded",
                            systemImage: "scope"
                        )
                        AdmissionsMetricCard(
                            title: "Needs Review",
                            value: "\(reviewBacklog)",
                            detail: "question flags",
                            systemImage: "bookmark"
                        )
                        AdmissionsMetricCard(
                            title: "Programme",
                            value: "\(completedAssignments)/\(totalAssignments)",
                            detail: "assignments complete",
                            systemImage: "calendar.badge.checkmark"
                        )
                    }
                    .padding(.vertical, RevisrSpacing.small)
                }

                Section("All Attempts") {
                    LabeledContent("Attempts", value: "\(attemptLevel.attemptCount)")
                    LabeledContent("Correct", value: "\(attemptLevel.correctCount)")
                    LabeledContent("Partial", value: "\(attemptLevel.partialCount)")
                    LabeledContent("Incorrect", value: "\(attemptLevel.incorrectCount)")
                    LabeledContent("Skipped", value: "\(attemptLevel.skippedCount)")
                    if let seconds = attemptLevel.averageSeconds {
                        LabeledContent("Average recorded time", value: format(seconds: seconds))
                    }
                    Text("Accuracy = Correct ÷ (Correct + Incorrect + Partial). Skipped attempts are reported separately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !errorDistribution.isEmpty {
                    Section("Error Types") {
                        ForEach(QuestionErrorType.allCases) { error in
                            if let count = errorDistribution[error], count > 0 {
                                LabeledContent(error.title, value: "\(count)")
                            }
                        }
                    }
                }

                Section("Topic Performance") {
                    ForEach(topicPerformance.prefix(8), id: \.topic) { item in
                        HStack {
                            Text(item.topic)
                            Spacer()
                            Text(item.summary.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                                .foregroundStyle(.secondary)
                            Text("\(item.summary.uniqueQuestionCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section("Test Performance") {
                    if tmuaResults.isEmpty {
                        ContentUnavailableView(
                            "No TMUA Results",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Question performance is tracked above. Add scaled or mock results when available.")
                        )
                    } else {
                        ForEach(tmuaResults.prefix(6)) { result in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.paperOrModuleLabel).font(.headline)
                                Text(resultValue(result))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("CSAT") {
                    ContentUnavailableView(
                        "Preparation starts after TMUA",
                        systemImage: "pause.circle",
                        description: Text("CSAT is supported by the admissions architecture but has no active programme or fabricated scoring model.")
                    )
                }
            }
            .navigationTitle("Progress")
        }
    }

    private var attemptLevel: QuestionPerformanceSummary {
        PerformanceProbe.measure("progress_attempt_summary") { AdmissionsAnalytics.attemptSummary(attempts) }
    }
    private var latest: QuestionPerformanceSummary {
        PerformanceProbe.measure("progress_latest_summary") { AdmissionsAnalytics.latestQuestionSummary(questions) }
    }
    private var reviewBacklog: Int {
        PerformanceProbe.measure("progress_review_count") { questions.filter { $0.reviewState != .none }.count }
    }
    private var completedAssignments: Int {
        days.flatMap(\.assignments).filter { $0.isImportedActive && $0.isComplete }.count
    }
    private var totalAssignments: Int {
        days.flatMap(\.assignments).filter(\.isImportedActive).count
    }
    private var errorDistribution: [QuestionErrorType: Int] { AdmissionsAnalytics.errorDistribution(attempts) }
    private var tmuaResults: [StudyResult] { results.filter { $0.subjectNameSnapshot == "TMUA" } }
    private var topicPerformance: [(topic: String, summary: QuestionPerformanceSummary)] {
        PerformanceProbe.measure("progress_topic_performance") {
            Dictionary(grouping: questions, by: \.primaryTopic)
                .map { ($0.key, AdmissionsAnalytics.latestQuestionSummary($0.value)) }
                .filter { $0.1.uniqueQuestionCount > 0 }
                .sorted {
                    if $0.1.accuracy != $1.1.accuracy { return ($0.1.accuracy ?? -1) < ($1.1.accuracy ?? -1) }
                    return $0.0 < $1.0
                }
        }
    }

    private func format(seconds: Double) -> String {
        let value = Int(seconds.rounded())
        return "\(value / 60)m \(value % 60)s"
    }

    private func resultValue(_ result: StudyResult) -> String {
        if let scaled = result.scaledScore { return "Scaled \(scaled.formatted(.number.precision(.fractionLength(1))))" }
        if let raw = result.rawScore, let maximum = result.maximumScore { return "\(raw.formatted()) / \(maximum.formatted())" }
        return result.date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct AdmissionsTopicsView: View {
    @Query(filter: #Predicate<AdmissionsTopicState> { $0.isImportedActive }, sort: \AdmissionsTopicState.displayOrder)
    private var topics: [AdmissionsTopicState]
    @Query(filter: #Predicate<AdmissionsQuestion> { $0.isImportedActive })
    private var questions: [AdmissionsQuestion]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        QuestionBankView()
                    } label: {
                        Label("Question Bank", systemImage: "books.vertical")
                    }
                    NavigationLink {
                        ExtraPracticeView()
                    } label: {
                        Label("Give Me More Practice", systemImage: "plus.circle")
                    }
                    NavigationLink {
                        NeedsReviewQuestionsView()
                    } label: {
                        Label("Questions Needing Review", systemImage: "bookmark")
                    }
                    NavigationLink {
                        SourceLibraryView()
                    } label: {
                        Label("Source Papers", systemImage: "doc.richtext")
                    }
                    NavigationLink {
                        SolutionBankView()
                    } label: {
                        Label("Solution Bank", systemImage: "checkmark.seal")
                    }
                }

                Section {
                    ForEach(topics) { topic in
                        NavigationLink {
                            AdmissionsTopicDetailView(topic: topic)
                        } label: {
                            topicRow(topic)
                        }
                    }
                } header: {
                    Text("TMUA Topics")
                } footer: {
                    Text("Specification coverage, manual strength, and question performance are separate signals.")
                }

                Section("CSAT") {
                    ContentUnavailableView(
                        "Not started",
                        systemImage: "pause.circle",
                        description: Text("Topics will appear only when authoritative CSAT resources are imported.")
                    )
                }
            }
            .navigationTitle("Topics")
        }
    }

    private func topicRow(_ topic: AdmissionsTopicState) -> some View {
        let related = PerformanceProbe.measure("topics_question_filter") {
            questions.filter { $0.primaryTopic == topic.name }
        }
        let performance = PerformanceProbe.measure("topics_performance") {
            AdmissionsAnalytics.latestQuestionSummary(related)
        }
        return VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Text(topic.name).font(.headline)
            HStack(spacing: RevisrSpacing.standard) {
                Label(topic.manualStatus.title, systemImage: topic.manualStatus.systemImage)
                Label(topic.specificationCoverage.title, systemImage: "checklist")
                if topic.needsReview { Label("Topic Review", systemImage: "bookmark.fill") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(related.count) bank questions · \(performance.uniqueQuestionCount) attempted · \(performance.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "No accuracy yet")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct AdmissionsTopicDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var topic: AdmissionsTopicState
    @Query(filter: #Predicate<AdmissionsQuestion> { $0.isImportedActive })
    private var questions: [AdmissionsQuestion]

    var body: some View {
        List {
            Section("Your Assessment") {
                Picker("Manual strength", selection: manualStatus) {
                    ForEach(TopicStatus.allCases) { status in Text(status.title).tag(status) }
                }
                Picker("TMUA specification", selection: coverage) {
                    ForEach(SpecificationCoverageState.allCases) { state in Text(state.title).tag(state) }
                }
                Toggle("Topic needs review", isOn: needsReview)
                Text("Attempting a question never changes these manual fields automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Question Performance") {
                LabeledContent("Available", value: "\(related.count)")
                LabeledContent("Attempted", value: "\(performance.uniqueQuestionCount)")
                LabeledContent("Latest-result accuracy", value: performance.accuracy?.formatted(.percent.precision(.fractionLength(0))) ?? "—")
                LabeledContent("Questions flagged", value: "\(related.filter { $0.reviewState != .none }.count)")
            }
            Section("Related Questions") {
                ForEach(related.prefix(100)) { question in
                    NavigationLink {
                        QuestionDetailView(question: question, assignment: nil, attemptOrigin: .questionBank)
                    } label: {
                        AdmissionsQuestionRow(question: question)
                    }
                }
            }
        }
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var related: [AdmissionsQuestion] {
        questions.filter { $0.primaryTopic == topic.name }.sorted { $0.externalQuestionID < $1.externalQuestionID }
    }
    private var performance: QuestionPerformanceSummary { AdmissionsAnalytics.latestQuestionSummary(related) }
    private var manualStatus: Binding<TopicStatus> {
        Binding(get: { topic.manualStatus }, set: { topic.manualStatus = $0; save() })
    }
    private var coverage: Binding<SpecificationCoverageState> {
        Binding(get: { topic.specificationCoverage }, set: { topic.specificationCoverage = $0; save() })
    }
    private var needsReview: Binding<Bool> {
        Binding(get: { topic.needsReview }, set: { topic.needsReview = $0; save() })
    }
    private func save() { try? modelContext.save() }
}

private struct NeedsReviewQuestionsView: View {
    @Query(filter: #Predicate<AdmissionsQuestion> { $0.isImportedActive })
    private var questions: [AdmissionsQuestion]

    var body: some View {
        List(reviewQuestions) { question in
            NavigationLink {
                QuestionDetailView(question: question, assignment: nil, attemptOrigin: .needsReview)
            } label: {
                AdmissionsQuestionRow(question: question)
            }
        }
        .overlay {
            if reviewQuestions.isEmpty {
                ContentUnavailableView("No Question Review Backlog", systemImage: "bookmark.slash")
            }
        }
        .navigationTitle("Needs Review")
    }

    private var reviewQuestions: [AdmissionsQuestion] {
        questions.filter { $0.reviewState != .none }.sorted { $0.externalQuestionID < $1.externalQuestionID }
    }
}
