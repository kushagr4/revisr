import Foundation

enum SubjectAccentID: String, Codable, CaseIterable, Sendable {
    case tmua
    case mathematics
    case furtherMathematics
}

enum TopicStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case strong
    case good
    case needsWork
    case weak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strong: "Strong"
        case .good: "Good"
        case .needsWork: "Needs Work"
        case .weak: "Weak"
        }
    }

    /// Explicit display ordering for the Needs Review list, not a mastery score.
    var reviewSortOrder: Int {
        switch self {
        case .weak: 0
        case .needsWork: 1
        case .good: 2
        case .strong: 3
        }
    }

    var systemImage: String {
        switch self {
        case .strong: "checkmark.seal"
        case .good: "circle"
        case .needsWork: "wrench.adjustable"
        case .weak: "arrow.down.circle"
        }
    }
}

enum StudyActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case questions
    case timedQuestions
    case pastPaper
    case mock
    case revision
    case recall
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .questions: "Questions"
        case .timedQuestions: "Timed Questions"
        case .pastPaper: "Past Paper"
        case .mock: "Mock"
        case .revision: "Revision"
        case .recall: "Recall"
        case .review: "Review"
        }
    }
}

enum PlannedBlockStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case completed
    case skipped
}

enum StudyTimerStatus: String, Codable, Sendable {
    case idle
    case running
    case paused
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    static let displayOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    var title: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

struct DayAvailability: Codable, Equatable, Identifiable, Sendable {
    var weekday: Weekday
    var isAvailable: Bool
    var startMinute: Int?

    var id: Weekday { weekday }

    init(weekday: Weekday, isAvailable: Bool, startMinute: Int? = nil) {
        self.weekday = weekday
        self.isAvailable = isAvailable
        self.startMinute = startMinute
    }
}
