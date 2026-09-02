import SwiftData
import SwiftUI

struct QuestionAttemptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var timers: [QuestionAttemptTimerState]
    @Query(filter: #Predicate<QuestionSolutionLink> { $0.isImportedActive })
    private var solutionLinks: [QuestionSolutionLink]
    let question: AdmissionsQuestion
    let assignment: ProgrammeAssignment?
    let origin: QuestionAttemptOrigin
    private let sourceURL: URL?
    @State private var outcome = QuestionAttemptOutcome.correct
    @State private var errorType: QuestionErrorType?
    @State private var notes = ""
    @State private var saveError: String?
    @State private var showsPDF = false

    init(
        question: AdmissionsQuestion,
        assignment: ProgrammeAssignment?,
        origin: QuestionAttemptOrigin
    ) {
        PerformanceProbe.begin("attempt_editor_open")
        self.question = question
        self.assignment = assignment
        self.origin = origin
        self.sourceURL = question.sourceDocument.flatMap { SourceLibraryService.resolvedURL(for: $0) }
        let questionID = question.externalQuestionID
        _solutionLinks = Query(filter: #Predicate<QuestionSolutionLink> {
            $0.isImportedActive && $0.question?.externalQuestionID == questionID
        })
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: RevisrSpacing.standard) {
                    Text(question.externalQuestionID)
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(format(seconds: Int(timer?.elapsed(at: context.date) ?? 0)))
                            .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                            .accessibilityLabel("Attempt time")
                            .accessibilityValue(format(seconds: Int(timer?.elapsed(at: context.date) ?? 0)))
                    }
                    timerControls
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, RevisrSpacing.standard)
            }

            Section("Outcome") {
                Picker("Result", selection: $outcome) {
                    ForEach(QuestionAttemptOutcome.allCases) { value in
                        Label(value.title, systemImage: value.systemImage).tag(value)
                    }
                }
                .pickerStyle(.inline)
                if outcome != .correct {
                    Picker("Error type", selection: $errorType) {
                        Text("Not recorded").tag(QuestionErrorType?.none)
                        ForEach(QuestionErrorType.allCases) { value in
                            Text(value.title).tag(QuestionErrorType?.some(value))
                        }
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                    .onChange(of: notes) { _, _ in PerformanceProbe.tick("notes_change") }
            }

            Section("Reference") {
                SolutionAccessView(question: question, resolutions: solutionResolutions)
            }

            Section {
                Button("Save Attempt", systemImage: "checkmark.circle") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(RevisrColors.accentTeal)
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Each save creates a new attempt. Earlier attempts and their error history remain unchanged.")
            }
        }
        .navigationTitle("Record Attempt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            if sourceURL != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Question", systemImage: "doc.text.magnifyingglass") {
                        showsPDF = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsPDF) {
            if let sourceURL {
                NavigationStack {
                    SourcePDFView(url: sourceURL, page: question.page)
                        .navigationTitle(question.externalQuestionID)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear(perform: ensureTimer)
        .onAppear { PerformanceProbe.end("attempt_editor_open") }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, timer?.status == .running {
                // No mutation is needed: elapsed time derives from persisted timestamps.
            }
        }
        .alert("Couldn’t Save Attempt", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var timerControls: some View {
        let status = timer?.status ?? .idle
        HStack(spacing: RevisrSpacing.standard) {
            switch status {
            case .idle:
                Button("Start", systemImage: "play.fill") { start() }
                    .buttonStyle(.borderedProminent)
            case .running:
                Button("Pause", systemImage: "pause.fill") { pause() }
                    .buttonStyle(.bordered)
            case .paused:
                Button("Resume", systemImage: "play.fill") { resume() }
                    .buttonStyle(.borderedProminent)
                Button("Reset", role: .destructive) { timer?.reset(); saveTimer() }
                    .buttonStyle(.bordered)
            }
        }
        .tint(RevisrColors.accentTeal)
    }

    private var timer: QuestionAttemptTimerState? { timers.first }
    private var solutionResolutions: [QuestionSolutionResolution] {
        PerformanceProbe.measure("attempt_solution_resolution") {
            SolutionLibraryService.resolutions(for: question, links: solutionLinks)
        }
    }

    private func ensureTimer() {
        if timers.isEmpty {
            modelContext.insert(QuestionAttemptTimerState())
            try? modelContext.save()
        }
    }

    private func start() {
        guard let timer else { return }
        timer.start(question: question, assignment: assignment)
        saveTimer()
    }

    private func pause() { timer?.pause(); saveTimer() }
    private func resume() { timer?.resume(); saveTimer() }
    private func saveTimer() { try? modelContext.save() }

    private func save() {
        let seconds = Int(timer?.elapsed() ?? 0)
        do {
            _ = try QuestionAttemptService.record(
                question: question,
                assignment: assignment,
                outcome: outcome,
                seconds: seconds,
                errorType: errorType,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                origin: origin,
                in: modelContext
            )
            timer?.reset()
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
