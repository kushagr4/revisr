import Foundation

enum StudyDurationPreset: String, CaseIterable, Identifiable {
    case thirty
    case sixty
    case ninety
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirty: "30 min"
        case .sixty: "60 min"
        case .ninety: "90 min"
        case .custom: "Custom"
        }
    }

    var minutes: Int? {
        switch self {
        case .thirty: 30
        case .sixty: 60
        case .ninety: 90
        case .custom: nil
        }
    }

    static func matching(minutes: Int) -> StudyDurationPreset {
        allCases.first(where: { $0.minutes == minutes }) ?? .custom
    }
}
