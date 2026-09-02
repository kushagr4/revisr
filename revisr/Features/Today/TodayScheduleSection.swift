import SwiftUI

struct TodayScheduleSection: View {
    let scheduledBlocks: [PlannedStudyBlock]
    let unscheduledBlocks: [PlannedStudyBlock]
    let nextBlockID: UUID?
    let isDayAvailable: Bool
    let calendar: Calendar

    let onOpenActions: (PlannedStudyBlock) -> Void
    let onStart: (PlannedStudyBlock) -> Void
    let onComplete: (PlannedStudyBlock) -> Void
    let onSkip: (PlannedStudyBlock) -> Void
    let onMove: (PlannedStudyBlock) -> Void
    let onDuplicate: (PlannedStudyBlock) -> Void
    let onDelete: (PlannedStudyBlock) -> Void

    var body: some View {
        Section("Today’s Plan") {
            if scheduledBlocks.isEmpty && unscheduledBlocks.isEmpty {
                TodayEmptyStateView(isAvailable: isDayAvailable)
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
    }

    private func interactiveRow(_ block: PlannedStudyBlock) -> some View {
        Button {
            onOpenActions(block)
        } label: {
            PlannedBlockRow(
                block: block,
                isNext: nextBlockID == block.id,
                calendar: calendar
            )
        }
        .buttonStyle(.plain)
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
