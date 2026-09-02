import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var presentation: AppPresentationState

    @Query(sort: \PlannedStudyBlock.createdAt) private var allBlocks: [PlannedStudyBlock]
    @Query(sort: \StudySession.date) private var allSessions: [StudySession]
    @Query(sort: \WeeklyFocus.displayOrder) private var allFocusItems: [WeeklyFocus]
    @Query private var allSettings: [AppSettings]
    @Query private var timerStates: [StudyTimerState]

    @State private var actionBlock: PlannedStudyBlock?
    @State private var completionBlock: PlannedStudyBlock?
    @State private var moveBlock: PlannedStudyBlock?
    @State private var deleteBlock: PlannedStudyBlock?
    @State private var errorMessage: TodayErrorMessage?
    @State private var feedbackTrigger = 0

    private let calendar = DateUtilities.appCalendar()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            todayList(now: timeline.date)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentation.presentQuickStudyEntry()
                } label: {
                    Label("Log Study", systemImage: "plus")
                }
                .accessibilityHint("Opens the quick study entry form")
            }
        }
        .tint(RevisrColors.accentTeal)
        .sheet(item: $completionBlock) { block in
            CompleteBlockSheet(block: block)
                .presentationDetents([.medium])
        }
        .sheet(item: $moveBlock) { block in
            MoveBlockSheet(
                block: block,
                availability: settings.availability
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Study Block",
            isPresented: actionDialogBinding,
            presenting: actionBlock,
            actions: blockActions
        )
        .alert(
            "Delete Study Block?",
            isPresented: deleteConfirmationBinding,
            presenting: deleteBlock
        ) { block in
            Button("Delete", role: .destructive) { delete(block) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The planned block will be removed. Any completed study history will be kept.")
        }
        .alert(item: $errorMessage) { error in
            Alert(
                title: Text("Couldn’t Update Study"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
    }

    private func todayList(now: Date) -> some View {
        let blocks = StudyAnalytics.blocks(on: now, from: allBlocks, calendar: calendar)
        let scheduled = StudyAnalytics.scheduledBlocks(from: blocks)
        let unscheduled = StudyAnalytics.unscheduledBlocks(from: blocks)
        let sessions = StudyAnalytics.sessions(on: now, from: allSessions, calendar: calendar)
        let manualSessions = StudyAnalytics.manualSessions(on: now, sessions: allSessions, calendar: calendar)
        let plannedDuration = StudyAnalytics.plannedDuration(on: now, blocks: allBlocks, calendar: calendar)
        let completedDuration = StudyAnalytics.actualDuration(on: now, sessions: allSessions, calendar: calendar)
        let nextBlock = StudyAnalytics.nextBlock(from: blocks, now: now, calendar: calendar)
        let focusItems = allFocusItems.filter {
            DateUtilities.isSameWeek($0.weekStart, now, calendar: calendar)
        }
        let isComplete = !blocks.isEmpty && blocks.allSatisfy { $0.status == .completed }

        return List {
            Section {
                TodaySummaryView(
                    date: now,
                    completedDuration: completedDuration,
                    plannedDuration: plannedDuration,
                    isPlanComplete: isComplete
                )
                .listRowInsets(
                    EdgeInsets(
                        top: RevisrSpacing.small,
                        leading: RevisrMetrics.contentMargin,
                        bottom: RevisrSpacing.standard,
                        trailing: RevisrMetrics.contentMargin
                    )
                )
                .listRowSeparator(.hidden)
            }

            if let activeTimer {
                Section {
                    ActiveStudyView(
                        state: activeTimer,
                        onPause: { pause(activeTimer) },
                        onResume: { resume(activeTimer) },
                        onFinish: { finish(activeTimer) }
                    )
                    .listRowSeparator(.hidden)
                }
            }

            TodayScheduleSection(
                scheduledBlocks: scheduled,
                unscheduledBlocks: unscheduled,
                nextBlockID: nextBlock?.id,
                isDayAvailable: isAvailable(on: now),
                calendar: calendar,
                onOpenActions: { actionBlock = $0 },
                onStart: start,
                onComplete: presentCompletion,
                onSkip: skip,
                onMove: presentMove,
                onDuplicate: duplicate,
                onDelete: presentDelete
            )

            if !manualSessions.isEmpty {
                Section("Additional Study") {
                    AdditionalStudyView(sessions: manualSessions)
                }
            }

            if !focusItems.isEmpty {
                Section("This Week’s Focus") {
                    WeeklyFocusView(items: focusItems)
                }
            }

            Section {
                ExamCountdownView(
                    examDate: settings.tmuaExamDate,
                    today: now,
                    calendar: calendar
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(RevisrColors.background)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: sessions.count)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: blocks.map(\.statusRawValue))
    }

    private var settings: AppSettings {
        allSettings.first ?? AppSettings()
    }

    private var activeTimer: StudyTimerState? {
        timerStates.first(where: { $0.status != .idle })
    }

    private var timerState: StudyTimerState? {
        timerStates.first
    }

    private var actionDialogBinding: Binding<Bool> {
        Binding(
            get: { actionBlock != nil },
            set: { if !$0 { actionBlock = nil } }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteBlock != nil },
            set: { if !$0 { deleteBlock = nil } }
        )
    }

    @ViewBuilder
    private func blockActions(for block: PlannedStudyBlock) -> some View {
        if block.status == .planned {
            Button("Start", systemImage: "play.fill") { start(block) }
        }
        if block.status != .completed {
            Button("Complete", systemImage: "checkmark") { presentCompletion(block) }
            Button("Move", systemImage: "calendar") { presentMove(block) }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(block) }
        if block.status == .planned {
            Button("Skip", systemImage: "forward.end") { skip(block) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { presentDelete(block) }
        Button("Cancel", role: .cancel) {}
    }

    private func isAvailable(on date: Date) -> Bool {
        let weekdayValue = calendar.component(.weekday, from: date)
        guard let weekday = Weekday(rawValue: weekdayValue) else { return true }
        return settings.availability.first(where: { $0.weekday == weekday })?.isAvailable ?? true
    }

    private func start(_ block: PlannedStudyBlock) {
        guard let timerState, let subject = block.subject else {
            showError(StudyActionError.missingSubject)
            return
        }

        do {
            try StudyTimerService.start(
                state: timerState,
                subject: subject,
                module: block.module,
                topic: block.topic,
                plannedBlock: block,
                activity: block.activity,
                plannedDuration: block.duration
            )
            try modelContext.save()
            feedbackTrigger += 1
        } catch {
            showError(error)
        }
    }

    private func pause(_ state: StudyTimerState) {
        state.pause()
        saveChanges()
    }

    private func resume(_ state: StudyTimerState) {
        state.resume()
        saveChanges()
    }

    private func finish(_ state: StudyTimerState) {
        do {
            _ = try StudyTimerService.finish(state: state, in: modelContext)
            feedbackTrigger += 1
        } catch {
            showError(error)
        }
    }

    private func presentCompletion(_ block: PlannedStudyBlock) {
        guard activeTimer?.plannedBlock?.id != block.id else {
            showError(StudyActionError.activeTimerExists)
            return
        }
        completionBlock = block
    }

    private func skip(_ block: PlannedStudyBlock) {
        guard activeTimer?.plannedBlock?.id != block.id else {
            showError(StudyActionError.activeTimerExists)
            return
        }
        do {
            try StudySessionService.skip(block: block, in: modelContext)
            feedbackTrigger += 1
        } catch {
            showError(error)
        }
    }

    private func presentMove(_ block: PlannedStudyBlock) {
        guard activeTimer?.plannedBlock?.id != block.id else {
            showError(StudyActionError.activeTimerExists)
            return
        }
        moveBlock = block
    }

    private func duplicate(_ block: PlannedStudyBlock) {
        do {
            _ = try StudySessionService.duplicate(block: block, in: modelContext)
            feedbackTrigger += 1
        } catch {
            showError(error)
        }
    }

    private func presentDelete(_ block: PlannedStudyBlock) {
        guard activeTimer?.plannedBlock?.id != block.id else {
            showError(StudyActionError.activeTimerExists)
            return
        }
        deleteBlock = block
    }

    private func delete(_ block: PlannedStudyBlock) {
        do {
            try StudySessionService.delete(block: block, in: modelContext)
            feedbackTrigger += 1
        } catch {
            showError(error)
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
            feedbackTrigger += 1
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = TodayErrorMessage(message: error.localizedDescription)
    }
}

private struct TodayErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
