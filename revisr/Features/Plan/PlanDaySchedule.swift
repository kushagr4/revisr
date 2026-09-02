import SwiftUI

struct PlanDaySchedule: View {
    let day: Date
    let scheduledBlocks: [PlannedStudyBlock]
    let unscheduledBlocks: [PlannedStudyBlock]
    let allDayBlocks: [PlannedStudyBlock]
    let availability: [DayAvailability]

    let onEdit: (PlannedStudyBlock) -> Void
    let onStart: (PlannedStudyBlock) -> Void
    let onComplete: (PlannedStudyBlock) -> Void
    let onSkip: (PlannedStudyBlock) -> Void
    let onMove: (PlannedStudyBlock) -> Void
    let onDuplicate: (PlannedStudyBlock) -> Void
    let onDelete: (PlannedStudyBlock) -> Void
    let onAdd: () -> Void

    private let calendar = DateUtilities.appCalendar()

    var body: some View {
        Section("Schedule") {
            if scheduledBlocks.isEmpty && unscheduledBlocks.isEmpty {
                PlanEmptyStateView(day: day, availability: availabilityForDay)
                addBlockButton
            } else if scheduledBlocks.isEmpty {
                Text("No scheduled blocks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scheduledBlocks) { block in
                    interactiveRow(block)
                }
            }
        }

        if !unscheduledBlocks.isEmpty {
            Section("Any time") {
                ForEach(unscheduledBlocks) { block in
                    interactiveRow(block)
                }
            }
        }

        if !scheduledBlocks.isEmpty || !unscheduledBlocks.isEmpty {
            Section {
                addBlockButton
            }
            .listRowSeparator(.hidden)
        }
    }

    private var addBlockButton: some View {
        Button(action: onAdd) {
            Label("Add Block", systemImage: "calendar.badge.plus")
                .font(.body.weight(.semibold))
        }
        .foregroundStyle(RevisrColors.accentTeal)
        .accessibilityHint("Adds planned study for this day")
    }

    private var availabilityForDay: DayAvailability? {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return nil }
        return availability.first(where: { $0.weekday == weekday })
    }

    private func interactiveRow(_ block: PlannedStudyBlock) -> some View {
        let conflicts = PlanningService.conflicts(
            for: block,
            among: allDayBlocks,
            availability: availability,
            calendar: calendar
        )

        return VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
            Button {
                onEdit(block)
            } label: {
                PlannedBlockRow(
                    block: block,
                    isNext: false,
                    calendar: calendar,
                    interactionHint: "Double tap to edit this planned block"
                )
            }
            .buttonStyle(.plain)

            ForEach(conflicts, id: \.self) { conflict in
                PlanningConflictView(conflict: conflict, day: block.day)
                    .padding(.leading, RevisrSpacing.standard)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if block.status != .completed {
                Button {
                    onComplete(block)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(RevisrColors.accentTeal)
            }
            if block.status == .planned {
                Button {
                    onSkip(block)
                } label: {
                    Label("Skip", systemImage: "forward.end")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if block.status != .completed {
                Button {
                    onMove(block)
                } label: {
                    Label("Move", systemImage: "calendar")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if block.status == .planned {
                Button("Start", systemImage: "play.fill") { onStart(block) }
            }
            Button("Edit", systemImage: "pencil") { onEdit(block) }
            if block.status != .completed {
                Button("Complete", systemImage: "checkmark") { onComplete(block) }
                Button("Move", systemImage: "calendar") { onMove(block) }
            }
            Button("Duplicate", systemImage: "plus.square.on.square") { onDuplicate(block) }
            if block.status == .planned {
                Button("Skip", systemImage: "forward.end") { onSkip(block) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(block) }
        }
    }
}

private struct PlanEmptyStateView: View {
    let day: Date
    let availability: DayAvailability?

    private let calendar = DateUtilities.appCalendar()

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, RevisrSpacing.small)
        .accessibilityElement(children: .combine)
    }

    private var isPast: Bool {
        day < calendar.startOfDay(for: .now)
    }

    private var title: String {
        if availability?.isAvailable == false { return "Normally unavailable" }
        return "Nothing planned"
    }

    private var icon: String {
        availability?.isAvailable == false ? "moon.zzz" : "calendar.badge.plus"
    }

    private var message: String {
        if availability?.isAvailable == false {
            return "You can still add a block if your plans have changed."
        }
        if isPast {
            return "No study was planned for this day."
        }
        let weekday = day.formatted(.dateTime.weekday(.wide))
        return "Add your first study block for \(weekday)."
    }
}
