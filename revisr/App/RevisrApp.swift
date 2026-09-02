import SwiftData
import SwiftUI

@main
struct RevisrApp: App {
    private let container: ModelContainer
    private let persistenceInitializationFailed: Bool

    init() {
        do {
            container = try AppContainer.make()
            persistenceInitializationFailed = false
        } catch {
            do {
                container = try AppContainer.make(isStoredInMemoryOnly: true)
                persistenceInitializationFailed = true
            } catch {
                fatalError("Unable to create the Revisr model container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if persistenceInitializationFailed {
                PersistenceUnavailableView()
            } else {
                StartupView()
            }
        }
        .modelContainer(container)
    }
}

private struct PersistenceUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Open Your Data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your existing study data has not been changed. Quit and reopen Revisr. If this continues, keep the app installed so the local data is not deleted.")
        }
    }
}

private struct StartupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var didAttemptSeeding = false
    @State private var startupError: StartupError?

    var body: some View {
        RootTabView()
            .task {
                guard !didAttemptSeeding else { return }
                didAttemptSeeding = true

                do {
                    try PerformanceProbe.measure("launch_seed_and_import") {
                        try SeedDataService.seedIfNeeded(in: modelContext)
                    }
#if DEBUG
                    try DebugTodayScenarioService.applyIfRequested(in: modelContext)
                    try DebugPlanScenarioService.applyIfRequested(in: modelContext)
                    try DebugProgressScenarioService.applyIfRequested(in: modelContext)
                    try DebugTopicsScenarioService.applyIfRequested(in: modelContext)
#endif
                } catch {
                    startupError = StartupError(message: error.localizedDescription)
                }
            }
            .alert(item: $startupError) { error in
                Alert(
                    title: Text("Couldn’t Prepare Revisr"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }
}

private struct StartupError: Identifiable {
    let id = UUID()
    let message: String
}
