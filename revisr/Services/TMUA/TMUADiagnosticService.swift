import Foundation
import SwiftData

enum TMUADiagnosticError: LocalizedError, Equatable {
    case incompleteProfile
    case contentUnavailable(String)
    case alreadyStarted
    case sectionLocked
    case invalidState
    case invalidAnswer
    case wrongSection
    case expansionNotAllowed
    case expansionInProgress

    var errorDescription: String? {
        switch self {
        case .incompleteProfile: "Finish your examination date and study availability first."
        case let .contentUnavailable(message): message
        case .alreadyStarted: "This diagnostic has started, so its length can no longer change. You can add questions after you finish."
        case .sectionLocked: "Submit Paper 1 of this round before starting Paper 2."
        case .invalidState: "This section can no longer be changed."
        case .invalidAnswer: "Choose one of the listed options."
        case .wrongSection: "This question does not belong to the open section."
        case .expansionNotAllowed: "Choose a longer diagnostic than the one you have already completed."
        case .expansionInProgress: "Finish the questions you have already added before adding more."
        }
    }
}

struct TMUADiagnosticSnapshot {
    let diagnostic: TMUADiagnostic
    let sections: [TMUADiagnosticSection]
    let items: [TMUADiagnosticItem]

    func items(in section: TMUADiagnosticSection) -> [TMUADiagnosticItem] {
        items.filter { $0.sectionID == section.stableID }.sorted { $0.ordinal < $1.ordinal }
    }

    var submittedItems: [TMUADiagnosticItem] {
        let submitted = Set(sections.filter { $0.status == .submitted }.map(\.stableID))
        return items.filter { submitted.contains($0.sectionID) }
    }

    var currentRound: Int { sections.map(\.round).max() ?? 0 }
    var openSections: [TMUADiagnosticSection] { sections.filter { $0.status != .submitted } }
    var isInitialComplete: Bool { diagnostic.initialCompletedAt != nil }
    var hasOpenExpansion: Bool { isInitialComplete && !openSections.isEmpty }
}

@MainActor
enum TMUADiagnosticService {
    static func diagnosticID(profileID: UUID) -> String {
        "tmua-flex-diagnostic-v1-\(profileID.uuidString)"
    }

    static func sectionID(diagnosticID: String, round: Int, paper: TMUAPaper) -> String {
        "\(diagnosticID)-R\(round)-P\(paper.rawValue)"
    }

    static func load(settings: AppSettings, in context: ModelContext) throws -> TMUADiagnosticSnapshot? {
        let id = diagnosticID(profileID: settings.id)
        var descriptor = FetchDescriptor<TMUADiagnostic>(predicate: #Predicate { $0.stableID == id })
        descriptor.fetchLimit = 1
        guard let diagnostic = try context.fetch(descriptor).first else { return nil }
        return try snapshot(for: diagnostic, in: context)
    }

    static func snapshot(for diagnostic: TMUADiagnostic, in context: ModelContext) throws -> TMUADiagnosticSnapshot {
        let id = diagnostic.stableID
        let sections = try context.fetch(FetchDescriptor<TMUADiagnosticSection>(
            predicate: #Predicate { $0.diagnosticID == id }))
            .sorted { ($0.round, $0.paperRawValue) < ($1.round, $1.paperRawValue) }
        let items = try context.fetch(FetchDescriptor<TMUADiagnosticItem>(
            predicate: #Predicate { $0.diagnosticID == id }))
        return TMUADiagnosticSnapshot(diagnostic: diagnostic, sections: sections, items: items)
    }

    /// Question identities the student has already met, in a diagnostic or in
    /// practice. They are never reassigned as new diagnostic evidence.
    static func exposedStableIDs(settings: AppSettings, in context: ModelContext) throws -> Set<String> {
        let profile = settings.id
        let attempts = try context.fetch(FetchDescriptor<TMUAPracticeAttempt>(
            predicate: #Predicate { $0.profileSettingsID == profile }))
        let diagnosticItems = try load(settings: settings, in: context)?.items ?? []
        return Set(attempts.map(\.itemStableID)).union(diagnosticItems.map(\.itemStableID))
    }

    static func create(
        settings: AppSettings,
        length: TMUADiagnosticLength,
        content: TMUAContentContext,
        at date: Date = .now,
        in context: ModelContext
    ) throws -> TMUADiagnosticSnapshot {
        guard settings.publicExamDate != nil, settings.publicWeeklyTargetMinutes != nil else {
            throw TMUADiagnosticError.incompleteProfile
        }
        if let existing = try load(settings: settings, in: context) { return existing }
        if let message = content.availability(for: length).message {
            throw TMUADiagnosticError.contentUnavailable(message)
        }
        let id = diagnosticID(profileID: settings.id)
        let selections = try selectRound(length: length, from: nil, content: content, prior: [], excluded: [])
        let composition = compositionNote(selections.flatMap(\.1), sourceMix: content.sourceMix)
        let diagnostic = TMUADiagnostic(stableID: id, profileSettingsID: settings.id, length: length,
            bankVersion: content.bank.bankVersion, distribution: content.distribution,
            sourceCompositionNote: composition, createdAt: date)
        context.insert(diagnostic)
        insertRound(0, selections: selections, target: length, diagnosticID: id, in: context)
        settings.publicDiagnosticLength = length
        do { try context.save() } catch { context.rollback(); throw error }
        return try snapshot(for: diagnostic, in: context)
    }

    /// Re-selects the initial questions for a different length. Allowed only
    /// before any section has started, so no student work is discarded.
    static func changeLength(
        _ snapshot: TMUADiagnosticSnapshot,
        to length: TMUADiagnosticLength,
        settings: AppSettings,
        content: TMUAContentContext,
        in context: ModelContext
    ) throws -> TMUADiagnosticSnapshot {
        guard snapshot.sections.allSatisfy({ $0.status == .notStarted && $0.round == 0 }),
              snapshot.items.allSatisfy({ $0.selectedOptionID == nil && !$0.isFlagged }) else {
            throw TMUADiagnosticError.alreadyStarted
        }
        if let message = content.availability(for: length).message {
            throw TMUADiagnosticError.contentUnavailable(message)
        }
        let selections = try selectRound(length: length, from: nil, content: content, prior: [], excluded: [])
        snapshot.items.forEach(context.delete)
        snapshot.sections.forEach(context.delete)
        let diagnostic = snapshot.diagnostic
        diagnostic.initialLengthRawValue = length.rawValue
        diagnostic.targetLength = length
        diagnostic.bankVersion = content.bank.bankVersion
        diagnostic.sourceCompositionNote = compositionNote(selections.flatMap(\.1), sourceMix: content.sourceMix)
        insertRound(0, selections: selections, target: length, diagnosticID: diagnostic.stableID, in: context)
        settings.publicDiagnosticLength = length
        do { try context.save() } catch { context.rollback(); throw error }
        return try self.snapshot(for: diagnostic, in: context)
    }

    static func start(_ section: TMUADiagnosticSection, in snapshot: TMUADiagnosticSnapshot,
                      at date: Date = .now, in context: ModelContext) throws {
        guard section.status == .notStarted else { throw TMUADiagnosticError.invalidState }
        if section.paper == .two,
           let first = snapshot.sections.first(where: { $0.round == section.round && $0.paper == .one }),
           first.status != .submitted {
            throw TMUADiagnosticError.sectionLocked
        }
        section.status = .inProgress
        section.startedAt = date
        section.runningSince = date
        section.lastSavedAt = date
        try save(context)
    }

    static func pause(_ section: TMUADiagnosticSection, at date: Date = .now, in context: ModelContext) throws {
        guard section.status == .inProgress, let since = section.runningSince else { return }
        section.accumulatedSeconds += max(0, date.timeIntervalSince(since))
        section.runningSince = nil
        section.pauseCount += 1
        section.lastSavedAt = date
        try save(context)
    }

    static func resume(_ section: TMUADiagnosticSection, at date: Date = .now, in context: ModelContext) throws {
        guard section.status == .inProgress else { throw TMUADiagnosticError.invalidState }
        guard section.runningSince == nil else { return }
        section.runningSince = date
        section.lastSavedAt = date
        try save(context)
    }

    /// After a termination the app cannot know how long the student kept
    /// working. A timer left running counts only up to the last saved
    /// interaction; later wall-clock time is discarded.
    static func recoverInterruptedTimers(_ snapshot: TMUADiagnosticSnapshot, in context: ModelContext) throws {
        var changed = false
        for section in snapshot.sections where section.status == .inProgress {
            guard let since = section.runningSince else { continue }
            let lastEvidence = max(since, section.lastSavedAt ?? since)
            section.accumulatedSeconds += lastEvidence.timeIntervalSince(since)
            section.runningSince = nil
            section.recoveredInterruptionCount += 1
            changed = true
        }
        if changed { try save(context) }
    }

    static func select(_ optionID: String?, for item: TMUADiagnosticItem, in section: TMUADiagnosticSection,
                       at date: Date = .now, in context: ModelContext) throws {
        try requireOpen(item, in: section)
        if let optionID {
            guard item.content?.options.contains(where: { $0.id == optionID }) == true else {
                throw TMUADiagnosticError.invalidAnswer
            }
        }
        item.selectedOptionID = optionID
        item.answeredAt = optionID == nil ? nil : date
        section.lastSavedAt = date
        try save(context)
    }

    static func setFlag(_ flagged: Bool, for item: TMUADiagnosticItem, in section: TMUADiagnosticSection,
                        at date: Date = .now, in context: ModelContext) throws {
        try requireOpen(item, in: section)
        item.isFlagged = flagged
        section.lastSavedAt = date
        try save(context)
    }

    static func move(_ section: TMUADiagnosticSection, to index: Int, count: Int,
                     at date: Date = .now, in context: ModelContext) throws {
        guard section.status == .inProgress else { throw TMUADiagnosticError.invalidState }
        section.currentIndex = min(max(0, index), max(0, count - 1))
        section.lastSavedAt = date
        try save(context)
    }

    /// Locks and marks a section from the pinned answer keys. A second call is
    /// rejected, so a submission can never be duplicated or rewritten.
    static func submit(_ section: TMUADiagnosticSection, in snapshot: TMUADiagnosticSnapshot,
                       at date: Date = .now, in context: ModelContext) throws {
        guard section.status == .inProgress else { throw TMUADiagnosticError.invalidState }
        if let since = section.runningSince {
            section.accumulatedSeconds += max(0, date.timeIntervalSince(since))
        }
        section.runningSince = nil
        for item in snapshot.items(in: section) {
            guard let selected = item.selectedOptionID else {
                item.markingRawValue = TMUAItemMarking.unanswered.rawValue
                continue
            }
            let key = item.content?.correctOptionId
            item.markingRawValue = (selected == key ? TMUAItemMarking.correct : .incorrect).rawValue
        }
        section.status = .submitted
        section.submittedAt = date
        section.lastSavedAt = date
        let diagnostic = snapshot.diagnostic
        diagnostic.lastSubmittedAt = date
        let allSubmitted = snapshot.sections.allSatisfy { $0.stableID == section.stableID || $0.status == .submitted }
        if allSubmitted && diagnostic.initialCompletedAt == nil {
            diagnostic.initialCompletedAt = date
        }
        try save(context)
    }

    /// Adds only the extra questions needed to reach a longer cumulative
    /// target. Earlier rounds, answers and timings are never modified.
    static func expand(
        _ snapshot: TMUADiagnosticSnapshot,
        to target: TMUADiagnosticLength,
        settings: AppSettings,
        content: TMUAContentContext,
        in context: ModelContext
    ) throws -> TMUADiagnosticSnapshot {
        let diagnostic = snapshot.diagnostic
        guard snapshot.isInitialComplete else { throw TMUADiagnosticError.invalidState }
        guard snapshot.openSections.isEmpty else { throw TMUADiagnosticError.expansionInProgress }
        guard target.totalQuestions > diagnostic.targetLength.totalQuestions else {
            throw TMUADiagnosticError.expansionNotAllowed
        }
        let prior = snapshot.items.compactMap(\.content)
        let exposed = try exposedStableIDs(settings: settings, in: context)
        let selections = try selectRound(length: target, from: diagnostic.targetLength, content: content,
                                         prior: prior, excluded: exposed)
        insertRound(snapshot.currentRound + 1, selections: selections, target: target,
                    diagnosticID: diagnostic.stableID, in: context)
        diagnostic.targetLength = target
        settings.publicDiagnosticLength = target
        do { try context.save() } catch { context.rollback(); throw error }
        return try self.snapshot(for: diagnostic, in: context)
    }

    static func canExpand(_ snapshot: TMUADiagnosticSnapshot, to target: TMUADiagnosticLength,
                          settings: AppSettings, content: TMUAContentContext,
                          in context: ModelContext) -> Bool {
        guard snapshot.isInitialComplete, snapshot.openSections.isEmpty,
              target.totalQuestions > snapshot.diagnostic.targetLength.totalQuestions,
              let exposed = try? exposedStableIDs(settings: settings, in: context) else { return false }
        let current = snapshot.diagnostic.targetLength
        return TMUAPaper.allCases.allSatisfy { paper in
            content.eligibleItems(for: paper).filter { !exposed.contains($0.stableId) }.count
                >= current.additionalQuestions(to: target, paper: paper)
        }
    }

    // MARK: - Helpers

    private static func selectRound(
        length: TMUADiagnosticLength,
        from previous: TMUADiagnosticLength?,
        content: TMUAContentContext,
        prior: [TMUAContentItem],
        excluded: Set<String>
    ) throws -> [(TMUAPaper, [TMUAContentItem])] {
        var running = prior
        var result: [(TMUAPaper, [TMUAContentItem])] = []
        do {
            for paper in TMUAPaper.allCases {
                let count = previous.map { $0.additionalQuestions(to: length, paper: paper) }
                    ?? length.questions(for: paper)
                let picks = try TMUADiagnosticSelector.select(paper: paper, count: count,
                    candidates: content.eligibleItems, prior: running, excludedStableIDs: excluded)
                running += picks
                result.append((paper, picks))
            }
        } catch let error as TMUASelectionError {
            throw TMUADiagnosticError.contentUnavailable(error.localizedDescription)
        }
        return result
    }

    private static func insertRound(_ round: Int, selections: [(TMUAPaper, [TMUAContentItem])],
                                    target: TMUADiagnosticLength, diagnosticID: String,
                                    in context: ModelContext) {
        for (paper, picks) in selections where !picks.isEmpty {
            let id = sectionID(diagnosticID: diagnosticID, round: round, paper: paper)
            let minutes = Int((Double(picks.count) * 75 / 20).rounded(.up))
            context.insert(TMUADiagnosticSection(stableID: id, diagnosticID: diagnosticID, round: round,
                paper: paper, roundTarget: target, advisoryMinutes: picks.count == 20 ? 75 : minutes))
            for (offset, item) in picks.enumerated() {
                context.insert(TMUADiagnosticItem(sectionID: id, diagnosticID: diagnosticID,
                                                  ordinal: offset, item: item))
            }
        }
    }

    static func compositionNote(_ items: [TMUAContentItem], sourceMix: TMUASourceMixStatus) -> String {
        let originals = items.filter { $0.category == .revisrOriginal }.count
        let past = items.filter { $0.category == .licensedPastPaper }.count
        let mocks = items.filter { $0.category == .licensedMock }.count
        var parts = ["\(originals) original Revisr"]
        if past > 0 { parts.append("\(past) licensed past-paper") }
        if mocks > 0 { parts.append("\(mocks) licensed mock") }
        var note = parts.joined(separator: ", ") + " question\(items.count == 1 ? "" : "s")"
        if let notice = sourceMix.studentNotice { note += ". " + notice }
        return note
    }

    private static func requireOpen(_ item: TMUADiagnosticItem, in section: TMUADiagnosticSection) throws {
        guard item.sectionID == section.stableID else { throw TMUADiagnosticError.wrongSection }
        guard section.status == .inProgress else { throw TMUADiagnosticError.invalidState }
    }

    private static func save(_ context: ModelContext) throws {
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
