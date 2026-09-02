import SwiftData
import SwiftUI

enum QuestionBankQuickFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case standby = "Standby"
    case unattempted = "Unattempted"
    case incorrect = "Incorrect"
    case needsReview = "Needs Review"
    case hard = "Hard"
    case preserved = "Preserved Papers"
    case solutionAvailable = "Solution Available"
    case workedSolution = "Worked Solution"
    case markScheme = "Mark Scheme"
    case solutionPending = "Solution Pending"
    case noDirectMapping = "No Direct Mapping"

    var id: String { rawValue }
}

struct QuestionBankView: View {
    @Query(filter: #Predicate<AdmissionsQuestion> { $0.isImportedActive }, sort: \AdmissionsQuestion.externalQuestionID)
    private var questions: [AdmissionsQuestion]
    @Query(filter: #Predicate<AdmissionsProgramme> { $0.isImportedActive })
    private var programmes: [AdmissionsProgramme]
    @Query(filter: #Predicate<SolutionDocument> { $0.isImportedActive })
    private var solutionDocuments: [SolutionDocument]
    @Query(filter: #Predicate<QuestionSolutionLink> { $0.isImportedActive })
    private var solutionLinks: [QuestionSolutionLink]
    @State private var searchText = ""
    @State private var quickFilter = QuestionBankQuickFilter.all

    init() {
        PerformanceProbe.begin("question_bank_open")
    }

    var body: some View {
        let solutionIndex = PerformanceProbe.measure("question_bank_solution_index") {
            QuestionBankSolutionIndex(documents: solutionDocuments, links: solutionLinks)
        }
        let currentProgrammeDay = programmes.first?.dayNumber(for: .now)
        let displayedQuestions = PerformanceProbe.measure("question_bank_filter") {
            filteredQuestions(using: solutionIndex, currentProgrammeDay: currentProgrammeDay)
        }

        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(QuestionBankQuickFilter.allCases) { filter in
                            Button(filter.rawValue) { quickFilter = filter }
                                .buttonStyle(.bordered)
                                .tint(quickFilter == filter ? RevisrColors.accentTeal : .secondary)
                                .accessibilityAddTraits(quickFilter == filter ? .isSelected : [])
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            Section("\(displayedQuestions.count) Questions") {
                ForEach(displayedQuestions) { question in
                    NavigationLink {
                        QuestionDetailView(
                            question: question,
                            assignment: todayAssignment(for: question, dayNumber: currentProgrammeDay),
                            attemptOrigin: .questionBank
                        )
                    } label: {
                        AdmissionsQuestionRow(
                            question: question,
                            assignment: todayAssignment(for: question, dayNumber: currentProgrammeDay),
                            solutionLabel: solutionLabel(for: question, using: solutionIndex)
                        )
                    }
                }
            }
        }
        .navigationTitle("Question Bank")
        .searchable(text: $searchText, prompt: "ID, source, topic or skill")
        .onAppear { PerformanceProbe.end("question_bank_open") }
    }

    private func filteredQuestions(
        using solutionIndex: QuestionBankSolutionIndex,
        currentProgrammeDay: Int?
    ) -> [AdmissionsQuestion] {
        questions.filter { question in
            let matchesQuickFilter: Bool = switch quickFilter {
            case .all: true
            case .today: todayAssignment(for: question, dayNumber: currentProgrammeDay) != nil
            case .standby: question.isStandby
            case .unattempted: question.attempts.isEmpty
            case .incorrect: AdmissionsAnalytics.latestMeaningfulAttempt(for: question)?.outcome == .incorrect
            case .needsReview: question.reviewState != .none
            case .hard: question.difficulty >= 4
            case .preserved: question.protection != .none
            case .solutionAvailable: !solutionIndex.links(for: question).isEmpty
            case .workedSolution:
                solutionIndex.links(for: question).contains { $0.solutionDocument?.solutionType == .workedSolution }
            case .markScheme:
                solutionIndex.links(for: question).contains { $0.solutionDocument?.solutionType == .markScheme }
            case .solutionPending:
                question.sourceDocument.map { solutionIndex.availability(for: $0) == .pendingSource } ?? true
            case .noDirectMapping:
                if let source = question.sourceDocument,
                   solutionIndex.availability(for: source) == .partial {
                    !solutionIndex.links(for: question).contains { $0.mappingConfidence == .verifiedPage }
                } else {
                    false
                }
            }
            guard matchesQuickFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let haystack = [
                question.externalQuestionID,
                question.family,
                question.sourceDocument?.displayName,
                question.primaryTopic,
                question.secondaryTopic,
                question.reasoningSkill,
                question.paper
            ].compactMap { $0 }.joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func solutionLabel(
        for question: AdmissionsQuestion,
        using solutionIndex: QuestionBankSolutionIndex
    ) -> String {
        let mapped = solutionIndex.links(for: question)
        if let preferred = mapped.compactMap(\.solutionDocument)
            .sorted(by: { $0.solutionType.preferenceOrder < $1.solutionType.preferenceOrder }).first {
            return preferred.solutionType.title
        }
        if let source = question.sourceDocument {
            return solutionIndex.availability(for: source).title
        }
        return SolutionAvailability.pendingSource.title
    }

    private func todayAssignment(
        for question: AdmissionsQuestion,
        dayNumber: Int?
    ) -> ProgrammeAssignment? {
        guard let dayNumber else { return nil }
        return question.programmeAssignments.first {
            $0.isImportedActive && $0.programmeDay?.dayNumber == dayNumber
        }
    }
}

struct ExtraPracticeView: View {
    @Query(filter: #Predicate<AdmissionsQuestion> { $0.isImportedActive })
    private var questions: [AdmissionsQuestion]
    @Query(filter: #Predicate<AdmissionsProgramme> { $0.isImportedActive })
    private var programmes: [AdmissionsProgramme]
    @State private var topic = "Any"
    @State private var difficulty = 0
    @State private var paperFit = "Any"
    @State private var needsReviewOnly = false
    @State private var result: [AdmissionsQuestion] = []

    var body: some View {
        List {
            Section("Practice Request") {
                Picker("Primary topic", selection: $topic) {
                    Text("Any").tag("Any")
                    ForEach(topics, id: \.self) { Text($0).tag($0) }
                }
                Picker("Difficulty", selection: $difficulty) {
                    Text("Any").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("TMUA paper fit", selection: $paperFit) {
                    Text("Any").tag("Any")
                    Text("Paper 1").tag("Paper 1")
                    Text("Paper 2").tag("Paper 2")
                }
                Toggle("Needs Review only", isOn: $needsReviewOnly)
                Button("Find Practice", systemImage: "sparkles") { select() }
                    .buttonStyle(.borderedProminent)
                    .tint(RevisrColors.accentTeal)
            }
            Section("Selection") {
                if result.isEmpty {
                    Text("Choose filters, then find up to ten questions. Selection is stable, prefers unattempted work, and excludes protected or future benchmark questions.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(result) { question in
                        NavigationLink {
                            QuestionDetailView(question: question, assignment: nil, attemptOrigin: .extraPractice)
                        } label: {
                            AdmissionsQuestionRow(question: question)
                        }
                    }
                }
            }
        }
        .navigationTitle("Extra Practice")
    }

    private var topics: [String] { Array(Set(questions.map(\.primaryTopic))).sorted() }

    private func select() {
        result = ExtraPracticeSelector.select(
            from: questions,
            filter: ExtraPracticeFilter(
                primaryTopic: topic == "Any" ? nil : topic,
                difficulty: difficulty == 0 ? nil : difficulty,
                tmuaPaperFit: paperFit == "Any" ? nil : paperFit,
                needsReviewOnly: needsReviewOnly
            ),
            programme: programmes.first
        )
    }
}

struct QuestionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var question: AdmissionsQuestion
    @Query(filter: #Predicate<QuestionSolutionLink> { $0.isImportedActive })
    private var solutionLinks: [QuestionSolutionLink]
    let assignment: ProgrammeAssignment?
    let attemptOrigin: QuestionAttemptOrigin
    private let localSourceURL: URL?
    @State private var showsAttempt = false
    @State private var showsPDF = false

    init(
        question: AdmissionsQuestion,
        assignment: ProgrammeAssignment?,
        attemptOrigin: QuestionAttemptOrigin
    ) {
        PerformanceProbe.begin("question_detail_open")
        self.question = question
        self.assignment = assignment
        self.attemptOrigin = attemptOrigin
        self.localSourceURL = question.sourceDocument.flatMap { SourceLibraryService.resolvedURL(for: $0) }
        let questionID = question.externalQuestionID
        _solutionLinks = Query(filter: #Predicate<QuestionSolutionLink> {
            $0.isImportedActive && $0.question?.externalQuestionID == questionID
        })
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Text(question.externalQuestionID)
                        .font(.title2.weight(.bold))
                    Text(question.descriptor ?? question.primaryTopic)
                        .foregroundStyle(.secondary)
                    HStack {
                        AdmissionsStatusBadge(text: question.difficultyLabel, systemImage: "gauge.with.dots.needle.50percent")
                        if question.protection != .none {
                            AdmissionsStatusBadge(text: "Protected", systemImage: "lock.fill", tint: .orange)
                        }
                    }
                }
                .padding(.vertical, RevisrSpacing.small)
            }

            Section("Work") {
                Button("Open Question", systemImage: "doc.text.magnifyingglass") { showsPDF = true }
                    .disabled(localSourceURL == nil)
                if localSourceURL == nil {
                    Label("This source paper is missing from the current private build.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Start or Record Attempt", systemImage: "timer") { showsAttempt = true }
                SolutionAccessView(question: question, resolutions: solutionResolutions)
                Picker("Review state", selection: reviewStateBinding) {
                    ForEach(QuestionReviewState.allCases) { state in Text(state.title).tag(state) }
                }
            }

            Section("Question Metadata") {
                LabeledContent("Source", value: question.sourceDocument?.displayName ?? question.family)
                if let paper = question.paper { LabeledContent("Paper", value: paper) }
                LabeledContent("Question", value: question.questionLabel)
                if let page = question.page { LabeledContent("PDF page", value: "\(page)") }
                LabeledContent("Primary topic", value: question.primaryTopic)
                if let secondary = question.secondaryTopic { LabeledContent("Secondary topic", value: secondary) }
                if let reasoning = question.reasoningSkill { LabeledContent("Reasoning skill", value: reasoning) }
                if let fit = question.tmuaPaperFit { LabeledContent("TMUA paper fit", value: fit) }
                LabeledContent("Difficulty", value: "\(question.difficulty) · \(question.difficultyLabel)")
                if let confidence = question.classificationConfidence {
                    LabeledContent("Classification confidence", value: confidence)
                }
                if let use = question.recommendedUse { LabeledContent("Recommended use", value: use) }
            }

            Section("Independent State") {
                LabeledContent("Programme", value: question.isScheduled ? "Scheduled" : "Not scheduled")
                LabeledContent("Standby", value: question.isStandby ? "Eligible" : "No")
                LabeledContent("Attempted", value: question.attempts.isEmpty ? "No" : "Yes")
                LabeledContent("Automatic selection", value: question.protection == .none ? "Allowed" : "Protected")
            }

            Section("Previous Attempts") {
                if sortedAttempts.isEmpty {
                    Text("No attempts recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedAttempts) { attempt in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(attempt.outcome.title, systemImage: attempt.outcome.systemImage)
                                .font(.headline)
                            Text("\(attempt.attemptedAt.formatted(date: .abbreviated, time: .shortened)) · \(format(seconds: attempt.timeTakenSeconds))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let error = attempt.errorType { Text(error.title).font(.caption) }
                            if !attempt.notes.isEmpty { Text(attempt.notes).font(.caption).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { PerformanceProbe.end("question_detail_open") }
        .sheet(isPresented: $showsAttempt) {
            NavigationStack {
                QuestionAttemptView(question: question, assignment: assignment, origin: attemptOrigin)
            }
        }
        .sheet(isPresented: $showsPDF) {
            if let url = localSourceURL {
                NavigationStack {
                    SourcePDFView(url: url, page: question.page)
                        .navigationTitle(question.externalQuestionID)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private var reviewStateBinding: Binding<QuestionReviewState> {
        Binding(
            get: { question.reviewState },
            set: { question.reviewState = $0; try? modelContext.save() }
        )
    }
    private var sortedAttempts: [QuestionAttempt] { question.attempts.sorted { $0.attemptedAt > $1.attemptedAt } }
    private var solutionResolutions: [QuestionSolutionResolution] {
        PerformanceProbe.measure("question_detail_solution_resolution") {
            SolutionLibraryService.resolutions(for: question, links: solutionLinks)
        }
    }
    private func format(seconds: Int) -> String { "\(seconds / 60)m \(seconds % 60)s" }
}
