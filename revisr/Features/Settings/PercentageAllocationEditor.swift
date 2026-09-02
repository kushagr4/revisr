import SwiftUI

struct PercentageTargetItem: Identifiable {
    let id: String
    let title: String
    let accessibilityLabel: String
}

struct PercentageAllocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedIndex: Int?

    let title: String
    let explanation: String
    let items: [PercentageTargetItem]
    let onSave: ([Int]) throws -> Void

    @State private var values: [String]
    @State private var issue: SettingsViewIssue?

    init(
        title: String,
        explanation: String,
        items: [PercentageTargetItem],
        initialValues: [Int],
        onSave: @escaping ([Int]) throws -> Void
    ) {
        self.title = title
        self.explanation = explanation
        self.items = items
        self.onSave = onSave
        _values = State(initialValue: initialValues.map(String.init))
    }

    private var parsedValues: [Int?] {
        values.map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private var total: Int {
        SettingsValidation.wholePercentageTotal(parsedValues)
    }

    private var isValid: Bool {
        SettingsValidation.isValidWholePercentageGroup(parsedValues)
    }

    private var hasOutOfRangeValue: Bool {
        parsedValues.contains { value in
            guard let value else { return true }
            return !(0...100).contains(value)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    percentageRow(item: item, index: index)
                }
            } header: {
                Text("Allocation")
            } footer: {
                Text(explanation)
            }

            if !isValid {
                Section {
                    Label(validationMessage, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(validationMessage)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!isValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedIndex = nil }
            }
        }
        .alert(item: $issue) { issue in
            Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
        }
        .tint(RevisrColors.accentTeal)
    }

    @ViewBuilder
    private func percentageRow(item: PercentageTargetItem, index: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                Text(item.title)
                percentageField(item: item, index: index)
            }
            .padding(.vertical, RevisrSpacing.xSmall)
        } else {
            HStack {
                Text(item.title)
                Spacer()
                percentageField(item: item, index: index)
            }
        }
    }

    private func percentageField(item: PercentageTargetItem, index: Int) -> some View {
        HStack(spacing: RevisrSpacing.xSmall) {
            TextField("0", text: $values[index])
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focusedIndex, equals: index)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityValue("\(values[index]) percent")
            Text("%")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 92, alignment: .trailing)
    }

    private var validationMessage: String {
        if hasOutOfRangeValue {
            return "Each target must be between 0% and 100%."
        }
        return "Targets must total 100%. Current total: \(total)%."
    }

    private func save() {
        guard isValid else { return }
        do {
            try onSave(parsedValues.compactMap { $0 })
            dismiss()
        } catch {
            issue = SettingsViewIssue(title: "Couldn’t Save Targets", message: error.localizedDescription)
        }
    }
}
