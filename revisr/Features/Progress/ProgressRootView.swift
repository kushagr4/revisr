import SwiftUI

struct ProgressRootView: View {
    var body: some View {
        NavigationStack {
            ProgressDashboardView()
                .navigationTitle("Progress")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
#Preview("Populated Week") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .populatedWeek))
}

#Preview("No Study") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .noStudy))
}

#Preview("Study, No Results") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .studyWithoutResults))
}

#Preview("One TMUA Result") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .oneTMUAResult))
}

#Preview("Several TMUA Results") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .severalTMUAResults))
}

#Preview("Progress Dark") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .populatedWeek))
        .preferredColorScheme(.dark)
}

#Preview("Progress Accessibility") {
    ProgressRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeProgressContainer(scenario: .populatedWeek))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
