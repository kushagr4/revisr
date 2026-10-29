import SwiftData
import SwiftUI

/// What a student has done with a catalogue question: auto-marked attempts for native questions,
/// self-recorded results for the rest, and review flags for either.
@MainActor
struct TMUACatalogueProgress {
    enum Status: String, CaseIterable {
        case all, notAttempted, attempted, needsReview, flagged

        var title: String {
            switch self {
            case .all: "Any status"
            case .notAttempted: "Not attempted"
            case .attempted: "Attempted"
            case .needsReview: "Incorrect or partly right last time"
            case .flagged: "Flagged for review"
            }
        }
    }

    let attempts: [String: [TMUAPracticeAttempt]]
    let logs: [String: [TMUAResourceLog]]
    let flagged: Set<String>

    init(settings: AppSettings, attempts: [TMUAPracticeAttempt], logs: [TMUAResourceLog], flags: [TMUAReviewFlag]) {
        self.attempts = Dictionary(grouping: attempts.filter { $0.profileSettingsID == settings.id }, by: \.itemStableID)
        self.logs = Dictionary(grouping: logs.filter { $0.profileSettingsID == settings.id && $0.questionID != nil },
                               by: { $0.questionID ?? "" })
        flagged = Set(flags.filter { $0.profileSettingsID == settings.id && $0.isFlagged }.map(\.itemStableID))
    }

    func history(_ entry: TMUACatalogueEntry) -> [TMUAPracticeAttempt] {
        entry.item.map { attempts[$0.stableId] ?? [] } ?? []
    }

    func recorded(_ entry: TMUACatalogueEntry) -> [TMUAResourceLog] {
        ([entry.id] + entry.aliases).flatMap { logs[$0] ?? [] }
    }

    func isFlagged(_ entry: TMUACatalogueEntry) -> Bool {
        // Any identity counts: the item ID for questions Revisr marks, the catalogue ID or a merged reprint otherwise.
        ([entry.id] + entry.aliases).contains(where: flagged.contains)
    }

    func lastActivity(_ entry: TMUACatalogueEntry) -> Date? {
        (history(entry).map(\.attemptedAt) + recorded(entry).map(\.recordedAt)).max()
    }

    /// "Correct", "Incorrect", "Partly right", "Attempted" or nil when untouched.
    func lastOutcome(_ entry: TMUACatalogueEntry) -> String? {
        if let attempt = history(entry).max(by: { $0.attemptedAt < $1.attemptedAt }) {
            return attempt.isCorrect ? "Correct" : "Incorrect"
        }
        return recorded(entry).max { $0.recordedAt < $1.recordedAt }?.outcome.title
    }

    func matches(_ entry: TMUACatalogueEntry, _ status: Status) -> Bool {
        switch status {
        case .all: true
        case .notAttempted: lastActivity(entry) == nil
        case .attempted: lastActivity(entry) != nil
        case .needsReview: ["Incorrect", "Partly right"].contains(lastOutcome(entry) ?? "")
        case .flagged: isFlagged(entry)
        }
    }
}

/// Questions → Practice: every question this build can open, with filters. Auto-marked questions
/// open in Revisr's practice screen; the rest open at their page in the paper and are self-marked.
struct TMUACataloguePracticeList: View {
    let settings: AppSettings
    let content: TMUAContentContext?
    let catalogue: TMUAQuestionCatalogue
    let progress: TMUACatalogueProgress
    /// Questions waiting in an unsubmitted diagnostic section: hidden so practice cannot reveal them.
    let reserved: Set<String>
    @State private var paper = 0
    @State private var topic = ""
    @State private var strand = ""
    @State private var source = ""
    @State private var difficulty = 0
    @State private var marking = ""
    @State private var status: TMUACatalogueProgress.Status = .all

    static let outsideSpecification = "outside"

    var body: some View {
        let pool = catalogue.practicable.filter { entry in !(entry.item.map { reserved.contains($0.stableId) } ?? false) }
        let sources = Array(Set(pool.map(\.sourceGroup))).sorted()
        let shown = pool.filter { entry in
            (paper == 0 || entry.paperFit.includes(paper == 1 ? .one : .two))
                && (topic.isEmpty || (topic == Self.outsideSpecification ? entry.topicKey == nil : entry.topicKey == topic))
                // Strands are known only for questions Revisr marks.
                && (strand.isEmpty || entry.item?.taxonomy.strand == strand)
                && (source.isEmpty || entry.sourceGroup == source)
                && (difficulty == 0 || entry.difficulty == difficulty)
                && (marking.isEmpty || entry.answerMode.rawValue == marking)
                && progress.matches(entry, status)
        }
        .sorted(by: Self.order)

        Section {
            Picker("Paper", selection: $paper) {
                Text("All").tag(0); Text("Paper 1").tag(1); Text("Paper 2").tag(2)
            }
            .pickerStyle(.segmented)
            Picker("Topic", selection: $topic) {
                Text("All topics").tag("")
                ForEach(content?.syllabus.topics ?? [], id: \.key) { Text($0.title).tag($0.key) }
                Text("Beyond the TMUA specification").tag(Self.outsideSpecification)
            }
            .onChange(of: topic) { _, _ in strand = "" }
            if let selected = content?.syllabus.topic(topic) {
                Picker("Strand", selection: $strand) {
                    Text("All strands").tag("")
                    ForEach(selected.strands, id: \.key) { Text($0.title).tag($0.key) }
                }
            }
            Picker("Marking", selection: $marking) {
                Text("Any marking").tag("")
                ForEach([TMUACatalogueEntry.AnswerMode.automatic, .selfMarked, .manualResult], id: \.self) { mode in
                    if pool.contains(where: { $0.answerMode == mode }) { Text(mode.title).tag(mode.rawValue) }
                }
            }
            Picker("Source", selection: $source) {
                Text("All sources").tag("")
                ForEach(sources, id: \.self) { Text($0).tag($0) }
            }
            Picker("Difficulty (estimated)", selection: $difficulty) {
                Text("Any").tag(0)
                ForEach(1...5, id: \.self) { Text("Level \($0)").tag($0) }
            }
            Picker("Status", selection: $status) {
                ForEach(TMUACatalogueProgress.Status.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } footer: {
            Text(Self.footer(content: content, pool: pool))
        }
        Section {
            if shown.isEmpty {
                Text(pool.isEmpty ? "No questions can be opened in this build yet. Papers and Sources list what is available on publishers’ websites."
                     : "No questions match these filters.")
                    .foregroundStyle(RevisrColors.secondaryLabel)
            }
            ForEach(shown) { entry in
                TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content) {
                    TMUACatalogueRow(entry: entry, progress: progress, syllabus: content?.syllabus)
                }
            }
        } header: {
            Text("\(shown.count) question\(shown.count == 1 ? "" : "s")")
        }
    }

    /// Revisr-marked questions first, then papers in library order, then question order.
    static func order(_ lhs: TMUACatalogueEntry, _ rhs: TMUACatalogueEntry) -> Bool {
        let left = lhs.answerMode == .automatic ? 0 : 1, right = rhs.answerMode == .automatic ? 0 : 1
        if left != right { return left < right }
        if lhs.sourceTitle != rhs.sourceTitle { return lhs.sourceTitle < rhs.sourceTitle }
        return lhs.id < rhs.id
    }

    static func footer(content: TMUAContentContext?, pool: [TMUACatalogueEntry]) -> String {
        let automatic = pool.filter { $0.answerMode == .automatic }.count
        let other = pool.count - automatic
        guard content?.distribution == .internal else {
            return "\(automatic) question\(automatic == 1 ? "" : "s") can be answered and marked in Revisr. Questions on publishers’ websites are listed under Papers and Sources. Difficulty levels are estimates."
        }
        return "Development build: \(automatic) questions are marked by Revisr (original drafts not yet reviewed, and official questions with keys read from the official solutions, not checked by a person). \(other) more open at their page in papers from your own library; you mark those yourself and they never count as evidence of mastery. Difficulty levels are estimates, not calibrated ratings."
    }
}

extension TMUACatalogueEntry {
    /// The provider name, or "Original Revisr questions".
    var sourceGroup: String { provider?.name ?? sourceTitle }
}

/// One catalogue question in a list.
struct TMUACatalogueRow: View {
    let entry: TMUACatalogueEntry
    let progress: TMUACatalogueProgress
    let syllabus: TMUASyllabus?

    var body: some View {
        let outcome = progress.lastOutcome(entry)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title(attempted: outcome != nil)).font(.subheadline.weight(.semibold))
                if progress.isFlagged(entry) {
                    Image(systemName: "flag.fill").foregroundStyle(RevisrColors.warning).accessibilityLabel("Flagged")
                }
            }
            Text(details).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
            Text([entry.answerMode == .automatic ? "Marked by Revisr" : "Self-marked", outcome.map { "last: \($0.lowercased())" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(entry.answerMode == .automatic ? RevisrColors.accentStrong : RevisrColors.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
    }

    private func title(attempted: Bool) -> String {
        if entry.origin == .revisrOriginal, let item = entry.item {
            // Titles of unattempted originals stay hidden: some name the method.
            return attempted ? item.title : (syllabus?.strandTitle(item.taxonomy.strand) ?? "Practice question")
        }
        return "\(entry.sourceTitle) · Q\(entry.label ?? "")"
    }

    private var details: String {
        var parts: [String] = []
        switch entry.paperFit {
        case .paper1: parts.append("Paper 1")
        case .paper2: parts.append("Paper 2")
        case .both: parts.append("Papers 1 and 2")
        case .unclassified: break
        }
        parts.append(entry.topicKey.flatMap { syllabus?.topicTitle($0) } ?? entry.legacyTopic ?? "Beyond the specification")
        if let level = entry.difficulty { parts.append("level \(level) (estimated)") }
        if entry.presentation == .document, let page = entry.page { parts.append("page \(page)") }
        return parts.joined(separator: " · ")
    }
}

/// Opens a catalogue question in the right screen for how it is presented.
struct TMUACatalogueLink<Label: View>: View {
    let settings: AppSettings
    let entry: TMUACatalogueEntry
    let catalogue: TMUAQuestionCatalogue
    let content: TMUAContentContext?
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            if let item = entry.item {
                TMUAPracticeView(settings: settings, item: item)
            } else {
                TMUACatalogueQuestionView(settings: settings, entry: entry, catalogue: catalogue, content: content)
            }
        } label: {
            label()
        }
        .accessibilityIdentifier("catalogue.question")
    }
}

/// A question Revisr cannot mark: shown at its page in the bundled paper (internal builds) or on
/// the publisher's site, with its solution where this build has one, and a self-recorded result.
struct TMUACatalogueQuestionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let settings: AppSettings
    let catalogue: TMUAQuestionCatalogue
    let content: TMUAContentContext?
    @State private var current: TMUACatalogueEntry
    @Query private var logs: [TMUAResourceLog]
    @Query private var flags: [TMUAReviewFlag]
    @State private var openPaper = false
    @State private var openSolution = false
    @State private var recording = false
    @State private var errorMessage: String?

    init(settings: AppSettings, entry: TMUACatalogueEntry, catalogue: TMUAQuestionCatalogue, content: TMUAContentContext?) {
        self.settings = settings
        self.catalogue = catalogue
        self.content = content
        _current = State(initialValue: entry)
    }

    private var source: TMUAResourceSource? { catalogue.sources.first { $0.id == current.sourceID } }
    private var siblings: [TMUACatalogueEntry] { current.sourceID.map(catalogue.entries(inSource:)) ?? [] }
    private var paperURL: URL? {
        current.presentation == .document ? current.sourceID.flatMap { SourceLibraryServiceLookup.paperURL($0) } : nil
    }
    private var solutionFile: TMUAResourceSource.SolutionFile? {
        guard let source else { return nil }
        return source.solutions.first { $0.resourceName == current.solutionResource } ?? source.solutions.first
    }
    private var flagged: Bool {
        flags.contains { $0.profileSettingsID == settings.id && $0.itemStableID == current.id && $0.isFlagged }
    }

    var body: some View {
        let ids = Set([current.id] + current.aliases)
        let mine = logs.filter { $0.profileSettingsID == settings.id && ids.contains($0.questionID ?? "") }
            .sorted { $0.recordedAt > $1.recordedAt }
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Question \(current.label ?? "")").font(.headline)
                    Text(current.sourceTitle).font(.subheadline)
                    Text(current.attribution).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                        .accessibilityIdentifier("catalogue.credit")
                    Text(detailLine).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    if let original = current.variantOf.flatMap(catalogue.entry) {
                        Text("Adapted from \(original.sourceTitle) · Q\(original.label ?? "")")
                            .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    if !current.alsoAppearsIn.isEmpty {
                        Text("Also printed in \(current.alsoAppearsIn.joined(separator: "; "))")
                            .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    if let note = source?.holdingNote {
                        Text(note).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                if paperURL != nil {
                    Button(current.page.map { "Open the question (page \($0))" } ?? "Open the paper", systemImage: "doc.text") {
                        openPaper = true
                    }
                    .accessibilityIdentifier("catalogue.openQuestion")
                }
                if let file = solutionFile {
                    Button(current.solutionPage.map { "Open the solution (page \($0))" } ?? "Open the \(file.title.lowercased())",
                           systemImage: "lightbulb") { openSolution = true }
                        .accessibilityIdentifier("catalogue.openSolution")
                }
                if let link = current.sourceURL, current.presentation == .external || source?.access == .providerLink {
                    Button(current.provider?.linkTitle ?? "Open \(current.provider?.name ?? "the publisher")’s website",
                           systemImage: "safari") { openURL(link) }
                        .accessibilityHint("Opens the publisher's page in Safari")
                }
                Button("Record your result", systemImage: "square.and.pencil") { recording = true }
                    .accessibilityIdentifier("catalogue.record")
                Toggle(isOn: Binding(get: { flagged }, set: setFlag)) {
                    Label("Flag for review", systemImage: "flag")
                }
            } footer: {
                Text(footer)
            }
            if !mine.isEmpty {
                Section("Your results") {
                    ForEach(mine, id: \.id) { log in
                        Text("\(log.outcome.title) · \(log.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Q\(current.label ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Up and down move through the paper's questions, as in Mail.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Previous question", systemImage: "chevron.up") { step(-1) }
                    .disabled(position.map { $0 == 0 } ?? true)
                    .accessibilityIdentifier("catalogue.previous")
                Button("Next question", systemImage: "chevron.down") { step(1) }
                    .disabled(position.map { $0 >= siblings.count - 1 } ?? true)
                    .accessibilityIdentifier("catalogue.next")
            }
        }
        .sheet(isPresented: $openPaper) {
            if let url = paperURL { NavigationStack { SourcePDFView(url: url, page: current.page) } }
        }
        .sheet(isPresented: $openSolution) {
            if let file = solutionFile, let url = SourceLibraryServiceLookup.solutionURL(file) {
                NavigationStack { SourcePDFView(url: url, page: current.solutionPage) }
            }
        }
        .sheet(isPresented: $recording) {
            TMUARecordResultSheet(title: "\(current.sourceTitle) · Q\(current.label ?? "")", questionCount: nil) { outcome, _, minutes in
                record(outcome, minutes: minutes)
            }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var position: Int? { siblings.firstIndex { $0.id == current.id } }

    private var detailLine: String {
        var parts: [String] = []
        switch current.paperFit {
        case .paper1: parts.append("Paper 1")
        case .paper2: parts.append("Paper 2")
        case .both: parts.append("Papers 1 and 2")
        case .unclassified: break
        }
        parts.append(current.topicKey.flatMap { content?.syllabus.topicTitle($0) } ?? current.legacyTopic ?? "Beyond the specification")
        if let level = current.difficulty { parts.append("level \(level), estimated") }
        if let format = current.format { parts.append(format.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private var footer: String {
        let marking = switch current.answerMode {
        case .automatic: "Revisr marks this question."
        case .selfMarked: "Mark it yourself against the publisher’s solution."
        case .manualResult: "This build has no solution for it, so record how it went."
        case .externalViewing: "Open it on the publisher’s website, then record how it went."
        }
        let rights = current.rights == .personalStudyCopy
            ? " Personal study copy from your own library, shown in this development build only."
            : " Revisr links to the publisher and does not reproduce the paper."
        return marking + " Results you record yourself track your progress and plan, but are never used as evidence of topic mastery." + rights
    }

    private func step(_ offset: Int) {
        guard let position, siblings.indices.contains(position + offset) else { return }
        current = siblings[position + offset]
    }

    private func record(_ outcome: TMUAResourceOutcome, minutes: Int?) {
        guard let sourceID = current.sourceID else { return }
        modelContext.insert(TMUAResourceLog(profileSettingsID: settings.id, sourceID: sourceID, questionID: current.id,
                                            outcome: outcome, minutes: minutes))
        do { try modelContext.save() } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func setFlag(_ value: Bool) {
        do {
            try TMUAProgrammeService.setReviewFlag(value, itemStableID: current.id, settings: settings, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Questions → Sources: who made the questions, with credit, links and what this build offers.
struct TMUASourcesListView: View {
    let settings: AppSettings
    let content: TMUAContentContext?
    let catalogue: TMUAQuestionCatalogue

    var body: some View {
        let groups = Dictionary(grouping: catalogue.sources, by: \.provider.key)
        let providers = groups.values.compactMap(\.first?.provider).sorted { $0.name < $1.name }
        let originals = catalogue.entries.filter { $0.origin == .revisrOriginal }
        if !originals.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Original Revisr questions").font(.subheadline.weight(.semibold))
                    Text("\(originals.count) questions written for Revisr from the public TMUA specification · marked by Revisr")
                        .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    Text(content?.distribution == .internal ? "Drafts: not yet reviewed by a person."
                         : "Each one passed independent review before publication.")
                        .font(.caption2).foregroundStyle(RevisrColors.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Revisr")
            }
        }
        ForEach(TMUAResourceProvider.Kind.allCases, id: \.rawValue) { kind in
            let rows = providers.filter { $0.kind == kind }
            if !rows.isEmpty {
                Section(kind.title) {
                    ForEach(rows, id: \.key) { provider in
                        NavigationLink {
                            TMUAProviderView(settings: settings, provider: provider, content: content, catalogue: catalogue)
                        } label: {
                            providerLabel(provider, sources: groups[provider.key] ?? [])
                        }
                        .accessibilityIdentifier("sources.provider")
                    }
                }
            }
        }
        let sites = TMUAResourceCatalogue.linkedProviders(TMUAResourceRegistry.bundled())
            .filter { groups[$0.key] == nil }
        if !sites.isEmpty {
            Section {
                ForEach(sites, id: \.key) { site in
                    if let link = site.link {
                        Link(destination: link) {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(site.linkTitle ?? site.name, systemImage: "safari").font(.subheadline.weight(.semibold))
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

    private func providerLabel(_ provider: TMUAResourceProvider, sources: [TMUAResourceSource]) -> some View {
        let questions = sources.reduce(0) { $0 + $1.questions.count }
        let inApp = sources.filter { $0.access == .studyCopy }.count
        return VStack(alignment: .leading, spacing: 3) {
            Text(provider.name).font(.subheadline.weight(.semibold))
            Text("\(sources.count) paper\(sources.count == 1 ? "" : "s") · \(questions) questions").font(.caption)
                .foregroundStyle(RevisrColors.secondaryLabel)
            Text(inApp > 0 ? "\(inApp) open in this build as personal study copies" : "Open on \(provider.name)’s website")
                .font(.caption2).foregroundStyle(RevisrColors.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One provider: credit, terms, link and its papers.
struct TMUAProviderView: View {
    @Environment(\.openURL) private var openURL
    let settings: AppSettings
    let provider: TMUAResourceProvider
    let content: TMUAContentContext?
    let catalogue: TMUAQuestionCatalogue

    var body: some View {
        let papers = catalogue.sources.filter { $0.provider.key == provider.key }
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(provider.name).font(.headline)
                    Text("Credit: \(provider.credit)").font(.subheadline).accessibilityIdentifier("sources.credit")
                    Text(provider.terms).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
                if let link = provider.link {
                    Button(provider.linkTitle ?? "Open \(provider.name)’s website", systemImage: "safari") { openURL(link) }
                        .accessibilityHint("Opens the publisher's page in Safari")
                }
            } footer: {
                Text("Revisr is not affiliated with or endorsed by \(provider.name).")
            }
            Section("Papers") {
                ForEach(papers) { source in
                    NavigationLink {
                        TMUAResourceSourceView(settings: settings, source: source, content: content)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title).font(.subheadline.weight(.semibold))
                            Text(source.subtitle).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Questions → Saved: flagged questions, questions to look at again, and recent work.
struct TMUASavedListView: View {
    let settings: AppSettings
    let content: TMUAContentContext?
    let catalogue: TMUAQuestionCatalogue
    let progress: TMUACatalogueProgress
    let reserved: Set<String>

    var body: some View {
        let visible = catalogue.entries.filter { !($0.item.map { reserved.contains($0.stableId) } ?? false) }
        let flagged = visible.filter(progress.isFlagged)
        let review = visible.filter { progress.matches($0, .needsReview) && !progress.isFlagged($0) }
        let recent = visible.filter { progress.lastActivity($0) != nil }
            .sorted { (progress.lastActivity($0) ?? .distantPast) > (progress.lastActivity($1) ?? .distantPast) }
        if flagged.isEmpty && review.isEmpty && recent.isEmpty {
            Section {
                Text("Questions you flag, answer or record a result for appear here.")
                    .foregroundStyle(RevisrColors.secondaryLabel)
            }
        }
        section("Flagged for review", flagged)
        section("Incorrect or partly right last time", review)
        section("Recently attempted", Array(recent.prefix(50)),
                footer: recent.count > 50 ? "Showing the 50 most recent of \(recent.count)." : nil)
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [TMUACatalogueEntry], footer: String? = nil) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { entry in
                    TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content) {
                        TMUACatalogueRow(entry: entry, progress: progress, syllabus: content?.syllabus)
                    }
                }
            } header: {
                Text("\(title) (\(rows.count))")
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }
}
