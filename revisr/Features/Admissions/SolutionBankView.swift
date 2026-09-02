import SwiftData
import SwiftUI

struct SolutionBankView: View {
    @Query(filter: #Predicate<SourceDocument> { $0.isImportedActive }, sort: \SourceDocument.displayName)
    private var sources: [SourceDocument]
    @Query(filter: #Predicate<SolutionDocument> { $0.isImportedActive }, sort: \SolutionDocument.displayName)
    private var documents: [SolutionDocument]
    @Query(filter: #Predicate<QuestionSolutionLink> { $0.isImportedActive })
    private var links: [QuestionSolutionLink]

    var body: some View {
        List {
            Section("Coverage") {
                LabeledContent("Available", value: "\(statusCount(.available)) papers")
                LabeledContent("Partial", value: "\(statusCount(.partial)) papers")
                LabeledContent("Pending source", value: "\(statusCount(.pendingSource)) papers")
                LabeledContent("Question mappings", value: "\(links.count) of \(questionCount)")
                Text("Coverage is calculated from the installed local resources. A partial paper has a source-level solution section but no reliable direct page for every question.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !pendingGroups.isEmpty {
                Section("Pending Local Sources") {
                    ForEach(pendingGroups, id: \.name) { group in
                        LabeledContent(group.name, value: "\(group.sources.count) papers · \(group.questions) questions")
                    }
                }
            }

            ForEach(families, id: \.self) { family in
                Section(family) {
                    ForEach(documents.filter { $0.family == family }) { document in
                        SolutionDocumentRow(document: document)
                    }
                }
            }
        }
        .navigationTitle("Solution Bank")
    }

    private var questionSources: [SourceDocument] { sources.filter { $0.questionUnitCount > 0 } }
    private var questionCount: Int { questionSources.reduce(0) { $0 + $1.questionUnitCount } }
    private var families: [String] { Array(Set(documents.map(\.family))).sorted() }

    private func status(for source: SourceDocument) -> SolutionAvailability {
        PerformanceProbe.measure("solution_bank_source_status") {
            SolutionLibraryService.availability(for: source, documents: documents, links: links)
        }
    }

    private func statusCount(_ value: SolutionAvailability) -> Int {
        questionSources.filter { status(for: $0) == value }.count
    }

    private var pendingGroups: [(name: String, sources: [SourceDocument], questions: Int)] {
        let pending = questionSources.filter { status(for: $0) == .pendingSource }
        return Dictionary(grouping: pending, by: pendingName)
            .map { (name: $0.key, sources: $0.value, questions: $0.value.reduce(0) { $0 + $1.questionUnitCount }) }
            .sorted { $0.name < $1.name }
    }

    private func pendingName(for source: SourceDocument) -> String {
        if source.family == "TMUA Mock", (source.paper ?? "").hasPrefix("Yotta") { return "Yotta" }
        return source.family
    }
}

private struct SolutionDocumentRow: View {
    let document: SolutionDocument
    @State private var showsMedia = false

    var body: some View {
        Button {
            if url != nil { showsMedia = true }
        } label: {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                HStack {
                    Text(document.displayName).font(.headline)
                    Spacer()
                    Image(systemName: url == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(url == nil ? .secondary : RevisrColors.accentTeal)
                }
                Text("\(document.solutionType.title) · \(document.provenanceOrganization)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if document.effectiveRelatedSourceIDs.isEmpty {
                    Text("Catalogued locally · no matching question paper in this bank")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .sheet(isPresented: $showsMedia) {
            if let url {
                NavigationStack {
                    SolutionMediaView(document: document, url: url)
                        .navigationTitle(document.solutionType.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private var url: URL? { SolutionLibraryService.bundledURL(for: document) }
}
