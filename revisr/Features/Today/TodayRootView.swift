import SwiftUI

struct TodayRootView: View {
    var body: some View {
        NavigationStack {
            TodayView()
        }
    }
}

#if DEBUG
#Preview("Normal Day") {
    NavigationStack { TodayView() }
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTodayContainer(scenario: .normal))
}

#Preview("Empty Day") {
    NavigationStack { TodayView() }
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTodayContainer(scenario: .empty))
}

#Preview("Completed Day") {
    NavigationStack { TodayView() }
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTodayContainer(scenario: .completed))
}

#Preview("Unavailable Day") {
    NavigationStack { TodayView() }
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTodayContainer(scenario: .unavailable))
}

#Preview("Dark Mode") {
    NavigationStack { TodayView() }
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTodayContainer(scenario: .normal))
        .preferredColorScheme(.dark)
}

#Preview("Accessibility Text") {
    NavigationStack { TodayView() }
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTodayContainer(scenario: .normal))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
