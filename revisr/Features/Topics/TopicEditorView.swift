import SwiftData
import SwiftUI

struct TopicEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.displayOrder) private var subjects: [Subject]
    @Query private var allTopics: [Topic]

    let topic: Topic?
    let preselectedModule: StudyModule?
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var selectedSubjectID: UUID?
    @State private var selectedModuleID: UUID?
    @State private var status: TopicStatus
    @State private var needsReview: Bool
    @State private var notes: String
    @State private var issue: TopicViewIssue?
    @State private var isDeleteConfirmationPresented = false

    init(
        topic: Topic? = nil,
        preselectedModule: StudyModule? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.topic = topic
        self.preselectedModule = preselectedModule
        self.onDelete = onDelete
        let module = topic?.module ?? preselectedModule
        _name = State(initialValue: topic?.name ?? "")
        _selectedSubjectID = State(initialValue: module?.subject?.id)
        _selectedModuleID = State(initialValue: module?.id)
        _status = State(initialValue: topic?.status ?? .good)
        _needsReview = State(initialValue: topic?.needsReview ?? false)
        _notes = State(initialValue: topic?.notes ?? "")
    }

    private var selectedSubject: Subject? {
        subjects.first(where: { $0.id == selectedSubjectID })
    }

    private var availableModules: [StudyModule] {
        selectedSubject?.modules.sorted { $0.displayOrder < $1.displayOrder } ?? []
    }

    private var selectedModule: StudyModule? {
        availableModules.first(where: { $0.id == selectedModuleID })
    }

    private var canChangeHierarchy: Bool {
        topic?.isCustom ?? true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Subject", selection: $selectedSubjectID) {
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(Optional(subject.id))
                        }
                    }
                    .disabled(!canChangeHierarchy)

                    Picker("Module", selection: $selectedModuleID) {
                        ForEach(availableModules) { module in
                            Text(module.name).tag(Optional(module.id))
                        }
                    }
                    .disabled(!canChangeHierarchy)
                }

                Section("Judgement") {
                    Picker("Status", selection: $status) {
                        ForEach(TopicStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(status)
                        }
                    }
                    Toggle("Needs Review", isOn: $needsReview)
                }

                Section("Notes") {
                    TextField("Optional reminders", text: $notes, axis: .vertical)
                        .lineLimit(3...7)
                }

                if topic?.isCustom == true {
                    Section {
                        Button("Delete Topic", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    } footer: {
                        Text("Historical study and plans keep their original topic labels.")
                    }
                }
            }
            .navigationTitle(topic == nil ? "Add Topic" : "Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(selectedModule == nil)
                }
            }
            .onAppear(perform: initialiseSelection)
            .onChange(of: selectedSubjectID) {
                guard canChangeHierarchy else { return }
                if !availableModules.contains(where: { $0.id == selectedModuleID }) {
                    selectedModuleID = availableModules.first?.id
                }
            }
            .alert(item: $issue) { issue in
                Alert(
                    title: Text(issue.title),
                    message: Text(issue.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog(
                "Delete this topic?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Topic", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The topic will no longer be available for new study or planning. Historical labels remain intact.")
            }
            .tint(RevisrColors.accentTeal)
        }
    }

    private func initialiseSelection() {
        if selectedSubjectID == nil {
            selectedSubjectID = subjects.first?.id
        }
        if selectedModuleID == nil {
            selectedModuleID = availableModules.first?.id
        }
    }

    private func save() {
        guard let module = selectedModule else { return }
        let draft = TopicDraft(
            name: name,
            status: status,
            needsReview: needsReview,
            notes: notes,
            module: module
        )

        do {
            if let topic {
                try TopicService.update(topic, from: draft, existingTopics: allTopics, in: modelContext)
            } else {
                try TopicService.create(from: draft, existingTopics: allTopics, in: modelContext)
            }
            dismiss()
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Save Topic", message: error.localizedDescription)
        }
    }

    private func delete() {
        guard let topic else { return }
        do {
            try TopicService.delete(topic, in: modelContext)
            onDelete?()
            dismiss()
        } catch {
            issue = TopicViewIssue(title: "Couldn’t Delete Topic", message: error.localizedDescription)
        }
    }
}
