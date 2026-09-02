import Foundation
import SwiftData

@MainActor
enum AdmissionsImportService {
    static let supportedFormatVersions = 1...2

    static func seedBundledManifestIfNeeded(in context: ModelContext) throws {
        let manifest = try AdmissionsManifest.bundled()
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsImportError.unsupportedFormat(manifest.formatVersion)
        }
        try validate(manifest)

        let states = try context.fetch(FetchDescriptor<AdmissionsImportState>())
        if let state = states.first,
           state.importRevision == manifest.importRevision,
           state.questionCount == manifest.questions.count,
           state.assignmentCount == manifest.programme.assignments.count,
           state.sourceCount == manifest.sources.count {
            ensureAttemptTimer(in: context)
            return
        }

        try upsert(manifest, in: context)
    }

    static func upsert(_ manifest: AdmissionsManifest, in context: ModelContext) throws {
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsImportError.unsupportedFormat(manifest.formatVersion)
        }
        try validate(manifest)
        do {
            try performUpsert(manifest, in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func performUpsert(_ manifest: AdmissionsManifest, in context: ModelContext) throws {
        var profiles = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<AdmissionsTestProfile>())
                .map { ($0.kindRawValue, $0) }
        )
        for record in manifest.profiles {
            let profile = profiles[record.kind.rawValue]
                ?? AdmissionsTestProfile(
                    kind: record.kind,
                    displayName: record.displayName,
                    status: record.isActive ? .active : .inactive
                )
            if profiles[record.kind.rawValue] == nil {
                context.insert(profile)
                profiles[record.kind.rawValue] = profile
            }
            profile.displayName = record.displayName
            profile.status = record.isActive ? .active : .inactive
        }

        let existingSources = try context.fetch(FetchDescriptor<SourceDocument>())
        existingSources.forEach { $0.isImportedActive = false }
        var sources = Dictionary(uniqueKeysWithValues: existingSources.map { ($0.stableSourceID, $0) })
        for record in manifest.sources {
            let source = sources[record.stableSourceID]
                ?? SourceDocument(
                    stableSourceID: record.stableSourceID,
                    displayName: record.displayName,
                    expectedFilename: record.expectedFilename,
                    family: record.family,
                    importRevision: manifest.importRevision
                )
            if sources[record.stableSourceID] == nil {
                context.insert(source)
                sources[record.stableSourceID] = source
            }
            source.displayName = record.displayName
            source.expectedFilename = record.expectedFilename
            source.family = record.family
            source.year = record.year
            source.paper = record.paper
            source.pageCount = record.pageCount
            source.questionUnitCount = record.questionUnitCount
            source.useRule = record.useRule
            source.inventoryStatus = record.inventoryStatus
            source.checksum = record.checksum
            if let mediaKind = record.mediaKind { source.mediaKind = mediaKind }
            if let value = record.normalizedTextChecksum { source.normalizedTextChecksum = value }
            if let value = record.semanticDocumentIdentity { source.semanticDocumentIdentity = value }
            if let value = record.duplicateReviewState { source.duplicateReviewState = value }
            if let values = record.possibleDuplicateSourceIDs { source.possibleDuplicateSourceIDs = values }
            source.importRevision = manifest.importRevision
            source.isImportedActive = true
        }

        let existingQuestions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        existingQuestions.forEach { $0.isImportedActive = false }
        var questions = Dictionary(
            uniqueKeysWithValues: existingQuestions.map { ($0.externalQuestionID, $0) }
        )
        for record in manifest.questions {
            let question = questions[record.externalQuestionID]
                ?? AdmissionsQuestion(
                    externalQuestionID: record.externalQuestionID,
                    admissionsTest: record.admissionsTest,
                    family: record.family,
                    questionLabel: record.questionLabel,
                    primaryTopic: record.primaryTopic,
                    difficulty: record.difficulty,
                    difficultyLabel: record.difficultyLabel,
                    scheduleEligible: record.scheduleEligible,
                    importRevision: record.importRevision
                )
            if questions[record.externalQuestionID] == nil {
                context.insert(question)
                questions[record.externalQuestionID] = question
            }
            question.admissionsTest = record.admissionsTest
            question.family = record.family
            question.year = record.year
            question.paper = record.paper
            question.section = record.section
            question.questionLabel = record.questionLabel
            question.page = record.page
            question.primaryTopic = record.primaryTopic
            question.secondaryTopic = record.secondaryTopic
            question.reasoningSkill = record.reasoningSkill
            question.tmuaPaperFit = record.tmuaPaperFit
            question.difficulty = record.difficulty
            question.difficultyLabel = record.difficultyLabel
            question.tmuaRelevance = record.tmuaRelevance
            question.format = record.format
            question.recommendedUse = record.recommendedUse
            question.scheduleEligible = record.scheduleEligible
            question.classificationConfidence = record.classificationConfidence
            question.descriptor = record.descriptor
            question.importRevision = record.importRevision
            question.protection = record.protection
            if let value = record.primaryPreparationStream { question.primaryPreparationStream = value }
            if let values = record.intendedUses { question.intendedUses = Set(values) }
            if let value = record.questionNumber { question.questionNumber = value }
            if let value = record.subpart { question.subpart = value }
            if let value = record.difficultyProvenance { question.difficultyProvenance = value }
            if let value = record.validityState { question.validityState = value }
            if let value = record.validityReason { question.validityReason = value }
            if let value = record.duplicateReviewState { question.duplicateReviewState = value }
            if let values = record.possibleDuplicateQuestionIDs { question.possibleDuplicateQuestionIDs = values }
            if let value = record.verifiedCanonicalQuestionID { question.verifiedCanonicalQuestionID = value }
            question.sourceDocument = record.sourceID.flatMap { sources[$0] }
            question.isImportedActive = true
        }

        let existingTopics = try context.fetch(FetchDescriptor<AdmissionsTopicState>())
        existingTopics.forEach { $0.isImportedActive = false }
        var topics = Dictionary(
            uniqueKeysWithValues: existingTopics.map { ($0.stableTopicID, $0) }
        )
        for record in manifest.topics {
            let topic = topics[record.stableTopicID]
                ?? AdmissionsTopicState(
                    stableTopicID: record.stableTopicID,
                    admissionsTest: .tmua,
                    name: record.name,
                    displayOrder: record.displayOrder
                )
            if topics[record.stableTopicID] == nil {
                context.insert(topic)
                topics[record.stableTopicID] = topic
            }
            topic.admissionsTest = .tmua
            topic.name = record.name
            topic.displayOrder = record.displayOrder
            topic.isImportedActive = true
        }

        guard let manifestStart = dayFormatter.date(from: manifest.programme.startDate) else {
            throw AdmissionsImportError.invalidStartDate(manifest.programme.startDate)
        }
        let existingProgrammes = try context.fetch(FetchDescriptor<AdmissionsProgramme>())
        existingProgrammes.forEach { $0.isImportedActive = false }
        var programmes = Dictionary(
            uniqueKeysWithValues: existingProgrammes.map { ($0.externalProgrammeID, $0) }
        )
        let programme = programmes[manifest.programme.externalProgrammeID]
            ?? AdmissionsProgramme(
                externalProgrammeID: manifest.programme.externalProgrammeID,
                admissionsTest: manifest.programme.admissionsTest,
                name: manifest.programme.name,
                startDate: manifestStart,
                importRevision: manifest.programme.importRevision
            )
        if programmes[manifest.programme.externalProgrammeID] == nil {
            context.insert(programme)
            programmes[manifest.programme.externalProgrammeID] = programme
        }
        programme.admissionsTest = manifest.programme.admissionsTest
        programme.name = manifest.programme.name
        programme.importRevision = manifest.programme.importRevision
        programme.isImportedActive = true
        // startDate becomes user-owned after first import, so reimport preserves it.

        let existingDays = try context.fetch(FetchDescriptor<ProgrammeDay>())
        existingDays.forEach { $0.isImportedActive = false }
        var days = Dictionary(uniqueKeysWithValues: existingDays.map { ($0.externalDayID, $0) })
        var daysByNumber: [Int: ProgrammeDay] = [:]
        for record in manifest.programme.days {
            let externalID = "\(manifest.programme.externalProgrammeID)-D\(String(format: "%02d", record.dayNumber))"
            let day = days[externalID]
                ?? ProgrammeDay(
                    externalDayID: externalID,
                    dayNumber: record.dayNumber,
                    focus: record.focus,
                    studyBrief: record.studyBrief,
                    allocatedQuestionCount: record.allocatedQuestionCount,
                    expectedQuestionMinutes: record.expectedQuestionMinutes,
                    expectedReviewMinutes: record.expectedReviewMinutes,
                    programme: programme
                )
            if days[externalID] == nil {
                context.insert(day)
                days[externalID] = day
            }
            day.dayNumber = record.dayNumber
            day.focus = record.focus
            day.studyBrief = record.studyBrief
            day.allocatedQuestionCount = record.allocatedQuestionCount
            day.expectedQuestionMinutes = record.expectedQuestionMinutes
            day.expectedReviewMinutes = record.expectedReviewMinutes
            day.dailyTarget = record.dailyTarget
            day.notes = record.notes
            if let value = record.scheduleOffsetDays { day.scheduleOffsetDays = value }
            if let value = record.earliestStartMinute { day.earliestStartMinute = value }
            day.programme = programme
            day.isImportedActive = true
            daysByNumber[record.dayNumber] = day
        }

        let existingAssignments = try context.fetch(FetchDescriptor<ProgrammeAssignment>())
        existingAssignments.forEach { $0.isImportedActive = false }
        var assignments = Dictionary(
            uniqueKeysWithValues: existingAssignments.map { ($0.externalAssignmentID, $0) }
        )
        for record in manifest.programme.assignments {
            guard let question = questions[record.questionID] else {
                throw AdmissionsImportError.unresolvedAssignment(record.externalAssignmentID)
            }
            guard let day = daysByNumber[record.dayNumber] else {
                throw AdmissionsImportError.unresolvedProgrammeDay(record.dayNumber)
            }
            let assignment = assignments[record.externalAssignmentID]
                ?? ProgrammeAssignment(
                    externalAssignmentID: record.externalAssignmentID,
                    displayOrder: record.displayOrder,
                    programmeDay: day,
                    question: question
                )
            if assignments[record.externalAssignmentID] == nil {
                context.insert(assignment)
                assignments[record.externalAssignmentID] = assignment
            }
            assignment.block = record.block
            assignment.purpose = record.purpose
            assignment.suggestedTimeCapMinutes = record.suggestedTimeCapMinutes
            assignment.displayOrder = record.displayOrder
            assignment.programmeDay = day
            assignment.question = question
            assignment.isImportedActive = true
        }

        let states = try context.fetch(FetchDescriptor<AdmissionsImportState>())
        let state = states.first
            ?? AdmissionsImportState(
                importRevision: manifest.importRevision,
                questionCount: manifest.questions.count,
                assignmentCount: manifest.programme.assignments.count,
                sourceCount: manifest.sources.count
            )
        if states.isEmpty { context.insert(state) }
        for duplicate in states.dropFirst() { context.delete(duplicate) }
        state.importRevision = manifest.importRevision
        state.questionCount = manifest.questions.count
        state.assignmentCount = manifest.programme.assignments.count
        state.sourceCount = manifest.sources.count
        state.lastImportedAt = .now

        ensureAttemptTimer(in: context)
        try context.save()
    }

    static func validate(_ manifest: AdmissionsManifest) throws {
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsImportError.unsupportedFormat(manifest.formatVersion)
        }
        try requireUnique(manifest.profiles.map { $0.kind.rawValue }, error: AdmissionsImportError.duplicateProfileID)
        try requireUnique(manifest.sources.map(\.stableSourceID), error: AdmissionsImportError.duplicateSourceID)
        try requireUnique(manifest.questions.map(\.externalQuestionID), error: AdmissionsImportError.duplicateQuestionID)
        try requireUnique(manifest.topics.map(\.stableTopicID), error: AdmissionsImportError.duplicateTopicID)
        try requireUnique(manifest.programme.days.map(\.dayNumber), error: AdmissionsImportError.duplicateProgrammeDay)
        try requireUnique(manifest.programme.assignments.map(\.externalAssignmentID), error: AdmissionsImportError.duplicateAssignmentID)

        let sourceIDs = Set(manifest.sources.map(\.stableSourceID))
        for source in manifest.sources {
            guard !source.expectedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AdmissionsImportError.missingResourceFilename(source.stableSourceID)
            }
            if let duplicates = source.possibleDuplicateSourceIDs,
               duplicates.contains(where: { !sourceIDs.contains($0) || $0 == source.stableSourceID }) {
                throw AdmissionsImportError.invalidPreparationClassification(source.stableSourceID)
            }
        }

        let questionIDs = Set(manifest.questions.map(\.externalQuestionID))
        for question in manifest.questions {
            if let sourceID = question.sourceID, !sourceIDs.contains(sourceID) {
                throw AdmissionsImportError.unresolvedQuestionSource(
                    questionID: question.externalQuestionID,
                    sourceID: sourceID
                )
            }
            if let page = question.page, page < 1 {
                throw AdmissionsImportError.invalidQuestionPage(question.externalQuestionID)
            }
            if let uses = question.intendedUses, Set(uses).count != uses.count {
                throw AdmissionsImportError.invalidPreparationClassification(question.externalQuestionID)
            }
            if question.validityState == .invalid && question.scheduleEligible {
                throw AdmissionsImportError.contradictoryQuestionMetadata(question.externalQuestionID)
            }
            if let duplicateIDs = question.possibleDuplicateQuestionIDs,
               duplicateIDs.contains(where: { !questionIDs.contains($0) || $0 == question.externalQuestionID }) {
                throw AdmissionsImportError.invalidPreparationClassification(question.externalQuestionID)
            }
            if question.duplicateReviewState == .confirmedDuplicate {
                guard let canonical = question.verifiedCanonicalQuestionID,
                      canonical != question.externalQuestionID,
                      questionIDs.contains(canonical) else {
                    throw AdmissionsImportError.contradictoryQuestionMetadata(question.externalQuestionID)
                }
            }
        }

        guard dayFormatter.date(from: manifest.programme.startDate) != nil else {
            throw AdmissionsImportError.invalidStartDate(manifest.programme.startDate)
        }
        let dayNumbers = Set(manifest.programme.days.map(\.dayNumber))
        var effectiveOffsets = Set<Int>()
        for day in manifest.programme.days {
            if day.dayNumber < 1
                || day.scheduleOffsetDays.map({ $0 < 0 }) == true
                || day.earliestStartMinute.map({ !(0..<1_440).contains($0) }) == true {
                throw AdmissionsImportError.invalidProgrammeDay(day.dayNumber)
            }
            let effectiveOffset = day.scheduleOffsetDays ?? (day.dayNumber - 1)
            if !effectiveOffsets.insert(effectiveOffset).inserted {
                throw AdmissionsImportError.invalidProgrammeDay(day.dayNumber)
            }
        }
        for assignment in manifest.programme.assignments {
            guard questionIDs.contains(assignment.questionID) else {
                throw AdmissionsImportError.unresolvedAssignment(assignment.externalAssignmentID)
            }
            guard dayNumbers.contains(assignment.dayNumber) else {
                throw AdmissionsImportError.unresolvedProgrammeDay(assignment.dayNumber)
            }
        }
    }

    private static func requireUnique<T: Hashable>(
        _ values: [T],
        error: (T) -> AdmissionsImportError
    ) throws {
        var seen = Set<T>()
        for value in values where !seen.insert(value).inserted { throw error(value) }
    }

    private static func ensureAttemptTimer(in context: ModelContext) {
        if (try? context.fetch(FetchDescriptor<QuestionAttemptTimerState>()).isEmpty) == true {
            context.insert(QuestionAttemptTimerState())
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
