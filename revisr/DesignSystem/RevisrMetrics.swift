import CoreGraphics
import SwiftUI

enum RevisrMetrics {
    static let compactCornerRadius: CGFloat = 8
    static let standardCornerRadius: CGFloat = 12
    static let prominentCornerRadius: CGFloat = 18
    static let contentMargin: CGFloat = RevisrSpacing.standard
    static let minimumTapTarget: CGFloat = 44
    static let rowVerticalPadding: CGFloat = RevisrSpacing.compact
    static let cardPadding: CGFloat = RevisrSpacing.large
    static let progressHeight: CGFloat = 8
}

struct RevisrCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(RevisrMetrics.cardPadding)
            .background(RevisrColors.elevatedSurface, in: RoundedRectangle(
                cornerRadius: RevisrMetrics.prominentCornerRadius,
                style: .continuous
            ))
    }
}

struct RevisrStatusLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(RevisrTypography.label)
            .foregroundStyle(color)
            .padding(.horizontal, RevisrSpacing.compact)
            .padding(.vertical, RevisrSpacing.small)
            .background(color.opacity(0.12), in: Capsule())
    }
}
