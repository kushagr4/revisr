import SwiftData
import SwiftUI

struct CompleteBlockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let block: PlannedStudyBlock

    @State private var durationMinutes: Int
    @State private var saveError: SheetError?

    init(block: PlannedStudyBlock) {
        self.block = block
        _durationMinutes = State(initialValue: max(5, Int(block.duration / 60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                        Text([block.subject?.name, block.module?.name]
                            .compactMap { $0 }
                            .joined(separator: " · "))
                            .font(.headline)
                        Text(block.activity.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, RevisrSpacing.xSmall)
                }

                Section {
                    Stepper(
                        "\(durationMinutes) minutes",
                        value: $durationMinutes,
                        in: 5...720,
                        step: 5
                    )
                    .monospacedDigit()
                } header: {
                    Text("Actual Study Time")
                } footer: {
                    Text("The planned duration was \(DateUtilities.durationText(block.duration)).")
                }
            }
            .navigationTitle("Complete Study")
            .navigationBarTitleDisplayMode(.inline)
            .tint(RevisrColors.accentTeal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert(item: $saveError) { error in
                Alert(
                    title: Text("Couldn’t Complete Study"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func save() {
        do {
            try StudySessionService.complete(
                block: block,
                actualDuration: TimeInterval(durationMinutes * 60),
                in: modelContext
            )
            dismiss()
        } catch {
            saveError = SheetError(message: error.localizedDescription)
        }
    }
}

private struct SheetError: Identifiable {
    let id = UUID()
    let message: String
}
