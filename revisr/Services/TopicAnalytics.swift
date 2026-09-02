import Foundation

enum TopicAnalytics {
    /// Current-topic analytics use only an explicit relationship. Snapshot names are
    /// intentionally excluded because a future topic may reuse an old topic's name.
    static func sessions(for topic: Topic, from sessions: [StudySession]) -> [StudySession] {
        sessions
            .filter { $0.topic?.id == topic.id }
            .sorted { $0.date > $1.date }
    }

    static func totalDuration(for topic: Topic, sessions: [StudySession]) -> TimeInterval {
        self.sessions(for: topic, from: sessions).reduce(0) { $0 + max(0, $1.duration) }
    }

    static func lastStudied(for topic: Topic, sessions: [StudySession]) -> Date? {
        self.sessions(for: topic, from: sessions).first?.date
    }

    static func recentSessions(
        for topic: Topic,
        sessions: [StudySession],
        limit: Int = 5
    ) -> [StudySession] {
        Array(self.sessions(for: topic, from: sessions).prefix(max(0, limit)))
    }

    static func lastStudiedByTopic(from sessions: [StudySession]) -> [UUID: Date] {
        var dates: [UUID: Date] = [:]
        for session in sessions {
            guard let topicID = session.topic?.id else { continue }
            if let latestDate = dates[topicID], session.date <= latestDate {
                continue
            } else {
                dates[topicID] = session.date
            }
        }
        return dates
    }

    static func needsReview(
        topics: [Topic],
        lastStudied: [UUID: Date]
    ) -> [Topic] {
        topics.filter(\.needsReview).sorted { lhs, rhs in
            if lhs.status.reviewSortOrder != rhs.status.reviewSortOrder {
                return lhs.status.reviewSortOrder < rhs.status.reviewSortOrder
            }
            let lhsDate = lastStudied[lhs.id]
            let rhsDate = lastStudied[rhs.id]
            switch (lhsDate, rhsDate) {
            case (nil, nil):
                if lhs.displayOrder != rhs.displayOrder { return lhs.displayOrder < rhs.displayOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            case (nil, _): return true
            case (_, nil): return false
            case (let lhsDate?, let rhsDate?):
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                if lhs.displayOrder != rhs.displayOrder { return lhs.displayOrder < rhs.displayOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    static func search(topics: [Topic], query: String) -> [Topic] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return topics.filter { topic in
            [topic.name, topic.module?.name, topic.module?.subject?.name]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }.sorted(by: curriculumOrder)
    }

    static func curriculumOrder(_ lhs: Topic, _ rhs: Topic) -> Bool {
        let lhsSubject = lhs.module?.subject?.displayOrder ?? .max
        let rhsSubject = rhs.module?.subject?.displayOrder ?? .max
        if lhsSubject != rhsSubject { return lhsSubject < rhsSubject }
        let lhsModule = lhs.module?.displayOrder ?? .max
        let rhsModule = rhs.module?.displayOrder ?? .max
        if lhsModule != rhsModule { return lhsModule < rhsModule }
        if lhs.displayOrder != rhs.displayOrder { return lhs.displayOrder < rhs.displayOrder }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
