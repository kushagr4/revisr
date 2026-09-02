import SwiftUI

struct PlanningConflictView: View {
    let conflict: PlanningConflict
    let day: Date

    var body: some View {
        Label(conflict.message(for: day), systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Planning warning. \(conflict.message(for: day))")
    }
}
