import Foundation

enum ProgressRange: String, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case lastThirtyDays
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .thisWeek: "This Week"
        case .lastThirtyDays: "Last 30 Days"
        case .allTime: "All Time"
        }
    }

    func interval(
        endingOn date: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> DateInterval {
        switch self {
        case .thisWeek:
            return DateUtilities.weekInterval(containing: date, calendar: calendar)
        case .lastThirtyDays:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
            let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .allTime:
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    func subtitle(
        endingOn date: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> String {
        switch self {
        case .thisWeek:
            return DateUtilities.weekRangeTitle(containing: date, calendar: calendar)
        case .lastThirtyDays:
            let interval = interval(endingOn: date, calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? date
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            return "\(interval.start.formatted(style))–\(lastDay.formatted(style))"
        case .allTime:
            return "Your complete history"
        }
    }
}
