import PDFKit
import SwiftData
import SwiftUI

struct AdmissionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @Query private var profiles: [AdmissionsTestProfile]
    @Query(filter: #Predicate<AdmissionsProgramme> { $0.isImportedActive })
    private var programmes: [AdmissionsProgramme]
    @Query(filter: #Predicate<SourceDocument> { $0.isImportedActive })
    private var sources: [SourceDocument]
    @Query(filter: #Predicate<SolutionDocument> { $0.isImportedActive })
    private var solutionDocuments: [SolutionDocument]
    @Query private var importStates: [AdmissionsImportState]

    var body: some View {
        NavigationStack {
            List {
                Section("Admissions Tests") {
                    ForEach(sortedProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.displayName).font(.headline)
                                Text(profile.kind == .tmua ? "Active preparation" : "Preparation starts after TMUA")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AdmissionsStatusBadge(
                                text: profile.status == .active ? "Active" : "Not started",
                                systemImage: profile.status == .active ? "checkmark.circle.fill" : "pause.circle",
                                tint: profile.status == .active ? RevisrColors.accentTeal : .secondary
                            )
                        }
                    }
                }

                Section("TMUA Programme") {
                    if let programme = programmes.first {
                        DatePicker(
                            "Start date",
                            selection: startDateBinding(programme),
                            displayedComponents: .date
                        )
                        NavigationLink {
                            ExamSettingsView(settings: settings)
                        } label: {
                            LabeledContent("Exam date", value: settings.tmuaExamDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                Section("Source Library") {
                    NavigationLink {
                        SourceLibraryView()
                    } label: {
                        LabeledContent("Source Papers", value: "\(availableSources) of \(sources.count) available")
                    }
                    NavigationLink {
                        SolutionBankView()
                    } label: {
                        LabeledContent("Solution Bank", value: "\(availableSolutions) of \(solutionDocuments.count) available")
                    }
                    Text("Question papers and solutions are stored locally within this private Revisr installation and are available offline. Revision exports still exclude PDF binaries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Admissions Metadata") {
                    LabeledContent("Questions", value: "\(importStates.first?.questionCount ?? 0)")
                    LabeledContent("Programme assignments", value: "\(importStates.first?.assignmentCount ?? 0)")
                    LabeledContent("Source records", value: "\(importStates.first?.sourceCount ?? 0)")
                    Text("Workbook metadata is imported deterministically during development; Revisr does not parse Excel files at launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    NavigationLink {
                        RevisionExportView()
                    } label: {
                        Label("Export Revision Data", systemImage: "square.and.arrow.up")
                    }
                    Text("Create local JSON or ZIP files for manual sharing and personal archival.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Label("No account, analytics, advertising, API, or cloud dependency", systemImage: "hand.raised")
                    Label("Core data and attempts remain on this iPhone", systemImage: "iphone")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var sortedProfiles: [AdmissionsTestProfile] {
        profiles.sorted {
            if $0.kind != $1.kind { return $0.kind == .tmua }
            return $0.displayName < $1.displayName
        }
    }

    private var settings: AppSettings {
        settingsRecords.first ?? AppSettings(appliedSeedVersion: SeedDataService.currentSeedVersion)
    }
    private var availableSources: Int {
        sources.filter { SourceLibraryService.bundledURL(for: $0) != nil }.count
    }
    private var availableSolutions: Int {
        solutionDocuments.filter { SolutionLibraryService.bundledURL(for: $0) != nil }.count
    }
    private func startDateBinding(_ programme: AdmissionsProgramme) -> Binding<Date> {
        Binding(
            get: { programme.startDate },
            set: { value in
                let start = Calendar.autoupdatingCurrent.startOfDay(for: value)
                programme.startDate = start
                settings.tmuaProgrammeStartDate = start
                try? modelContext.save()
            }
        )
    }
}

struct SourceLibraryView: View {
    @Query(filter: #Predicate<SourceDocument> { $0.isImportedActive }, sort: \SourceDocument.displayName)
    private var sources: [SourceDocument]

    var body: some View {
        List {
            Section {
                LabeledContent("Source Papers", value: "\(audit.resolvedCount) of \(audit.expectedCount) available")
                Text("The validated paper library is included in this private installation and works without setup or a network connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !audit.missingSourceIDs.isEmpty {
                    Text("Missing: \(audit.missingSourceIDs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(families, id: \.self) { family in
                Section(family) {
                    ForEach(sources.filter { $0.family == family }) { source in
                        SourceDocumentRow(source: source)
                    }
                }
            }
        }
        .navigationTitle("Source Papers")
    }

    private var families: [String] { Array(Set(sources.map(\.family))).sorted() }
    private var audit: SourceLibraryAudit {
        PerformanceProbe.measure("source_library_audit") {
            SourceLibraryService.audit(sources: sources)
        }
    }
}

private struct SourceDocumentRow: View {
    let source: SourceDocument

    var body: some View {
        NavigationLink {
            SourceDocumentDetailView(source: source)
        } label: {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                HStack {
                    Text(source.displayName).font(.headline)
                    Spacer()
                    Label(
                        availableURL != nil ? "Available" : "Missing",
                        systemImage: availableURL != nil ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(availableURL != nil ? RevisrColors.accentTeal : .secondary)
                }
                HStack {
                    Text("\(source.questionUnitCount) questions")
                    if let pages = displayedPageCount { Text("· \(pages) pages") }
                    if source.questions.contains(where: { $0.protection != .none }) { Text("· Protected") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows question paper and solution availability")
    }

    private var availableURL: URL? { SourceLibraryService.bundledURL(for: source) }
    private var displayedPageCount: Int? {
        PerformanceProbe.measure("source_row_pdf_open") {
            availableURL.flatMap { PDFDocument(url: $0)?.pageCount } ?? source.pageCount
        }
    }
}

private struct SourceDocumentDetailView: View {
    let source: SourceDocument
    @Query(filter: #Predicate<SolutionDocument> { $0.isImportedActive })
    private var documents: [SolutionDocument]
    @Query(filter: #Predicate<QuestionSolutionLink> { $0.isImportedActive })
    private var links: [QuestionSolutionLink]
    @State private var shownDocument: SolutionDocument?
    @State private var showsQuestionPaper = false

    var body: some View {
        List {
            Section("Local Resources") {
                Button("View Question Paper", systemImage: "doc.text.magnifyingglass") {
                    showsQuestionPaper = true
                }
                .disabled(questionPaperURL == nil)
                LabeledContent("Question Paper", value: questionPaperURL == nil ? "Unavailable" : "Available")
                LabeledContent("Solutions", value: status.title)
            }

            Section("Solutions") {
                if relatedDocuments.isEmpty {
                    Text("A matching local solution source has not been supplied yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedDocuments) { document in
                        Button {
                            if SolutionLibraryService.bundledURL(for: document) != nil {
                                shownDocument = document
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.solutionType.title).font(.headline)
                                Text("\(document.provenanceOrganization) · \(mappedCount(for: document)) question mappings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Paper") {
                LabeledContent("Questions", value: "\(source.questionUnitCount)")
                if let pages = source.pageCount { LabeledContent("Pages", value: "\(pages)") }
                if let year = source.year { LabeledContent("Year", value: "\(year)") }
                if let paper = source.paper { LabeledContent("Paper", value: paper) }
            }
        }
        .navigationTitle(source.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsQuestionPaper) {
            if let questionPaperURL {
                NavigationStack {
                    SourcePDFView(url: questionPaperURL, page: 1)
                        .navigationTitle("Question Paper")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .sheet(item: $shownDocument) { document in
            if let url = SolutionLibraryService.bundledURL(for: document) {
                NavigationStack {
                    SolutionMediaView(document: document, url: url)
                        .navigationTitle(document.solutionType.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private var questionPaperURL: URL? { SourceLibraryService.bundledURL(for: source) }
    private var relatedDocuments: [SolutionDocument] {
        documents.filter { $0.effectiveRelatedSourceIDs.contains(source.stableSourceID) }
            .sorted { $0.solutionType.preferenceOrder < $1.solutionType.preferenceOrder }
    }
    private var status: SolutionAvailability {
        SolutionLibraryService.availability(for: source, documents: documents, links: links)
    }
    private func mappedCount(for document: SolutionDocument) -> Int {
        links.filter { $0.solutionDocument?.stableSolutionID == document.stableSolutionID }.count
    }
}
