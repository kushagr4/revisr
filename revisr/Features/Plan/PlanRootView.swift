import SwiftUI

struct PlanRootView: View {
    let initialDate: Date

    init(initialDate: Date = .now) {
        self.initialDate = initialDate
    }

    var body: some View {
        NavigationStack {
            PlanView(initialDate: initialDate)
        }
    }
}

#if DEBUG
#Preview("Normal Monday") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .normalMonday))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .normalMonday))
}

#Preview("Tuesday after 14:00") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .tuesday))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .tuesday))
}

#Preview("Unavailable Thursday") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .unavailableThursday))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .unavailableThursday))
}

#Preview("Unavailable Exception") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .unavailableException))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .unavailableException))
}

#Preview("Mixed Status") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .mixedStatus))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .mixedStatus))
}

#Preview("Empty Future Week") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .emptyFutureWeek))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .emptyFutureWeek))
}

#Preview("Plan Dark") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .normalMonday))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .normalMonday))
        .preferredColorScheme(.dark)
}

#Preview("Plan Accessibility") {
    PlanRootView(initialDate: PreviewData.planPreviewDate(for: .normalMonday))
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makePlanContainer(scenario: .normalMonday))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
