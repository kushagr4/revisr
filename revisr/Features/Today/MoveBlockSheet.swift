import SwiftData
import SwiftUI

struct MoveBlockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let block: PlannedStudyBlock
    let availability: [DayAvailability]

    @State private var selectedDay: Date
    @State private var includesTime: Bool
    @State private var selectedTime: Date
    @State private var saveError: MoveSheetError?

    private let calendar = DateUtilities.appCalendar()

    init(block: PlannedStudyBlock, availability: [DayAvailability]) {
        self.block = block
        self.availability = availability
        let calendar = DateUtilities.appCalendar()
        _selectedDay = State(initialValue: block.day)
        _includesTime = State(initialValue: block.startMinute != nil)
        _selectedTime = State(
            initialValue: block.scheduledStart(using: calendar)
                ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: block.day)
                ?? block.day
        )
    }

    private var selectedAvailability: DayAvailability? {
        let weekdayValue = calendar.component(.weekday, from: selectedDay)
        guard let weekday = Weekday(rawValue: weekdayValue) else { return nil }
        return availability.first(where: { $0.weekday == weekday })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $selectedDay, displayedComponents: .date)
                    Toggle("Schedule a time", isOn: $includesTime)
                    if includesTime {
                        DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Move To")
                } footer: {
                    Group {
                        if selectedAvailability?.isAvailable == false {
                            Text("This day is normally unavailable. You can still move the block here.")
                        } else if let startMinute = selectedAvailability?.startMinute {
                            Text("This day is normally available from \(timeText(for: startMinute)).")
                        }
                    }
                }
            }
            .navigationTitle("Move Study")
            .navigationBarTitleDisplayMode(.inline)
            .tint(RevisrColors.accentTeal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert(item: $saveError) { error in
                Alert(
                    title: Text("Couldn’t Move Study"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func save() {
        let startMinute: Int?
        if includesTime {
            let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
            startMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        } else {
            startMinute = nil
        }

        do {
            try StudySessionService.move(
                block: block,
                to: selectedDay,
                startMinute: startMinute,
                calendar: calendar,
                in: modelContext
            )
            dismiss()
        } catch {
            saveError = MoveSheetError(message: error.localizedDescription)
        }
    }

    private func timeText(for minute: Int) -> String {
        let day = calendar.startOfDay(for: selectedDay)
        let date = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct MoveSheetError: Identifiable {
    let id = UUID()
    let message: String
}
