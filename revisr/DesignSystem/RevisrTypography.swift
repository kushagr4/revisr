import SwiftUI

enum RevisrTypography {
    static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let cardTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    static let metric = Font.system(.title, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.body
    static let bodyEmphasized = Font.body.weight(.semibold)
    static let supporting = Font.subheadline
    static let label = Font.system(.caption, design: .default, weight: .semibold)
    static let caption = Font.caption
    static let timer = Font.system(.largeTitle, design: .monospaced, weight: .medium)
}
