import SwiftData
import SwiftUI

struct TMUARootTabView: View {
    let settings: AppSettings
    @Query private var programmes: [PublicProgramme]
    @State private var tab = Self.initialTab
    @State private var showingSettings = Self.initialTab == "settings"

    private static var initialTab: String {
#if DEBUG
        DebugTMUAScenarioService.value("--tmua-tab") ?? "today"
#else
        "today"
#endif
    }

    private var programme: PublicProgramme? {
        programmes.first { $0.stableID == TMUAProgrammeService.programmeID(settings: settings) }
    }

    var body: some View {
        if let programme {
            TabView(selection: $tab) {
                TMUATodayView(settings: settings, programme: programme)
                    .tabItem { Label("Today", systemImage: "checklist") }.tag("today")
                TMUAPlanView(settings: settings, programme: programme)
                    .tabItem { Label("Plan", systemImage: "calendar") }.tag("plan")
                TMUAProgressView(settings: settings, programme: programme)
                    .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }.tag("progress")
                TMUATopicsView(settings: settings, programme: programme)
                    .tabItem { Label("Topics", systemImage: "list.bullet.rectangle") }.tag("topics")
                TMUAQuestionsView(settings: settings)
                    .tabItem { Label("Questions", systemImage: "square.stack.3d.up") }.tag("questions")
            }
            // Settings opens from a gear on every tab: a sixth tab would be
            // folded into iOS's More menu, which nests navigation stacks.
            .environment(\.tmuaShowSettings, { showingSettings = true })
            .sheet(isPresented: $showingSettings) {
                TMUASettingsView(settings: settings, programme: programme, onDone: { showingSettings = false })
            }
            .tint(RevisrColors.accentStrong)
        } else {
            TMUADiagnosticHubView(settings: settings)
        }
    }
}

/// Values every tab derives from saved records, computed once per render.
@MainActor
struct TMUAStudentState {
    let content: TMUAContentContext?
    let snapshot: TMUADiagnosticSnapshot?
    let report: TMUADiagnosticReport?

    init(settings: AppSettings, context: ModelContext) {
        content = TMUAContentStore.context()
        snapshot = try? TMUADiagnosticService.load(settings: settings, in: context)
        if let snapshot, let syllabus = content?.syllabus {
            report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: syllabus)
        } else {
            report = nil
        }
    }
}

// MARK: - Today

private struct TMUATodayView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let programme: PublicProgramme
    @Query(sort: \PublicProgrammeTask.scheduledDate) private var allTasks: [PublicProgrammeTask]
    @Query private var sections: [TMUADiagnosticSection]

    var body: some View {
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let programmeTasks = allTasks.filter { $0.programmeID == programme.stableID }
        let tasks = programmeTasks.filter { $0.isActive && calendar.isDate($0.scheduledDate, inSameDayAs: today) }
        let complete = tasks.filter { $0.completedAt != nil }.count
        let minutes = tasks.reduce(0) { $0 + $1.allocatedMinutes }
        let next = tasks.first { $0.completedAt == nil }
            ?? programmeTasks.first { $0.isActive && $0.completedAt == nil && $0.scheduledDate > today }
        let days = PublicPreparationService.daysUntilExam(programme.examDateSnapshot)
        let state = TMUAStudentState(settings: settings, context: modelContext)
        let openDiagnostic = state.snapshot?.hasOpenExpansion == true
        let completedSinceRefresh = programmeTasks.filter { $0.completedAt != nil }.count - programme.completedCountAtRefresh
        let restDay = PublicProgrammeAvailability.isAvailable(on: today, schedule: programme.availabilitySnapshot,
                                                              calendar: calendar) == false

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(days > 0 ? "\(days)" : days == 0 ? "Today" : "Done")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Text(days > 0 ? "day\(days == 1 ? "" : "s") until your TMUA" : days == 0 ? "is your TMUA" : "Your exam date has passed")
                                .font(.headline).foregroundStyle(RevisrColors.secondaryLabel)
                        }
                        .accessibilityElement(children: .combine)
                        if tasks.isEmpty {
                            RevisrStatusLabel(title: days == 0 ? "Exam day" : restDay ? "Rest day" : "No tasks today",
                                              systemImage: days == 0 ? "flag.checkered" : "leaf",
                                              color: RevisrColors.secondaryLabel)
                        } else {
                            Text("\(complete) of \(tasks.count) tasks · \(minutes) minutes planned")
                                .font(RevisrTypography.bodyEmphasized)
                            ProgressView(value: Double(complete), total: Double(tasks.count))
                                .tint(RevisrColors.accentTeal)
                                .accessibilityLabel("Today's progress")
                                .accessibilityValue("\(complete) of \(tasks.count) complete")
                        }
                        if let next {
                            NavigationLink {
                                TMUATaskView(settings: settings, task: next)
                            } label: {
                                Label(calendar.isDate(next.scheduledDate, inSameDayAs: today)
                                      ? "Next: \(next.activity.title) · \(next.topic)"
                                      : "Next on \(next.scheduledDate.formatted(.dateTime.weekday(.wide))): \(next.topic)",
                                      systemImage: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else if !tasks.isEmpty {
                            RevisrStatusLabel(title: "Everything for today is done", systemImage: "checkmark.seal.fill",
                                              color: RevisrColors.success)
                        }
                    }
                    .padding(.vertical, RevisrSpacing.small)
                }
                if openDiagnostic {
                    Section {
                        NavigationLink {
                            TMUADiagnosticHubView(settings: settings, embedded: true)
                        } label: {
                            Label("Continue your added diagnostic questions", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
                if TMUAProgrammeService.settingsChanged(programme, settings: settings) || completedSinceRefresh >= 5 {
                    Section {
                        Label(TMUAProgrammeService.settingsChanged(programme, settings: settings)
                              ? "Your preparation settings changed. Refresh your plan in the Plan tab."
                              : "You have completed \(completedSinceRefresh) tasks since your plan was last refreshed. Refreshing lets your recent results shape what comes next.",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    }
                }
                if !tasks.isEmpty {
                    Section("Today") {
                        ForEach(tasks, id: \.stableID) { task in
                            NavigationLink { TMUATaskView(settings: settings, task: task) } label: {
                                TMUATaskRow(task: task)
                            }
                        }
                    }
                }
                if let report = state.report {
                    let focus = report.topics.filter { $0.level == .strongDifficulty || $0.level == .possibleImprovement }
                    Section {
                        if focus.isEmpty {
                            Text("Your diagnostic did not single out particular topics, so your plan spreads practice across the syllabus.")
                                .font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                        } else {
                            ForEach(focus.prefix(3), id: \.name) { TMUAEvidenceRow(result: $0) }
                        }
                    } header: {
                        Text("Current priorities")
                    } footer: {
                        Text("Based on a \(report.length.title.lowercased()) diagnostic (\(report.length.confidenceTitle.lowercased()) evidence) and your recent practice.")
                    }
                }
            }
            .navigationTitle("Today")
            .tmuaSettingsButton()
        }
    }
}

struct TMUATaskRow: View {
    let task: PublicProgrammeTask

    var body: some View {
        HStack(alignment: .top, spacing: RevisrSpacing.compact) {
            Image(systemName: task.completedAt == nil ? Self.symbol(task.activity) : "checkmark.circle.fill")
                .foregroundStyle(task.completedAt == nil ? RevisrColors.accentTeal : RevisrColors.success)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.activity.title).font(.headline)
                Text(task.topic).font(.subheadline)
                Text(task.reason).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                Text(task.completedAt == nil ? "\(task.allocatedMinutes) minutes"
                     : "Completed\(task.completionNote.isEmpty ? "" : " · \(task.completionNote)")")
                    .font(.caption).foregroundStyle(task.completedAt == nil ? RevisrColors.secondaryLabel : RevisrColors.success)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ activity: PublicPlanningActivity) -> String {
        switch activity {
        case .targeted: "scope"
        case .consolidation: "square.stack"
        case .errorReview: "arrow.uturn.backward.circle"
        case .mixed: "shuffle"
        case .timed: "timer"
        case .fullPaper: "doc.text"
        case .finalReview: "flag.checkered"
        case .spacedReview: "clock.arrow.circlepath"
        case .diagnosticRefinement: "plus.magnifyingglass"
        }
    }
}

// MARK: - Plan

private struct TMUAPlanView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let programme: PublicProgramme
    @Query(sort: \PublicProgrammeTask.scheduledDate) private var allTasks: [PublicProgrammeTask]
    @State private var showingRefresh = false
    @State private var errorMessage: String?
    @State private var showPast = false

    var body: some View {
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let tasks = allTasks.filter { $0.programmeID == programme.stableID && ($0.isActive || $0.completedAt != nil) }
        let byDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.scheduledDate) }
        let start = showPast ? calendar.startOfDay(for: programme.generatedAt) : min(today, calendar.startOfDay(for: programme.examDateSnapshot))
        let end = calendar.startOfDay(for: programme.examDateSnapshot)
        let count = max(0, min(730, calendar.dateComponents([.day], from: start, to: end).day ?? 0))
        let dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let weeks = Dictionary(grouping: dates) { calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? $0 }
        let changed = TMUAProgrammeService.settingsChanged(programme, settings: settings)

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                        Text("\(tasks.filter { $0.isActive }.count) planned tasks · \(tasks.filter { $0.completedAt != nil }.count) complete")
                            .font(.headline)
                        Text("Last refreshed \(programme.refreshedAt.formatted(date: .abbreviated, time: .shortened)) · version \(programme.revision)")
                            .font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                        if let summary = programme.refreshSummary {
                            Text(summary).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                        }
                    }
                    Button("Refresh future plan", systemImage: "arrow.triangle.2.circlepath") { showingRefresh = true }
                    Toggle("Show earlier days", isOn: $showPast)
                } footer: {
                    Text(changed ? "Your settings changed, so all future incomplete tasks will be rebuilt. Completed work stays saved."
                         : "Completed work is always kept. The next three days stay stable; later incomplete tasks may change based on your results.")
                }
                ForEach(weeks.keys.sorted(), id: \.self) { week in
                    Section("Week of \(week.formatted(.dateTime.day().month(.abbreviated)))") {
                        ForEach(weeks[week, default: []].sorted(), id: \.self) { date in
                            dayRow(date, tasks: byDay[date] ?? [], calendar: calendar)
                        }
                    }
                }
                Section {
                    Label("Exam day · \(programme.examDateSnapshot.formatted(date: .complete, time: .omitted))",
                          systemImage: "flag.checkered")
                } footer: {
                    Text("Exam day has no revision tasks. The final three study days use lighter final-review sessions.")
                }
            }
            .navigationTitle("Plan")
            .tmuaSettingsButton()
            .confirmationDialog("Refresh your future plan?", isPresented: $showingRefresh, titleVisibility: .visible) {
                Button("Refresh plan") { refresh() }
            } message: {
                Text(changed ? "Future incomplete tasks will be rebuilt for your new settings."
                     : "Tasks in the next three days stay the same. Later work will reflect your latest results.")
            }
            .alert("Couldn’t Refresh", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func dayRow(_ date: Date, tasks: [PublicProgrammeTask], calendar: Calendar) -> some View {
        let available = PublicProgrammeAvailability.isAvailable(on: date, schedule: settings.publicAvailability,
                                                                calendar: calendar)
        let days = calendar.dateComponents([.day], from: date, to: calendar.startOfDay(for: programme.examDateSnapshot)).day ?? 0
        let isToday = calendar.isDateInToday(date)
        return NavigationLink {
            TMUADayView(settings: settings, date: date, tasks: tasks)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + (isToday ? " · Today" : ""))
                        .font(.subheadline.weight(isToday ? .bold : .semibold))
                    Text(tasks.isEmpty ? (available == false ? "Rest day" : "No tasks")
                         : "\(tasks.count) task\(tasks.count == 1 ? "" : "s") · \(tasks.reduce(0) { $0 + $1.allocatedMinutes }) min"
                            + (days <= 3 && days > 0 ? " · final review" : ""))
                        .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                }
                Spacer()
                if !tasks.isEmpty {
                    Text("\(tasks.filter { $0.completedAt != nil }.count)/\(tasks.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func refresh() {
        guard let content = TMUAContentStore.context() else { return }
        do {
            try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TMUADayView: View {
    let settings: AppSettings
    let date: Date
    let tasks: [PublicProgrammeTask]

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "leaf",
                    description: Text("Use this day to rest or for optional practice in Questions."))
            } else {
                ForEach(tasks, id: \.stableID) { task in
                    NavigationLink { TMUATaskView(settings: settings, task: task) } label: { TMUATaskRow(task: task) }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
    }
}

// MARK: - Task and practice

struct TMUATaskView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let task: PublicProgrammeTask

    var body: some View {
        if task.activity == .diagnosticRefinement {
            if task.completedAt != nil {
                ContentUnavailableView("Diagnostic extended", systemImage: "checkmark.seal",
                    description: Text("Your extra diagnostic questions are part of your results."))
            } else {
                TMUADiagnosticHubView(settings: settings, embedded: true)
            }
        } else if let id = task.questionID, let item = TMUAContentStore.context()?.bank.latestItems.first(where: { $0.stableId == id }) {
            TMUAPracticeView(settings: settings, item: item, task: task)
        } else {
            ContentUnavailableView("Question unavailable", systemImage: "exclamationmark.triangle",
                description: Text("This question is not available in this build. Refresh your plan to replace it; completed work is unchanged."))
        }
    }
}

struct TMUAPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    let settings: AppSettings
    let item: TMUAContentItem
    var task: PublicProgrammeTask?

    @Query private var attempts: [TMUAPracticeAttempt]
    @Query private var flags: [TMUAReviewFlag]
    @State private var selection: String?
    @State private var result: TMUAPracticeAttempt?
    @State private var activeSeconds: TimeInterval = 0
    @State private var resumedAt: Date? = .now
    @State private var errorMessage: String?

    private var history: [TMUAPracticeAttempt] {
        attempts.filter { $0.profileSettingsID == settings.id && $0.itemStableID == item.stableId }
            .sorted { $0.attemptedAt > $1.attemptedAt }
    }

    private var flagged: Bool {
        flags.contains { $0.profileSettingsID == settings.id && $0.itemStableID == item.stableId && $0.isFlagged }
    }

    private var taskDone: Bool { task?.completedAt != nil }
    private var showsAnswer: Bool { result != nil || taskDone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RevisrSpacing.large) {
                if let task {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(task.activity.title) · \(task.allocatedMinutes) minutes").font(.subheadline.weight(.semibold))
                        Text(task.reason).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                }
                HStack {
                    Text("Paper \(item.paper) · \(TMUAContentStore.context()?.syllabus.strandTitle(item.taxonomy.strand) ?? "")")
                        .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    Spacer()
                    Text(item.category.attributionTitle).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                }
                MathText(item.stem, textStyle: .title3)
                VStack(spacing: RevisrSpacing.compact) {
                    ForEach(item.options, id: \.id) { option in
                        TMUAOptionButton(option: option, selected: shownSelection == option.id,
                                         state: markingState(option)) {
                            guard !showsAnswer else { return }
                            selection = option.id
                        }
                    }
                }
                if showsAnswer {
                    let correct = (result?.isCorrect) ?? (history.first?.isCorrect ?? false)
                    RevisrStatusLabel(title: correct ? "Correct" : "Not this time — review the solution",
                                      systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill",
                                      color: correct ? RevisrColors.success : RevisrColors.critical)
                    TMUASolutionCard(solution: item.solution)
                } else {
                    Button {
                        check()
                    } label: {
                        Text("Check answer").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection == nil)
                }
                Toggle("Flag for later review", isOn: Binding(get: { flagged }, set: { setFlag($0) }))
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your attempts").font(.headline)
                        ForEach(history.prefix(5), id: \.id) { attempt in
                            Text("\(attempt.attemptedAt.formatted(date: .abbreviated, time: .shortened)) · \(attempt.isCorrect ? "Correct" : "Incorrect") (\(attempt.selectedOptionID))")
                                .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                        }
                    }
                }
            }
            .padding(RevisrSpacing.large)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resumedAt = .now } else { accumulate() }
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var shownSelection: String? {
        if let result { return result.selectedOptionID }
        if taskDone, let id = task?.completionAttemptID { return attempts.first { $0.id == id }?.selectedOptionID }
        return selection
    }

    private func markingState(_ option: TMUAOption) -> TMUAOptionButton.Marking {
        guard showsAnswer else { return .neutral }
        if option.id == item.correctOptionId { return shownSelection == option.id ? .correct : .key }
        return shownSelection == option.id ? .incorrect : .neutral
    }

    private func accumulate() {
        if let resumedAt { activeSeconds += Date.now.timeIntervalSince(resumedAt) }
        resumedAt = nil
    }

    private func check() {
        guard let selection else { return }
        accumulate()
        do {
            result = try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: selection,
                seconds: Int(activeSeconds), task: task, settings: settings, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setFlag(_ value: Bool) {
        do {
            try TMUAProgrammeService.setReviewFlag(value, itemStableID: item.stableId, settings: settings, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Progress

private struct TMUAProgressView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let programme: PublicProgramme
    @Query private var allTasks: [PublicProgrammeTask]
    @Query(sort: \TMUAPracticeAttempt.attemptedAt, order: .reverse) private var allAttempts: [TMUAPracticeAttempt]

    var body: some View {
        let tasks = allTasks.filter { $0.programmeID == programme.stableID }
        let progress = PublicProgrammeProgressSnapshot(tasks: tasks)
        let attempts = allAttempts.filter { $0.profileSettingsID == settings.id }
        let correct = attempts.filter(\.isCorrect).count
        let practiceSeconds = attempts.reduce(0) { $0 + $1.seconds }
        let reviews = tasks.filter { $0.completedAt != nil && ($0.activity == .errorReview || $0.activity == .spacedReview) }.count
        let state = TMUAStudentState(settings: settings, context: modelContext)
        let syllabus = state.content?.syllabus

        NavigationStack {
            List {
                Section("Programme") {
                    if progress.plannedTaskCount == 0 {
                        Text("No tasks yet.").foregroundStyle(RevisrColors.secondaryLabel)
                    } else {
                        LabeledContent("Completed tasks", value: "\(progress.completedTaskCount) of \(progress.plannedTaskCount)")
                        ProgressView(value: Double(progress.completedTaskCount), total: Double(progress.plannedTaskCount))
                            .tint(RevisrColors.accentTeal)
                            .accessibilityLabel("Programme tasks complete")
                            .accessibilityValue("\(progress.completedTaskCount) of \(progress.plannedTaskCount)")
                        LabeledContent("Mistake reviews completed", value: "\(reviews)")
                    }
                }
                Section {
                    LabeledContent("Question attempts", value: "\(attempts.count)")
                    if !attempts.isEmpty {
                        LabeledContent("Correct", value: "\(correct) of \(attempts.count)")
                    }
                    LabeledContent("Recorded practice time", value: "\(practiceSeconds / 60) min")
                    if let report = state.report {
                        LabeledContent("Diagnostic time", value: "\(report.activeSeconds / 60) min")
                    }
                } header: {
                    Text("Practice")
                } footer: {
                    Text("Attempts count every answer you check, including repeats; tasks count planned work. Neither on its own shows mastery.")
                }
                if let report = state.report {
                    Section("Diagnostic history") {
                        LabeledContent("\(report.length.title) diagnostic", value: report.combinedScore)
                        if let snapshot = state.snapshot {
                            ForEach(Dictionary(grouping: snapshot.sections.filter { $0.status == .submitted }, by: \.round)
                                .sorted { $0.key < $1.key }, id: \.key) { round, sections in
                                let items = snapshot.items.filter { item in sections.contains { $0.stableID == item.sectionID } }
                                LabeledContent(round == 0 ? "Initial (\(snapshot.diagnostic.initialLength.title))" : "Added round \(round)",
                                               value: "\(items.filter { $0.marking == .correct }.count) / \(items.count) · \(sections.compactMap(\.submittedAt).max()?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                            }
                        }
                    }
                }
                Section("Recent activity") {
                    if attempts.isEmpty {
                        Text("Your answered practice questions will appear here.").foregroundStyle(RevisrColors.secondaryLabel)
                    } else {
                        ForEach(attempts.prefix(15), id: \.id) { attempt in
                            HStack {
                                Image(systemName: attempt.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(attempt.isCorrect ? RevisrColors.success : RevisrColors.critical)
                                VStack(alignment: .leading) {
                                    Text(syllabus?.strandTitle(attempt.strandKey) ?? attempt.strandKey).font(.subheadline)
                                    Text(attempt.attemptedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .navigationTitle("Progress")
            .tmuaSettingsButton()
        }
    }
}

// MARK: - Topics

private struct TMUATopicsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let programme: PublicProgramme
    @Query private var allTasks: [PublicProgrammeTask]
    @Query private var allAttempts: [TMUAPracticeAttempt]

    var body: some View {
        let state = TMUAStudentState(settings: settings, context: modelContext)
        let tasks = allTasks.filter { $0.programmeID == programme.stableID }
        let attempts = allAttempts.filter { $0.profileSettingsID == settings.id }
        let diagnosticItems = state.snapshot?.submittedItems ?? []
        let evidence = Dictionary(uniqueKeysWithValues: (state.report?.topics ?? []).map { ($0.name, $0) })
        let eligible = state.content?.eligibleItems ?? []

        NavigationStack {
            List {
                Section {
                    Text("Evidence comes from diagnostic answers and is labelled with its confidence. Scheduled focus shows what your plan asks you to practise — it is not a measure of mastery.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                if let syllabus = state.content?.syllabus {
                    ForEach(syllabus.topics, id: \.key) { topic in
                        let topicDiagnostic = diagnosticItems.filter { $0.topicKey == topic.key }
                        let topicAttempts = attempts.filter { $0.topicKey == topic.key }
                        let scheduled = tasks.filter { $0.isActive && $0.completedAt == nil && $0.topic == topic.title }.count
                        let completed = tasks.filter { $0.completedAt != nil && $0.topic == topic.title }.count
                        let available = eligible.filter { $0.taxonomy.topic == topic.key }.count
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                if let result = evidence[topic.title] {
                                    let style = TMUAEvidenceRow.style(result.level)
                                    RevisrStatusLabel(title: result.level.title, systemImage: style.0, color: style.1)
                                } else {
                                    RevisrStatusLabel(title: "Not assessed in your diagnostic", systemImage: "circle.dashed",
                                                      color: RevisrColors.secondaryLabel)
                                }
                                Text("Diagnostic: \(topicDiagnostic.filter { $0.marking == .correct }.count)/\(topicDiagnostic.count) · Practice: \(topicAttempts.filter(\.isCorrect).count)/\(topicAttempts.count) correct")
                                    .font(.footnote.monospacedDigit())
                                Text("Plan: \(completed) done, \(scheduled) scheduled · \(available) question\(available == 1 ? "" : "s") available")
                                    .font(.footnote.monospacedDigit()).foregroundStyle(RevisrColors.secondaryLabel)
                            }
                            .accessibilityElement(children: .combine)
                            DisclosureGroup("Syllabus strands") {
                                ForEach(topic.strands, id: \.key) { strand in
                                    let sampled = topicDiagnostic.filter { $0.strandKey == strand.key }.count
                                    let count = eligible.filter { $0.taxonomy.strand == strand.key }.count
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(strand.title).font(.subheadline)
                                        Text("\(strand.specRefs.joined(separator: ", ")) · \(sampled) diagnostic · \(count) available")
                                            .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .font(.subheadline)
                        } header: {
                            Text(topic.title + (topic.papers == [2] ? " · Paper 2" : ""))
                        }
                    }
                } else {
                    ContentUnavailableView("Syllabus unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Topics")
            .tmuaSettingsButton()
        }
    }
}

// MARK: - Questions

private struct TMUAQuestionsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    @Query private var attempts: [TMUAPracticeAttempt]
    @Query private var flags: [TMUAReviewFlag]
    @Query private var sections: [TMUADiagnosticSection]
    @Query private var diagnosticItems: [TMUADiagnosticItem]
    @State private var paper: Int = 0
    @State private var topic: String = ""
    @State private var difficulty: Int = 0
    @State private var source: String = ""
    @State private var flaggedOnly = false
    @State private var debugPractice: TMUAContentItem?

    var body: some View {
        let content = TMUAContentStore.context()
        let openSectionIDs = Set(sections.filter { $0.status != .submitted }.map(\.stableID))
        // Questions waiting in an unsubmitted diagnostic section stay hidden so
        // practice cannot reveal their solutions early.
        let reserved = Set(diagnosticItems.filter { openSectionIDs.contains($0.sectionID) }.map(\.itemStableID))
        let mine = attempts.filter { $0.profileSettingsID == settings.id }
        let flagged = Set(flags.filter { $0.profileSettingsID == settings.id && $0.isFlagged }.map(\.itemStableID))
        let items = (content?.eligibleItems ?? []).filter { item in
            !reserved.contains(item.stableId)
                && (paper == 0 || item.paper == paper)
                && (topic.isEmpty || item.taxonomy.topic == topic)
                && (difficulty == 0 || item.difficulty == difficulty)
                && (source.isEmpty || item.category.rawValue == source)
                && (!flaggedOnly || flagged.contains(item.stableId))
        }
        let byItem = Dictionary(grouping: mine, by: \.itemStableID)

        NavigationStack {
            List {
                Section {
                    Picker("Paper", selection: $paper) {
                        Text("All").tag(0); Text("Paper 1").tag(1); Text("Paper 2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Picker("Topic", selection: $topic) {
                        Text("All topics").tag("")
                        ForEach(content?.syllabus.topics ?? [], id: \.key) { Text($0.title).tag($0.key) }
                    }
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Any").tag(0)
                        ForEach(1...5, id: \.self) { Text("Level \($0)").tag($0) }
                    }
                    Picker("Source", selection: $source) {
                        Text("All sources").tag("")
                        ForEach([TMUAContentCategory.revisrOriginal, .licensedPastPaper, .licensedMock], id: \.self) {
                            Text($0.attributionTitle).tag($0.rawValue)
                        }
                    }
                    Toggle("Flagged for review only", isOn: $flaggedOnly)
                } footer: {
                    if let content, content.distribution == .internal {
                        Text("Development build: \(content.unreviewedItemCount) questions are unreviewed drafts. \(content.licensedItemCount) licensed past or mock questions are available.")
                    }
                }
                Section("\(items.count) question\(items.count == 1 ? "" : "s")") {
                    if items.isEmpty {
                        Text("No questions match these filters.").foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    ForEach(items, id: \.versionKey) { item in
                        NavigationLink {
                            TMUAPracticeView(settings: settings, item: item)
                        } label: {
                            let history = byItem[item.stableId] ?? []
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    if flagged.contains(item.stableId) {
                                        Image(systemName: "flag.fill").foregroundStyle(RevisrColors.warning)
                                            .accessibilityLabel("Flagged")
                                    }
                                }
                                Text("Paper \(item.paper) · \(content?.syllabus.topicTitle(item.taxonomy.topic) ?? "") · level \(item.difficulty)")
                                    .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                                Text(history.isEmpty ? item.category.attributionTitle
                                     : "\(history.count) attempt\(history.count == 1 ? "" : "s") · last \(history.max { $0.attemptedAt < $1.attemptedAt }?.isCorrect == true ? "correct" : "incorrect")")
                                    .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .navigationTitle("Questions")
            .tmuaSettingsButton()
            .navigationDestination(item: $debugPractice) { TMUAPracticeView(settings: settings, item: $0) }
#if DEBUG
            .onAppear {
                if DebugTMUAScenarioService.value("--tmua-open") == "practice", debugPractice == nil {
                    debugPractice = items.first { $0.paper == 2 }
                }
            }
#endif
        }
    }
}

// MARK: - Settings

private struct TMUASettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let programme: PublicProgramme
    var onDone: () -> Void = {}
    @State private var editing = false
    @State private var examDate = Date.now
    @State private var weekly: Int?
    @State private var availability: [DayAvailability] = []
    @State private var session: Int?
    @State private var message: String?
    @AppStorage("tmua.reminder.enabled") private var reminderEnabled = false
    @AppStorage("tmua.reminder.minutes") private var reminderMinutes = 18 * 60

    var body: some View {
        let content = TMUAContentStore.context()
        NavigationStack {
            List {
                Section {
                    LabeledContent("Exam date", value: settings.publicExamDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not set")
                    LabeledContent("Weekly time", value: SettingsFormatting.weeklyTarget(settings.publicWeeklyTargetMinutes ?? 0))
                    LabeledContent("Study days", value: settings.publicAvailability.filter(\.isAvailable)
                        .map { String($0.weekday.title.prefix(3)) }.joined(separator: " "))
                    LabeledContent("Longest session", value: settings.publicSessionMinutes.map { "\($0) min" } ?? "No limit")
                    Button("Change preparation details") { beginEditing() }
                } header: {
                    Text("Preparation")
                } footer: {
                    Text("Changes rebuild future incomplete tasks. Completed tasks, attempts and diagnostic answers are never reset.")
                }
                Section("Diagnostic") {
                    NavigationLink("Diagnostic and results") {
                        TMUADiagnosticHubView(settings: settings, embedded: true)
                    }
                }
                Section {
                    Toggle("Daily study reminder", isOn: Binding(get: { reminderEnabled }, set: { setReminder($0) }))
                    if reminderEnabled {
                        DatePicker("Time", selection: Binding(
                            get: { Self.date(minutes: reminderMinutes) },
                            set: { reminderMinutes = Self.minutes(of: $0); TMUAReminderScheduler.schedule(minutes: reminderMinutes) }),
                            displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("A local reminder on this iPhone. Nothing is sent to a server.")
                }
                Section("Content in this build") {
                    if let content {
                        LabeledContent("Distribution", value: content.distribution == .internal ? "Development" : "Public")
                        LabeledContent("Original Revisr questions", value: "\(content.originalItemCount)")
                        LabeledContent("Licensed past/mock questions", value: "\(content.licensedItemCount)")
                        if content.unreviewedItemCount > 0 {
                            Text("\(content.unreviewedItemCount) questions are unreviewed development drafts and are excluded from public builds.")
                                .font(.footnote).foregroundStyle(RevisrColors.warning)
                        }
                        Text("Question bank \(content.bank.bankVersion) · \(content.syllabus.taxonomyVersion)")
                            .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    Text("Syllabus areas follow the \(content?.syllabus.specification.publisher ?? "UAT-UK") TMUA Content Specification (\(content?.syllabus.specification.assessmentWindow ?? "")). Revisr is independent and not endorsed by any examination provider.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                Section("Privacy") {
                    Text("Your plan, answers and progress are stored only on this iPhone. Revisr does not need an account and collects no personal information.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
            .sheet(isPresented: $editing) { editSheet }
            .alert("Preparation", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private var editSheet: some View {
        let calendar = DateUtilities.appCalendar()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let hint = TMUAAvailabilityEditor.validationMessage(weeklyMinutes: weekly, availability: availability,
                                                            sessionMinutes: session)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RevisrSpacing.large) {
                    DatePicker("Exam date", selection: $examDate, in: tomorrow..., displayedComponents: .date)
                    TMUAAvailabilityEditor(weeklyMinutes: $weekly, availability: $availability,
                                           sessionMinutes: $session, examDate: examDate)
                    if let hint { Text(hint).font(.footnote).foregroundStyle(RevisrColors.warning) }
                }
                .padding(RevisrSpacing.large)
            }
            .navigationTitle("Preparation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(hint != nil) }
            }
        }
    }

    private func beginEditing() {
        examDate = settings.publicExamDate ?? .now
        weekly = settings.publicWeeklyTargetMinutes
        availability = settings.publicAvailability
        session = settings.publicSessionMinutes
        editing = true
    }

    private func save() {
        guard let weekly else { return }
        do {
            try PublicPreparationService.saveFlexibleTMUAProfile(examDate: examDate, weeklyMinutes: weekly,
                availability: availability, sessionMinutes: session, settings: settings, in: modelContext)
            editing = false
            if let content = TMUAContentStore.context() {
                let updated = try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content,
                                                                         in: modelContext)
                message = "Your future plan was rebuilt. " + (updated.refreshSummary ?? "")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func setReminder(_ enabled: Bool) {
        reminderEnabled = enabled
        if enabled { TMUAReminderScheduler.requestAndSchedule(minutes: reminderMinutes) { granted in
            if !granted { reminderEnabled = false }
        } } else { TMUAReminderScheduler.cancel() }
    }

    static func date(minutes: Int) -> Date {
        DateUtilities.appCalendar().date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(of date: Date) -> Int {
        let parts = DateUtilities.appCalendar().dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
    }
}


private struct TMUAShowSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var tmuaShowSettings: () -> Void {
        get { self[TMUAShowSettingsKey.self] }
        set { self[TMUAShowSettingsKey.self] = newValue }
    }
}

private struct TMUASettingsButton: ViewModifier {
    @Environment(\.tmuaShowSettings) private var showSettings

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape", action: showSettings)
            }
        }
    }
}

extension View {
    func tmuaSettingsButton() -> some View { modifier(TMUASettingsButton()) }
}
