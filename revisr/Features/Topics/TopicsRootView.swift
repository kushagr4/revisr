import SwiftUI

struct TopicsRootView: View {
    var body: some View {
        NavigationStack {
            TopicsDashboardView()
                .navigationTitle("Topics")
        }
    }
}

#if DEBUG
#Preview("Topics Populated") {
    TopicsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTopicsContainer(scenario: .populated))
}

#Preview("No Needs Review") {
    TopicsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTopicsContainer(scenario: .noNeedsReview))
}

#Preview("Search Results") {
    NavigationStack {
        TopicsDashboardView(initialSearchText: "complex")
            .navigationTitle("Topics")
    }
    .environmentObject(AppPresentationState())
    .modelContainer(try! PreviewData.makeTopicsContainer(scenario: .populated))
}

#Preview("Topic Detail Studied") {
    let container = try! PreviewData.makeTopicsContainer(scenario: .populated)
    let topic = try! PreviewData.topic(named: "Complex Numbers", module: "CP1", in: container)
    NavigationStack { TopicDetailView(topic: topic) }
        .modelContainer(container)
}

#Preview("Topic Detail Never Studied") {
    let container = try! PreviewData.makeTopicsContainer(scenario: .neverStudied)
    let topic = try! PreviewData.topic(named: "Functions", module: "Pure", in: container)
    NavigationStack { TopicDetailView(topic: topic) }
        .modelContainer(container)
}

#Preview("Topics Dark") {
    TopicsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTopicsContainer(scenario: .populated))
        .preferredColorScheme(.dark)
}

#Preview("Topics Accessibility") {
    TopicsRootView()
        .environmentObject(AppPresentationState())
        .modelContainer(try! PreviewData.makeTopicsContainer(scenario: .populated))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
