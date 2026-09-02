import SwiftUI

struct SolutionAccessView: View {
    let question: AdmissionsQuestion
    let resolutions: [QuestionSolutionResolution]
    @State private var selected: QuestionSolutionResolution?
    @State private var pending: QuestionSolutionResolution?
    @State private var requirement: SolutionRevealRequirement?

    var body: some View {
        Group {
            if let primary = resolutions.first {
                Button(primary.document.solutionType.actionTitle, systemImage: "checkmark.seal") {
                    request(primary)
                }
                if resolutions.count > 1 {
                    ForEach(Array(resolutions.dropFirst())) { resolution in
                        Button("View \(resolution.document.solutionType.title)", systemImage: "doc.text") {
                            request(resolution)
                        }
                    }
                }
            } else {
                Label("No direct solution mapping", systemImage: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(alertTitle, isPresented: Binding(
            get: { requirement != nil },
            set: { if !$0 { requirement = nil; pending = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button(confirmTitle, role: .destructive) {
                selected = pending
                pending = nil
                requirement = nil
            }
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $selected) { resolution in
            NavigationStack {
                SolutionMediaView(resolution: resolution)
                    .navigationTitle(resolution.document.solutionType.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func request(_ resolution: QuestionSolutionResolution) {
        let needed = SolutionLibraryService.revealRequirement(for: question)
        if needed == .none {
            selected = resolution
        } else {
            pending = resolution
            requirement = needed
        }
    }

    private var alertTitle: String {
        requirement == .protectedQuestion ? "Reveal Protected Solution?" : "View Before Attempting?"
    }

    private var alertMessage: String {
        if requirement == .protectedQuestion {
            return "This is a protected or future benchmark question. Revealing its solution may compromise a later timed attempt."
        }
        return "You have not recorded an attempt for this question. Reveal the solution anyway?"
    }

    private var confirmTitle: String {
        requirement == .protectedQuestion ? "Reveal Protected Solution" : "Reveal Solution"
    }
}
