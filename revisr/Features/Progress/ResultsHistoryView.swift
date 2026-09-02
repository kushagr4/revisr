import SwiftData
import SwiftUI

struct ResultsHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\StudyResult.date, order: .reverse)]) private var allResults: [StudyResult]

    let kind: StudyResultKind
    @State private var editingResult: StudyResult?

    private var results: [StudyResult] {
        switch kind {
        case .tmua: ProgressAnalytics.tmuaResults(from: allResults)
        case .aLevel: ProgressAnalytics.aLevelResults(from: allResults)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    ProgressEmptyRow(
                        title: "No results",
                        message: "Results you add will appear here.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                } else {
                    ForEach(results) { result in
                        Button {
                            editingResult = result
                        } label: {
                            StudyResultRow(result: result, kind: kind)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(kind == .tmua ? "TMUA History" : "A-Level History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingResult) { result in
                StudyResultEditorView(kind: kind, result: result)
            }
            .tint(RevisrColors.accentTeal)
        }
    }
}
