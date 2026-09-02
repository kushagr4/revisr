import SwiftUI

struct WeekDaySelector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let weekStart: Date
    let selectedDay: Date
    let blocks: [PlannedStudyBlock]
    let availability: [DayAvailability]
    let onSelect: (Date) -> Void

    private let calendar = DateUtilities.appCalendar()

    private var days: [Date] {
        DateUtilities.daysInWeek(containing: weekStart, calendar: calendar)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RevisrSpacing.small) {
                            dayButtons(fixedWidth: 104)
                        }
                        .padding(.horizontal, 1)
                    }
                    .onAppear {
                        proxy.scrollTo(selectedDay, anchor: .center)
                    }
                    .onChange(of: selectedDay) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo(selectedDay, anchor: .center)
                        }
                    }
                }
            } else {
                HStack(spacing: RevisrSpacing.xSmall) {
                    dayButtons(fixedWidth: nil)
                }
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
    }

    @ViewBuilder
    private func dayButtons(fixedWidth: CGFloat?) -> some View {
        ForEach(days, id: \.self) { day in
            let dayBlocks = StudyAnalytics.blocks(on: day, from: blocks, calendar: calendar)
            let plannedDuration = dayBlocks.reduce(0) { $0 + max(0, $1.duration) }
            let selected = DateUtilities.isSameDay(day, selectedDay, calendar: calendar)
            let today = DateUtilities.isSameDay(day, .now, calendar: calendar)
            let available = availabilityForDay(day)?.isAvailable ?? true

            Button {
                onSelect(day)
            } label: {
                VStack(spacing: RevisrSpacing.xSmall) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? RevisrColors.accentTeal : .secondary)

                    Text(day.formatted(.dateTime.day()))
                        .font(.body.weight(selected ? .bold : .medium))
                        .foregroundStyle(selected ? Color.white : available ? Color.primary : Color.secondary)
                        .frame(
                            width: dynamicTypeSize.isAccessibilitySize ? 72 : 36,
                            height: dynamicTypeSize.isAccessibilitySize ? 72 : 36
                        )
                        .background(selected ? RevisrColors.accentTeal : Color.clear, in: Circle())
                        .overlay {
                            if today && !selected {
                                Circle()
                                    .stroke(RevisrColors.accentTeal, lineWidth: 1.5)
                            }
                        }

                    Circle()
                        .fill(dayBlocks.isEmpty ? (available ? Color.clear : Color.secondary.opacity(0.55)) : RevisrColors.accentTeal)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
                .frame(width: fixedWidth)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id(day)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(
                day: day,
                selected: selected,
                available: available,
                blockCount: dayBlocks.count,
                plannedDuration: plannedDuration
            ))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func availabilityForDay(_ day: Date) -> DayAvailability? {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return nil }
        return availability.first(where: { $0.weekday == weekday })
    }

    private func accessibilityLabel(
        day: Date,
        selected: Bool,
        available: Bool,
        blockCount: Int,
        plannedDuration: TimeInterval
    ) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let selection = selected ? "Selected. " : ""
        let availability = available ? "" : "Normally unavailable. "
        let blocksText = blockCount == 1 ? "1 study block" : "\(blockCount) study blocks"
        return "\(date). \(selection)\(availability)\(blocksText), \(DateUtilities.durationText(plannedDuration)) planned."
    }
}
