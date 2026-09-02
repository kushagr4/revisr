import SwiftData
import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var presentation: AppPresentationState
    @Query private var settingsRecords: [AppSettings]
    @State private var debugDestination: SettingsDestination?

    private var settings: AppSettings? { settingsRecords.first }

    var body: some View {
        Form {
            if let settings {
                Section("Study Schedule") {
                    NavigationLink {
                        AvailabilitySettingsView(settings: settings)
                    } label: {
                        SettingsNavigationLabel(title: "Availability", systemImage: "calendar.badge.clock")
                    }

                    NavigationLink {
                        WeeklyTargetSettingsView(settings: settings)
                    } label: {
                        LabeledContent {
                            Text(SettingsFormatting.weeklyTarget(settings.weeklyTargetMinutes))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } label: {
                            SettingsNavigationLabel(title: "Weekly Study Target", systemImage: "clock")
                        }
                    }
                }

                Section("Study Targets") {
                    NavigationLink {
                        SubjectTargetSettingsView(settings: settings)
                    } label: {
                        LabeledContent {
                            Text(subjectAllocationSummary(settings))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } label: {
                            SettingsNavigationLabel(title: "Subject Allocation", systemImage: "chart.pie")
                        }
                    }

                    NavigationLink {
                        TMUATargetSettingsView(settings: settings)
                    } label: {
                        LabeledContent {
                            Text(tmuaAllocationSummary(settings))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } label: {
                            SettingsNavigationLabel(title: "TMUA Allocation", systemImage: "doc.on.doc")
                        }
                    }
                }

                Section("Exam") {
                    NavigationLink {
                        ExamSettingsView(settings: settings)
                    } label: {
                        LabeledContent {
                            Text(settings.tmuaExamDate.formatted(.dateTime.day().month(.abbreviated).year()))
                                .foregroundStyle(.secondary)
                        } label: {
                            SettingsNavigationLabel(title: "TMUA", systemImage: "calendar")
                        }
                    }
                }

                Section {
                    LabeledContent("Storage", value: "On this iPhone")
                        .accessibilityHint("Revisr data is stored locally on this device")
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your Revisr data is stored locally on this device. Cloud backup and export are not currently available.")
                }

                Section("About") {
                    LabeledContent("Revisr", value: AppMetadata.versionText)
                    if let build = AppMetadata.buildNumber {
                        LabeledContent("Build", value: build)
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Preparing settings…")
                        Spacer()
                    }
                }
            }
        }
        .tint(RevisrColors.accentTeal)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentation.presentQuickStudyEntry()
                } label: {
                    Label("Log Study", systemImage: "stopwatch")
                }
                .accessibilityHint("Opens the quick study entry form")
            }
        }
        .navigationDestination(item: $debugDestination) { destination in
            if let settings {
                switch destination {
                case .availability: AvailabilitySettingsView(settings: settings)
                case .subjects: SubjectTargetSettingsView(settings: settings)
                case .tmua: TMUATargetSettingsView(settings: settings)
                case .exam: ExamSettingsView(settings: settings)
                case .weekly: WeeklyTargetSettingsView(settings: settings)
                }
            }
        }
        .onAppear(perform: openDebugDestinationIfNeeded)
        .onChange(of: settingsRecords.count) { _, _ in openDebugDestinationIfNeeded() }
    }

    private func subjectAllocationSummary(_ settings: AppSettings) -> String {
        [settings.tmuaTarget, settings.furtherMathematicsTarget, settings.mathematicsTarget]
            .map(SettingsFormatting.percentage)
            .joined(separator: " / ")
    }

    private func tmuaAllocationSummary(_ settings: AppSettings) -> String {
        [settings.tmuaPaper1Target, settings.tmuaPaper2Target]
            .map(SettingsFormatting.percentage)
            .joined(separator: " / ")
    }

    private func openDebugDestinationIfNeeded() {
#if DEBUG
        guard settings != nil, debugDestination == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--settings-availability") { debugDestination = .availability }
        else if arguments.contains("--settings-subjects")
            || arguments.contains("--settings-subjects-invalid") { debugDestination = .subjects }
        else if arguments.contains("--settings-tmua") { debugDestination = .tmua }
        else if arguments.contains("--settings-exam") { debugDestination = .exam }
        else if arguments.contains("--settings-weekly") { debugDestination = .weekly }
#endif
    }
}

private struct SettingsNavigationLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .symbolRenderingMode(.monochrome)
    }
}

private enum SettingsDestination: String, Identifiable {
    case availability
    case subjects
    case tmua
    case exam
    case weekly

    var id: String { rawValue }
}

enum AppMetadata {
    static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Version \(version ?? "—")"
    }

    static var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}

struct SettingsViewIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#if DEBUG
#Preview("Settings Root") {
    SettingsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeSettingsContainer())
}

#Preview("Settings Dark") {
    SettingsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeSettingsContainer())
        .preferredColorScheme(.dark)
}

#Preview("Settings Accessibility") {
    SettingsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeSettingsContainer())
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
