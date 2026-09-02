import Foundation

enum DateUtilities {
    static func appCalendar(
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = Weekday.monday.rawValue
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func startOfDay(for date: Date, calendar: Calendar = appCalendar()) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfWeek(for date: Date, calendar: Calendar = appCalendar()) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = appCalendar()) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isSameWeek(_ lhs: Date, _ rhs: Date, calendar: Calendar = appCalendar()) -> Bool {
        startOfWeek(for: lhs, calendar: calendar) == startOfWeek(for: rhs, calendar: calendar)
    }

    static func weekInterval(
        containing date: Date,
        calendar: Calendar = appCalendar()
    ) -> DateInterval {
        let start = startOfWeek(for: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func daysInWeek(
        containing date: Date,
        calendar: Calendar = appCalendar()
    ) -> [Date] {
        let start = startOfWeek(for: date, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekRangeTitle(
        containing date: Date,
        calendar: Calendar = appCalendar(),
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let days = daysInWeek(containing: date, calendar: calendar)
        guard let start = days.first, let end = days.last else { return "" }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let sameMonth = sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: end)

        if sameMonth {
            let startText = start.formatted(.dateTime.day().locale(locale))
            let endText = end.formatted(.dateTime.day().month(.wide).locale(locale))
            return "\(startText)–\(endText)"
        }

        if sameYear {
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
            return "\(start.formatted(style))–\(end.formatted(style))"
        }

        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale)
        return "\(start.formatted(style))–\(end.formatted(style))"
    }

    static func daysUntil(
        _ targetDate: Date,
        from sourceDate: Date,
        calendar: Calendar = appCalendar()
    ) -> Int {
        let sourceDay = calendar.startOfDay(for: sourceDate)
        let targetDay = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: sourceDay, to: targetDay).day ?? 0
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration.rounded()) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        return switch (hours, minutes) {
        case (0, let minutes): "\(minutes)m"
        case (let hours, 0): "\(hours)h"
        default: "\(hours)h \(minutes)m"
        }
    }

    static func timerText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func relativeStudyText(
        _ date: Date?,
        relativeTo now: Date = .now,
        calendar: Calendar = appCalendar()
    ) -> String {
        guard let date else { return "Never studied" }
        let studiedDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: studiedDay, to: today).day ?? 0
        switch days {
        case 0: return "Studied today"
        case 1: return "Studied yesterday"
        case 2...6: return "Studied \(days) days ago"
        default:
            return "Studied \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }
}
