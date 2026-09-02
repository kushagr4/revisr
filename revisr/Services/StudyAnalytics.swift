import Foundation

enum StudyAnalytics {
    static func sessions(
        in interval: DateInterval,
        from sessions: [StudySession]
    ) -> [StudySession] {
        sessions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    static func blocks(
        in interval: DateInterval,
        from blocks: [PlannedStudyBlock]
    ) -> [PlannedStudyBlock] {
        blocks.filter { $0.day >= interval.start && $0.day < interval.end }
    }

    static func results(
        in interval: DateInterval,
        from results: [StudyResult]
    ) -> [StudyResult] {
        results.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    static func actualDuration(in interval: DateInterval, sessions: [StudySession]) -> TimeInterval {
        self.sessions(in: interval, from: sessions).reduce(0) { $0 + max(0, $1.duration) }
    }

    static func plannedDuration(in interval: DateInterval, blocks: [PlannedStudyBlock]) -> TimeInterval {
        self.blocks(in: interval, from: blocks).reduce(0) { $0 + max(0, $1.duration) }
    }
    static func blocks(
        inWeekContaining date: Date,
        from blocks: [PlannedStudyBlock],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> [PlannedStudyBlock] {
        let interval = DateUtilities.weekInterval(containing: date, calendar: calendar)
        return blocks.filter { $0.day >= interval.start && $0.day < interval.end }
    }

    static func blocks(
        on date: Date,
        from blocks: [PlannedStudyBlock],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> [PlannedStudyBlock] {
        blocks.filter { DateUtilities.isSameDay($0.day, date, calendar: calendar) }
    }

    static func sessions(
        on date: Date,
        from sessions: [StudySession],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> [StudySession] {
        sessions.filter { DateUtilities.isSameDay($0.date, date, calendar: calendar) }
    }

    static func plannedDuration(
        on date: Date,
        blocks: [PlannedStudyBlock],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> TimeInterval {
        self.blocks(on: date, from: blocks, calendar: calendar)
            .reduce(0) { $0 + max(0, $1.duration) }
    }

    static func weeklyPlannedDuration(
        containing date: Date,
        blocks: [PlannedStudyBlock],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> TimeInterval {
        self.blocks(inWeekContaining: date, from: blocks, calendar: calendar)
            .reduce(0) { $0 + max(0, $1.duration) }
    }

    /// Completed time comes exclusively from sessions. A linked completed block is
    /// deliberately not added separately, so timer finishes cannot be double counted.
    static func actualDuration(
        on date: Date,
        sessions: [StudySession],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> TimeInterval {
        self.sessions(on: date, from: sessions, calendar: calendar)
            .reduce(0) { $0 + max(0, $1.duration) }
    }

    static func completionFraction(planned: TimeInterval, actual: TimeInterval) -> Double {
        guard planned > 0 else { return 0 }
        return min(max(actual / planned, 0), 1)
    }

    static func scheduledBlocks(from blocks: [PlannedStudyBlock]) -> [PlannedStudyBlock] {
        blocks
            .filter(\.isScheduled)
            .sorted {
                if $0.startMinute == $1.startMinute {
                    return $0.createdAt < $1.createdAt
                }
                return ($0.startMinute ?? 0) < ($1.startMinute ?? 0)
            }
    }

    static func unscheduledBlocks(from blocks: [PlannedStudyBlock]) -> [PlannedStudyBlock] {
        blocks
            .filter { !$0.isScheduled }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    static func nextBlock(
        from blocks: [PlannedStudyBlock],
        now: Date,
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> PlannedStudyBlock? {
        let unfinished = blocks.filter { $0.status == .planned }
        let scheduled = scheduledBlocks(from: unfinished)

        if let current = scheduled.first(where: { block in
            guard let start = block.scheduledStart(using: calendar) else { return false }
            let end = start.addingTimeInterval(max(0, block.duration))
            return start <= now && now < end
        }) {
            return current
        }

        if let upcoming = scheduled.first(where: { block in
            guard let start = block.scheduledStart(using: calendar) else { return false }
            return start > now
        }) {
            return upcoming
        }

        return unscheduledBlocks(from: unfinished).first
    }

    static func manualSessions(
        on date: Date,
        sessions: [StudySession],
        calendar: Calendar = DateUtilities.appCalendar()
    ) -> [StudySession] {
        self.sessions(on: date, from: sessions, calendar: calendar)
            .filter { $0.plannedBlock == nil }
            .sorted { $0.date < $1.date }
    }
}
