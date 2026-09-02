import SwiftData
import SwiftUI

struct WeeklyTargetSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    let settings: AppSettings
    @State private var hours: String
    @State private var minutes: String
    @State private var issue: SettingsViewIssue?

    private enum Field { case hours, minutes }

    init(settings: AppSettings) {
        self.settings = settings
        _hours = State(initialValue: String(settings.weeklyTargetMinutes / 60))
        _minutes = State(initialValue: String(settings.weeklyTargetMinutes % 60))
    }

    private var parsedHours: Int? { Int(hours.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var parsedMinutes: Int? { Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var totalMinutes: Int? {
        guard let parsedHours, let parsedMinutes,
              parsedHours >= 0, (0...59).contains(parsedMinutes),
              parsedHours <= (Int.max - parsedMinutes) / 60
        else { return nil }
        return parsedHours * 60 + parsedMinutes
    }

    private var isValid: Bool {
        totalMinutes.map(SettingsValidation.isValidWeeklyTarget) == true
    }

    var body: some View {
        Form {
            Section {
                durationRow
            } footer: {
                Text("Use an exact weekly target greater than zero. This does not change or create planned study blocks.")
            }

            if !isValid {
                Section {
                    Label("Enter a target greater than zero with 0–59 minutes.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Weekly Study Target")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!isValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .alert(item: $issue) { issue in
            Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
        }
        .tint(RevisrColors.accentTeal)
    }

    @ViewBuilder
    private var durationRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                Text("Target")
                durationFields
            }
            .padding(.vertical, RevisrSpacing.xSmall)
        } else {
            HStack {
                Text("Target")
                Spacer()
                durationFields
            }
        }
    }

    private var durationFields: some View {
        HStack(spacing: RevisrSpacing.small) {
            TextField("34", text: $hours)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .hours)
                .accessibilityLabel("Weekly target hours")
            Text("hours").foregroundStyle(.secondary)
            TextField("0", text: $minutes)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .minutes)
                .accessibilityLabel("Weekly target minutes")
            Text("minutes").foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        guard let totalMinutes, isValid else { return }
        do {
            try SettingsService.saveWeeklyTarget(minutes: totalMinutes, settings: settings, in: modelContext)
            dismiss()
        } catch {
            issue = SettingsViewIssue(title: "Couldn’t Save Target", message: error.localizedDescription)
        }
    }
}
