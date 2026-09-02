import SwiftData
import SwiftUI

struct QuickStudyEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.displayOrder) private var subjects: [Subject]

    @State private var selectedSubjectID: UUID?
    @State private var selectedModuleID: UUID?
    @State private var selectedTopicID: UUID?
    @State private var durationPreset: StudyDurationPreset = .sixty
    @State private var customDurationMinutes = 60
    @State private var activity: StudyActivity = .revision
    @State private var notes = ""
    @State private var showsOptionalFields = false
    @State private var saveError: SaveError?

    private var selectedSubject: Subject? {
        subjects.first(where: { $0.id == selectedSubjectID })
    }

    private var availableModules: [StudyModule] {
        selectedSubject?.modules.sorted(by: { $0.displayOrder < $1.displayOrder }) ?? []
    }

    private var selectedModule: StudyModule? {
        availableModules.first(where: { $0.id == selectedModuleID })
    }

    private var availableTopics: [Topic] {
        selectedModule?.topics.sorted(by: { $0.displayOrder < $1.displayOrder }) ?? []
    }

    private var selectedTopic: Topic? {
        availableTopics.first(where: { $0.id == selectedTopicID })
    }

    private var durationMinutes: Int {
        durationPreset.minutes ?? customDurationMinutes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Study") {
                    Picker("Subject", selection: $selectedSubjectID) {
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

                    if durationPreset == .custom {
                        Stepper(
                            "\(customDurationMinutes) minutes",
                            value: $customDurationMinutes,
                            in: 15...720,
                            step: 15
                        )
                    }
                }

                Section {
                    DisclosureGroup("More Details", isExpanded: $showsOptionalFields) {
                        Picker("Module", selection: $selectedModuleID) {
                            Text("None").tag(UUID?.none)
                            ForEach(availableModules) { module in
                                Text(module.name).tag(Optional(module.id))
                            }
                        }

                        Picker("Topic", selection: $selectedTopicID) {
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

                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
            }
            .navigationTitle("Log Study")
            .navigationBarTitleDisplayMode(.inline)
            .tint(RevisrColors.accentTeal)
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
            .onAppear {
                if selectedSubjectID == nil {
                    selectedSubjectID = subjects.first?.id
                }
            }
            .onChange(of: selectedSubjectID) {
                selectedModuleID = nil
                selectedTopicID = nil
            }
            .onChange(of: selectedModuleID) {
                selectedTopicID = nil
            }
            .alert(item: $saveError) { error in
                Alert(
                    title: Text("Couldn’t Save Study"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func save() {
        guard let subject = selectedSubject else { return }
        let duration = TimeInterval(durationMinutes * 60)

        guard DomainValidation.isValidDuration(duration) else {
            saveError = SaveError(message: "Choose a duration greater than zero.")
            return
        }

        let session = StudySession(
            date: .now,
            duration: duration,
            activity: activity,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject,
            module: selectedModule,
            topic: selectedTopic,
            subjectNameSnapshot: subject.name,
            moduleNameSnapshot: selectedModule?.name,
            topicNameSnapshot: selectedTopic?.name
        )

        modelContext.insert(session)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.delete(session)
            saveError = SaveError(message: error.localizedDescription)
        }
    }
}

private struct SaveError: Identifiable {
    let id = UUID()
    let message: String
}
