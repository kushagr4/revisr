import SwiftData
import SwiftUI

struct PublicRootTabView: View {
    let settings: AppSettings
    let onEditSettings: () -> Void
    @Query private var programmes: [PublicProgramme]

    private var programme: PublicProgramme? {
        programmes.first { $0.stableID == PublicProgrammeService.programmeID(settings: settings) }
    }

    var body: some View {
        Group {
            if let programme {
                TabView {
                    PublicTodayView(settings: settings, programme: programme)
                        .tabItem { Label("Today", systemImage: "checklist") }
                    PublicPlanView(settings: settings, programme: programme)
                        .tabItem { Label("Plan", systemImage: "calendar") }
                    PublicProgressView(programme: programme)
                        .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
                    PublicTopicsView(programme: programme)
                        .tabItem { Label("Topics", systemImage: "list.bullet.rectangle") }
                    PublicProgrammeSettingsView(settings: settings, programme: programme,
                        onEditSettings: onEditSettings)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else {
                ContentUnavailableView("Programme unavailable", systemImage: "calendar.badge.exclamationmark",
                    description: Text("Your diagnostics remain saved. Reopen Revisr to retry the local programme."))
            }
        }
        .tint(RevisrColors.accentTeal)
    }
}

private struct PublicTodayView: View {
    let settings: AppSettings
    let programme: PublicProgramme
    @Query(sort: \PublicProgrammeTask.scheduledDate) private var allTasks: [PublicProgrammeTask]

    private var today: Date { DateUtilities.appCalendar().startOfDay(for: .now) }
    private var tasks: [PublicProgrammeTask] {
        allTasks.filter { $0.programmeID == programme.stableID && $0.isActive
            && DateUtilities.isSameDay($0.scheduledDate, today) }
    }
    private var minutes: Int { tasks.reduce(0) { $0 + $1.allocatedMinutes } }
    private var complete: Int { tasks.filter { $0.completedAt != nil }.count }
    private var nextTask: PublicProgrammeTask? { tasks.first { $0.completedAt == nil } }
    private var examDay: Bool { DateUtilities.isSameDay(programme.examDateSnapshot, today) }
    private var examPassed: Bool {
        today > DateUtilities.appCalendar().startOfDay(for: programme.examDateSnapshot)
    }
    private var focusTitle: String {
        if let nextTask { return nextTask.topic }
        if examDay { return "Your examination is today" }
        if examPassed { return "Your examination date has passed" }
        return "A clear day to reset"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
                        Label("Your \(settings.publicExam.title) programme", systemImage: "sparkle.magnifyingglass")
                            .font(RevisrTypography.cardTitle)
                        Text(focusTitle)
                            .font(RevisrTypography.metric)
                        Text("Exam \(programme.examDateSnapshot.formatted(date: .abbreviated, time: .omitted)) · \(settings.publicWeeklyTargetMinutes ?? 0) minutes available each week")
                            .font(RevisrTypography.supporting).foregroundStyle(RevisrColors.secondaryLabel)
                        if tasks.isEmpty {
                            RevisrStatusLabel(
                                title: examDay ? "Exam day" : examPassed ? "Preparation window ended" : "Rest or unfilled day",
                                systemImage: examDay ? "flag.checkered" : "leaf",
                                color: examDay ? RevisrColors.warning : RevisrColors.secondaryLabel
                            )
                        } else {
                            Text("Today's mandatory work: \(complete) of \(tasks.count) complete · \(minutes) estimated minutes")
                                .font(RevisrTypography.bodyEmphasized)
                            ProgressView(value: Double(complete), total: Double(max(1, tasks.count)))
                                .tint(RevisrColors.accentTeal)
                                .accessibilityLabel("Today's completion")
                                .accessibilityValue("\(complete) of \(tasks.count) tasks complete")
                            if let nextTask {
                                NavigationLink {
                                    PublicProgrammeTaskView(task: nextTask)
                                } label: {
                                    Label("Start next task", systemImage: "arrow.right.circle.fill")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(RevisrColors.accentTeal)
                            } else {
                                RevisrStatusLabel(title: "All today's work complete", systemImage: "checkmark.circle.fill",
                                                  color: RevisrColors.success)
                            }
                        }
                    }
                    .padding(.vertical, RevisrSpacing.compact)
                }
                if PublicProgrammeService.settingsChanged(programme, settings: settings) {
                    Section {
                        Label("Your preparation settings changed. Review the future schedule in Plan.",
                              systemImage: "calendar.badge.exclamationmark")
                    }
                }
                if tasks.isEmpty {
                    Section {
                        ContentUnavailableView(
                            examDay ? "Exam day" : examPassed ? "Preparation window ended" : "No mandatory work today",
                            systemImage: examDay ? "flag.checkered" : "leaf",
                            description: Text(examDay
                                ? "Your revision programme ends before today. Use your own exam-day routine."
                                : examPassed
                                    ? "Your saved plan remains available for review. Update the exam date in Settings to continue planning."
                                    : "This is an available rest or unfilled day. Your next planned tasks are in Plan."))
                    }
                } else {
                    Section("Today's tasks") {
                        ForEach(tasks, id: \.stableID) { task in
                            NavigationLink { PublicProgrammeTaskView(task: task) } label: {
                                PublicTaskRow(task: task)
                            }
                        }
                    }
                }
                Section {
                    Text("Optional practice is separate from the mandatory tasks above. Completing a task records actual work; scheduled questions alone do not count as learned.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Today")
        }
    }
}

private struct PublicPlanView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let programme: PublicProgramme
    @Query(sort: \PublicProgrammeTask.scheduledDate) private var allTasks: [PublicProgrammeTask]
    @State private var showingRefreshConfirmation = false
    @State private var refreshError: String?

    var body: some View {
        let calendar = DateUtilities.appCalendar()
        let tasks = allTasks.filter { $0.programmeID == programme.stableID && $0.isActive }
        let tasksByDay = Dictionary(grouping: tasks) {
            calendar.startOfDay(for: $0.scheduledDate)
        }
        let start = calendar.startOfDay(for: programme.generatedAt)
        let end = calendar.startOfDay(for: programme.examDateSnapshot)
        let dateCount = max(0, min(730, calendar.dateComponents([.day], from: start, to: end).day ?? 0))
        let dates = (0..<dateCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let completedSinceRefresh = tasks.filter { $0.completedAt != nil }.count
            - programme.completedCountAtRefresh

        return NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                        Text("\(programme.exam.title) revision plan").font(.title3.bold())
                        Text("\(dates.count) calendar days · \(tasks.count) tasks · \(tasks.filter { $0.completedAt != nil }.count) complete")
                            .foregroundStyle(.secondary)
                        Text("Based on your diagnostic results, available weekdays and weekly target. Tasks show the reason they were selected.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, RevisrSpacing.compact)
                }
                if PublicProgrammeService.settingsChanged(programme, settings: settings) {
                    Section {
                        Label("Your exam date or availability changed. Review and apply a revised future schedule.",
                              systemImage: "calendar.badge.exclamationmark")
                    }
                } else if completedSinceRefresh >= 3 {
                    Section {
                        Label("New completed work can inform your next refresh. The next three days stay stable.",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section {
                    Button("Review and refresh future plan", systemImage: "arrow.triangle.2.circlepath") {
                        showingRefreshConfirmation = true
                    }
                } footer: {
                    Text("Completed work and attempts stay saved. Missed tasks do not pile up; future incomplete tasks may change.")
                }
                Section("Calendar") {
                    ForEach(dates, id: \.self) { date in
                        let dayTasks = tasksByDay[calendar.startOfDay(for: date)] ?? []
                        NavigationLink {
                            PublicProgrammeDayView(date: date, tasks: dayTasks)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                        .font(.headline)
                                    Text(dayTasks.isEmpty ? "Rest or no eligible task"
                                         : "\(dayTasks.count) tasks · \(dayTasks.reduce(0) { $0 + $1.allocatedMinutes }) estimated minutes")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !dayTasks.isEmpty {
                                    Text("\(dayTasks.filter { $0.completedAt != nil }.count)/\(dayTasks.count)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan")
            .confirmationDialog("Refresh future work?", isPresented: $showingRefreshConfirmation) {
                Button("Apply revised schedule") {
                    do {
                        _ = try PublicProgrammeService.refresh(settings: settings, in: modelContext)
                    } catch {
                        refreshError = error.localizedDescription
                    }
                }
            } message: {
                Text(PublicProgrammeService.settingsChanged(programme, settings: settings)
                     ? "Future incomplete tasks will be rebuilt for your new date and availability. Completed work stays saved."
                     : "The next three days stay stable. Later incomplete tasks may change based on your recorded progress.")
            }
            .alert("Couldn’t Refresh Plan", isPresented: Binding(
                get: { refreshError != nil }, set: { if !$0 { refreshError = nil } }
            )) { Button("OK", role: .cancel) { refreshError = nil } }
                message: { Text(refreshError ?? "Please try again.") }
        }
    }
}

private struct PublicProgrammeDayView: View {
    let date: Date
    let tasks: [PublicProgrammeTask]

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView("No mandatory work", systemImage: "leaf",
                    description: Text("This day is available for rest or optional practice."))
            } else {
                Section("Tasks") {
                    ForEach(tasks, id: \.stableID) { task in
                        NavigationLink { PublicProgrammeTaskView(task: task) } label: {
                            PublicTaskRow(task: task)
                        }
                    }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
    }
}

private struct PublicTaskRow: View {
    let task: PublicProgrammeTask

    var body: some View {
        HStack(alignment: .top, spacing: RevisrSpacing.standard) {
            Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(task.completedAt == nil ? .secondary : RevisrColors.accentTeal)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.activity.title).font(.headline)
                Text(task.questionID.map { "\(task.topic) · \($0)" } ?? "\(task.topic) · paper")
                    .font(.subheadline)
                Text(task.reason).font(RevisrTypography.caption).foregroundStyle(RevisrColors.secondaryLabel)
                HStack(spacing: RevisrSpacing.small) {
                    Text("\(task.allocatedMinutes) estimated minutes")
                    if task.completedAt != nil { Text("Completed") }
                }
                .font(RevisrTypography.caption)
                .foregroundStyle(task.completedAt == nil ? RevisrColors.secondaryLabel : RevisrColors.success)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.completedAt == nil ? "Not started" : "Completed")
    }
}

private struct PublicProgressView: View {
    let programme: PublicProgramme
    @Query private var allTasks: [PublicProgrammeTask]
    @Query private var allAttempts: [QuestionAttempt]

    var body: some View {
        let programmeTasks = allTasks.filter { $0.programmeID == programme.stableID }
        let progress = PublicProgrammeProgressSnapshot(tasks: programmeTasks)
        let attempts = allAttempts.filter { progress.completedAttemptIDs.contains($0.id) }

        return NavigationStack {
            List {
                Section("Programme work") {
                    LabeledContent("Completed tasks", value: "\(progress.completedTaskCount)")
                    LabeledContent("Active tasks", value: "\(progress.activeTaskCount)")
                    LabeledContent("Recorded question attempts", value: "\(attempts.count)")
                    ProgressView(value: Double(progress.completedTaskCount),
                                 total: Double(max(1, progress.plannedTaskCount))) {
                        Text("Programme completion")
                    }
                    .tint(RevisrColors.accentTeal)
                    .accessibilityValue("\(progress.completedTaskCount) of \(progress.plannedTaskCount) planned tasks complete")
                    Text("Scheduled work counts as progress only after you complete it.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                if attempts.isEmpty {
                    Section {
                        ContentUnavailableView("No completed question work yet", systemImage: "chart.bar",
                            description: Text("Complete a planned question to see practice outcomes here."))
                    }
                } else {
                    Section("Recorded outcomes") {
                        ForEach(QuestionAttemptOutcome.allCases) { outcome in
                            LabeledContent(outcome.title,
                                value: "\(attempts.filter { $0.outcome == outcome }.count)")
                        }
                    }
                    Section("Topics practised") {
                        ForEach(Dictionary(grouping: programmeTasks.filter {
                            $0.completedAt != nil && $0.questionID != nil
                        }, by: \.topic)
                            .map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }, id: \.0) { topic in
                            LabeledContent(topic.0, value: "\(topic.1) completed")
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}

private struct PublicTopicsView: View {
    let programme: PublicProgramme
    @Query private var allTasks: [PublicProgrammeTask]

    private var tasks: [PublicProgrammeTask] {
        allTasks.filter { $0.programmeID == programme.stableID && $0.isActive && $0.questionID != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Topic focus comes from assessed diagnostics and recorded practice. Areas with little evidence receive exploratory work.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                }
                Section("Planned topics") {
                    ForEach(Dictionary(grouping: tasks, by: \.topic)
                        .map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }, id: \.0) { topic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.0).font(.headline)
                            Text("\(topic.1.filter { $0.completedAt != nil }.count) of \(topic.1.count) tasks complete")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let reason = topic.1.first?.reason {
                                Text(reason).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Topics")
        }
    }
}

private struct PublicProgrammeSettingsView: View {
    let settings: AppSettings
    let programme: PublicProgramme
    let onEditSettings: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Preparation") {
                    LabeledContent("Examination", value: settings.publicExam.title)
                    LabeledContent("Exam date", value: settings.publicExamDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not set")
                    LabeledContent("Weekly target", value: "\(settings.publicWeeklyTargetMinutes ?? 0) minutes")
                    LabeledContent("Available days", value: settings.publicAvailability
                        .filter(\.isAvailable).map { $0.weekday.title }.joined(separator: ", "))
                    Button("Edit preparation details", action: onEditSettings)
                }
                if PublicProgrammeService.settingsChanged(programme, settings: settings) {
                    Section("Plan review") {
                        Text("Your saved programme still uses the earlier date or availability. Open Plan to review and apply a refresh.")
                    }
                }
                Section("Privacy") {
                    Text("Your diagnostics, programme and attempts are stored locally on this iPhone. No account or network service is needed.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct PublicProgrammeTaskView: View {
    @Environment(\.modelContext) private var modelContext
    let task: PublicProgrammeTask
    @State private var question: AdmissionsQuestion?
    @State private var source: SourceDocument?
    @State private var resolutions: [QuestionSolutionResolution] = []
    @State private var outcome = QuestionAttemptOutcome.correct
    @State private var errorType: QuestionErrorType?
    @State private var minutesSpent = 0
    @State private var notes = ""
    @State private var showingPDF = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text(task.activity.title).font(.title3.bold())
                LabeledContent("Focus", value: task.topic)
                LabeledContent("Planned time", value: "\(task.allocatedMinutes) minutes")
                Text(task.reason).foregroundStyle(.secondary)
            }
            Section("Paper") {
                if let source, let url = SourceLibraryService.bundledURL(for: source) {
                    Button(task.questionID == nil ? "Open complete paper" : "Open question in paper") {
                        showingPDF = true
                    }
                    Text(source.displayName).font(.footnote).foregroundStyle(.secondary)
                    Text("The paper is a local development resource pending rights review.")
                        .font(.footnote).foregroundStyle(.secondary)
                    .sheet(isPresented: $showingPDF) {
                        NavigationStack {
                            SourcePDFView(url: url, page: question?.page)
                                .navigationTitle(source.displayName)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                } else {
                    Text("The local paper is unavailable. This task cannot be completed until the resource is restored.")
                        .foregroundStyle(.secondary)
                }
            }
            if task.completedAt == nil && task.isActive {
                if task.questionID != nil {
                    Section {
                        Picker("Outcome", selection: $outcome) {
                            ForEach(QuestionAttemptOutcome.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        if outcome != .correct {
                            Picker("Error type", selection: $errorType) {
                                Text("Not recorded").tag(QuestionErrorType?.none)
                                ForEach(QuestionErrorType.allCases) { value in
                                    Text(value.title).tag(QuestionErrorType?.some(value))
                                }
                            }
                        }
                        Stepper("Minutes spent: \(minutesSpent)", value: $minutesSpent, in: 0...600)
                        TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                        if let question, !resolutions.isEmpty {
                            SolutionAccessView(question: question, resolutions: resolutions)
                        }
                        Button("Save completed question") { completeQuestion() }
                            .disabled(question == nil || source == nil)
                    } header: {
                        Text("Record your work")
                    } footer: {
                        Text("For BMO, the outcome is your self-assessment. Leave minutes at zero if you did not time the work.")
                    }
                } else {
                    Section {
                        TextField("Notes about your paper", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                        Button("Mark paper session complete") { completePaper() }
                            .disabled(source == nil)
                    } header: {
                        Text("Complete paper")
                    } footer: {
                        Text("Completion is self-reported. No score is inferred from this paper session.")
                    }
                }
            } else {
                Section("Completed") {
                    LabeledContent("Completed", value: task.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Saved")
                    if !task.completionNote.isEmpty { Text(task.completionNote) }
                    Text("Your earlier result is preserved when the plan changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(task.questionID ?? "Full paper")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepare)
        .alert("Couldn’t Save Work", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) { errorMessage = nil } }
            message: { Text(errorMessage ?? "Please try again.") }
    }

    private func prepare() {
        do {
            if let id = task.questionID {
                question = try modelContext.fetch(FetchDescriptor<AdmissionsQuestion>())
                    .first { $0.externalQuestionID == id }
            }
            if let questionSource = question?.sourceDocument {
                source = questionSource
            } else {
                source = try modelContext.fetch(FetchDescriptor<SourceDocument>())
                    .first { $0.stableSourceID == task.sourceID }
            }
            if let question {
                let links = try modelContext.fetch(FetchDescriptor<QuestionSolutionLink>())
                    .filter { $0.question?.externalQuestionID == question.externalQuestionID }
                resolutions = SolutionLibraryService.resolutions(for: question, links: links)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func completeQuestion() {
        guard let question else { return }
        do {
            try PublicProgrammeService.completeQuestion(task, question: question, outcome: outcome,
                seconds: minutesSpent * 60, errorType: errorType,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), in: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }

    private func completePaper() {
        do {
            try PublicProgrammeService.completePaper(task,
                note: notes.trimmingCharacters(in: .whitespacesAndNewlines), in: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }
}
