import SwiftData
import SwiftUI

/// What a student has done with a catalogue question: answers Revisr marked (practice and submitted
/// diagnostic answers), results the student recorded themselves, and review flags. Every identity
/// of a question counts, so a re-indexed or merged question keeps its history.
@MainActor
struct TMUACatalogueProgress {
    enum Status: String, CaseIterable {
        case all, notAttempted, attempted, previouslyIncorrect, notYetChecked, flagged

        var title: String {
            switch self {
            case .all: "Any status"
            case .notAttempted: "Not attempted"
            case .attempted: "Attempted"
            case .previouslyIncorrect: "Previously incorrect"
            case .notYetChecked: "Not yet checked"
            case .flagged: "Flagged for review"
            }
        }
    }

    /// The latest result for a question, and whether Revisr marked it or the student recorded it.
    struct Result {
        let outcome: TMUAResourceOutcome
        let date: Date
        let markedByRevisr: Bool
    }

    let attempts: [String: [TMUAPracticeAttempt]]
    let logs: [String: [TMUAResourceLog]]
    /// Submitted diagnostic answers, by question: whether it was right and when the section was submitted.
    let diagnostic: [String: (correct: Bool, date: Date)]
    let flagged: Set<String>

    init(settings: AppSettings, attempts: [TMUAPracticeAttempt], logs: [TMUAResourceLog], flags: [TMUAReviewFlag],
         diagnostic: [String: (correct: Bool, date: Date)] = [:]) {
        self.attempts = Dictionary(grouping: attempts.filter { $0.profileSettingsID == settings.id }, by: \.itemStableID)
        self.logs = Dictionary(grouping: logs.filter { $0.profileSettingsID == settings.id && $0.questionID != nil },
                               by: { $0.questionID ?? "" })
        self.diagnostic = diagnostic
        flagged = Set(flags.filter { $0.profileSettingsID == settings.id && $0.isFlagged }.map(\.itemStableID))
    }

    /// Answered, submitted diagnostic questions of this profile, keyed by question.
    static func diagnosticResults(settings: AppSettings, sections: [TMUADiagnosticSection],
                                  items: [TMUADiagnosticItem]) -> [String: (correct: Bool, date: Date)] {
        let diagnosticID = TMUADiagnosticService.diagnosticID(profileID: settings.id)
        let submitted = Dictionary(sections.filter { $0.diagnosticID == diagnosticID }
            .compactMap { section in section.submittedAt.map { (section.stableID, $0) } }, uniquingKeysWith: { first, _ in first })
        var result: [String: (correct: Bool, date: Date)] = [:]
        for item in items where item.diagnosticID == diagnosticID {
            guard let date = submitted[item.sectionID], let marking = item.marking, marking != .unanswered else { continue }
            if let current = result[item.itemStableID], current.date >= date { continue }
            result[item.itemStableID] = (marking == .correct, date)
        }
        return result
    }

    private func identities(_ entry: TMUACatalogueEntry) -> [String] { [entry.id] + entry.aliases }

    func history(_ entry: TMUACatalogueEntry) -> [TMUAPracticeAttempt] {
        entry.item.map { attempts[$0.stableId] ?? [] } ?? []
    }

    func recorded(_ entry: TMUACatalogueEntry) -> [TMUAResourceLog] {
        identities(entry).flatMap { logs[$0] ?? [] }
    }

    func isFlagged(_ entry: TMUACatalogueEntry) -> Bool {
        // Any identity counts: the item ID for questions Revisr marks, the catalogue ID or a merged reprint otherwise.
        identities(entry).contains(where: flagged.contains)
    }

    /// Results Revisr marked: the latest practice answer and the submitted diagnostic answer.
    private func marked(_ entry: TMUACatalogueEntry) -> [Result] {
        var results: [Result] = []
        if let attempt = history(entry).max(by: TMUAPracticeAttempt.isEarlier) {
            results.append(Result(outcome: attempt.isCorrect ? .correct : .incorrect, date: attempt.attemptedAt,
                                  markedByRevisr: true))
        }
        if let item = entry.item, let answer = diagnostic[item.stableId] {
            results.append(Result(outcome: answer.correct ? .correct : .incorrect, date: answer.date, markedByRevisr: true))
        }
        return results
    }

    private func newest(_ results: [Result]) -> Result? {
        results.max { ($0.date, $0.markedByRevisr ? 1 : 0) < ($1.date, $1.markedByRevisr ? 1 : 0) }
    }

    private func recordedResult(_ logs: [TMUAResourceLog]) -> [Result] {
        logs.max(by: TMUAResourceLog.isEarlier).map { [Result(outcome: $0.outcome, date: $0.recordedAt, markedByRevisr: false)] } ?? []
    }

    /// The most recent result of any kind; ties go to the result Revisr marked.
    func latest(_ entry: TMUACatalogueEntry) -> Result? {
        newest(marked(entry) + recordedResult(recorded(entry)))
    }

    /// The latest result other than "Skipped": skipping a question again never hides an earlier mistake.
    func latestWorked(_ entry: TMUACatalogueEntry) -> Result? {
        newest(marked(entry) + recordedResult(recorded(entry).filter { $0.outcome != .skipped }))
    }

    func lastActivity(_ entry: TMUACatalogueEntry) -> Date? { latest(entry)?.date }

    /// "Correct", "Incorrect", "Partly right", "Not yet checked", "Skipped" or nil when untouched.
    func lastOutcome(_ entry: TMUACatalogueEntry) -> String? { latest(entry)?.outcome.title }

    func matches(_ entry: TMUACatalogueEntry, _ status: Status) -> Bool {
        switch status {
        case .all: return true
        case .flagged: return isFlagged(entry)
        default: break
        }
        // A skipped question has not been attempted; for mistakes, the latest result actually worked counts.
        let worked = latestWorked(entry)?.outcome
        switch status {
        case .notAttempted: return worked == nil
        case .attempted: return worked != nil
        case .previouslyIncorrect: return worked == .incorrect || worked == .partial
        case .notYetChecked: return worked == .attempted
        case .all, .flagged: return true
        }
    }
}

/// Practice filters. The Questions tab keeps them, so they survive switching between its views.
struct TMUAPracticeFilters: Equatable {
    var paper = 0
    /// A syllabus topic key, `outside`, `unclassified`, or empty for every topic.
    var topic = ""
    var strand = ""
    var source = ""
    var difficulty = 0
    var marking = ""
    var status: TMUACatalogueProgress.Status = .all

    static let outside = "outside"
    static let unclassified = "unclassified"

    var isDefault: Bool { self == TMUAPracticeFilters() }
}

/// A filter row whose title and chosen value both stay readable: side by side when they fit,
/// otherwise the value wraps on its own line. VoiceOver reads "title, value".
struct TMUAFilterMenu<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    let title: String
    @Binding var selection: Value
    let options: [Option]
    let identifier: String

    var body: some View {
        let current = options.first { $0.value == selection }?.label ?? ""
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { Text($0.label).tag($0.value) }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RevisrSpacing.small) {
                    Text(title).foregroundStyle(.primary)
                    Spacer(minLength: RevisrSpacing.small)
                    Text(current).foregroundStyle(RevisrColors.accentStrong).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(current).foregroundStyle(RevisrColors.accentStrong).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(current)
        .accessibilityIdentifier(identifier)
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
    @Binding var filters: TMUAPracticeFilters

    var body: some View {
        let pool = Self.pool(catalogue, reserved: reserved)
        let shown = Self.filter(pool, filters, progress: progress, catalogue: catalogue)
        let syllabus = content?.syllabus
        Section {
            Picker("Paper", selection: $filters.paper) {
                Text("All").tag(0); Text("Paper 1").tag(1); Text("Paper 2").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("filter.paper")
            TMUAFilterMenu(title: "Topic", selection: $filters.topic, options: [.init(value: "", label: "All topics")]
                + (syllabus?.topics ?? []).map { .init(value: $0.key, label: $0.title) }
                + [.init(value: TMUAPracticeFilters.unclassified, label: "Topic not yet classified"),
                   .init(value: TMUAPracticeFilters.outside, label: "Beyond the TMUA specification")],
                identifier: "filter.topic")
            .onChange(of: filters.topic) { _, _ in filters.strand = "" }
            if let selected = syllabus?.topic(filters.topic) {
                TMUAFilterMenu(title: "Strand", selection: $filters.strand,
                               options: [.init(value: "", label: "All strands")] + selected.strands.map { .init(value: $0.key, label: $0.title) },
                               identifier: "filter.strand")
            }
            TMUAFilterMenu(title: "Marking", selection: $filters.marking,
                           options: [.init(value: "", label: "Any marking")]
                + [TMUACatalogueEntry.AnswerMode.automatic, .selfMarked, .manualResult]
                    .filter { mode in pool.contains { $0.answerMode == mode } }
                    .map { .init(value: $0.rawValue, label: $0.title) },
                           identifier: "filter.marking")
            TMUAFilterMenu(title: "Source", selection: $filters.source,
                           options: [.init(value: "", label: "All sources")]
                + Array(Set(pool.map(\.sourceGroup))).sorted().map { .init(value: $0, label: $0) },
                           identifier: "filter.source")
            TMUAFilterMenu(title: "Difficulty", selection: $filters.difficulty,
                           options: [.init(value: 0, label: "Any level")]
                + (1...5).map { .init(value: $0, label: "Level \($0) · \(TMUACatalogueEntry.levelTitle($0))") },
                           identifier: "filter.difficulty")
            TMUAFilterMenu(title: "Status", selection: $filters.status,
                           options: TMUACatalogueProgress.Status.allCases.map { .init(value: $0, label: $0.title) },
                           identifier: "filter.status")
            if !filters.isDefault {
                Button("Clear filters", systemImage: "xmark.circle") { filters = TMUAPracticeFilters() }
                    .accessibilityIdentifier("filter.clear")
            }
        } footer: {
            Text(Self.footer(content: content, pool: pool, strandChosen: !filters.strand.isEmpty))
        }
        Section {
            if shown.isEmpty {
                Text(pool.isEmpty ? "No questions can be opened in this build yet. Papers and Sources list what is available on publishers’ websites."
                     : "No questions match these filters.")
                    .foregroundStyle(RevisrColors.secondaryLabel)
            }
            ForEach(shown) { entry in
                TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content, byValue: true) {
                    TMUACatalogueRow(entry: entry, progress: progress, syllabus: syllabus)
                }
            }
        } header: {
            Text("\(shown.count) question\(shown.count == 1 ? "" : "s")")
                .accessibilityIdentifier("practice.count")
        }
    }

    static func pool(_ catalogue: TMUAQuestionCatalogue, reserved: Set<String>) -> [TMUACatalogueEntry] {
        reserved.isEmpty ? catalogue.practicable
            : catalogue.practicable.filter { entry in !(entry.item.map { reserved.contains($0.stableId) } ?? false) }
    }

    /// The questions a set of filters shows, in practice order. Pure, so it can be measured and tested.
    static func filter(_ pool: [TMUACatalogueEntry], _ filters: TMUAPracticeFilters, progress: TMUACatalogueProgress,
                       catalogue: TMUAQuestionCatalogue) -> [TMUACatalogueEntry] {
        pool.filter { entry in
            (filters.paper == 0 || entry.paperFit.includes(filters.paper == 1 ? .one : .two))
                && Self.matchesTopic(entry, filters.topic)
                && (filters.strand.isEmpty || entry.strandKey == filters.strand)
                && (filters.source.isEmpty || entry.sourceGroup == filters.source)
                && (filters.difficulty == 0 || entry.difficulty == filters.difficulty)
                && (filters.marking.isEmpty || entry.answerMode.rawValue == filters.marking)
                && progress.matches(entry, filters.status)
        }
        .sorted { order($0, $1, catalogue: catalogue) }
    }

    static func matchesTopic(_ entry: TMUACatalogueEntry, _ topic: String) -> Bool {
        switch topic {
        case "": true
        case TMUAPracticeFilters.outside: entry.topicBasis == .outsideSpecification
        case TMUAPracticeFilters.unclassified: entry.topicKey == nil && entry.topicBasis != .outsideSpecification
        default: entry.topicKey == topic
        }
    }

    /// Revisr-marked questions first, then the library's own order: paper by paper, question by question.
    static func order(_ lhs: TMUACatalogueEntry, _ rhs: TMUACatalogueEntry, catalogue: TMUAQuestionCatalogue) -> Bool {
        let left = lhs.answerMode == .automatic ? 0 : 1, right = rhs.answerMode == .automatic ? 0 : 1
        if left != right { return left < right }
        return (catalogue.position(of: lhs.id), lhs.id) < (catalogue.position(of: rhs.id), rhs.id)
    }

    static func footer(content: TMUAContentContext?, pool: [TMUACatalogueEntry], strandChosen: Bool = false) -> String {
        let automatic = pool.filter { $0.answerMode == .automatic }.count
        let other = pool.count - automatic
        let strand = strandChosen
            ? " Strands are known only for questions Revisr marks and for some provisionally classified ones, so other questions on this topic are hidden while a strand is chosen."
            : ""
        guard content?.distribution == .internal else {
            return "\(automatic.formatted()) question\(automatic == 1 ? "" : "s") can be answered and marked in Revisr. Questions on publishers’ websites are listed under Papers and Sources. Difficulty levels are estimates." + strand
        }
        return "Development build: Revisr marks \(automatic.formatted()) questions (answer keys not yet checked by a person). \(other.formatted()) more open at their page in papers from your own library: you mark those yourself, and they never count as evidence of mastery. Difficulty levels are estimates." + strand
    }
}

extension TMUACatalogueEntry {
    /// The provider name, or "Original Revisr questions".
    var sourceGroup: String { provider?.name ?? sourceTitle }

    /// "Paper 1", "Paper 2", "Papers 1 and 2" or nil, with "(estimated)" when the library index judged it.
    var paperFitTitle: String? {
        let title: String? = switch paperFit {
        case .paper1: "Paper 1"
        case .paper2: "Paper 2"
        case .both: "Papers 1 and 2"
        case .unclassified: nil
        }
        return title.map { paperFitBasis == .libraryEstimate ? "\($0) (estimated)" : $0 }
    }

    /// The topic as a student should read it, including how provisional it is.
    func topicTitle(_ syllabus: TMUASyllabus?) -> String {
        switch topicBasis {
        case .outsideSpecification: return "Beyond the TMUA specification"
        case .unclassified where topicKey == nil: return "Topic not yet classified"
        default:
            let title = topicKey.flatMap { syllabus?.topicTitle($0) } ?? "Topic not yet classified"
            return topicBasis == .provisionalDraft ? "\(title) (provisional)" : title
        }
    }

    /// Where the topic comes from, in a sentence; nil for a question's own Revisr record.
    var topicBasisNote: String? {
        switch topicBasis {
        case .revisrRecord: nil
        case .libraryIndex: "Topic from the original Revisr library index."
        case .provisionalDraft: "Provisional topic: two independent AI classifications of the page agreed. Not reviewed by a person."
        case .outsideSpecification: "The library index places this question outside the TMUA specification. It is never set as topic practice."
        case .unclassified: "No syllabus topic is known for this question yet, so it is never set as topic practice."
        }
    }
}

/// One catalogue question in a list.
struct TMUACatalogueRow: View {
    let entry: TMUACatalogueEntry
    let progress: TMUACatalogueProgress
    let syllabus: TMUASyllabus?

    var body: some View {
        let result = progress.latest(entry)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title(attempted: result != nil)).font(.subheadline.weight(.semibold))
                if progress.isFlagged(entry) {
                    Image(systemName: "flag.fill").foregroundStyle(RevisrColors.warning).accessibilityLabel("Flagged")
                }
            }
            Text(details).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
            Text([entry.answerMode.title, result.map { "last: \($0.outcome.title.lowercased())" + ($0.markedByRevisr ? "" : " (your marking)") }]
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
        if let paper = entry.paperFitTitle { parts.append(paper) }
        parts.append(entry.topicTitle(syllabus))
        if let level = entry.difficulty { parts.append("level \(level) (estimated)") }
        return parts.joined(separator: " · ")
    }
}

/// Navigation value for one catalogue question, for lists whose rows can change while it is open.
struct TMUACatalogueRoute: Hashable {
    let id: String
}

/// The screen for a catalogue question: Revisr's practice screen for a question it marks, the
/// self-marked question screen otherwise.
struct TMUACatalogueDestination: View {
    let settings: AppSettings
    let entry: TMUACatalogueEntry
    let catalogue: TMUAQuestionCatalogue
    let content: TMUAContentContext?

    var body: some View {
        if let item = entry.item {
            TMUAPracticeView(settings: settings, item: item)
        } else {
            TMUACatalogueQuestionView(settings: settings, entry: entry, catalogue: catalogue, content: content)
        }
    }
}

/// Opens a catalogue question in the right screen for how it is presented. A question waiting in
/// an open diagnostic section cannot be opened, so practice never reveals it early. In filtered
/// lists (Practice, Saved) the link is a value, so recording a result that moves the question out
/// of the list does not close the open screen.
struct TMUACatalogueLink<Label: View>: View {
    let settings: AppSettings
    let entry: TMUACatalogueEntry
    let catalogue: TMUAQuestionCatalogue
    let content: TMUAContentContext?
    var reserved: Set<String> = []
    var byValue = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let item = entry.item, reserved.contains(item.stableId) {
            VStack(alignment: .leading, spacing: 2) {
                label()
                SwiftUI.Label("In your open diagnostic: available once you submit it", systemImage: "lock")
                    .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
            }
            .accessibilityElement(children: .combine)
        } else if byValue {
            NavigationLink(value: TMUACatalogueRoute(id: entry.id)) { label() }
                .accessibilityIdentifier("catalogue.question")
        } else {
            NavigationLink {
                TMUACatalogueDestination(settings: settings, entry: entry, catalogue: catalogue, content: content)
            } label: {
                label()
            }
            .accessibilityIdentifier("catalogue.question")
        }
    }
}

/// Where a self-marked question was opened from. Inside a planned worksheet, Previous and Next walk
/// the worksheet's own questions and each result is recorded against the worksheet task.
struct TMUAWorksheetContext {
    let task: PublicProgrammeTask
    let entries: [TMUACatalogueEntry]
    /// Catalogue ID → the ID the worksheet stored, which differs once a stored question has been
    /// merged into another; results are recorded and read under the stored ID.
    let storedIDs: [String: String]

    /// The worksheet's questions this build can show, once each, with the IDs it stored them under.
    init(task: PublicProgrammeTask, catalogue: TMUAQuestionCatalogue) {
        self.task = task
        var entries: [TMUACatalogueEntry] = []
        var stored: [String: String] = [:]
        for id in TMUAProgrammeService.worksheetQuestionIDs(task.sourceID) {
            guard let entry = catalogue.entry(id), stored[entry.id] == nil else { continue }
            entries.append(entry)
            stored[entry.id] = id
        }
        self.entries = entries
        storedIDs = stored
    }

    func storedID(_ entry: TMUACatalogueEntry) -> String { storedIDs[entry.id] ?? entry.id }
}

/// A question Revisr cannot mark: shown at its page in the bundled paper (internal builds) or on
/// the publisher's site, with its solution where this build has one, and a self-recorded result.
struct TMUACatalogueQuestionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings
    let catalogue: TMUAQuestionCatalogue
    let content: TMUAContentContext?
    let worksheet: TMUAWorksheetContext?
    @State private var current: TMUACatalogueEntry
    @Query private var logs: [TMUAResourceLog]
    @Query private var flags: [TMUAReviewFlag]
    @State private var openPaper = false
    @State private var openSolution = false
    @State private var showingOverview = false
    @State private var errorMessage: String?

    init(settings: AppSettings, entry: TMUACatalogueEntry, catalogue: TMUAQuestionCatalogue,
         content: TMUAContentContext?, worksheet: TMUAWorksheetContext? = nil) {
        self.settings = settings
        self.catalogue = catalogue
        self.content = content
        self.worksheet = worksheet
        _current = State(initialValue: entry)
    }

    private var source: TMUAResourceSource? { catalogue.sources.first { $0.id == current.sourceID } }
    /// The worksheet's questions, or this paper's other self-marked questions; questions Revisr
    /// marks open in the practice screen instead, so stepping never lands on one here.
    private var sequence: [TMUACatalogueEntry] {
        if let worksheet { return worksheet.entries }
        return current.sourceID.map { catalogue.entries(inSource: $0).filter { $0.item == nil } } ?? []
    }
    private var paperURL: URL? {
        current.presentation == .document ? current.sourceID.flatMap { SourceLibraryServiceLookup.paperURL($0) } : nil
    }
    private var solutionFile: TMUAResourceSource.SolutionFile? {
        guard let source else { return nil }
        return source.solutions.first { $0.resourceName == current.solutionResource } ?? source.solutions.first
    }
    /// Recording against the worksheet is possible until it is finished.
    private var openWorksheet: TMUAWorksheetContext? { worksheet.flatMap { $0.task.completedAt == nil ? $0 : nil } }

    var body: some View {
        let sequence = self.sequence
        let position = sequence.firstIndex { $0.id == current.id }
        let ids = Set([current.id] + current.aliases)
        let mine = logs.filter { $0.profileSettingsID == settings.id }
        let history = mine.filter { ids.contains($0.questionID ?? "") }
            .sorted { TMUAResourceLog.isEarlier($1, $0) }
        let progress = worksheet.map { TMUAProgrammeService.worksheetProgress($0.task, logs: mine) }
        // While the worksheet is open its own result is shown; once finished, the question's latest one.
        let shown = openWorksheet.map { progress?.results[$0.storedID(current)] } ?? history.first?.outcome
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let worksheet, let position {
                        Text("Question \(position + 1) of \(sequence.count) · \(worksheet.task.topic) worksheet")
                            .font(.headline)
                    } else {
                        Text("Question \(current.label ?? "")").font(.headline)
                    }
                    Text(current.sourceTitle + (worksheet == nil ? "" : " · Q\(current.label ?? "")")).font(.subheadline)
                    Text(current.attribution).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                        .accessibilityIdentifier("catalogue.credit")
                    Text(detailLine).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    if let note = current.topicBasisNote {
                        Text(note).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
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
            } footer: {
                Text(footer)
            }
            Section {
                TMUASelfMarkControls(selected: shown) { record($0) }
                if let worksheet, openWorksheet != nil, let progress, progress.results[worksheet.storedID(current)] != nil {
                    // The next question this build can show that has no result yet.
                    if let entry = worksheet.entries.first(where: { progress.results[worksheet.storedID($0)] == nil }) {
                        Button("Next question without a result", systemImage: "arrow.right.circle.fill") { current = entry }
                            .accessibilityIdentifier("worksheet.nextUnrecorded")
                    } else if progress.unrecorded == 0 {
                        Button("Finish the worksheet", systemImage: "checkmark.circle.fill") { finish(worksheet.task) }
                            .disabled(!progress.canFinish)
                            .accessibilityIdentifier("worksheet.finishFromQuestion")
                    } else {
                        // Questions missing from this build stay unrecorded: finishing asks first, on the worksheet.
                        Button("Back to the worksheet", systemImage: "list.bullet") { dismiss() }
                            .accessibilityIdentifier("worksheet.backToSheet")
                    }
                }
            } header: {
                Text(openWorksheet != nil ? "Your result in this worksheet" : "Your result")
            } footer: {
                Text(recordFooter(progress: progress))
            }
            Section {
                Toggle(isOn: Binding(get: { isFlagged }, set: setFlag)) {
                    Label("Flag for review", systemImage: "flag")
                }
                .accessibilityIdentifier("catalogue.flag")
            } footer: {
                Text("Flagged questions are listed under Questions → Saved.")
            }
            if !history.isEmpty {
                Section("Your results for this question") {
                    ForEach(history, id: \.id) { log in
                        Text("\(log.outcome.title) · \(log.recordedAt.formatted(date: .abbreviated, time: .omitted))"
                             + (log.programmeTaskID == nil ? "" : " · in a planned worksheet"))
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(worksheet != nil ? (position.map { "\($0 + 1) of \(sequence.count)" } ?? "Worksheet") : "Q\(current.label ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Up and down move through the worksheet's (or paper's) questions, as in Mail.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if worksheet != nil {
                    Button("All questions in this worksheet", systemImage: "list.number") { showingOverview = true }
                        .accessibilityIdentifier("worksheet.overview")
                }
                Button("Previous question", systemImage: "chevron.up") { step(-1, in: sequence) }
                    .disabled(position.map { $0 == 0 } ?? true)
                    .accessibilityIdentifier("catalogue.previous")
                Button("Next question", systemImage: "chevron.down") { step(1, in: sequence) }
                    .disabled(position.map { $0 >= sequence.count - 1 } ?? true)
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
        .sheet(isPresented: $showingOverview) {
            if let worksheet, let progress {
                TMUAWorksheetOverviewSheet(worksheet: worksheet, progress: progress, current: current.id) { entry in
                    current = entry
                    showingOverview = false
                }
            }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let paper = current.paperFitTitle { parts.append(paper) }
        parts.append(current.topicTitle(content?.syllabus))
        if let level = current.difficulty { parts.append("level \(level), estimated") }
        if let format = current.format { parts.append(format.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private var footer: String {
        let marking = switch current.answerMode {
        case .automatic: "Revisr marks this question."
        case .selfMarked: "Try the question first, then mark it yourself against the publisher’s solution. A solutions page can show answers to neighbouring questions too."
        case .manualResult: "This build has no solution for it, so Revisr cannot tell you the answer. Record how it went."
        case .externalViewing: "Open it on the publisher’s website, then record how it went."
        }
        let rights = current.rights == .personalStudyCopy
            ? " Personal study copy from your own library, shown in this development build only."
            : " Revisr links to the publisher and does not reproduce the paper."
        return marking + rights
    }

    private func recordFooter(progress: TMUAWorksheetProgress?) -> String {
        let note = "You mark this yourself. A question you mark incorrect or partly right can come back once in a later worksheet; your results are never used as evidence of topic mastery."
        guard let progress else { return note }
        if let task = worksheet?.task, task.completedAt != nil {
            // A worksheet finished before R5 has one whole-worksheet result and no question results.
            let result = progress.recorded == 0 ? task.completionNote : progress.tally
            return "This worksheet is finished (\(result)). A result you record now is saved to this question’s history only. " + note
        }
        return "\(progress.summary) in this worksheet. " + note
    }

    private var isFlagged: Bool {
        // Any identity counts: the catalogue ID or a merged reprint's earlier ID.
        let ids = Set([current.id] + current.aliases)
        return flags.contains { $0.profileSettingsID == settings.id && ids.contains($0.itemStableID) && $0.isFlagged }
    }

    private func step(_ offset: Int, in sequence: [TMUACatalogueEntry]) {
        guard let position = sequence.firstIndex(where: { $0.id == current.id }),
              sequence.indices.contains(position + offset) else { return }
        current = sequence[position + offset]
    }

    private func record(_ outcome: TMUAResourceOutcome) {
        guard let sourceID = current.sourceID else { return }
        do {
            if let worksheet = openWorksheet {
                try TMUAProgrammeService.recordWorksheetResult(outcome, questionID: worksheet.storedID(current),
                    paperSourceID: sourceID, task: worksheet.task, settings: settings, in: modelContext)
            } else {
                modelContext.insert(TMUAResourceLog(profileSettingsID: settings.id, sourceID: sourceID,
                                                    questionID: current.id, outcome: outcome))
                do { try modelContext.save() } catch { modelContext.rollback(); throw error }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish(_ task: PublicProgrammeTask) {
        do {
            try TMUAProgrammeService.finishWorksheet(task, settings: settings, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setFlag(_ value: Bool) {
        do {
            // Unflagging clears every identity, so a reprint's earlier flag cannot keep it in Saved.
            let ids = value ? [current.id] : ([current.id] + current.aliases).filter { id in
                id == current.id || flags.contains { $0.profileSettingsID == settings.id && $0.itemStableID == id && $0.isFlagged }
            }
            for id in ids {
                try TMUAProgrammeService.setReviewFlag(value, itemStableID: id, settings: settings, in: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One-tap self-marking for a question Revisr cannot mark.
struct TMUASelfMarkControls: View {
    let selected: TMUAResourceOutcome?
    let onRecord: (TMUAResourceOutcome) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    static let order: [TMUAResourceOutcome] = [.correct, .partial, .incorrect, .attempted, .skipped]

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: RevisrSpacing.small), GridItem(.flexible(), spacing: RevisrSpacing.small)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: RevisrSpacing.small) {
            ForEach(Self.order, id: \.self) { outcome in
                Button {
                    onRecord(outcome)
                } label: {
                    Label(outcome.title, systemImage: selected == outcome ? "checkmark.circle.fill" : Self.symbol(outcome))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(selected == outcome ? Self.tint(outcome) : RevisrColors.secondaryLabel)
                .accessibilityAddTraits(selected == outcome ? .isSelected : [])
                .accessibilityValue(selected == outcome ? "Recorded" : "")
                .accessibilityIdentifier("selfmark.\(outcome.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }

    static func symbol(_ outcome: TMUAResourceOutcome) -> String {
        switch outcome {
        case .correct: "checkmark.circle"
        case .partial: "circle.lefthalf.filled"
        case .incorrect: "xmark.circle"
        case .attempted: "questionmark.circle"
        case .skipped: "forward.circle"
        }
    }

    static func tint(_ outcome: TMUAResourceOutcome) -> Color {
        switch outcome {
        case .correct: RevisrColors.success
        case .partial, .attempted: RevisrColors.warning
        case .incorrect: RevisrColors.critical
        case .skipped: RevisrColors.secondaryLabel
        }
    }
}

/// Every question in a worksheet with its recorded result; choosing one jumps to it.
struct TMUAWorksheetOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let worksheet: TMUAWorksheetContext
    let progress: TMUAWorksheetProgress
    let current: String
    let onSelect: (TMUACatalogueEntry) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(worksheet.entries.enumerated()), id: \.element.id) { offset, entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            TMUAWorksheetQuestionRow(number: offset + 1, entry: entry, outcome: progress.results[worksheet.storedID(entry)],
                                                     isCurrent: entry.id == current)
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text(progress.summary)
                }
            }
            .navigationTitle("Worksheet questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A worksheet question: its number, where it comes from and its result in this worksheet.
struct TMUAWorksheetQuestionRow: View {
    let number: Int
    let entry: TMUACatalogueEntry
    let outcome: TMUAResourceOutcome?
    var isCurrent = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RevisrSpacing.compact) {
            Text("\(number).").font(.subheadline.monospacedDigit().weight(.semibold)).frame(minWidth: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.sourceTitle) · Q\(entry.label ?? "")").font(.subheadline.weight(isCurrent ? .bold : .semibold))
                Text([entry.provider?.name, entry.difficulty.map { "level \($0), estimated" }, entry.page.map { "page \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
            }
            Spacer(minLength: 0)
            Label(outcome?.title ?? "No result yet",
                  systemImage: outcome.map(TMUASelfMarkControls.symbol) ?? "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(outcome.map(TMUASelfMarkControls.tint) ?? RevisrColors.secondaryLabel)
                .labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("worksheet.question")
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

/// Questions → Saved: flagged questions, questions to look at again, unfinished worksheets and
/// recent work. A question is matched by every identity it has had, so re-indexing or merging a
/// reprint never drops it from here.
struct TMUASavedListView: View {
    let settings: AppSettings
    let content: TMUAContentContext?
    let catalogue: TMUAQuestionCatalogue
    let progress: TMUACatalogueProgress
    let reserved: Set<String>
    @Query private var tasks: [PublicProgrammeTask]
    @Query private var logs: [TMUAResourceLog]

    var body: some View {
        let visible = catalogue.entries.filter { !($0.item.map { reserved.contains($0.stableId) } ?? false) }
        let latest = Dictionary(visible.compactMap { entry in progress.latestWorked(entry).map { (entry.id, $0) } },
                                uniquingKeysWith: { first, _ in first })
        let flagged = visible.filter(progress.isFlagged)
        let incorrect = visible.filter { [.incorrect, .partial].contains(latest[$0.id]?.outcome) && !progress.isFlagged($0) }
        let unchecked = visible.filter { latest[$0.id]?.outcome == .attempted && !progress.isFlagged($0) }
        let recent = visible.filter { latest[$0.id] != nil }
            .sorted { (latest[$0.id]?.date ?? .distantPast, $0.id) > (latest[$1.id]?.date ?? .distantPast, $1.id) }
        let programmeID = TMUAProgrammeService.programmeID(settings: settings)
        let started = TMUAProgrammeService.startedWorksheetTaskIDs(logs.filter { $0.profileSettingsID == settings.id })
        let worksheets = tasks.filter { $0.programmeID == programmeID && $0.isActive && $0.completedAt == nil
            && $0.activity == .topicWorksheet && started.contains($0.stableID) }
            .sorted { ($0.scheduledDate, $0.stableID) < ($1.scheduledDate, $1.stableID) }
        if flagged.isEmpty && incorrect.isEmpty && unchecked.isEmpty && recent.isEmpty && worksheets.isEmpty {
            Section {
                Text("Questions you flag, answer or record a result for appear here.")
                    .foregroundStyle(RevisrColors.secondaryLabel)
            }
        }
        if !worksheets.isEmpty {
            Section {
                ForEach(worksheets, id: \.stableID) { task in
                    // A value, so finishing the worksheet (which removes this row) does not close it.
                    NavigationLink(value: TMUATaskRoute(id: task.stableID)) {
                        TMUATaskRow(task: task, logs: logs.filter { $0.profileSettingsID == settings.id }, showsDate: true)
                    }
                    .accessibilityIdentifier("saved.worksheet")
                }
            } header: {
                Text("Worksheets in progress (\(worksheets.count))")
            }
        }
        section("Flagged for review", flagged, identifier: "saved.flagged")
        section("Previously incorrect", incorrect, identifier: "saved.incorrect",
                footer: "Your latest result was incorrect or partly right. Results you marked yourself are included and say so.")
        section("Not yet checked", unchecked, identifier: "saved.unchecked",
                footer: "You recorded these as worked but not yet marked against the solution.")
        section("Recently attempted", Array(recent.prefix(50)), identifier: "saved.recent",
                footer: recent.count > 50 ? "Showing the 50 most recent of \(recent.count)." : nil)
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [TMUACatalogueEntry], identifier: String, footer: String? = nil) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { entry in
                    TMUACatalogueLink(settings: settings, entry: entry, catalogue: catalogue, content: content, byValue: true) {
                        TMUACatalogueRow(entry: entry, progress: progress, syllabus: content?.syllabus)
                    }
                }
            } header: {
                Text("\(title) (\(rows.count))").accessibilityIdentifier(identifier)
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }
}
