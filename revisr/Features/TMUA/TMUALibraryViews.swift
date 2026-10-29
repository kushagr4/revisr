import SwiftData
import SwiftUI

/// Papers filters (R5). The Questions tab keeps them, so they survive switching views.
struct TMUAPaperFilters: Equatable {
    var exam = ""
    var provider = ""
    var year = 0
    var solutionsOnly = false

    var isDefault: Bool { self == TMUAPaperFilters() }

    /// The examination a paper belongs to, for filtering: MAT and STEP apart, UKMT competitions together.
    static func exam(_ source: TMUAResourceSource) -> String {
        switch source.kind {
        case .officialTMUA: "TMUA (official)"
        case .independentMock: "TMUA mocks"
        case .competition: "UKMT competitions"
        case .reference: "Reference"
        case .otherAdmissionsTest: source.family
        }
    }
}

/// Papers & sources: the original Revisr collection in the new journey, labelled with what this
/// build may show and how each item can be practised.
struct TMUAResourceLibraryView: View {
    let settings: AppSettings
    let content: TMUAContentContext?
    /// Questions → Papers lists the linked sites under Sources instead.
    var showsSites = true
    /// Kept by the Questions tab; elsewhere the view keeps its own.
    var filters: Binding<TMUAPaperFilters>? = nil
    var reserved: Set<String> = []
    @Query private var logs: [TMUAResourceLog]
    @State private var ownFilters = TMUAPaperFilters()

    var body: some View {
        let binding = filters ?? $ownFilters
        let current = binding.wrappedValue
        let sources = TMUAResourceCatalogue.sources(distribution: content?.distribution ?? .public,
                                                     items: content?.eligibleItems ?? [])
        let shown = sources.filter { source in
            (current.exam.isEmpty || TMUAPaperFilters.exam(source) == current.exam)
                && (current.provider.isEmpty || source.provider.name == current.provider)
                && (current.year == 0 || source.year == current.year)
                && (!current.solutionsOnly || !source.solutions.isEmpty)
        }
        let mine = logs.filter { $0.profileSettingsID == settings.id }
        let started = Set(mine.map(\.sourceID))

        Section {
            TMUAFilterMenu(title: "Exam", selection: binding.exam, options: [.init(value: "", label: "All exams")]
                + orderedUnique(sources.map(TMUAPaperFilters.exam)).map { .init(value: $0, label: $0) }, identifier: "papers.exam")
            TMUAFilterMenu(title: "Publisher", selection: binding.provider, options: [.init(value: "", label: "All publishers")]
                + Array(Set(sources.map(\.provider.name))).sorted().map { .init(value: $0, label: $0) }, identifier: "papers.provider")
            TMUAFilterMenu(title: "Year", selection: binding.year, options: [.init(value: 0, label: "Any year")]
                + Array(Set(sources.compactMap(\.year))).sorted(by: >).map { .init(value: $0, label: String($0)) }, identifier: "papers.year")
            Toggle("Only papers with solutions", isOn: binding.solutionsOnly)
                .accessibilityIdentifier("papers.solutionsOnly")
            if !current.isDefault {
                Button("Clear filters", systemImage: "xmark.circle") { binding.wrappedValue = TMUAPaperFilters() }
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
                            TMUAResourceSourceView(settings: settings, source: source, content: content, reserved: reserved)
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

    /// How many of the paper's questions open in Revisr, and how they are marked. The paper's own
    /// question count is in its subtitle; this line says how many of those this build can show.
    private func accessLine(_ source: TMUAResourceSource) -> String {
        let total = source.questions.count
        switch source.access {
        case .studyCopy:
            let marking = source.solutions.isEmpty ? "no solutions in this build, so record your own results"
                : source.autoMarkedCount > 0 ? "\(source.autoMarkedCount) marked by Revisr, the rest self-marked"
                : "self-marked with its solutions"
            return total == 0 ? "Personal study copy" : "All \(total) open in Revisr (personal study copy) · \(marking)"
        case .providerLink:
            return (total == 0 ? "" : "None of the \(total) open in Revisr · ") + "on \(source.provider.name)’s website"
                + (source.solutions.isEmpty ? "" : " · solutions in your library")
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }
}

struct TMUAResourceSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let settings: AppSettings
    let source: TMUAResourceSource
    let content: TMUAContentContext?
    var reserved: Set<String> = []
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
            Text("Q\(question.label) · \(catalogue.entry(question.id)?.topicTitle(content?.syllabus) ?? question.topic)")
                .font(.subheadline)
            Text([question.difficultyLabel + " (estimated)", question.page.map { "page \($0)" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
        }
        if let entry = catalogue.entry(question.id) {
            TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content, reserved: reserved) {
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
    /// No default: saving needs an explicit result, so a task never completes on an untouched form.
    @State private var outcome: TMUAResourceOutcome?
    @State private var correct = 0
    @State private var minutes = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Result", selection: $outcome) {
                        Text("Choose a result").tag(TMUAResourceOutcome?.none)
                        ForEach(TMUAResourceOutcome.paperOutcomes, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    .accessibilityIdentifier("record.result")
                    if let questionCount {
                        Stepper("Correct by your marking: \(correct) / \(questionCount)", value: $correct, in: 0...questionCount)
                    }
                    Stepper(minutes == 0 ? "Time: not recorded" : "Time: \(minutes) min", value: $minutes, in: 0...240, step: 5)
                } footer: {
                    Text("You mark this yourself. The result is saved with the paper, which is then not set again in your plan; it is not used as evidence of topic mastery.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let outcome else { return }
                        onSave(outcome, questionCount == nil ? nil : correct, minutes == 0 ? nil : minutes)
                        dismiss()
                    }
                    .disabled(outcome == nil)
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
    @State private var openSolution: TMUAResourceSource.SolutionFile?
    @State private var errorMessage: String?

    var body: some View {
        let content = TMUAContentStore.context()
        let source = TMUAResourceCatalogue.sources(distribution: content?.distribution ?? .public,
                                                    items: content?.eligibleItems ?? []).first { $0.id == task.sourceID }
        // Questions in an open diagnostic round stay locked in the paper's detail.
        let reserved = (try? TMUADiagnosticService.load(settings: settings, in: modelContext))
            .map(TMUAProgrammeService.reservedStableIDs) ?? []
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
                            .accessibilityIdentifier("resource.openPaper")
                    }
                    // Solutions sit beside the paper, for marking once the attempt is done.
                    ForEach(source.solutions, id: \.resourceName) { file in
                        Button("Open \(file.title.lowercased())", systemImage: "lightbulb") { openSolution = file }
                    }
                    if let link = source.provider.link {
                        Button(source.provider.linkTitle ?? "Open \(source.provider.name)'s website", systemImage: "safari") {
                            openURL(link)
                        }
                    }
                    NavigationLink("Questions, solutions and details") {
                        TMUAResourceSourceView(settings: settings, source: source, content: content, reserved: reserved)
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
                Text("You mark this paper yourself. Your result completes the task and the paper is not set again; it is never used as evidence of topic mastery.")
            }
        }
        .navigationTitle(source?.title ?? "Paper practice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $openingPaper) {
            if let url = SourceLibraryServiceLookup.paperURL(task.sourceID) {
                NavigationStack { SourcePDFView(url: url, page: nil) }
            }
        }
        .sheet(item: $openSolution) { file in
            if let url = SourceLibraryServiceLookup.solutionURL(file) {
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

/// A planned topic worksheet: self-marked questions on one topic from papers in the library. The
/// student works through them in order, recording a result for each; the worksheet is finished
/// from those results, so its record always matches the work actually recorded (R5).
struct TMUAWorksheetTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings
    let task: PublicProgrammeTask
    @Query private var logs: [TMUAResourceLog]
    @State private var confirmingFinish = false
    @State private var errorMessage: String?

    var body: some View {
        let content = TMUAContentStore.context()
        let catalogue = TMUACatalogueStore.catalogue(content)
        let ids = TMUAProgrammeService.worksheetQuestionIDs(task.sourceID)
        let context = TMUAWorksheetContext(task: task, catalogue: catalogue)
        let entries = context.entries
        let mine = logs.filter { $0.profileSettingsID == settings.id }
        let progress = TMUAProgrammeService.worksheetProgress(task, logs: mine)
        let sources = entries.reduce(into: [String]()) { names, entry in
            let name = entry.provider?.name ?? entry.sourceTitle
            if !names.contains(name) { names.append(name) }
        }
        // The first question this build can show without a result; otherwise the first question.
        let resume = entries.first { progress.results[context.storedID($0)] == nil } ?? entries.first
        List {
            Section {
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Text("Topic worksheet · self-marked").font(.subheadline.weight(.semibold))
                        .foregroundStyle(RevisrColors.secondaryLabel)
                    Text("\(entries.count) question\(entries.count == 1 ? "" : "s") · about \(task.allocatedMinutes) minutes")
                        .font(.headline)
                    if !sources.isEmpty {
                        Text("From \(ListFormatter.localizedString(byJoining: sources))")
                            .font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    ProgressView(value: Double(progress.recorded), total: Double(max(1, entries.count)))
                        .tint(RevisrColors.accentTeal)
                        .accessibilityHidden(true)
                    Text(stateLine(progress)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(task.completedAt == nil ? RevisrColors.accentStrong : RevisrColors.success)
                        .accessibilityIdentifier("worksheet.state")
                }
                .accessibilityElement(children: .combine)
                .padding(.vertical, 4)
                if task.completedAt == nil, let resume {
                    NavigationLink {
                        TMUACatalogueQuestionView(settings: settings, entry: resume, catalogue: catalogue, content: content,
                                                  worksheet: context)
                    } label: {
                        Label(progress.recorded == 0 ? "Start with question 1"
                              : entries.allSatisfy({ progress.results[context.storedID($0)] != nil }) ? "Review your answers"
                              : "Continue with question \((entries.firstIndex { $0.id == resume.id } ?? 0) + 1)",
                              systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                    .accessibilityIdentifier("worksheet.continue")
                }
            } footer: {
                Text(task.reason)
            }
            Section("Questions") {
                if entries.isEmpty {
                    Text("These questions are not available in this build. Refresh your plan to replace this worksheet; completed work is unchanged.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                } else if entries.count < ids.count {
                    Text("\(ids.count - entries.count) of this worksheet’s questions are not in this build.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                    NavigationLink {
                        TMUACatalogueQuestionView(settings: settings, entry: entry, catalogue: catalogue, content: content,
                                                  worksheet: context)
                    } label: {
                        TMUAWorksheetQuestionRow(number: offset + 1, entry: entry, outcome: progress.results[context.storedID(entry)])
                    }
                }
            }
            Section {
                if let done = task.completedAt {
                    // The tick is decorative: VoiceOver would otherwise read it as "Selected".
                    Label {
                        Text("Finished \(done.formatted(date: .abbreviated, time: .omitted)) · \(task.completionNote)")
                            .accessibilityIdentifier("worksheet.done")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    }
                    .foregroundStyle(RevisrColors.success)
                    Button("Done", systemImage: "chevron.backward") { dismiss() }
                        .accessibilityIdentifier("worksheet.leave")
                } else {
                    Button("Finish the worksheet", systemImage: "checkmark.circle") {
                        if progress.unrecorded > 0 { confirmingFinish = true } else { finish() }
                    }
                    .disabled(!progress.canFinish)
                    .accessibilityIdentifier("worksheet.finish")
                }
            } footer: {
                Text(task.completedAt != nil ? "Your results are kept with each question. A question you marked incorrect or partly right can come back once in a later worksheet; none of it counts as evidence of topic mastery."
                     : progress.canFinish ? "Finishing completes this task with the results you recorded. Questions without a result are not counted as correct."
                     : "Record a result for at least one question to finish. You mark these yourself, and they never count as evidence of topic mastery.")
            }
        }
        .navigationTitle(task.topic)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Finish with \(progress.unrecorded) question\(progress.unrecorded == 1 ? "" : "s") unrecorded?",
                            isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("Finish the worksheet") { finish() }
            Button("Keep working", role: .cancel) {}
        } message: {
            Text("They stay unrecorded and are not counted as correct. Results you recorded are kept.")
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func stateLine(_ progress: TMUAWorksheetProgress) -> String {
        // A worksheet finished before R5 was recorded as a whole, not question by question.
        if task.completedAt != nil, progress.recorded == 0 { return "Completed · \(task.completionNote)" }
        return switch progress.state {
        case .notStarted: "Not started"
        case .inProgress: "In progress · \(progress.recorded) of \(progress.questionIDs.count) recorded"
        case .readyToFinish: "All recorded · \(progress.tally)"
        case .completed: "Completed · \(progress.tally)"
        case .completedWithGaps: "Completed with gaps · \(progress.tally)"
        }
    }

    private func finish() {
        do {
            try TMUAProgrammeService.finishWorksheet(task, settings: settings, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
