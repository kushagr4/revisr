import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            AdmissionsTodayView()
                .tabItem { Label("Today", systemImage: "house") }

            AdmissionsPlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }

            AdmissionsProgressView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            AdmissionsTopicsView()
                .tabItem { Label("Topics", systemImage: "list.bullet.rectangle") }

            AdmissionsSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(RevisrColors.accentTeal)
    }
}
