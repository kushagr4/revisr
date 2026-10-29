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
    @Query private var logs: [TMUAResourceLog]
    @State private var errorMessage: String?
    @State private var confirmingRefresh = false
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 48

    var body: some View {
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let programmeTasks = allTasks.filter { $0.programmeID == programme.stableID }
        let tasks = programmeTasks.filter { $0.isActive && calendar.isDate($0.scheduledDate, inSameDayAs: today) }
        let complete = tasks.filter { $0.completedAt != nil }.count
        let minutes = tasks.reduce(0) { $0 + $1.allocatedMinutes }
        let remainingMinutes = tasks.filter { $0.completedAt == nil }.reduce(0) { $0 + $1.allocatedMinutes }
        let missed = programmeTasks.filter { $0.isActive && $0.completedAt == nil && $0.scheduledDate < today }
        let mine = logs.filter { $0.profileSettingsID == settings.id }
        // A worksheet already under way comes first; then today's plan in order; then the next study day.
        let started = TMUAProgrammeService.startedWorksheetTaskIDs(mine)
        let next = tasks.first { $0.completedAt == nil && started.contains($0.stableID) }
            ?? tasks.first { $0.completedAt == nil }
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
                                .font(.system(size: countdownSize, weight: .bold, design: .rounded))
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
                                .accessibilityIdentifier("today.summary")
                            // The summary text above already reads "n of m tasks".
                            ProgressView(value: Double(complete), total: Double(tasks.count))
                                .tint(RevisrColors.accentTeal)
                                .accessibilityHidden(true)
                            if remainingMinutes > 0 {
                                Text("\(tasks.count - complete) to do · about \(remainingMinutes) minutes left")
                                    .font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                                    .accessibilityIdentifier("today.remaining")
                            }
                        }
                        if next == nil, !tasks.isEmpty {
                            RevisrStatusLabel(title: "Everything for today is done", systemImage: "checkmark.seal.fill",
                                              color: RevisrColors.success)
                        }
                    }
                    .padding(.vertical, RevisrSpacing.small)
                }
                if let next {
                    let isToday = calendar.isDate(next.scheduledDate, inSameDayAs: today)
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(next.activity.title, systemImage: TMUATaskRow.symbol(next.activity))
                                .font(.headline)
                            Text(next.topic).font(.subheadline)
                            Text(TMUATaskRow.involves(next, logs: mine)).font(.subheadline)
                                .foregroundStyle(RevisrColors.secondaryLabel)
                        }
                        .accessibilityElement(children: .combine)
                        // Value-based links keep an open task fixed: when it is
                        // completed, "next" moves on but the pushed screen must not.
                        NavigationLink(value: TMUATaskRoute(id: next.stableID)) {
                            Label(started.contains(next.stableID) ? "Continue" : isToday ? "Start" : "Look ahead",
                                  systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                        }
                        .accessibilityIdentifier("today.next")
                    } header: {
                        Text(isToday ? "Up next" : "Next study day · \(next.scheduledDate.formatted(.dateTime.weekday(.wide).day().month()))")
                    }
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
                if !tasks.isEmpty {
                    Section("Today") {
                        ForEach(tasks, id: \.stableID) { task in
                            NavigationLink(value: TMUATaskRoute(id: task.stableID)) {
                                TMUATaskRow(task: task, logs: mine)
                            }
                        }
                    }
                }
                if !missed.isEmpty {
                    Section {
                        ForEach(missed.prefix(5), id: \.stableID) { task in
                            NavigationLink(value: TMUATaskRoute(id: task.stableID)) {
                                TMUATaskRow(task: task, logs: mine, showsDate: true)
                            }
                        }
                        Button("Move unfinished work into my plan", systemImage: "arrow.triangle.2.circlepath") {
                            confirmingRefresh = true
                        }
                        .accessibilityIdentifier("today.refresh")
                    } header: {
                        Text("Unfinished from earlier days (\(missed.count))")
                            .accessibilityIdentifier("today.missed")
                    } footer: {
                        Text(missed.count > 5 ? "Showing 5 of \(missed.count). " : "")
                            + Text("You can still do these. Refreshing your plan returns their questions to the days ahead and keeps any worksheet you have started; nothing you completed changes.")
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
                        Text("From your \(report.length.title.lowercased()) diagnostic (\(report.length.confidenceTitle.lowercased()) evidence). Your plan also gives a topic more practice when recent answers Revisr marked were wrong; results you mark yourself only decide which questions come back.")
                    }
                }
            }
            .navigationTitle("Today")
            .tmuaSettingsButton()
            .navigationDestination(for: TMUATaskRoute.self) { route in
                if let task = programmeTasks.first(where: { $0.stableID == route.id }) {
                    TMUATaskView(settings: settings, task: task)
                }
            }
            .confirmationDialog("Move unfinished work into your plan?", isPresented: $confirmingRefresh,
                                titleVisibility: .visible) {
                Button("Refresh my plan") { refresh() }
            } message: {
                Text(TMUAProgrammeService.settingsChanged(programme, settings: settings)
                     ? "Your settings changed, so your plan is rebuilt from today for them. Completed work is kept, and a worksheet you have started stays where it is."
                     : "Your plan is rebuilt from today. Tasks in the next three days stay as they are, completed work is kept, and a worksheet you have started stays where it is.")
            }
            .alert("Couldn’t Refresh", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func refresh() {
        guard let content = TMUAContentStore.context() else { return }
        do {
            try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, resourceSessions: true, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TMUATaskRow: View {
    let task: PublicProgrammeTask
    var logs: [TMUAResourceLog] = []
    var showsDate = false

    var body: some View {
        let progress = task.activity == .topicWorksheet ? TMUAProgrammeService.worksheetProgress(task, logs: logs) : nil
        HStack(alignment: .top, spacing: RevisrSpacing.compact) {
            Image(systemName: task.completedAt == nil ? Self.symbol(task.activity) : "checkmark.circle.fill")
                .foregroundStyle(task.completedAt == nil ? RevisrColors.accentTeal : RevisrColors.success)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.activity.title).font(.headline)
                Text(showsDate ? "\(task.topic) · \(task.scheduledDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
                     : task.topic).font(.subheadline)
                Text(Self.firstSentence(task.reason)).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                Text(status(progress))
                    .font(.caption.weight(progress?.state == .inProgress ? .semibold : .regular))
                    .foregroundStyle(task.completedAt == nil ? RevisrColors.secondaryLabel : RevisrColors.success)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task.row")
    }

    private func status(_ progress: TMUAWorksheetProgress?) -> String {
        if task.completedAt != nil {
            return "Completed" + (task.completionNote.isEmpty ? "" : " · \(task.completionNote)")
        }
        if let progress {
            return progress.recorded > 0
                ? "In progress · \(progress.recorded) of \(progress.questionIDs.count) recorded · \(task.allocatedMinutes) minutes"
                : "Not started · \(task.allocatedMinutes) minutes"
        }
        return "\(task.allocatedMinutes) minutes"
    }

    /// The opening sentence: the full reason stays on the task screen.
    static func firstSentence(_ text: String) -> String {
        guard let range = text.range(of: ". ") else { return text }
        return String(text[..<range.lowerBound]) + "."
    }

    /// What the task involves, in a line: questions, how they are marked and the time.
    static func involves(_ task: PublicProgrammeTask, logs: [TMUAResourceLog]) -> String {
        switch task.activity {
        case .topicWorksheet:
            let progress = TMUAProgrammeService.worksheetProgress(task, logs: logs)
            let count = progress.questionIDs.count
            return "\(count) self-marked questions · about \(task.allocatedMinutes) minutes"
                + (progress.recorded > 0 ? " · \(progress.recorded) recorded" : "")
        case .resourcePractice:
            return "A paper from your library, self-marked · \(task.allocatedMinutes) minutes"
        case .diagnosticRefinement:
            return "Optional extra diagnostic questions · about \(task.allocatedMinutes) minutes"
        case .fullPaper:
            return "A full paper · \(task.allocatedMinutes) minutes"
        default:
            return "1 question marked by Revisr · \(task.allocatedMinutes) minutes"
        }
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
        case .resourcePractice: "doc.richtext"
        case .topicWorksheet: "list.bullet.clipboard"
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
        let contentSummary = TMUAProgrammeService.contentSummary(programme: programme,
            tasks: allTasks.filter { $0.programmeID == programme.stableID },
            seenStableIDs: TMUAProgrammeService.seenStableIDs(settings: settings, in: modelContext),
            availability: programme.availabilitySnapshot, calendar: calendar)

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                        Text("\(tasks.filter { $0.isActive }.count) planned tasks · \(tasks.filter { $0.completedAt != nil }.count) complete")
                            .font(.headline)
                            .accessibilityIdentifier("plan.summary")
                        Text("Last refreshed \(programme.refreshedAt.formatted(date: .abbreviated, time: .shortened)) · version \(programme.revision)")
                            .font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                        if let summary = programme.refreshSummary {
                            Text(summary).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                        }
                    }
                    if let notice = contentSummary.message {
                        Label(notice, systemImage: "books.vertical")
                            .font(.footnote)
                            .foregroundStyle(RevisrColors.secondaryLabel)
                            .accessibilityIdentifier("plan.contentNotice")
                    }
                    Button("Refresh future plan", systemImage: "arrow.triangle.2.circlepath") { showingRefresh = true }
                        .accessibilityIdentifier("plan.refresh")
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
        .accessibilityIdentifier(isToday ? "plan.day.today" : "plan.day")
    }

    private func refresh() {
        guard let content = TMUAContentStore.context() else { return }
        do {
            try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, resourceSessions: true, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TMUADayView: View {
    let settings: AppSettings
    let date: Date
    let tasks: [PublicProgrammeTask]
    @Query private var logs: [TMUAResourceLog]

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "leaf",
                    description: Text("Use this day to rest or for optional practice in Questions."))
            } else {
                ForEach(tasks, id: \.stableID) { task in
                    NavigationLink { TMUATaskView(settings: settings, task: task) } label: {
                        TMUATaskRow(task: task, logs: logs.filter { $0.profileSettingsID == settings.id })
                    }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
    }
}

// MARK: - Task and practice

/// Navigation value for one planned task.
struct TMUATaskRoute: Hashable {
    let id: String
}

/// A planned task looked up by its identity, for stacks that do not already hold the task list.
struct TMUATaskRouteDestination: View {
    let settings: AppSettings
    @Query private var tasks: [PublicProgrammeTask]

    init(settings: AppSettings, id: String) {
        self.settings = settings
        _tasks = Query(filter: #Predicate<PublicProgrammeTask> { $0.stableID == id })
    }

    var body: some View {
        if let task = tasks.first { TMUATaskView(settings: settings, task: task) }
    }
}

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
        } else if task.activity == .resourcePractice {
            TMUAResourceTaskView(settings: settings, task: task)
        } else if task.activity == .topicWorksheet {
            TMUAWorksheetTaskView(settings: settings, task: task)
        } else if let id = task.questionID, isReserved(id) {
            ContentUnavailableView("Finish your added diagnostic questions first", systemImage: "lock",
                description: Text("This question is part of your open diagnostic round. Its practice task returns after you submit that round."))
        } else if let id = task.questionID, let item = TMUAContentStore.context()?.bank.latestItems.first(where: { $0.stableId == id }) {
            // Practice state belongs to one task; never carry it to another.
            TMUAPracticeView(settings: settings, item: item, task: task)
                .id(task.stableID)
        } else {
            ContentUnavailableView("Question unavailable", systemImage: "exclamationmark.triangle",
                description: Text("This question is not available in this build. Refresh your plan to replace it; completed work is unchanged."))
        }
    }

    private func isReserved(_ id: String) -> Bool {
        guard task.completedAt == nil,
              let snapshot = try? TMUADiagnosticService.load(settings: settings, in: modelContext) else { return false }
        return TMUAProgrammeService.reservedStableIDs(snapshot: snapshot).contains(id)
    }
}

struct TMUAPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
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

    /// Every identity of the question: its item ID and, in the catalogue, its question ID and reprints.
    private var identities: [String] {
        let entry = TMUACatalogueStore.catalogue(TMUAContentStore.context()).entry(item.stableId)
        return [item.stableId] + ([entry?.id].compactMap { $0 } + (entry?.aliases ?? [])).filter { $0 != item.stableId }
    }

    private var flagged: Bool {
        let ids = Set(identities)
        return flags.contains { $0.profileSettingsID == settings.id && ids.contains($0.itemStableID) && $0.isFlagged }
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
                Text("Paper \(item.paper) · \(TMUAContentStore.context()?.syllabus.strandTitle(item.taxonomy.strand) ?? "")")
                    .font(.footnote.weight(.semibold)).foregroundStyle(RevisrColors.secondaryLabel)
                TMUAQuestionStem(content: item)
                    .padding(.horizontal, item.presentation == nil ? 0 : -(RevisrSpacing.large - 6))
                TMUAAnswerOptions(content: item, selectedID: shownSelection, marking: markingState) { option in
                    guard !showsAnswer else { return }
                    selection = option.id
                }
                TMUASourceCredit(content: item)
                if showsAnswer {
                    // A finished task shows its own attempt, not a later one from elsewhere in the app.
                    let correct = result?.isCorrect ?? taskAttempt?.isCorrect ?? history.first?.isCorrect ?? false
                    RevisrStatusLabel(title: correct ? "Correct" : "Not this time — review the solution",
                                      systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill",
                                      color: correct ? RevisrColors.success : RevisrColors.critical)
                        .accessibilityIdentifier("practice.result")
                    TMUAWorkedSolution(item: item)
                    if task != nil {
                        Button {
                            dismiss()
                        } label: {
                            Label("Done · back to your plan", systemImage: "chevron.backward")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("practice.done")
                    }
                } else {
                    Button {
                        check()
                    } label: {
                        Text("Check answer").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                    .disabled(selection == nil)
                    .accessibilityIdentifier("practice.check")
                }
                Toggle("Flag for later review", isOn: Binding(get: { flagged }, set: { setFlag($0) }))
                    .accessibilityIdentifier("practice.flag")
                // Earlier answers name the option chosen, so they stay hidden until this attempt is
                // checked: a review question is answered afresh, not from memory of the last result.
                if showsAnswer, !history.isEmpty {
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
        // A title can name the method or the trap, so it appears only once the question is answered.
        .navigationTitle(showsAnswer ? item.title : "Practice question")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resumedAt = .now } else { accumulate() }
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var taskAttempt: TMUAPracticeAttempt? {
        guard taskDone, let id = task?.completionAttemptID else { return nil }
        return attempts.first { $0.id == id }
    }

    private var shownSelection: String? {
        if let result { return result.selectedOptionID }
        if let taskAttempt { return taskAttempt.selectedOptionID }
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
            // Unflagging clears every identity, so a flag saved under another one cannot keep it in Saved.
            let ids = value ? [item.stableId] : identities.filter { id in
                id == item.stableId || flags.contains { $0.profileSettingsID == settings.id && $0.itemStableID == id && $0.isFlagged }
            }
            for id in ids {
                try TMUAProgrammeService.setReviewFlag(value, itemStableID: id, settings: settings, in: modelContext)
            }
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
    @Query private var allLogs: [TMUAResourceLog]

    var body: some View {
        let tasks = allTasks.filter { $0.programmeID == programme.stableID }
        let selfMarked = allLogs.filter { $0.profileSettingsID == settings.id && $0.questionID != nil }
        // One question, however many identities its results were saved under.
        let catalogue = TMUACatalogueStore.catalogue(TMUAContentStore.context())
        let selfMarkedLatest = Dictionary(grouping: selfMarked, by: { log in
            log.questionID.map { catalogue.entry($0)?.id ?? $0 } ?? ""
        }).compactMapValues { $0.max(by: TMUAResourceLog.isEarlier)?.outcome }
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
                            .accessibilityIdentifier("progress.completedTasks")
                        ProgressView(value: Double(progress.completedTaskCount), total: Double(progress.plannedTaskCount))
                            .tint(RevisrColors.accentTeal)
                            .accessibilityHidden(true)
                        LabeledContent("Mistake reviews completed", value: "\(reviews)")
                    }
                }
                Section {
                    LabeledContent("Question attempts", value: "\(attempts.count)")
                        .accessibilityIdentifier("progress.attempts")
                    if !attempts.isEmpty {
                        LabeledContent("Correct", value: "\(correct) of \(attempts.count)")
                    }
                    LabeledContent("Recorded practice time", value: "\(practiceSeconds / 60) min")
                    if let report = state.report {
                        LabeledContent("Diagnostic time", value: "\(report.activeSeconds / 60) min")
                    }
                } header: {
                    Text("Marked by Revisr")
                } footer: {
                    Text("Attempts count every answer you check, including repeats; tasks count planned work. Neither on its own shows mastery.")
                }
                Section {
                    LabeledContent("Questions you recorded", value: "\(selfMarkedLatest.count)")
                        .accessibilityIdentifier("progress.selfMarked")
                    if !selfMarkedLatest.isEmpty {
                        let count = { (outcome: TMUAResourceOutcome) in selfMarkedLatest.values.filter { $0 == outcome }.count }
                        LabeledContent("Correct by your marking", value: "\(count(.correct)) of \(selfMarkedLatest.count)")
                        LabeledContent("Incorrect or partly right", value: "\(count(.incorrect) + count(.partial))")
                        LabeledContent("Not yet checked · skipped", value: "\(count(.attempted)) · \(count(.skipped))")
                    }
                    LabeledContent("Worksheets finished", value: "\(tasks.filter { $0.activity == .topicWorksheet && $0.completedAt != nil }.count)")
                } header: {
                    Text("Self-marked practice")
                } footer: {
                    Text("Questions from papers in your library that you marked against their solutions, counted by your latest result. Revisr cannot check these, so they never count as evidence of topic mastery; a question you marked incorrect may come back in a later worksheet.")
                }
                if let report = state.report {
                    Section("Diagnostic history") {
                        LabeledContent("\(report.length.title) diagnostic", value: report.combinedScore)
                            .accessibilityIdentifier("progress.diagnostic")
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
        let catalogue = TMUACatalogueStore.catalogue(state.content).practicable

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
                        let selfMarked = catalogue.filter { $0.topicKey == topic.key && $0.answerMode != .automatic }.count
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
                                Text("Plan: \(completed) done, \(scheduled) scheduled · \(available) question\(available == 1 ? "" : "s") marked by Revisr")
                                    .font(.footnote.monospacedDigit()).foregroundStyle(RevisrColors.secondaryLabel)
                                if selfMarked > 0 {
                                    Text("\(selfMarked) more to self-mark in papers from your library")
                                        .font(.footnote.monospacedDigit()).foregroundStyle(RevisrColors.secondaryLabel)
                                }
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
    let settings: AppSettings
    @Query private var attempts: [TMUAPracticeAttempt]
    @Query private var logs: [TMUAResourceLog]
    @Query private var flags: [TMUAReviewFlag]
    @Query private var sections: [TMUADiagnosticSection]
    @Query private var diagnosticItems: [TMUADiagnosticItem]
    @State private var library = Self.initialLibrary
    /// Kept here, not in each view, so the filters survive switching between Practice and the others.
    @State private var practiceFilters = TMUAPracticeFilters()
    @State private var paperFilters = TMUAPaperFilters()
    @State private var debugPractice: TMUAContentItem?

    /// The unified library's four views (R4).
    enum Library: String, CaseIterable {
        case practice, papers, sources, saved

        var title: String {
            switch self {
            case .practice: "Practice"
            case .papers: "Papers"
            case .sources: "Sources"
            case .saved: "Saved"
            }
        }
    }

    private static var initialLibrary: Library {
#if DEBUG
        // "questions" and "sources" are the pre-R4 names of Practice and Papers.
        switch DebugTMUAScenarioService.value("--tmua-library") {
        case "sources": .papers
        case let value?: Library(rawValue: value) ?? .practice
        case nil: .practice
        }
#else
        .practice
#endif
    }

    var body: some View {
        let content = TMUAContentStore.context()
        let catalogue = TMUACatalogueStore.catalogue(content)
        let diagnosticID = TMUADiagnosticService.diagnosticID(profileID: settings.id)
        let openSectionIDs = Set(sections.filter { $0.diagnosticID == diagnosticID && $0.status != .submitted }.map(\.stableID))
        // Questions waiting in an unsubmitted diagnostic section stay hidden so
        // practice cannot reveal their solutions early.
        let reserved = Set(diagnosticItems.filter { openSectionIDs.contains($0.sectionID) }.map(\.itemStableID))
        let progress = TMUACatalogueProgress(settings: settings, attempts: attempts, logs: logs, flags: flags,
            diagnostic: TMUACatalogueProgress.diagnosticResults(settings: settings, sections: sections, items: diagnosticItems))
        NavigationStack {
            List {
                Section {
                    Picker("Library", selection: $library) {
                        ForEach(Library.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("questions.library")
                }
                switch library {
                case .practice:
                    TMUACataloguePracticeList(settings: settings, content: content, catalogue: catalogue,
                                              progress: progress, reserved: reserved, filters: $practiceFilters)
                case .papers:
                    TMUAResourceLibraryView(settings: settings, content: content, showsSites: false,
                                            filters: $paperFilters, reserved: reserved)
                case .sources:
                    TMUASourcesListView(settings: settings, content: content, catalogue: catalogue)
                case .saved:
                    TMUASavedListView(settings: settings, content: content, catalogue: catalogue,
                                      progress: progress, reserved: reserved)
                }
            }
            .navigationTitle("Questions")
            .tmuaSettingsButton()
            .navigationDestination(for: TMUACatalogueRoute.self) { route in
                if let entry = catalogue.entry(route.id) {
                    TMUACatalogueDestination(settings: settings, entry: entry, catalogue: catalogue, content: content)
                }
            }
            .navigationDestination(for: TMUATaskRoute.self) { route in
                TMUATaskRouteDestination(settings: settings, id: route.id)
            }
            .navigationDestination(item: $debugPractice) { TMUAPracticeView(settings: settings, item: $0) }
#if DEBUG
            .onAppear {
                if DebugTMUAScenarioService.value("--tmua-open") == "practice", debugPractice == nil {
                    let wanted = DebugTMUAScenarioService.value("--tmua-item")
                    debugPractice = content?.eligibleItems.first { wanted == nil ? $0.paper == 2 : $0.stableId == wanted }
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
                    .accessibilityIdentifier("settings.diagnostic")
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
                        LabeledContent("Official past-paper study copies", value: "\(content.studyCopyItemCount)")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).accessibilityIdentifier("settings.done")
                }
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
                                                                         resourceSessions: true, in: modelContext)
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
                    .accessibilityIdentifier("settings.open")
            }
        }
    }
}

extension View {
    func tmuaSettingsButton() -> some View { modifier(TMUASettingsButton()) }
}
