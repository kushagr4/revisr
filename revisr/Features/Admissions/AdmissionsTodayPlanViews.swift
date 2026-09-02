import SwiftData
import SwiftUI

private enum AdmissionsQAClock {
    static var now: Date {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["REVISR_QA_DATE"],
           let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        #endif
        return .now
    }
}

struct AdmissionsTodayView: View {
    @Query(filter: #Predicate<AdmissionsProgramme> { $0.isImportedActive })
    private var programmes: [AdmissionsProgramme]
    @Query(filter: #Predicate<ProgrammeDay> { $0.isImportedActive }, sort: \ProgrammeDay.dayNumber)
    private var days: [ProgrammeDay]

    var body: some View {
        NavigationStack {
            Group {
                if let programme = programmes.first {
                    if let scheduledDay = scheduledDay(for: programme) {
                        if programme.isAvailable(scheduledDay, at: AdmissionsQAClock.now) {
                            List {
                                programmeSection(programme, day: scheduledDay)
                                questionsSection(scheduledDay)
                            }
                            .listStyle(.insetGrouped)
                        } else {
                            ContentUnavailableView(
                                "Programme Available After \(formattedStart(scheduledDay))",
                                systemImage: "clock.badge.checkmark",
                                description: Text("There is no mandatory work before your available study time today.")
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "No Mandatory Programme Work Today",
                            systemImage: "calendar.badge.checkmark",
                            description: Text("Use Extra Practice or Needs Review if you would like to study today.")
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "TMUA Programme Unavailable",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Reopen Revisr to retry the local metadata import.")
                    )
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: QuestionBankView()) {
                        Label("Question Bank", systemImage: "books.vertical")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func programmeSection(_ programme: AdmissionsProgramme, day: ProgrammeDay) -> some View {
        Section {
            VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
                HStack {
                    AdmissionsStatusBadge(text: "TMUA · Day \(day.dayNumber)", systemImage: "target")
                    Spacer()
                    Text(programme.date(for: day.dayNumber), format: .dateTime.day().month(.abbreviated))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(day.focus)
                    .font(.title2.weight(.bold))
                Text(day.studyBrief)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(Duration.admissionsMinutes(day.expectedTotalMinutes), systemImage: "clock")
                    Spacer()
                    Text("\(completedCount(day))/\(day.allocatedQuestionCount) complete")
                }
                .font(.subheadline)
                ProgressView(value: Double(completedCount(day)), total: Double(max(1, day.allocatedQuestionCount)))
                    .tint(RevisrColors.accentTeal)
                    .accessibilityLabel("Day \(day.dayNumber) progress")
                    .accessibilityValue("\(completedCount(day)) of \(day.allocatedQuestionCount) questions complete")
            }
            .padding(.vertical, RevisrSpacing.small)
        } header: {
            Text(programmePhase(programme))
        }
    }

    private func questionsSection(_ day: ProgrammeDay) -> some View {
        Section("Today's Questions") {
            ForEach(day.assignments.filter(\.isImportedActive).sorted(by: assignmentOrder)) { assignment in
                if let question = assignment.question {
                    NavigationLink {
                        QuestionDetailView(
                            question: question,
                            assignment: assignment,
                            attemptOrigin: .programme
                        )
                    } label: {
                        AdmissionsQuestionRow(question: question, assignment: assignment)
                    }
                }
            }
        }
    }

    private func scheduledDay(for programme: AdmissionsProgramme) -> ProgrammeDay? {
        guard let day = programme.programmeDay(for: AdmissionsQAClock.now) else { return nil }
        return days.first(where: { $0.externalDayID == day.externalDayID })
    }

    private func formattedStart(_ day: ProgrammeDay) -> String {
        guard let minute = day.earliestStartMinute else { return "your available time" }
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func programmePhase(_ programme: AdmissionsProgramme) -> String {
        if AdmissionsQAClock.now < programme.startDate { return "Programme starts soon" }
        if programme.dayNumber(for: AdmissionsQAClock.now) == nil { return "Programme complete" }
        return "TMUA 30-Day Programme"
    }

    private func completedCount(_ day: ProgrammeDay) -> Int {
        day.assignments.filter { $0.isImportedActive && $0.isComplete }.count
    }

    private func assignmentOrder(_ lhs: ProgrammeAssignment, _ rhs: ProgrammeAssignment) -> Bool {
        lhs.displayOrder < rhs.displayOrder
    }
}

struct AdmissionsPlanView: View {
    @Query(filter: #Predicate<AdmissionsProgramme> { $0.isImportedActive })
    private var programmes: [AdmissionsProgramme]
    @Query(filter: #Predicate<ProgrammeDay> { $0.isImportedActive }, sort: \ProgrammeDay.dayNumber)
    private var days: [ProgrammeDay]

    var body: some View {
        NavigationStack {
            List {
                if let programme = programmes.first {
                    Section {
                        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                            Text(programme.name)
                                .font(.title3.weight(.bold))
                            Label(
                                "Starts \(programme.startDate.formatted(date: .abbreviated, time: .omitted))",
                                systemImage: "calendar"
                            )
                            .foregroundStyle(.secondary)
                            Text("Historical work is preserved. Remaining days follow the revised exam-date schedule; flex dates carry no mandatory backlog.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, RevisrSpacing.small)
                    }

                    Section("30-Day Timeline") {
                        ForEach(days) { day in
                            NavigationLink {
                                ProgrammeDayDetailView(programme: programme, day: day)
                            } label: {
                                ProgrammeDayRow(programme: programme, day: day)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No Programme", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .navigationTitle("Plan")
        }
    }
}

private struct ProgrammeDayRow: View {
    let programme: AdmissionsProgramme
    let day: ProgrammeDay

    var body: some View {
        HStack(spacing: RevisrSpacing.standard) {
            VStack {
                Text("DAY")
                    .font(.caption2.weight(.bold))
                Text("\(day.dayNumber)")
                    .font(.title3.weight(.bold))
            }
            .foregroundStyle(isCurrent ? RevisrColors.accentTeal : .secondary)
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(day.focus)
                    .font(.headline)
                Text("\(programme.date(for: day.dayNumber).formatted(.dateTime.day().month(.abbreviated))) · \(day.allocatedQuestionCount) questions · \(Duration.admissionsMinutes(day.expectedTotalMinutes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if completed == day.allocatedQuestionCount, completed > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(RevisrColors.accentTeal)
                    .accessibilityLabel("Complete")
            } else if completed > 0 {
                Text("\(completed)/\(day.allocatedQuestionCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var completed: Int { day.assignments.filter { $0.isImportedActive && $0.isComplete }.count }
    private var isCurrent: Bool { programme.dayNumber(for: AdmissionsQAClock.now) == day.dayNumber }
}

private struct ProgrammeDayDetailView: View {
    let programme: AdmissionsProgramme
    let day: ProgrammeDay

    var body: some View {
        List {
            Section {
                Text(day.studyBrief)
                LabeledContent("Date", value: programme.date(for: day.dayNumber).formatted(date: .long, time: .omitted))
                LabeledContent("Question work", value: Duration.admissionsMinutes(day.expectedQuestionMinutes))
                LabeledContent("Review and learning", value: Duration.admissionsMinutes(day.expectedReviewMinutes))
                if let target = day.dailyTarget { LabeledContent("Target", value: target) }
                if let notes = day.notes { Text(notes).foregroundStyle(.secondary) }
            }
            Section("Questions") {
                ForEach(day.assignments.filter(\.isImportedActive).sorted { $0.displayOrder < $1.displayOrder }) { assignment in
                    if let question = assignment.question {
                        NavigationLink {
                            QuestionDetailView(question: question, assignment: assignment, attemptOrigin: .programme)
                        } label: {
                            AdmissionsQuestionRow(question: question, assignment: assignment)
                        }
                    }
                }
            }
        }
        .navigationTitle("Day \(day.dayNumber): \(day.focus)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
