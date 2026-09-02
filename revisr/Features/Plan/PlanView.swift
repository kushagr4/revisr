import SwiftData
import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var presentation: AppPresentationState

    @State private var displayedWeek: Date
    @State private var selectedDay: Date
    @State private var isAddingBlock = false

    private let calendar = DateUtilities.appCalendar()

    init(initialDate: Date = .now) {
        let calendar = DateUtilities.appCalendar()
        var resolvedDate = initialDate
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--plan-unavailable") {
            let monday = DateUtilities.startOfWeek(for: initialDate, calendar: calendar)
            resolvedDate = calendar.date(byAdding: .day, value: 3, to: monday) ?? initialDate
        } else if ProcessInfo.processInfo.arguments.contains("--plan-tuesday") {
            let monday = DateUtilities.startOfWeek(for: initialDate, calendar: calendar)
            resolvedDate = calendar.date(byAdding: .day, value: 1, to: monday) ?? initialDate
        }
#endif
        _displayedWeek = State(initialValue: DateUtilities.startOfWeek(for: resolvedDate, calendar: calendar))
        _selectedDay = State(initialValue: calendar.startOfDay(for: resolvedDate))
#if DEBUG
        _isAddingBlock = State(initialValue: ProcessInfo.processInfo.arguments.contains("--plan-add"))
#endif
    }

    var body: some View {
        PlanWeekView(
            weekStart: displayedWeek,
            selectedDay: $selectedDay,
            onPreviousWeek: { changeWeek(by: -1) },
            onNextWeek: { changeWeek(by: 1) },
            onCurrentWeek: showCurrentWeek,
            onAddBlock: {
                selectedDay = calendar.startOfDay(for: $0)
                isAddingBlock = true
            }
        )
        .id(displayedWeek)
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    presentation.presentQuickStudyEntry()
                } label: {
                    Label("Log Study", systemImage: "stopwatch")
                }
                .accessibilityHint("Logs study you have already completed")

                Button {
                    isAddingBlock = true
                } label: {
                    Label("Add Block", systemImage: "calendar.badge.plus")
                }
                .accessibilityHint("Adds planned study for the selected day")
            }
        }
        .sheet(isPresented: $isAddingBlock) {
            PlannedBlockEditorView(date: selectedDay)
        }
        .tint(RevisrColors.accentTeal)
    }

    private func changeWeek(by offset: Int) {
        guard let week = calendar.date(byAdding: .weekOfYear, value: offset, to: displayedWeek) else { return }
        displayedWeek = DateUtilities.startOfWeek(for: week, calendar: calendar)
        selectedDay = displayedWeek
    }

    private func showCurrentWeek() {
        let today = calendar.startOfDay(for: .now)
        displayedWeek = DateUtilities.startOfWeek(for: today, calendar: calendar)
        selectedDay = today
    }
}

private struct PlanWeekView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var presentation: AppPresentationState

    @Query private var weekBlocks: [PlannedStudyBlock]
    @Query private var settingsRecords: [AppSettings]
    @Query private var timerStates: [StudyTimerState]

    let weekStart: Date
    @Binding var selectedDay: Date
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onCurrentWeek: () -> Void
    let onAddBlock: (Date) -> Void

    @State private var editBlock: PlannedStudyBlock?
    @State private var completionBlock: PlannedStudyBlock?
    @State private var moveBlock: PlannedStudyBlock?
    @State private var deleteBlock: PlannedStudyBlock?
    @State private var errorMessage: PlanErrorMessage?
    @State private var feedbackTrigger = 0

    private let calendar = DateUtilities.appCalendar()

    init(
        weekStart: Date,
        selectedDay: Binding<Date>,
        onPreviousWeek: @escaping () -> Void,
        onNextWeek: @escaping () -> Void,
        onCurrentWeek: @escaping () -> Void,
        onAddBlock: @escaping (Date) -> Void
    ) {
        self.weekStart = weekStart
        _selectedDay = selectedDay
        self.onPreviousWeek = onPreviousWeek
        self.onNextWeek = onNextWeek
        self.onCurrentWeek = onCurrentWeek
        self.onAddBlock = onAddBlock
        let end = DateUtilities.appCalendar().date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        _weekBlocks = Query(
            filter: #Predicate<PlannedStudyBlock> { block in
                block.day >= weekStart && block.day < end
            },
            sort: [SortDescriptor(\PlannedStudyBlock.createdAt)]
        )
    }

    private var selectedBlocks: [PlannedStudyBlock] {
        StudyAnalytics.blocks(on: selectedDay, from: weekBlocks, calendar: calendar)
    }

    private var scheduledBlocks: [PlannedStudyBlock] {
        StudyAnalytics.scheduledBlocks(from: selectedBlocks)
    }

    private var unscheduledBlocks: [PlannedStudyBlock] {
        StudyAnalytics.unscheduledBlocks(from: selectedBlocks)
    }

    private var settings: AppSettings {
        settingsRecords.first ?? AppSettings()
    }

    private var activeTimer: StudyTimerState? {
        timerStates.first(where: { $0.status != .idle })
    }

    private var weeklyTotal: TimeInterval {
        StudyAnalytics.weeklyPlannedDuration(containing: weekStart, blocks: weekBlocks, calendar: calendar)
    }

    private var isCurrentWeek: Bool {
        DateUtilities.isSameWeek(weekStart, .now, calendar: calendar)
    }

    private var allWeekComplete: Bool {
        !weekBlocks.isEmpty && weekBlocks.allSatisfy { $0.status == .completed }
    }

    var body: some View {
        List {
            Section {
                WeekHeaderView(
                    weekStart: weekStart,
                    plannedDuration: weeklyTotal,
                    isCurrentWeek: isCurrentWeek,
                    isComplete: allWeekComplete,
                    onPrevious: onPreviousWeek,
                    onNext: onNextWeek,
                    onCurrentWeek: onCurrentWeek
                )

                WeekDaySelector(
                    weekStart: weekStart,
                    selectedDay: selectedDay,
                    blocks: weekBlocks,
                    availability: settings.availability,
                    onSelect: selectDay
                )
            }
            .listRowSeparator(.hidden)

            Section {
                PlanDayHeader(
                    day: selectedDay,
                    plannedDuration: StudyAnalytics.plannedDuration(
                        on: selectedDay,
                        blocks: weekBlocks,
                        calendar: calendar
                    ),
                    availability: availability(for: selectedDay)
                )
                .listRowSeparator(.hidden)
            }

            if activeTimer != nil {
                Section {
                    Button {
                        presentation.showToday()
                    } label: {
                        HStack {
                            Label("Study timer running", systemImage: "timer")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("View")
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(RevisrColors.accentTeal)
                }
            }

            PlanDaySchedule(
                day: selectedDay,
                scheduledBlocks: scheduledBlocks,
                unscheduledBlocks: unscheduledBlocks,
                allDayBlocks: selectedBlocks,
                availability: settings.availability,
                onEdit: { editBlock = $0 },
                onStart: start,
                onComplete: presentCompletion,
                onSkip: skip,
                onMove: presentMove,
                onDuplicate: duplicate,
                onDelete: presentDelete,
                onAdd: { onAddBlock(selectedDay) }
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(RevisrColors.background)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedDay)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: weekBlocks.map(\.id))
        .sheet(item: $editBlock) { block in
            PlannedBlockEditorView(block: block)
        }
        .sheet(item: $completionBlock) { block in
            CompleteBlockSheet(block: block)
                .presentationDetents([.medium])
        }
        .sheet(item: $moveBlock) { block in
            MoveBlockSheet(block: block, availability: settings.availability)
                .presentationDetents([.medium])
        }
        .alert("Delete Study Block?", isPresented: deleteBinding, presenting: deleteBlock) { block in
            Button("Delete", role: .destructive) { delete(block) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The planned block will be removed. Any completed study history will be kept.")
        }
        .alert(item: $errorMessage) { error in
            Alert(
                title: Text("Couldn’t Update Plan"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteBlock != nil },
            set: { if !$0 { deleteBlock = nil } }
        )
    }

    private func availability(for day: Date) -> DayAvailability? {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return nil }
        return settings.availability.first(where: { $0.weekday == weekday })
    }

    private func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        feedbackTrigger += 1
    }

    private func start(_ block: PlannedStudyBlock) {
        guard let timerState = timerStates.first, let subject = block.subject else {
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
            presentation.showToday()
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

    private func showError(_ error: Error) {
        errorMessage = PlanErrorMessage(message: error.localizedDescription)
    }
}

private struct PlanErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
