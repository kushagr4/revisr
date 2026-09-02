import SwiftUI

struct PlanDayHeader: View {
    let day: Date
    let plannedDuration: TimeInterval
    let availability: DayAvailability?

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(availability?.isAvailable == false ? Color.secondary : RevisrColors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let duration = "\(DateUtilities.durationText(plannedDuration)) planned"
        guard let availability else { return duration }
        if !availability.isAvailable {
            return plannedDuration > 0 ? "Normally unavailable · \(duration)" : "Normally unavailable"
        }
        if let minute = availability.startMinute {
            let calendar = DateUtilities.appCalendar()
            let start = calendar.startOfDay(for: day)
            let time = calendar.date(byAdding: .minute, value: minute, to: start) ?? start
            return "Available from \(time.formatted(date: .omitted, time: .shortened)) · \(duration)"
        }
        return duration
    }
}
