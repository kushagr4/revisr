import SwiftData
import SwiftUI

/// Papers & sources: the original Revisr collection in the new journey, labelled with what this
/// build may show and how each item can be practised.
struct TMUAResourceLibraryView: View {
    let settings: AppSettings
    let content: TMUAContentContext?
    /// Questions → Papers lists the linked sites under Sources instead.
    var showsSites = true
    @Query private var logs: [TMUAResourceLog]
    @State private var kind: String = ""
    @State private var provider: String = ""

    var body: some View {
        let sources = TMUAResourceCatalogue.sources(distribution: content?.distribution ?? .public,
                                                     items: content?.eligibleItems ?? [])
        let providers = Array(Set(sources.map(\.provider.name))).sorted()
        let shown = sources.filter { source in
            (kind.isEmpty || source.kind.rawValue == kind) && (provider.isEmpty || source.provider.name == provider)
        }
        let mine = logs.filter { $0.profileSettingsID == settings.id }
        let started = Set(mine.map(\.sourceID))

        Section {
            Picker("Type", selection: $kind) {
                Text("All types").tag("")
                ForEach(TMUAResourceProvider.Kind.allCases, id: \.rawValue) { kind in
                    if sources.contains(where: { $0.kind == kind }) { Text(kind.title).tag(kind.rawValue) }
                }
            }
            Picker("Source", selection: $provider) {
                Text("All sources").tag("")
                ForEach(providers, id: \.self) { Text($0).tag($0) }
            }
        } footer: {
            Text(content?.distribution == .internal
                 ? "Development build: papers from your own library are shown as personal study copies. They are not licensed for distribution and never appear in a public build. Official TMUA questions whose answer has been read from the official worked solutions are marked automatically (keys not yet checked by a person); everything else is self-marked."
                 : "Papers are listed with their publisher and open on the publisher's own website. Revisr does not reproduce them, and results you record yourself are not used as evidence of mastery.")
        }
        if shown.isEmpty {
            Section { Text("No papers match these filters.").foregroundStyle(RevisrColors.secondaryLabel) }
        }
        ForEach(TMUAResourceProvider.Kind.allCases, id: \.rawValue) { group in
            let rows = shown.filter { $0.kind == group }
            if !rows.isEmpty {
                Section(group.title) {
                    ForEach(rows) { source in
                        NavigationLink {
                            TMUAResourceSourceView(settings: settings, source: source, content: content)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(source.title).font(.subheadline.weight(.semibold))
                                    if started.contains(source.id) {
                                        Image(systemName: "checkmark.circle").foregroundStyle(RevisrColors.success)
                                            .accessibilityLabel("Started")
                                    }
                                }
                                Text(source.subtitle).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                                Text(accessLine(source)).font(.caption2).foregroundStyle(RevisrColors.secondaryLabel)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityIdentifier("library.source")
                    }
                }
            }
        }
        let sites = showsSites ? TMUAResourceCatalogue.linkedProviders(TMUAResourceRegistry.bundled()) : []
        if !sites.isEmpty {
            Section {
                ForEach(sites, id: \.key) { site in
                    if let link = site.link {
                        Link(destination: link) {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(site.linkTitle ?? site.name, systemImage: "safari")
                                    .font(.subheadline.weight(.semibold))
                                Text(site.terms).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                            }
                        }
                        .accessibilityHint("Opens \(site.name)'s website in Safari")
                        .accessibilityIdentifier("library.site")
                    }
                }
            } header: {
                Text("Other preparation sites")
            } footer: {
                Text("Independent sites, not affiliated with Revisr. Some of their materials are paid. Revisr links to them and does not reproduce their papers.")
            }
        }
    }

    private func accessLine(_ source: TMUAResourceSource) -> String {
        switch source.access {
        case .studyCopy:
            source.autoMarkedCount > 0
                ? "Personal study copy · \(source.autoMarkedCount) auto-marked from the official solutions"
                : "Personal study copy · self-marked"
        case .providerLink:
            source.solutions.isEmpty ? "Opens on \(source.provider.name)'s website · self-marked"
                : "Opens on \(source.provider.name)'s website · solutions in your library"
        }
    }
}

struct TMUAResourceSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let settings: AppSettings
    let source: TMUAResourceSource
    let content: TMUAContentContext?
    @Query private var logs: [TMUAResourceLog]
    @Query private var attempts: [TMUAPracticeAttempt]
    @State private var openPage: Int??
    @State private var openSolution: TMUAResourceSource.SolutionFile?
    @State private var recordingPaper = false
    @State private var errorMessage: String?

    var body: some View {
        let mine = logs.filter { $0.profileSettingsID == settings.id && $0.sourceID == source.id }
        let practised = Dictionary(grouping: attempts.filter { $0.profileSettingsID == settings.id }, by: \.itemStableID)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.title).font(.title3.weight(.semibold))
                    Text("Source: \(source.provider.credit)").font(.subheadline)
                        .accessibilityIdentifier("library.credit")
                    Text(source.kind.title + (source.year.map { " · \($0)" } ?? ""))
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    if let correction = source.labelCorrection {
                        Text("Label corrected: \(correction).").font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    if let note = source.holdingNote {
                        Text(note).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                }
                .accessibilityElement(children: .combine)
                if source.access == .studyCopy, SourceLibraryServiceLookup.paperURL(source.id) != nil {
                    Button("Open the paper", systemImage: "doc.text") { openPage = .some(nil) }
                        .accessibilityIdentifier("library.openPaper")
                }
                ForEach(source.solutions, id: \.resourceName) { file in
                    Button("Open \(file.title.lowercased())", systemImage: "lightbulb") {
                        openSolution = file
                    }
                }
                if let link = source.provider.link {
                    Button(source.provider.linkTitle ?? "Open \(source.provider.name)'s website", systemImage: "safari") {
                        openURL(link)
                    }
                    .accessibilityHint("Opens the publisher's page in Safari")
                    .accessibilityIdentifier("library.providerLink")
                }
                Button("Record a whole-paper result", systemImage: "square.and.pencil") { recordingPaper = true }
                    .accessibilityIdentifier("library.recordPaper")
            } footer: {
                Text(source.access == .studyCopy
                     ? "Personal study copy from your own library, shown in this development build only. \(source.provider.terms)"
                     : "\(source.provider.terms) Revisr links to the publisher and does not reproduce the paper.")
            }
            if let paper = mine.filter({ $0.questionID == nil }).max(by: { $0.recordedAt < $1.recordedAt }) {
                Section("Your last whole-paper result") {
                    Text(paperSummary(paper)).font(.subheadline)
                }
            }
            if !source.questions.isEmpty {
                Section {
                    ForEach(source.questions) { question in
                        questionRow(question, logs: mine, practised: practised)
                    }
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Topics and difficulty come from the original Revisr library index and are estimates, not calibrated ratings. Self-recorded results track your progress but are never used as evidence of mastery.")
                }
            }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { openPage.map { PageRoute(page: $0) } }, set: { if $0 == nil { openPage = nil } })) { route in
            if let url = SourceLibraryServiceLookup.paperURL(source.id) {
                NavigationStack { SourcePDFView(url: url, page: route.page) }
            }
        }
        .sheet(item: $openSolution) { file in
            if let url = SourceLibraryServiceLookup.solutionURL(file) {
                NavigationStack { SourcePDFView(url: url, page: nil) }
            }
        }
        .sheet(isPresented: $recordingPaper) {
            TMUARecordResultSheet(title: source.title, questionCount: source.questions.isEmpty ? nil : source.questions.count) { outcome, correct, minutes in
                record(questionID: nil, outcome: outcome, correct: correct, minutes: minutes)
            }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private func questionRow(_ question: TMUAResourceQuestion, logs: [TMUAResourceLog],
                             practised: [String: [TMUAPracticeAttempt]]) -> some View {
        let catalogue = TMUACatalogueStore.catalogue(content)
        let detail = VStack(alignment: .leading, spacing: 2) {
            Text("Q\(question.label) · \(question.topic)").font(.subheadline)
            Text([question.difficultyLabel + " (estimated)", question.page.map { "page \($0)" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
        }
        if let entry = catalogue.entry(question.id) {
            TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        detail
                        if entry.id != question.id {
                            // A reprint: one identity, so it is never practised twice as fresh.
                            Text("Same question as \(entry.sourceTitle) · Q\(entry.label ?? "")")
                                .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                        }
                    }
                    Spacer()
                    Text(status(entry, question: question, logs: logs, practised: practised))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.answerMode == .automatic ? RevisrColors.accentStrong : RevisrColors.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
            }
        } else {
            detail
        }
    }

    private func status(_ entry: TMUACatalogueEntry, question: TMUAResourceQuestion, logs: [TMUAResourceLog],
                        practised: [String: [TMUAPracticeAttempt]]) -> String {
        if let item = entry.item {
            let history = practised[item.stableId] ?? []
            guard let last = history.max(by: { $0.attemptedAt < $1.attemptedAt }) else { return "Auto-marked" }
            return last.isCorrect ? "Correct" : "Incorrect"
        }
        let ids = Set([entry.id] + entry.aliases)
        return logs.filter { ids.contains($0.questionID ?? "") }.max { $0.recordedAt < $1.recordedAt }?.outcome.title ?? ""
    }

    private func paperSummary(_ log: TMUAResourceLog) -> String {
        var parts = [log.outcome.title]
        if let correct = log.correctCount, let total = log.questionCount { parts.append("\(correct) / \(total) by your marking") }
        if let minutes = log.minutes { parts.append("\(minutes) min") }
        parts.append(log.recordedAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private func record(questionID: String?, outcome: TMUAResourceOutcome, correct: Int? = nil, minutes: Int? = nil) {
        modelContext.insert(TMUAResourceLog(profileSettingsID: settings.id, sourceID: source.id, questionID: questionID,
                                            outcome: outcome, correctCount: correct,
                                            questionCount: questionID == nil && !source.questions.isEmpty ? source.questions.count : nil,
                                            minutes: minutes))
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private struct PageRoute: Identifiable {
        let page: Int?
        var id: Int { page ?? 0 }
    }
}

extension TMUAResourceSource.SolutionFile: Identifiable {
    var id: String { resourceName }
}

/// Self-recorded result for a question or a whole paper Revisr cannot mark.
struct TMUARecordResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Set for a whole-paper result.
    let questionCount: Int?
    let onSave: (TMUAResourceOutcome, Int?, Int?) -> Void
    @State private var outcome: TMUAResourceOutcome = .attempted
    @State private var correct = 0
    @State private var minutes = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Result", selection: $outcome) {
                        ForEach(TMUAResourceOutcome.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if let questionCount {
                        Stepper("Correct by your marking: \(correct) / \(questionCount)", value: $correct, in: 0...questionCount)
                    }
                    Stepper(minutes == 0 ? "Time: not recorded" : "Time: \(minutes) min", value: $minutes, in: 0...240, step: 5)
                } footer: {
                    Text("You mark this yourself. It updates your progress and your plan, but it is not used as evidence of topic mastery.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(outcome, questionCount == nil ? nil : correct, minutes == 0 ? nil : minutes)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A planned paper session: open the paper from the library (or on the publisher's site), then
/// record a self-marked result to complete the task.
struct TMUAResourceTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let settings: AppSettings
    let task: PublicProgrammeTask
    @State private var recording = false
    @State private var openingPaper = false
    @State private var errorMessage: String?

    var body: some View {
        let content = TMUAContentStore.context()
        let source = TMUAResourceCatalogue.sources(distribution: content?.distribution ?? .public,
                                                    items: content?.eligibleItems ?? []).first { $0.id == task.sourceID }
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(task.activity.title) · \(task.allocatedMinutes) minutes").font(.subheadline.weight(.semibold))
                    Text(task.reason).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            if let source {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.title).font(.headline)
                        Text("Source: \(source.provider.credit)").font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    if source.access == .studyCopy, SourceLibraryServiceLookup.paperURL(source.id) != nil {
                        Button("Open the paper", systemImage: "doc.text") { openingPaper = true }
                    }
                    if let link = source.provider.link {
                        Button(source.provider.linkTitle ?? "Open \(source.provider.name)'s website", systemImage: "safari") {
                            openURL(link)
                        }
                    }
                    NavigationLink("Questions, solutions and details") {
                        TMUAResourceSourceView(settings: settings, source: source, content: content)
                    }
                }
            } else {
                Section {
                    Text("This paper is not available in this build. Refresh your plan to replace it; completed work is unchanged.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            Section {
                if let done = task.completedAt {
                    Label("Done \(done.formatted(date: .abbreviated, time: .omitted)) · \(task.completionNote)",
                          systemImage: "checkmark.circle.fill").foregroundStyle(RevisrColors.success)
                } else {
                    Button("Record my result", systemImage: "square.and.pencil") { recording = true }
                        .disabled(source == nil)
                        .accessibilityIdentifier("resource.record")
                }
            } footer: {
                Text("You mark this paper yourself. The result counts towards your progress and plan, but not as evidence of topic mastery.")
            }
        }
        .navigationTitle(source?.title ?? "Paper practice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $openingPaper) {
            if let url = SourceLibraryServiceLookup.paperURL(task.sourceID) {
                NavigationStack { SourcePDFView(url: url, page: nil) }
            }
        }
        .sheet(isPresented: $recording) {
            TMUARecordResultSheet(title: source?.title ?? "Paper", questionCount: source.map { $0.questions.isEmpty ? nil : $0.questions.count } ?? nil) { outcome, correct, minutes in
                do {
                    try TMUAProgrammeService.completeResourceSession(task, outcome: outcome, correct: correct,
                        questionCount: source.map(\.questions.count), minutes: minutes, settings: settings, in: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

/// A planned topic worksheet (R4): self-marked questions on one topic from papers in the library.
/// Each question opens at its page; the worksheet completes with the student's own result.
struct TMUAWorksheetTaskView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let task: PublicProgrammeTask
    @Query private var attempts: [TMUAPracticeAttempt]
    @Query private var logs: [TMUAResourceLog]
    @Query private var flags: [TMUAReviewFlag]
    @State private var recording = false
    @State private var errorMessage: String?

    var body: some View {
        let content = TMUAContentStore.context()
        let catalogue = TMUACatalogueStore.catalogue(content)
        let entries = TMUAProgrammeService.worksheetQuestionIDs(task.sourceID).compactMap(catalogue.entry)
        let progress = TMUACatalogueProgress(settings: settings, attempts: attempts, logs: logs, flags: flags)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(task.activity.title) · \(task.allocatedMinutes) minutes").font(.subheadline.weight(.semibold))
                    Text(task.reason).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            Section("\(entries.count) question\(entries.count == 1 ? "" : "s")") {
                if entries.isEmpty {
                    Text("These questions are not available in this build. Refresh your plan to replace this worksheet; completed work is unchanged.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                }
                ForEach(entries) { entry in
                    TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content) {
                        TMUACatalogueRow(entry: entry, progress: progress, syllabus: content?.syllabus)
                    }
                }
            }
            Section {
                if let done = task.completedAt {
                    Label("Done \(done.formatted(date: .abbreviated, time: .omitted)) · \(task.completionNote)",
                          systemImage: "checkmark.circle.fill").foregroundStyle(RevisrColors.success)
                } else {
                    Button("Record my result", systemImage: "square.and.pencil") { recording = true }
                        .disabled(entries.isEmpty)
                        .accessibilityIdentifier("worksheet.record")
                }
            } footer: {
                Text("You mark these questions yourself. Your result counts towards your progress and plan, but not as evidence of topic mastery.")
            }
        }
        .navigationTitle(task.topic)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $recording) {
            TMUARecordResultSheet(title: task.topic, questionCount: entries.count) { outcome, correct, minutes in
                do {
                    try TMUAProgrammeService.completeResourceSession(task, outcome: outcome, correct: correct,
                        questionCount: entries.count, minutes: minutes, settings: settings, in: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
