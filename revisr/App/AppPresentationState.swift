import SwiftUI

enum AppTab: Hashable {
    case today
    case plan
    case progress
    case topics
    case settings
}

@MainActor
final class AppPresentationState: ObservableObject {
    @Published var isQuickStudyEntryPresented = false
    @Published var selectedTab: AppTab = .today

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--plan-demo")
            || ProcessInfo.processInfo.arguments.contains("--plan-unavailable")
            || ProcessInfo.processInfo.arguments.contains("--plan-tuesday")
            || ProcessInfo.processInfo.arguments.contains("--plan-open") {
            selectedTab = .plan
        }
        if ProcessInfo.processInfo.arguments.contains("--progress-demo")
            || ProcessInfo.processInfo.arguments.contains("--progress-open")
            || ProcessInfo.processInfo.arguments.contains("--progress-add-tmua")
            || ProcessInfo.processInfo.arguments.contains("--progress-add-alevel") {
            selectedTab = .progress
        }
        if ProcessInfo.processInfo.arguments.contains("--topics-demo")
            || ProcessInfo.processInfo.arguments.contains("--topics-open")
            || ProcessInfo.processInfo.arguments.contains("--topics-add")
            || ProcessInfo.processInfo.arguments.contains("--topics-detail")
            || ProcessInfo.processInfo.arguments.contains("--topics-search")
            || ProcessInfo.processInfo.arguments.contains("--topics-mathematics")
            || ProcessInfo.processInfo.arguments.contains("--topics-further")
            || ProcessInfo.processInfo.arguments.contains("--topics-tmua") {
            selectedTab = .topics
        }
        if ProcessInfo.processInfo.arguments.contains("--settings-open")
            || ProcessInfo.processInfo.arguments.contains("--settings-availability")
            || ProcessInfo.processInfo.arguments.contains("--settings-subjects")
            || ProcessInfo.processInfo.arguments.contains("--settings-subjects-invalid")
            || ProcessInfo.processInfo.arguments.contains("--settings-tmua")
            || ProcessInfo.processInfo.arguments.contains("--settings-exam")
            || ProcessInfo.processInfo.arguments.contains("--settings-weekly") {
            selectedTab = .settings
        }
#endif
    }

    func presentQuickStudyEntry() {
        isQuickStudyEntryPresented = true
    }

    func showToday() {
        selectedTab = .today
    }
}
