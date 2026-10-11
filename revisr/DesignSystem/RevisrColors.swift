import SwiftUI

enum RevisrColors {
    static let accentTeal = Color("AccentColor")
    static let deepNavy = Color(red: 0.025, green: 0.10, blue: 0.25)

    static let tmua = Color(red: 0.12, green: 0.55, blue: 0.58)
    static let mathematics = Color(red: 0.33, green: 0.45, blue: 0.67)
    static let furtherMathematics = Color(red: 0.43, green: 0.37, blue: 0.63)

    static let background = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)
    static let tintedSurface = accentTeal.opacity(0.09)
    static let separator = Color(uiColor: .separator)
    static let primaryLabel = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let critical = Color(uiColor: .systemRed)

    static func subjectAccent(_ identifier: SubjectAccentID?) -> Color {
        switch identifier {
        case .tmua: tmua
        case .mathematics: mathematics
        case .furtherMathematics: furtherMathematics
        case nil: accentTeal
        }
    }
}
