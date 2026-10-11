import SwiftData
import SwiftUI

struct PublicPreparationSetupView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings

    @State private var exam: PublicExamKind
    @State private var examDate: Date?
    @State private var draftExamDate: Date
    @State private var showingDatePicker = false
    @State private var weeklyMinutes: Int
    @State private var availability: [DayAvailability]
    @State private var editing: Bool
    @State private var showingProgramme: Bool
    @State private var errorMessage: String?

    init(settings: AppSettings) {
        self.settings = settings
        _exam = State(initialValue: settings.publicExam)
        _examDate = State(initialValue: settings.publicExamDate)
        _draftExamDate = State(initialValue: settings.publicExamDate
            ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        _weeklyMinutes = State(initialValue: settings.publicWeeklyTargetMinutes ?? 600)
        _availability = State(initialValue: settings.publicAvailability)
        _editing = State(initialValue: settings.publicOnboardingStage == .profile)
        _showingProgramme = State(initialValue: settings.publicOnboardingStage == .programme)
    }

    var body: some View {
        Group {
            if editing {
                setupForm
            } else if showingProgramme {
                PublicRootTabView(settings: settings) {
                    editing = true
                    showingProgramme = false
                }
            } else {
                DiagnosticHomeView(settings: settings, onEdit: { editing = true },
                                   onProgrammeGenerated: { showingProgramme = true })
            }
        }
        .tint(RevisrColors.accentTeal)
    }

    private var setupForm: some View {
        NavigationStack {
            Form {
                    Section {
                        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                            Label("A revision plan built around you", systemImage: "sparkles")
                                .font(RevisrTypography.cardTitle)
                            Text("Choose your examination, time and available days. Revisr will use your diagnostic results to shape what you practise next.")
                                .font(RevisrTypography.supporting)
                                .foregroundStyle(RevisrColors.secondaryLabel)
                            ProgressView(value: examDate == nil ? 0.25 : 0.7)
                                .tint(RevisrColors.accentTeal)
                                .accessibilityLabel("Preparation setup progress")
                        }
                        .padding(.vertical, RevisrSpacing.small)
                    }
                    Section {
                        Picker("Examination", selection: $exam) {
                            ForEach(PublicExamKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        Button {
                            showingDatePicker = true
                        } label: {
                            LabeledContent("Examination date", value: examDate?.formatted(date: .abbreviated, time: .omitted) ?? "Choose date")
                        }
                    } header: {
                        Text("Your goal")
                    } footer: {
                        Text("Your date determines the time available for a future personalised plan.")
                    }

                    Section {
                        Stepper(value: $weeklyMinutes, in: 30...10_080, step: 30) {
                            LabeledContent("Weekly study target", value: SettingsFormatting.weeklyTarget(weeklyMinutes))
                        }
                        ForEach(Weekday.displayOrder) { day in
                            Toggle(day.title, isOn: availabilityBinding(for: day))
                        }
                    } header: {
                        Text("Study availability")
                    } footer: {
                        Text("You can refine your availability later. Your plan will respect unavailable days.")
                    }

                    Section {
                        Button("Save and continue") { saveProfile() }
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                            .disabled(examDate == nil)
                    }
            }
            .navigationTitle("Set up Revisr")
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    Form {
                        DatePicker(
                            "Examination date",
                            selection: $draftExamDate,
                            in: Date.now...,
                            displayedComponents: .date
                        )
                    }
                    .navigationTitle("Exam date")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingDatePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Use date") {
                                examDate = draftExamDate
                                showingDatePicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("Couldn’t Save Preparation", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func availabilityBinding(for day: Weekday) -> Binding<Bool> {
        Binding(
            get: { availability.first(where: { $0.weekday == day })?.isAvailable ?? true },
            set: { isAvailable in
                guard let index = availability.firstIndex(where: { $0.weekday == day }) else { return }
                availability[index].isAvailable = isAvailable
            }
        )
    }

    private func saveProfile() {
        guard let examDate else { return }
        do {
            try PublicPreparationService.saveProfile(
                exam: exam,
                examDate: examDate,
                weeklyMinutes: weeklyMinutes,
                availability: availability,
                settings: settings,
                in: modelContext
            )
            editing = false
            showingProgramme = settings.publicOnboardingStage == .programme
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
