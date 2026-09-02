import SwiftData
import SwiftUI

struct SubjectTargetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let initialPercentages: [Int]?

    init(settings: AppSettings, initialPercentages: [Int]? = nil) {
        self.settings = settings
        self.initialPercentages = initialPercentages
    }

    var body: some View {
        PercentageAllocationEditor(
            title: "Subject Allocation",
            explanation: "Targets compare your logged study time across the three core subjects. They must total 100%.",
            items: [
                PercentageTargetItem(id: "tmua", title: "TMUA", accessibilityLabel: "TMUA target"),
                PercentageTargetItem(id: "further", title: "Further Mathematics", accessibilityLabel: "Further Mathematics target"),
                PercentageTargetItem(id: "mathematics", title: "Mathematics", accessibilityLabel: "Mathematics target")
            ],
            initialValues: startingPercentages
        ) { values in
            try SettingsService.saveSubjectTargets(
                tmua: values[0],
                furtherMathematics: values[1],
                mathematics: values[2],
                settings: settings,
                in: modelContext
            )
        }
    }

    private var startingPercentages: [Int] {
        if let initialPercentages { return initialPercentages }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--settings-subjects-invalid") {
            return [60, 30, 20]
        }
#endif
        return [
            SettingsValidation.wholePercentage(from: settings.tmuaTarget),
            SettingsValidation.wholePercentage(from: settings.furtherMathematicsTarget),
            SettingsValidation.wholePercentage(from: settings.mathematicsTarget)
        ]
    }
}

struct TMUATargetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings

    var body: some View {
        PercentageAllocationEditor(
            title: "TMUA Allocation",
            explanation: "Set how your TMUA study target is divided between Paper 1 and Paper 2. The values must total 100%.",
            items: [
                PercentageTargetItem(id: "paper1", title: "Paper 1", accessibilityLabel: "TMUA Paper 1 target"),
                PercentageTargetItem(id: "paper2", title: "Paper 2", accessibilityLabel: "TMUA Paper 2 target")
            ],
            initialValues: [
                SettingsValidation.wholePercentage(from: settings.tmuaPaper1Target),
                SettingsValidation.wholePercentage(from: settings.tmuaPaper2Target)
            ]
        ) { values in
            try SettingsService.saveTMUATargets(
                paper1: values[0],
                paper2: values[1],
                settings: settings,
                in: modelContext
            )
        }
    }
}

#if DEBUG
#Preview("Subject Targets Valid") {
    let container = try! PreviewData.makeSettingsContainer()
    let settings = try! PreviewData.settings(in: container)
    NavigationStack { SubjectTargetSettingsView(settings: settings) }
        .modelContainer(container)
}

#Preview("Subject Targets Invalid Draft") {
    let container = try! PreviewData.makeSettingsContainer()
    let settings = try! PreviewData.settings(in: container)
    NavigationStack {
        SubjectTargetSettingsView(settings: settings, initialPercentages: [60, 30, 20])
    }
    .modelContainer(container)
}

#Preview("TMUA Allocation") {
    let container = try! PreviewData.makeSettingsContainer()
    let settings = try! PreviewData.settings(in: container)
    NavigationStack { TMUATargetSettingsView(settings: settings) }
        .modelContainer(container)
}
#endif
