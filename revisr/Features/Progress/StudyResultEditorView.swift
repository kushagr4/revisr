import SwiftData
import SwiftUI

struct StudyResultEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.displayOrder) private var subjects: [Subject]

    let kind: StudyResultKind
    let result: StudyResult?

    @State private var date: Date
    @State private var selectedSubjectID: UUID?
    @State private var selectedModuleID: UUID?
    @State private var label: String
    @State private var rawScoreText: String
    @State private var maximumScoreText: String
    @State private var scaledScoreText: String
    @State private var notes: String
    @State private var issue: EditorIssue?
    @State private var isDeleteConfirmationPresented = false

    init(kind: StudyResultKind, result: StudyResult? = nil) {
        self.kind = kind
        self.result = result
        _date = State(initialValue: result?.date ?? .now)
        _selectedSubjectID = State(initialValue: result?.subject?.id)
        _selectedModuleID = State(initialValue: result?.module?.id)
        _label = State(initialValue: result?.paperOrModuleLabel ?? (kind == .tmua ? "Paper 1" : ""))
        _rawScoreText = State(initialValue: Self.text(for: result?.rawScore))
        _maximumScoreText = State(initialValue: Self.text(for: result?.maximumScore))
        _scaledScoreText = State(initialValue: Self.text(for: result?.scaledScore))
        _notes = State(initialValue: result?.notes ?? "")
    }

    private var eligibleSubjects: [Subject] {
        subjects.filter { subject in
            guard let category = StudySubjectCategory.classify(subject: subject, snapshot: subject.name) else {
                return false
            }
            return kind == .tmua ? category == .tmua : category != .tmua
        }
    }

    private var selectedSubject: Subject? {
        eligibleSubjects.first(where: { $0.id == selectedSubjectID })
    }

    private var availableModules: [StudyModule] {
        selectedSubject?.modules.sorted { $0.displayOrder < $1.displayOrder } ?? []
    }

    private var selectedModule: StudyModule? {
        availableModules.first(where: { $0.id == selectedModuleID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Result") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    if kind == .tmua {
                        Picker("Paper", selection: $label) {
                            Text("Paper 1").tag("Paper 1")
                            Text("Paper 2").tag("Paper 2")
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker("Subject", selection: $selectedSubjectID) {
                            ForEach(eligibleSubjects) { subject in
                                Text(subject.name).tag(Optional(subject.id))
                            }
                        }

                        Picker("Module", selection: $selectedModuleID) {
                            Text("Custom label").tag(UUID?.none)
                            ForEach(availableModules) { module in
                                Text(module.name).tag(Optional(module.id))
                            }
                        }

                        TextField("Module or assessment label", text: $label)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section {
                    TextField("Raw score", text: $rawScoreText)
                        .keyboardType(.decimalPad)
                    TextField("Maximum score", text: $maximumScoreText)
                        .keyboardType(.decimalPad)

                    if kind == .tmua {
                        TextField("Scaled score (optional)", text: $scaledScoreText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Score")
                } footer: {
                    Text(kind == .tmua
                        ? "Enter raw marks, a scaled score, or both. Revisr records the scaled score you provide; it does not calculate an official conversion."
                        : "A-Level charts use the raw score as a percentage of the maximum.")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if result != nil {
                    Section {
                        Button("Delete Result", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    }
                }
            }
            .navigationTitle(result == nil ? "Add \(kind.title)" : "Edit \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: initialiseSelection)
            .onChange(of: selectedSubjectID) {
                guard result == nil || selectedSubjectID != result?.subject?.id else { return }
                selectedModuleID = nil
            }
            .onChange(of: selectedModuleID) {
                if let selectedModule {
                    label = selectedModule.name
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
                "Delete this result?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Result", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only this result will be removed. Study sessions and plans are unchanged.")
            }
            .tint(RevisrColors.accentTeal)
        }
    }

    private func initialiseSelection() {
        if selectedSubjectID == nil {
            if let matchingSnapshot = eligibleSubjects.first(where: { $0.name == result?.subjectNameSnapshot }) {
                selectedSubjectID = matchingSnapshot.id
            } else {
                selectedSubjectID = eligibleSubjects.first?.id
            }
        }

        if kind == .tmua, let subject = selectedSubject {
            selectedModuleID = subject.modules.first(where: { $0.name == label })?.id
        }
    }

    private func save() {
        guard let subject = selectedSubject else {
            issue = EditorIssue(title: "Subject Unavailable", message: "Revisr could not find a subject for this result.")
            return
        }

        do {
            let input = StudyResultInput(
                date: date,
                label: label,
                rawScore: try parsedNumber(rawScoreText, field: "raw score"),
                maximumScore: try parsedNumber(maximumScoreText, field: "maximum score"),
                scaledScore: try parsedNumber(scaledScoreText, field: "scaled score"),
                notes: notes,
                subject: subject,
                module: resolvedModule(for: subject)
            )

            if let result {
                try StudyResultService.update(result, input: input, kind: kind, in: modelContext)
            } else {
                try StudyResultService.create(input: input, kind: kind, in: modelContext)
            }
            dismiss()
        } catch {
            issue = EditorIssue(title: "Check This Result", message: error.localizedDescription)
        }
    }

    private func delete() {
        guard let result else { return }
        do {
            try StudyResultService.delete(result, in: modelContext)
            dismiss()
        } catch {
            issue = EditorIssue(title: "Couldn’t Delete Result", message: error.localizedDescription)
        }
    }

    private func resolvedModule(for subject: Subject) -> StudyModule? {
        if kind == .tmua {
            return subject.modules.first(where: { $0.name == label })
        }
        return selectedModule
    }

    private func parsedNumber(_ text: String, field: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            throw NumberEntryError.invalid(field)
        }
        return value
    }

    private static func text(for value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

private struct EditorIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum NumberEntryError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let field): "Enter a valid number for the \(field)."
        }
    }
}
