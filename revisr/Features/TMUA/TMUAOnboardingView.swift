import SwiftData
import SwiftUI

/// Routes a flexible TMUA profile to onboarding, its diagnostic or its plan.
struct TMUAFlowRootView: View {
    let settings: AppSettings
    @State private var showingLegacySetup = false

    var body: some View {
        Group {
            if showingLegacySetup {
                PublicPreparationSetupView(settings: settings)
            } else {
                switch settings.publicOnboardingStage {
                case .profile?, nil:
                    TMUAOnboardingView(settings: settings, onChooseOtherExam: {
                        settings.publicFlowVersion = nil
                        showingLegacySetup = true
                    })
                case .diagnostics?, .diagnosticsComplete?:
                    TMUADiagnosticHubView(settings: settings)
                case .programme?:
                    TMUARootTabView(settings: settings)
                }
            }
        }
        .tint(RevisrColors.accentTeal)
    }
}

enum TMUAOnboardingStep: Int, CaseIterable {
    case welcome, examDate, availability, length

    var progress: Double { Double(rawValue) / Double(Self.allCases.count - 1) }
}

struct TMUAOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    var onChooseOtherExam: () -> Void = {}

    @State private var step: TMUAOnboardingStep = .welcome
    @State private var examDate: Date
    @State private var weeklyMinutes: Int?
    @State private var availability: [DayAvailability]
    @State private var sessionMinutes: Int?
    @State private var length: TMUADiagnosticLength?
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(settings: AppSettings, onChooseOtherExam: @escaping () -> Void = {}) {
        self.settings = settings
        self.onChooseOtherExam = onChooseOtherExam
        let calendar = DateUtilities.appCalendar()
        let suggestion = calendar.date(byAdding: .month, value: 2, to: calendar.startOfDay(for: .now)) ?? .now
        _examDate = State(initialValue: settings.publicExamDate ?? suggestion)
        _weeklyMinutes = State(initialValue: settings.publicWeeklyTargetMinutes)
        _availability = State(initialValue: settings.publicAvailabilityData == nil
            ? AppSettings.publicDefaultAvailability : settings.publicAvailability)
        _sessionMinutes = State(initialValue: settings.publicSessionMinutes)
        _length = State(initialValue: settings.publicDiagnosticLength)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome {
                    ProgressView(value: step.progress)
                        .tint(RevisrColors.accentTeal)
                        .padding(.horizontal, RevisrSpacing.large)
                        .padding(.top, RevisrSpacing.small)
                        .accessibilityLabel("Setup progress")
                        .accessibilityValue("Step \(step.rawValue) of \(TMUAOnboardingStep.allCases.count - 1)")
                }
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: welcome
                        case .examDate: examDateStep
                        case .availability: TMUAAvailabilityEditor(weeklyMinutes: $weeklyMinutes,
                            availability: $availability, sessionMinutes: $sessionMinutes, examDate: examDate,
                            showsHeading: true)
                        case .length: TMUALengthPicker(selection: $length)
                        }
                    }
                    .padding(RevisrSpacing.large)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") { go(-1) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t Continue", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.large) {
            Image(systemName: "function")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(RevisrColors.accentTeal)
                .frame(width: 84, height: 84)
                .background(RevisrColors.tintedSurface, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
                .padding(.top, RevisrSpacing.xLarge)
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                Text("Revisr").font(RevisrTypography.screenTitle)
                Text("TMUA preparation built around you.")
                    .font(.title3).foregroundStyle(RevisrColors.secondaryLabel)
            }
            VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
                welcomePoint("scope", "Understand where you currently stand")
                welcomePoint("target", "Discover the areas of mathematics to prioritise")
                welcomePoint("calendar", "Build a study programme around your examination date")
                welcomePoint("arrow.triangle.2.circlepath", "Adapt your revision as you improve")
            }
            Text("No account needed. Everything stays on this iPhone.")
                .font(RevisrTypography.supporting).foregroundStyle(RevisrColors.secondaryLabel)
            Text("Revisr is independent and is not affiliated with or endorsed by UAT-UK or any examination provider.")
                .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
        }
    }

    private func welcomePoint(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.body.weight(.medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(RevisrColors.accentTeal).frame(width: 28)
        }
    }

    private var examDateStep: some View {
        let calendar = DateUtilities.appCalendar()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let days = PublicPreparationService.daysUntilExam(examDate)
        return VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
            stepHeading("When are you sitting the TMUA?",
                        "Choose your actual test date. Revisr plans revision up to the day before it.")
            DatePicker("Examination date", selection: $examDate, in: tomorrow..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(RevisrColors.accentTeal)
            HStack {
                Label("\(days) day\(days == 1 ? "" : "s") to go", systemImage: "hourglass")
                    .font(.headline)
                Spacer()
                Text(examDate.formatted(date: .complete, time: .omitted))
                    .font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
            }
            .padding(RevisrSpacing.standard)
            .background(RevisrColors.tintedSurface, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
            .accessibilityElement(children: .combine)
            Text("Exam day itself is left free of revision tasks.")
                .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
        }
    }

    private func stepHeading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(RevisrColors.secondaryLabel)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: RevisrSpacing.small) {
            if let hint = blockingHint {
                Text(hint).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            Button(action: advance) {
                Text(primaryTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(blockingHint != nil || isSaving)
            if step == .welcome {
                Button("Preparing for SMC or BMO instead?", action: onChooseOtherExam)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, RevisrSpacing.large)
        .padding(.vertical, RevisrSpacing.compact)
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Build my revision plan"
        case .examDate, .availability: "Continue"
        case .length: length.map { "Start with \($0.totalQuestions) questions" } ?? "Choose a length"
        }
    }

    private var blockingHint: String? {
        switch step {
        case .welcome: return nil
        case .examDate:
            return PublicPreparationService.daysUntilExam(examDate) > 0 ? nil : "Choose a date after today."
        case .availability:
            return TMUAAvailabilityEditor.validationMessage(weeklyMinutes: weeklyMinutes,
                availability: availability, sessionMinutes: sessionMinutes)
        case .length:
            return length == nil ? "Choose how many diagnostic questions to answer." : nil
        }
    }

    private func go(_ delta: Int) {
        guard let next = TMUAOnboardingStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func advance() {
        guard step == .length else { go(1); return }
        guard let length, let weeklyMinutes else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try PublicPreparationService.saveFlexibleTMUAProfile(
                examDate: examDate, weeklyMinutes: weeklyMinutes, availability: availability,
                sessionMinutes: sessionMinutes, settings: settings, in: modelContext)
            settings.publicDiagnosticLength = length
            if let content = TMUAContentStore.context(), content.availability(for: length).isAvailable {
                _ = try TMUADiagnosticService.create(settings: settings, length: length,
                                                     content: content, in: modelContext)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Availability editor (onboarding and Settings)

struct TMUAAvailabilityEditor: View {
    @Binding var weeklyMinutes: Int?
    @Binding var availability: [DayAvailability]
    @Binding var sessionMinutes: Int?
    let examDate: Date
    var showsHeading = false

    static let presetHours = [3, 5, 8, 12]
    static let sessionOptions: [Int?] = [nil, 30, 45, 60, 90, 120]
    @State private var customSelected = false

    static func validationMessage(weeklyMinutes: Int?, availability: [DayAvailability],
                                  sessionMinutes: Int?) -> String? {
        guard let weeklyMinutes, weeklyMinutes > 0 else { return "Choose your weekly study time." }
        let days = availability.filter(\.isAvailable).count
        guard days > 0 else { return "Choose at least one study day." }
        let task = PublicPlanningPolicy.questionMinutes(for: .tmua)
        if weeklyMinutes / days < task {
            return "That is under \(task) minutes on each study day. Add time or choose fewer days."
        }
        if let sessionMinutes, sessionMinutes < task { return "Sessions need at least \(task) minutes." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.large) {
            if showsHeading {
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Text("How much time can you realistically dedicate to TMUA preparation?")
                        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Be honest. A plan you can keep beats an ambitious one you can’t.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
                Text("Each week").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: RevisrSpacing.small)],
                          spacing: RevisrSpacing.small) {
                    ForEach(Self.presetHours, id: \.self) { hours in
                        chip("\(hours) hours", selected: !customSelected && weeklyMinutes == hours * 60) {
                            customSelected = false
                            weeklyMinutes = hours * 60
                        }
                    }
                    chip("Custom", selected: customSelected || isCustomValue) {
                        customSelected = true
                        if weeklyMinutes == nil { weeklyMinutes = 240 }
                    }
                }
                if customSelected || isCustomValue {
                    Stepper(value: Binding(get: { weeklyMinutes ?? 240 }, set: { weeklyMinutes = $0 }),
                            in: 30...4_200, step: 30) {
                        Text(SettingsFormatting.weeklyTarget(weeklyMinutes ?? 240)).font(.body.monospacedDigit())
                    }
                }
            }
            VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
                Text("Study days").font(.headline)
                HStack(spacing: 6) {
                    ForEach(Weekday.displayOrder) { day in
                        let on = availability.first { $0.weekday == day }?.isAvailable ?? false
                        Button {
                            guard let index = availability.firstIndex(where: { $0.weekday == day }) else { return }
                            availability[index].isAvailable.toggle()
                        } label: {
                            Text(String(day.title.prefix(3)))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: RevisrMetrics.minimumTapTarget)
                                .foregroundStyle(on ? Color.white : RevisrColors.primaryLabel)
                                .background(on ? RevisrColors.accentTeal : RevisrColors.secondaryBackground,
                                            in: RoundedRectangle(cornerRadius: RevisrMetrics.compactCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.title)
                        .accessibilityValue(on ? "Study day" : "Rest day")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
                Picker("Longest session in a day", selection: $sessionMinutes) {
                    ForEach(Self.sessionOptions, id: \.self) { option in
                        Text(option.map { "\($0) minutes" } ?? "No limit").tag(option)
                    }
                }
                .pickerStyle(.menu)
                Text("Optional. Revisr never plans more than this on one day.")
                    .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            }
            summary
        }
    }

    private var isCustomValue: Bool {
        guard let weeklyMinutes else { return false }
        return !Self.presetHours.map { $0 * 60 }.contains(weeklyMinutes)
    }

    @ViewBuilder
    private var summary: some View {
        let days = availability.filter(\.isAvailable).count
        if let weeklyMinutes, days > 0 {
            let perDay = min(weeklyMinutes / days, sessionMinutes ?? .max)
            let studyDays = PublicPreparationService.studyDaysBeforeExam(examDate, availability: availability)
            VStack(alignment: .leading, spacing: 4) {
                Text("About \(perDay) minutes on each study day")
                    .font(.headline)
                Text("\(studyDays) study day\(studyDays == 1 ? "" : "s") before your exam")
                    .foregroundStyle(RevisrColors.secondaryLabel)
            }
            .padding(RevisrSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RevisrColors.tintedSurface, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
            .accessibilityElement(children: .combine)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: RevisrMetrics.minimumTapTarget)
                .foregroundStyle(selected ? Color.white : RevisrColors.primaryLabel)
                .background(selected ? RevisrColors.accentTeal : RevisrColors.secondaryBackground,
                            in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Diagnostic length picker

struct TMUALengthPicker: View {
    @Binding var selection: TMUADiagnosticLength?
    var options: [TMUADiagnosticLength] = TMUADiagnosticLength.allCases
    var exposed: Set<String> = []
    var showsHeading = true

    var body: some View {
        let content = TMUAContentStore.context()
        VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
            if showsHeading {
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Text("How many diagnostic questions would you like to answer?")
                        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Every option covers both TMUA papers and leads to a full revision plan. More questions give broader evidence; fewer take less time. You can add more questions later.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            ForEach(options) { option in
                let availability = content?.availability(for: option, excluding: exposed)
                    ?? .blocked("Question content could not be loaded.")
                TMUALengthCard(length: option, selected: selection == option, availability: availability) {
                    selection = option
                }
            }
            Text("You can pause at any point and come back later, even after closing the app.")
                .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
        }
    }
}

private struct TMUALengthCard: View {
    let length: TMUADiagnosticLength
    let selected: Bool
    let availability: TMUADiagnosticAvailability
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text(length.title).font(.headline)
                    Text("\(length.totalQuestions) questions").font(.subheadline)
                        .foregroundStyle(RevisrColors.secondaryLabel)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? RevisrColors.accentTeal : RevisrColors.secondaryLabel)
                        .imageScale(.large)
                }
                if length.isRecommended {
                    Text("Recommended for the most detailed personalisation")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RevisrColors.accentTeal.opacity(0.15), in: Capsule())
                        .foregroundStyle(RevisrColors.accentTeal)
                }
                Text("Paper 1: \(length.paperOneQuestions) · Paper 2: \(length.paperTwoQuestions) · about \(length.advisoryMinutes(for: .one) + length.advisoryMinutes(for: .two)) minutes")
                    .font(.subheadline.monospacedDigit())
                Text(length.summary).font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                if let message = availability.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(RevisrColors.warning)
                }
            }
            .padding(RevisrSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RevisrColors.secondaryBackground, in: RoundedRectangle(cornerRadius: RevisrMetrics.prominentCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RevisrMetrics.prominentCornerRadius)
                    .strokeBorder(selected ? RevisrColors.accentTeal : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: RevisrMetrics.prominentCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(!availability.isAvailable)
        .opacity(availability.isAvailable ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(availability.isAvailable ? "Selects this diagnostic length" : "Unavailable in this build")
    }
}
