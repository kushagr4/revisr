import SwiftData
import SwiftUI

struct AvailabilitySettingsView: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(Weekday.displayOrder) { weekday in
                    let availability = SettingsService.availability(for: weekday, in: settings)
                    NavigationLink {
                        AvailabilityDayEditor(settings: settings, weekday: weekday)
                    } label: {
                        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                            Text(weekday.title)
                            Text(SettingsFormatting.availabilitySummary(availability))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, RevisrSpacing.xSmall)
                    }
                    .accessibilityLabel("\(weekday.title), \(SettingsFormatting.availabilitySummary(availability))")
                    .accessibilityHint("Opens availability settings for \(weekday.title)")
                }
            } footer: {
                Text("Availability guides planning and warnings. Existing study blocks and history are never removed when it changes.")
            }
        }
        .navigationTitle("Availability")
        .navigationBarTitleDisplayMode(.inline)
        .tint(RevisrColors.accentTeal)
    }
}

struct AvailabilityDayEditor: View {
    @Environment(\.modelContext) private var modelContext

    let settings: AppSettings
    let weekday: Weekday

    @State private var isAvailable: Bool
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    @State private var issue: SettingsViewIssue?

    private let calendar = DateUtilities.appCalendar()

    init(settings: AppSettings, weekday: Weekday) {
        self.settings = settings
        self.weekday = weekday
        let availability = SettingsService.availability(for: weekday, in: settings)
        _isAvailable = State(initialValue: availability.isAvailable)
        _hasStartTime = State(initialValue: availability.startMinute != nil)
        _startTime = State(initialValue: Self.time(for: availability.startMinute ?? 9 * 60))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Available", isOn: $isAvailable)
                    .onChange(of: isAvailable) { _, _ in persist() }

                Toggle("Available from a specific time", isOn: $hasStartTime)
                    .disabled(!isAvailable)
                    .onChange(of: hasStartTime) { _, _ in persist() }

                if hasStartTime {
                    DatePicker(
                        "Available from",
                        selection: $startTime,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!isAvailable)
                    .onChange(of: startTime) { _, _ in persist() }
                }
            } footer: {
                Text(isAvailable ? "This guides conflict warnings; it does not prevent planning." : "The previous start time is preserved and ignored until this day is available again.")
            }
        }
        .navigationTitle(weekday.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $issue) { issue in
            Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
        }
        .tint(RevisrColors.accentTeal)
    }

    private var startMinute: Int? {
        guard hasStartTime else { return nil }
        return calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
    }

    private func persist() {
        do {
            try SettingsService.updateAvailability(
                weekday: weekday,
                isAvailable: isAvailable,
                startMinute: startMinute,
                settings: settings,
                in: modelContext
            )
        } catch {
            issue = SettingsViewIssue(title: "Couldn’t Save Availability", message: error.localizedDescription)
        }
    }

    private static func time(for minute: Int) -> Date {
        let calendar = DateUtilities.appCalendar()
        let day = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: minute, to: day) ?? day
    }
}

#if DEBUG
#Preview("Availability") {
    let container = try! PreviewData.makeSettingsContainer()
    let settings = try! PreviewData.settings(in: container)
    NavigationStack { AvailabilitySettingsView(settings: settings) }
        .modelContainer(container)
}
#endif
