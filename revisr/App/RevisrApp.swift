import SwiftData
import SwiftUI

@main
struct RevisrApp: App {
    private let container: ModelContainer
    private let persistenceInitializationFailed: Bool

    init() {
        do {
#if DEBUG
            if let url = try DebugUITestSupport.isolatedStoreURL() {
                container = try AppContainer.make(storeURL: url)
                DebugUITestSupport.installFixtureBankIfRequested()
            } else {
                container = try AppContainer.make()
            }
#else
            container = try AppContainer.make()
#endif
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
    @State private var settings: AppSettings?

    var body: some View {
        Group {
            if let settings {
                if settings.publicOnboardingStage != nil {
                    if settings.publicFlowVersion == 2 {
                        TMUAFlowRootView(settings: settings)
                    } else {
                        PublicPreparationSetupView(settings: settings)
                    }
                } else {
                    RootTabView()
                }
            } else if let startupError {
                ContentUnavailableView(
                    "Couldn’t Prepare Revisr",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupError.message)
                )
            } else {
                ProgressView("Preparing Revisr")
            }
        }
        .task {
            guard !didAttemptSeeding else { return }
            didAttemptSeeding = true

            do {
                let preparedSettings = try PerformanceProbe.measure("launch_seed_and_import") {
                    try SeedDataService.bootstrapForLaunch(in: modelContext)
                }
#if DEBUG
                try DebugTodayScenarioService.applyIfRequested(in: modelContext)
                try DebugPlanScenarioService.applyIfRequested(in: modelContext)
                try DebugProgressScenarioService.applyIfRequested(in: modelContext)
                try DebugTopicsScenarioService.applyIfRequested(in: modelContext)
                try DebugTMUAScenarioService.applyIfRequested(in: modelContext)
#endif
                settings = preparedSettings
            } catch {
                startupError = StartupError(message: error.localizedDescription)
            }
        }
    }
}

private struct StartupError {
    let message: String
}
