import SwiftData
import SwiftUI

struct DiagnosticHomeView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let onEdit: () -> Void
    let onProgrammeGenerated: () -> Void

    @State private var assessment: DiagnosticAssessment?
    @State private var selections: [DiagnosticPaperSelection] = []
    @State private var papers: [DiagnosticPaperRecord] = []
    @State private var responses: [DiagnosticResponse] = []
    @State private var issue: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
                        Text("Step 2 of 2")
                            .font(RevisrTypography.label)
                            .foregroundStyle(RevisrColors.accentTeal)
                        Label("Build your starting point", systemImage: "doc.text.magnifyingglass")
                            .font(RevisrTypography.cardTitle)
                        Text("Complete two \(settings.publicExam.title) papers. Your answers are saved as you go. For multiple-choice papers, the solution PDF unlocks after you submit your answers. Your results will guide the future revision plan.")
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(papers.filter { $0.status == .completed }.count), total: 2) {
                            Text("\(papers.filter { $0.status == .completed }.count) of 2 papers complete")
                        }
                    }
                    .padding(.vertical, RevisrSpacing.compact)
                }

                if let issue {
                    Section("Content needs review") {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Text("Your preparation details and any earlier diagnostic work remain saved.")
                            .font(.footnote)
                    }
                } else {
                    ForEach(selections, id: \.source.stableSourceID) { selection in
                        if let paper = papers.first(where: { $0.ordinal == selection.ordinal }) {
                            Section("Paper \(selection.ordinal)") {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(selection.displayName).font(.headline)
                                    Text("\(selection.policy.questionCount) questions · \(selection.policy.durationMinutes) minute paper")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(selection.ordinal == 2 && papers.first(where: { $0.ordinal == 1 })?.status != .completed
                                         ? "Unlocks after Paper 1" : statusText(paper))
                                        .font(.subheadline.weight(.semibold))
                                }
                                if selection.ordinal == 2 && papers.first(where: { $0.ordinal == 1 })?.status != .completed {
                                    Label("Complete Paper 1 to unlock", systemImage: "lock")
                                        .foregroundStyle(.secondary)
                                } else {
                                    NavigationLink(paper.status == .notStarted ? "Start paper" :
                                        paper.status == .completed ? "View summary" : "Resume paper") {
                                        DiagnosticPaperView(
                                            settings: settings,
                                            exam: settings.publicExam,
                                            paper: paper,
                                            selection: selection
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if let assessment, assessment.completedAt != nil {
                        Section("Diagnostic complete") {
                            NavigationLink("View your diagnostic report") {
                                DiagnosticReportView(
                                    exam: assessment.exam,
                                    papers: papers,
                                    responses: responses,
                                    questions: selections.flatMap(\.questions)
                                )
                            }
                            Text("Your results are saved. Generate a programme from your diagnostic evidence, exam date and study availability.")
                                .foregroundStyle(.secondary)
                            Button("Create my revision programme") {
                                do {
                                    _ = try PublicProgrammeService.generateIfNeeded(
                                        settings: settings, in: modelContext)
                                    onProgrammeGenerated()
                                } catch {
                                    issue = error.localizedDescription
                                }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }

                Section {
                    Button("Edit preparation details", action: onEdit)
                } footer: {
                    Text("Papers and solutions are local development resources pending redistribution rights review.")
                }
            }
            .navigationTitle("Diagnostics")
            .onAppear(perform: prepare)
        }
    }

    private func statusText(_ paper: DiagnosticPaperRecord) -> String {
        let paperResponses = responses.filter { $0.paperID == paper.stableID }
        switch paper.status {
        case .notStarted: return "Ready when you are"
        case .answering:
            let count = paperResponses.filter {
                settings.publicExam == .bmo ? $0.wasAttempted : $0.selectedOption != nil
            }.count
            return "\(count) of \(paperResponses.count) recorded · saved locally"
        case .marking: return "Answers submitted · self-marking in progress"
        case .completed: return "Complete · results saved"
        }
    }

    private func prepare() {
        do {
            let sources = try modelContext.fetch(FetchDescriptor<SourceDocument>())
            let questions = try modelContext.fetch(FetchDescriptor<AdmissionsQuestion>())
            let solutions = try modelContext.fetch(FetchDescriptor<SolutionDocument>())
            let links = try modelContext.fetch(FetchDescriptor<QuestionSolutionLink>())
            let selected = try DiagnosticPaperSelector.select(
                exam: settings.publicExam,
                sources: sources,
                questions: questions,
                solutions: solutions,
                links: links
            )
            let current = try DiagnosticAssessmentService.loadOrCreate(
                settings: settings, selection: selected, in: modelContext
            )
            selections = selected
            assessment = current
            papers = try modelContext.fetch(FetchDescriptor<DiagnosticPaperRecord>())
                .filter { $0.assessmentID == current.stableID }.sorted { $0.ordinal < $1.ordinal }
            let paperIDs = Set(papers.map(\.stableID))
            responses = try modelContext.fetch(FetchDescriptor<DiagnosticResponse>())
                .filter { paperIDs.contains($0.paperID) }
            issue = nil
        } catch {
            issue = error.localizedDescription
        }
    }
}

private struct DiagnosticPDFSheet: Identifiable {
    let id: String
    let title: String
    let url: URL
    let page: Int?
}

struct DiagnosticPaperView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let settings: AppSettings
    let exam: PublicExamKind
    let paper: DiagnosticPaperRecord
    let selection: DiagnosticPaperSelection

    @State private var responses: [DiagnosticResponse] = []
    @State private var currentIndex = 0
    @State private var openedPDF: DiagnosticPDFSheet?
    @State private var showingSubmitConfirmation = false
    @State private var showingFinishConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
                    Text(selection.displayName).font(.title3.bold())
                    Text("Paper \(paper.ordinal) · \(selection.policy.durationMinutes) minute paper")
                        .foregroundStyle(.secondary)
                    if let credit = selection.policy.creatorCredit {
                        Text("Original paper: \(credit)").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Source: \(selection.source.displayName)").font(.footnote).foregroundStyle(.secondary)
                    }
                    if paper.status == .answering {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Label(elapsedText(paper.elapsed(at: timeline.date)), systemImage: "clock")
                                .font(.subheadline.monospacedDigit())
                        }
                        HStack {
                            if paper.runningSince == nil {
                                Button("Resume timer") { act { try DiagnosticAssessmentService.resume(paper, in: modelContext) } }
                            } else {
                                Button("Pause timer") { act { try DiagnosticAssessmentService.pause(paper, in: modelContext) } }
                            }
                        }
                    } else if paper.startedAt != nil {
                        Label("Recorded elapsed time: \(elapsedText(paper.accumulatedSeconds))", systemImage: "clock")
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, RevisrSpacing.compact)
            }

            if paper.status == .notStarted {
                Section("Before you start") {
                    Text(exam == .bmo
                         ? "Write complete proofs on paper. After submission, you may enter self-estimated marks out of 10 per question. No examiner mark scheme is bundled."
                         : "Record one A–E answer per question, then submit your answers before opening the solution PDF. Mark your work honestly against that PDF.")
                    Text("The elapsed timer can be paused. Your work is saved after each change.")
                        .foregroundStyle(.secondary)
                    Button("Start Paper \(paper.ordinal)") {
                        act { try DiagnosticAssessmentService.start(paper, in: modelContext) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if paper.status == .completed {
                completedSection
            } else if let question = selection.questions[safe: currentIndex],
                      let response = responses.first(where: { $0.questionID == question.externalQuestionID }) {
                Section {
                    HStack {
                        Text("Question \(currentIndex + 1) of \(selection.questions.count)")
                            .font(.headline)
                        Spacer()
                        Text(question.primaryTopic).font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(currentIndex + 1), total: Double(selection.questions.count))
                    Button("Open question paper at Q\(question.questionNumber ?? currentIndex + 1)") {
                        openQuestionPDF(question)
                    }
                    if paper.status == .answering {
                        answerControls(response)
                    } else {
                        markingControls(response)
                    }
                    HStack {
                        Button("Previous") { currentIndex -= 1 }
                            .disabled(currentIndex == 0)
                        Spacer()
                        Button("Next") { currentIndex += 1 }
                            .disabled(currentIndex + 1 >= selection.questions.count)
                    }
                    .fontWeight(.semibold)
                } footer: {
                    Text("Saved on this iPhone. Unanswered and unassessed questions remain distinct in your report.")
                }

                if paper.status == .answering {
                    Section {
                        Button(exam == .bmo ? "Submit proofs for self-assessment" : "Submit answers for self-marking") {
                            showingSubmitConfirmation = true
                        }
                    }
                } else {
                    Section {
                        if let solution = selection.solution,
                           let url = SolutionLibraryService.bundledURL(for: solution) {
                            Button("Open \(solution.solutionType.title)") {
                                openedPDF = DiagnosticPDFSheet(
                                    id: solution.stableSolutionID,
                                    title: solution.displayName,
                                    url: url,
                                    page: nil
                                )
                            }
                            Text("Credit: \(solution.provenanceOrganization)")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if exam == .bmo {
                            Text("No verified local BMO mark scheme is available. Marks you enter are self-estimates.")
                                .foregroundStyle(.secondary)
                        }
                        Button("Finish Paper \(paper.ordinal)") { showingFinishConfirmation = true }
                    }
                }
            }
        }
        .navigationTitle("Paper \(paper.ordinal)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onDisappear(perform: pauseRunningTimer)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pauseRunningTimer() }
        }
        .sheet(item: $openedPDF) { item in
            NavigationStack {
                SourcePDFView(url: item.url, page: item.page)
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .confirmationDialog("Submit answers?", isPresented: $showingSubmitConfirmation) {
            Button(exam == .bmo ? "Submit and enter estimates" : "Submit and unlock marking") {
                act { try DiagnosticAssessmentService.submitAnswers(paper, in: modelContext) }
            }
        } message: {
            Text(exam == .bmo
                 ? "\(recordedCount) of \(responses.count) proofs recorded. Your attempts and notes will be locked. You can then enter self-estimated marks; no examiner scheme is bundled."
                 : "\(recordedCount) of \(responses.count) answers recorded. They will be locked before the PDF solutions become available for self-marking.")
        }
        .confirmationDialog("Finish this paper?", isPresented: $showingFinishConfirmation) {
            Button("Finish Paper") {
                act { try DiagnosticAssessmentService.complete(paper, settings: settings, in: modelContext) }
            }
        } message: {
            Text("\(unassessedCount) recorded responses are unassessed. You can finish with these gaps, but the result cannot be edited afterward.")
        }
        .alert("Couldn’t Save Diagnostic", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func answerControls(_ response: DiagnosticResponse) -> some View {
        if exam == .bmo {
            Toggle("I attempted a written proof", isOn: Binding(
                get: { response.wasAttempted },
                set: { value in act { try DiagnosticAssessmentService.recordProofAttempt(value, response: response, paper: paper, in: modelContext) } }
            ))
            TextField("Notes about your proof", text: Binding(
                get: { response.notes },
                set: { value in act { try DiagnosticAssessmentService.recordNotes(value, response: response, paper: paper, in: modelContext) } }
            ), axis: .vertical)
            .lineLimit(2...5)
        } else {
            Picker("Your answer", selection: Binding(
                get: { response.selectedOption ?? "" },
                set: { value in act { try DiagnosticAssessmentService.recordChoice(value.isEmpty ? nil : value, response: response, paper: paper, in: modelContext) } }
            )) {
                Text("Unanswered").tag("")
                ForEach(["A", "B", "C", "D", "E"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func markingControls(_ response: DiagnosticResponse) -> some View {
        if exam == .bmo {
            LabeledContent("Written proof", value: response.wasAttempted ? "Attempted" : "Unanswered")
            if response.wasAttempted {
                Picker("Self-estimated marks", selection: Binding(
                    get: { response.selfEstimatedMarks ?? -1 },
                    set: { value in act { try DiagnosticAssessmentService.recordEstimatedMarks(value < 0 ? nil : value, response: response, paper: paper, in: modelContext) } }
                )) {
                    Text("Unassessed").tag(-1)
                    ForEach(0...10, id: \.self) { value in Text("\(value) of 10").tag(value) }
                }
                .pickerStyle(.menu)
                Text("This is your estimate, not an examiner mark.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent("Your locked answer", value: response.selectedOption ?? "Unanswered")
            if response.selectedOption != nil {
                Picker("After checking the solution", selection: Binding(
                    get: { response.marking },
                    set: { value in act { try DiagnosticAssessmentService.recordMarking(value, response: response, paper: paper, in: modelContext) } }
                )) {
                    Text("Unassessed").tag(DiagnosticMarking.unassessed)
                    Text("Correct").tag(DiagnosticMarking.correct)
                    Text("Incorrect").tag(DiagnosticMarking.incorrect)
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var completedSection: some View {
        let result = DiagnosticAnalysis.report(
            exam: exam,
            papers: [paper],
            responses: responses,
            questions: selection.questions
        ).papers.first
        return Section("Paper complete") {
            Label("Your work is saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(RevisrColors.accentTeal)
            if let result {
                Text(result.displayScore).font(.headline)
                Text("\(result.answeredCount) of \(result.questionCount) answered · \(result.assessedCount) assessed")
                Text(result.provenance).font(.footnote).foregroundStyle(.secondary)
            }
            Button("Back to diagnostics") { dismiss() }
        }
    }

    private var unassessedCount: Int {
        responses.filter { response in
            if exam == .bmo { return response.wasAttempted && response.selfEstimatedMarks == nil }
            return response.selectedOption != nil && response.marking == .unassessed
        }.count
    }

    private var recordedCount: Int {
        responses.filter { exam == .bmo ? $0.wasAttempted : $0.selectedOption != nil }.count
    }

    private func openQuestionPDF(_ question: AdmissionsQuestion) {
        guard let url = SourceLibraryService.bundledURL(for: selection.source) else {
            errorMessage = "The local question paper is unavailable."
            return
        }
        openedPDF = DiagnosticPDFSheet(
            id: selection.source.stableSourceID,
            title: selection.displayName,
            url: url,
            page: question.page
        )
    }

    private func refresh() {
        do {
            responses = try modelContext.fetch(FetchDescriptor<DiagnosticResponse>())
                .filter { $0.paperID == paper.stableID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func act(_ operation: () throws -> Void) {
        do {
            try operation()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pauseRunningTimer() {
        guard paper.status == .answering, paper.runningSince != nil else { return }
        do {
            try DiagnosticAssessmentService.pause(paper, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

struct DiagnosticReportView: View {
    let exam: PublicExamKind
    let papers: [DiagnosticPaperRecord]
    let responses: [DiagnosticResponse]
    let questions: [AdmissionsQuestion]

    private var report: DiagnosticReport {
        DiagnosticAnalysis.report(exam: exam, papers: papers, responses: responses, questions: questions)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Label("Your starting point", systemImage: "chart.bar.doc.horizontal")
                        .font(RevisrTypography.cardTitle)
                    Text("This report describes the evidence Revisr has from two completed papers. It is a planning baseline, not a predicted examination score.")
                        .font(RevisrTypography.supporting)
                        .foregroundStyle(RevisrColors.secondaryLabel)
                    if exam == .bmo {
                        RevisrStatusLabel(title: "Self-assessed marks", systemImage: "pencil.and.outline",
                                          color: RevisrColors.warning)
                    }
                }
                .padding(.vertical, RevisrSpacing.small)
            }
            Section("Paper results") {
                ForEach(report.papers, id: \.sourceID) { paper in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Paper \(paper.ordinal)").font(.headline)
                        Text(paper.displayScore)
                        Text("\(paper.answeredCount) answered · \(paper.assessedCount) assessed · \(elapsedText(paper.elapsedSeconds)) recorded time")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(paper.provenance).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    .padding(.vertical, RevisrSpacing.compact)
                    .accessibilityElement(children: .combine)
                }
            }
            Section("Topics") {
                ForEach(report.topics, id: \.name) { topic in
                    signalRow(topic)
                }
            }
            if !report.skills.isEmpty {
                Section("Reasoning skills") {
                    ForEach(report.skills, id: \.name) { skill in signalRow(skill) }
                }
            }
            Section("Timing") {
                Text("The recorded time covers active paper sessions only. Pauses and time outside the assessment screen are excluded; individual question times were not measured.")
                    .foregroundStyle(RevisrColors.secondaryLabel)
            }
            Section("Next") {
                Text("Your diagnostic baseline is saved. Return to Diagnostics to generate a revision programme from these signals.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Diagnostic report")
    }

    private func signalRow(_ signal: DiagnosticTopicResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(signal.name).font(.headline)
            let style = signalStyle(signal.level)
            RevisrStatusLabel(title: signal.level.title, systemImage: style.systemImage,
                              color: style.color)
            Text(signal.explanation).font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
            if signal.unansweredCount > 0 || signal.unassessedCount > 0 {
                Text("\(signal.unansweredCount) unanswered · \(signal.unassessedCount) unassessed")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, RevisrSpacing.compact)
    }

    private func elapsedText(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private func signalStyle(_ level: DiagnosticEvidenceLevel) -> (systemImage: String, color: Color) {
        switch level {
        case .strongDifficulty: ("exclamationmark.triangle.fill", RevisrColors.critical)
        case .possibleImprovement: ("arrow.up.right.circle.fill", RevisrColors.warning)
        case .relativeStrength: ("checkmark.circle.fill", RevisrColors.success)
        case .insufficient: ("questionmark.circle.fill", RevisrColors.secondaryLabel)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
