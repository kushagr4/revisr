import SwiftData
import SwiftUI

struct PlannedBlockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.displayOrder) private var subjects: [Subject]
    @Query private var settingsRecords: [AppSettings]

    private let block: PlannedStudyBlock?

    @State private var hierarchy: PlanningHierarchySelection
    @State private var selectedDay: Date
    @State private var schedulesTime: Bool
    @State private var selectedTime: Date
    @State private var durationPreset: StudyDurationPreset
    @State private var customDurationMinutes: Int
    @State private var activity: StudyActivity
    @State private var comparisonBlocks: [PlannedStudyBlock] = []
    @State private var saveError: PlannedBlockEditorError?
    @State private var feedbackTrigger = 0

    private let calendar = DateUtilities.appCalendar()

    init(date: Date) {
        block = nil
        let calendar = DateUtilities.appCalendar()
        let day = calendar.startOfDay(for: date)
        _hierarchy = State(initialValue: PlanningHierarchySelection())
        _selectedDay = State(initialValue: day)
        let startsScheduled: Bool
#if DEBUG
        startsScheduled = ProcessInfo.processInfo.arguments.contains("--plan-scheduled")
#else
        startsScheduled = false
#endif
        _schedulesTime = State(initialValue: startsScheduled)
        _selectedTime = State(
            initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        )
        _durationPreset = State(initialValue: .sixty)
        _customDurationMinutes = State(initialValue: 60)
        _activity = State(initialValue: .revision)
    }

    init(block: PlannedStudyBlock) {
        self.block = block
        let calendar = DateUtilities.appCalendar()
        let minutes = max(5, Int(block.duration / 60))
        _hierarchy = State(
            initialValue: PlanningHierarchySelection(
                subjectID: block.subject?.id,
                moduleID: block.module?.id,
                topicID: block.topic?.id
            )
        )
        _selectedDay = State(initialValue: block.day)
        _schedulesTime = State(initialValue: block.startMinute != nil)
        _selectedTime = State(
            initialValue: block.scheduledStart(using: calendar)
                ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: block.day)
                ?? block.day
        )
        _durationPreset = State(initialValue: StudyDurationPreset.matching(minutes: minutes))
        _customDurationMinutes = State(initialValue: minutes)
        _activity = State(initialValue: block.activity)
    }

    private var selectedSubject: Subject? {
        subjects.first(where: { $0.id == hierarchy.subjectID })
    }

    private var availableModules: [StudyModule] {
        selectedSubject?.modules.sorted(by: { $0.displayOrder < $1.displayOrder }) ?? []
    }

    private var selectedModule: StudyModule? {
        availableModules.first(where: { $0.id == hierarchy.moduleID })
    }

    private var availableTopics: [Topic] {
        selectedModule?.topics.sorted(by: { $0.displayOrder < $1.displayOrder }) ?? []
    }

    private var selectedTopic: Topic? {
        availableTopics.first(where: { $0.id == hierarchy.topicID })
    }

    private var durationMinutes: Int {
        durationPreset.minutes ?? customDurationMinutes
    }

    private var startMinute: Int? {
        guard schedulesTime else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var conflicts: [PlanningConflict] {
        PlanningService.conflicts(
            day: selectedDay,
            startMinute: startMinute,
            duration: TimeInterval(durationMinutes * 60),
            excluding: block?.id,
            among: comparisonBlocks,
            availability: settingsRecords.first?.availability ?? AppSettings.defaultAvailability,
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Study") {
                    Picker("Subject", selection: subjectBinding) {
                        Text("Choose Subject").tag(UUID?.none)
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(Optional(subject.id))
                        }
                    }

                    Picker("Duration", selection: $durationPreset) {
                        ForEach(StudyDurationPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    if durationPreset == .custom {
                        Stepper(
                            "\(customDurationMinutes) minutes",
                            value: $customDurationMinutes,
                            in: 5...720,
                            step: 5
                        )
                        .monospacedDigit()
                    }
                }

                Section("When") {
                    DatePicker("Date", selection: $selectedDay, displayedComponents: .date)
                    Toggle("Schedule a time", isOn: $schedulesTime)
                    if schedulesTime {
                        DatePicker("Start", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    } else {
                        Label("Any time", systemImage: "clock.badge.questionmark")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Module", selection: moduleBinding) {
                        Text("None").tag(UUID?.none)
                        ForEach(availableModules) { module in
                            Text(module.name).tag(Optional(module.id))
                        }
                    }

                    Picker("Topic", selection: topicBinding) {
                        Text("None").tag(UUID?.none)
                        ForEach(availableTopics) { topic in
                            Text(topic.name).tag(Optional(topic.id))
                        }
                    }
                    .disabled(selectedModule == nil)

                    Picker("Activity", selection: $activity) {
                        ForEach(StudyActivity.allCases) { activity in
                            Text(activity.title).tag(activity)
                        }
                    }
                } header: {
                    Text("Details")
                } footer: {
                    if block?.status == .completed {
                        Text("Completed study history keeps its original labels and duration when this plan is edited.")
                    }
                }

                if !conflicts.isEmpty {
                    Section("Planning Guidance") {
                        ForEach(conflicts, id: \.self) { conflict in
                            PlanningConflictView(conflict: conflict, day: selectedDay)
                        }
                    }
                }
            }
            .navigationTitle(block == nil ? "Add Block" : "Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(selectedSubject == nil)
                }
            }
            .tint(RevisrColors.accentTeal)
            .task {
                if hierarchy.subjectID == nil {
                    hierarchy.selectSubject(subjects.first?.id)
                }
                loadComparisonBlocks()
            }
            .onChange(of: selectedDay) {
                loadComparisonBlocks()
            }
            .alert(item: $saveError) { error in
                Alert(
                    title: Text("Couldn’t Save Block"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sensoryFeedback(.success, trigger: feedbackTrigger)
        }
    }

    private var subjectBinding: Binding<UUID?> {
        Binding(
            get: { hierarchy.subjectID },
            set: { hierarchy.selectSubject($0) }
        )
    }

    private var moduleBinding: Binding<UUID?> {
        Binding(
            get: { hierarchy.moduleID },
            set: { hierarchy.selectModule($0) }
        )
    }

    private var topicBinding: Binding<UUID?> {
        Binding(
            get: { hierarchy.topicID },
            set: { hierarchy.selectTopic($0) }
        )
    }

    private func loadComparisonBlocks() {
        let dayStart = calendar.startOfDay(for: selectedDay)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<PlannedStudyBlock>(
            predicate: #Predicate { block in
                block.day >= dayStart && block.day < nextDay
            }
        )
        comparisonBlocks = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func save() {
        guard let subject = selectedSubject else { return }
        let draft = PlannedBlockDraft(
            day: selectedDay,
            startMinute: startMinute,
            duration: TimeInterval(durationMinutes * 60),
            activity: activity,
            subject: subject,
            module: selectedModule,
            topic: selectedTopic
        )

        do {
            if let block {
                try PlanningService.update(block: block, from: draft, in: modelContext)
            } else {
                _ = try PlanningService.create(from: draft, in: modelContext)
            }
            feedbackTrigger += 1
            dismiss()
        } catch {
            saveError = PlannedBlockEditorError(message: error.localizedDescription)
        }
    }
}

private struct PlannedBlockEditorError: Identifiable {
    let id = UUID()
    let message: String
}
