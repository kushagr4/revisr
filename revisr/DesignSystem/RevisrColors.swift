import SwiftUI

enum RevisrColors {
    static let accentTeal = Color("AccentColor")
    /// A darker teal for filled controls with white text and for tinted text
    /// on light backgrounds; meets WCAG contrast where `accentTeal` does not.
    static let accentStrong = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.62, blue: 0.60, alpha: 1)
            : UIColor(red: 0.03, green: 0.45, blue: 0.45, alpha: 1)
    })
    /// Teal for filled controls carrying white text (selected chips, answer
    /// badges, prominent buttons). Same as `accentStrong` in light mode; darker
    /// in dark mode, where `accentStrong` gives white text only about 3.3:1.
    /// `accentStrong` stays the tint for teal text on dark backgrounds.
    static let accentFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.0, green: 0.47, blue: 0.45, alpha: 1)
            : UIColor(red: 0.03, green: 0.45, blue: 0.45, alpha: 1)
    })
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
    // In light mode the system secondary label (about 3.5:1 on white) and the
    // system green, orange and red (about 2–3.6:1) fall short of WCAG AA for
    // text, which the R1 accessibility audit flagged. Darker light-mode values
    // keep the same hues; dark mode keeps the system colours.
    static let secondaryLabel = adaptive(light: UIColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1),
                                         dark: .secondaryLabel)
    static let success = adaptive(light: UIColor(red: 0.12, green: 0.47, blue: 0.20, alpha: 1), dark: .systemGreen)
    static let warning = adaptive(light: UIColor(red: 0.69, green: 0.31, blue: 0.0, alpha: 1), dark: .systemOrange)
    static let critical = adaptive(light: UIColor(red: 0.76, green: 0.15, blue: 0.11, alpha: 1), dark: .systemRed)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func subjectAccent(_ identifier: SubjectAccentID?) -> Color {
        switch identifier {
        case .tmua: tmua
        case .mathematics: mathematics
        case .furtherMathematics: furtherMathematics
        case nil: accentTeal
        }
    }
}
