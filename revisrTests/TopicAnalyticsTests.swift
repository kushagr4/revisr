import XCTest
@testable import revisr

final class TopicAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    func testTopicHistoryUsesExplicitRelationshipOnly() {
        let topic = Topic(name: "Integration", displayOrder: 0)
        let linked = session(date: makeDate(2026, 8, 12), minutes: 60, topic: topic, snapshot: "Integration")
        let sameNameSnapshot = session(date: makeDate(2026, 8, 13), minutes: 500, topic: nil, snapshot: "Integration")
        let unrelated = session(date: makeDate(2026, 8, 14), minutes: 120, topic: nil, snapshot: "Other")

        let history = TopicAnalytics.sessions(for: topic, from: [linked, sameNameSnapshot, unrelated])

        XCTAssertEqual(history.map(\.id), [linked.id])
        XCTAssertEqual(TopicAnalytics.totalDuration(for: topic, sessions: [linked, sameNameSnapshot]), 60 * 60)
    }

    func testTotalLastStudiedAndRecentSessionsUseActualSessions() {
        let topic = Topic(name: "Complex Numbers", displayOrder: 0)
        let sessions = [
            session(date: makeDate(2026, 8, 10), minutes: 45, topic: topic),
            session(date: makeDate(2026, 8, 13), minutes: 75, topic: topic),
            session(date: makeDate(2026, 8, 12), minutes: 60, topic: topic)
        ]

        XCTAssertEqual(TopicAnalytics.totalDuration(for: topic, sessions: sessions), 180 * 60)
        XCTAssertEqual(TopicAnalytics.lastStudied(for: topic, sessions: sessions), makeDate(2026, 8, 13))
        XCTAssertEqual(TopicAnalytics.recentSessions(for: topic, sessions: sessions, limit: 2).map(\.date), [makeDate(2026, 8, 13), makeDate(2026, 8, 12)])
    }

    func testNoSessionTopicHasEmptyHistory() {
        let topic = Topic(name: "Functions", displayOrder: 0)

        XCTAssertEqual(TopicAnalytics.totalDuration(for: topic, sessions: []), 0)
        XCTAssertNil(TopicAnalytics.lastStudied(for: topic, sessions: []))
        XCTAssertTrue(TopicAnalytics.recentSessions(for: topic, sessions: []).isEmpty)
    }

    func testPlannedBlocksDoNotContributeToActualTopicStudy() {
        let topic = Topic(name: "Probability", displayOrder: 0)
        _ = PlannedStudyBlock(day: .now, duration: 90 * 60, activity: .revision, topic: topic)

        XCTAssertEqual(TopicAnalytics.totalDuration(for: topic, sessions: []), 0)
    }

    func testNeedsReviewOrderingUsesStatusThenNeverStudiedThenOldest() {
        let weakStudied = Topic(name: "Weak studied", status: .weak, needsReview: true, displayOrder: 2)
        let weakNever = Topic(name: "Weak never", status: .weak, needsReview: true, displayOrder: 1)
        let needsWork = Topic(name: "Needs work", status: .needsWork, needsReview: true, displayOrder: 0)
        let good = Topic(name: "Good", status: .good, needsReview: true, displayOrder: 0)
        let strong = Topic(name: "Strong", status: .strong, needsReview: true, displayOrder: 0)
        let notReview = Topic(name: "Not review", status: .weak, needsReview: false, displayOrder: 0)

        let sorted = TopicAnalytics.needsReview(
            topics: [strong, good, weakStudied, needsWork, weakNever, notReview],
            lastStudied: [weakStudied.id: makeDate(2026, 8, 1)]
        )

        XCTAssertEqual(sorted.map(\.name), ["Weak never", "Weak studied", "Needs work", "Good", "Strong"])
    }

    func testSearchMatchesTopicModuleAndSubjectCaseInsensitively() {
        let maths = Subject(name: "Mathematics", targetPercentage: 1, displayOrder: 0)
        let pure = StudyModule(name: "Pure", displayOrder: 0, subject: maths)
        let integration = Topic(name: "Integration", displayOrder: 0, module: pure)
        let mechanics = StudyModule(name: "Mechanics", displayOrder: 1, subject: maths)
        let forces = Topic(name: "Forces", displayOrder: 0, module: mechanics)

        XCTAssertEqual(TopicAnalytics.search(topics: [forces, integration], query: "INTEGRATION").map(\.id), [integration.id])
        XCTAssertEqual(TopicAnalytics.search(topics: [forces, integration], query: "mechanics").map(\.id), [forces.id])
        XCTAssertEqual(TopicAnalytics.search(topics: [forces, integration], query: "mathematics").count, 2)
        XCTAssertTrue(TopicAnalytics.search(topics: [forces, integration], query: "chemistry").isEmpty)
    }

    func testRelativeStudyTextIsDeterministic() {
        let now = makeDate(2026, 8, 15)
        XCTAssertEqual(DateUtilities.relativeStudyText(nil, relativeTo: now, calendar: calendar), "Never studied")
        XCTAssertEqual(DateUtilities.relativeStudyText(makeDate(2026, 8, 15), relativeTo: now, calendar: calendar), "Studied today")
        XCTAssertEqual(DateUtilities.relativeStudyText(makeDate(2026, 8, 14), relativeTo: now, calendar: calendar), "Studied yesterday")
        XCTAssertEqual(DateUtilities.relativeStudyText(makeDate(2026, 8, 12), relativeTo: now, calendar: calendar), "Studied 3 days ago")
    }

    private func session(
        date: Date,
        minutes: Int,
        topic: Topic?,
        snapshot: String? = nil
    ) -> StudySession {
        StudySession(
            date: date,
            duration: TimeInterval(minutes * 60),
            activity: .revision,
            topic: topic,
            subjectNameSnapshot: "Mathematics",
            topicNameSnapshot: snapshot ?? topic?.name
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }
}
