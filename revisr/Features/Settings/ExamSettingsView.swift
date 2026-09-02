import SwiftData
import SwiftUI

struct ExamSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    let settings: AppSettings
    @State private var examDate: Date
    @State private var issue: SettingsViewIssue?

    init(settings: AppSettings) {
        self.settings = settings
        _examDate = State(initialValue: settings.tmuaExamDate)
    }

    var body: some View {
        Form {
            Section {
                DatePicker("TMUA Exam", selection: $examDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .onChange(of: examDate) { _, newDate in save(newDate) }
            } footer: {
                Text("The countdown on Today updates from this calendar date. Past dates are allowed.")
            }
        }
        .navigationTitle("TMUA Exam")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $issue) { issue in
            Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
        }
        .tint(RevisrColors.accentTeal)
    }

    private func save(_ date: Date) {
        do {
            try SettingsService.saveExamDate(date, settings: settings, in: modelContext)
            examDate = settings.tmuaExamDate
        } catch {
            issue = SettingsViewIssue(title: "Couldn’t Save Exam Date", message: error.localizedDescription)
        }
    }
}

#if DEBUG
#Preview("Exam Date") {
    let container = try! PreviewData.makeSettingsContainer()
    let settings = try! PreviewData.settings(in: container)
    NavigationStack { ExamSettingsView(settings: settings) }
        .modelContainer(container)
}
#endif
