import Foundation
import SwiftData

@Model
final class AdmissionsTestProfile {
    @Attribute(.unique) var kindRawValue: String
    var displayName: String
    var statusRawValue: String

    var kind: AdmissionsTestKind {
        get { AdmissionsTestKind(rawValue: kindRawValue) ?? .tmua }
        set { kindRawValue = newValue.rawValue }
    }

    var status: AdmissionsTestStatus {
        get { AdmissionsTestStatus(rawValue: statusRawValue) ?? .inactive }
        set { statusRawValue = newValue.rawValue }
    }

    init(kind: AdmissionsTestKind, displayName: String, status: AdmissionsTestStatus) {
        self.kindRawValue = kind.rawValue
        self.displayName = displayName
        self.statusRawValue = status.rawValue
    }
}

@Model
final class SourceDocument {
    @Attribute(.unique) var stableSourceID: String
    var displayName: String
    var expectedFilename: String
    var family: String
    var year: Int?
    var paper: String?
    var pageCount: Int?
    var questionUnitCount: Int
    var useRule: String?
    var inventoryStatus: String?
    var checksum: String?
    var mediaKindRawValue: String?
    var normalizedTextChecksum: String?
    var semanticDocumentIdentity: String?
    var duplicateReviewStateRawValue: String?
    var possibleDuplicateSourceIDsRawValue: String?
    /// Legacy app-managed filename retained for migration compatibility.
    /// Current private builds resolve bundled PDFs by stableSourceID.
    var localFilename: String?
    var importRevision: String
    var isImportedActive: Bool

    @Relationship(deleteRule: .nullify, inverse: \AdmissionsQuestion.sourceDocument)
    var questions: [AdmissionsQuestion]

    var mediaKind: SolutionMediaKind {
        get {
            mediaKindRawValue.flatMap(SolutionMediaKind.init(rawValue:))
                ?? (expectedFilename.lowercased().hasSuffix(".mp4") ? .video : .pdf)
        }
        set { mediaKindRawValue = newValue.rawValue }
    }

    var duplicateReviewState: DuplicateReviewState? {
        get { duplicateReviewStateRawValue.flatMap(DuplicateReviewState.init(rawValue:)) }
        set { duplicateReviewStateRawValue = newValue?.rawValue }
    }

    var possibleDuplicateSourceIDs: [String] {
        get { CanonicalStringArrayCodec.decode(possibleDuplicateSourceIDsRawValue) ?? [] }
        set { possibleDuplicateSourceIDsRawValue = CanonicalStringArrayCodec.encode(newValue) }
    }

    init(
        stableSourceID: String,
        displayName: String,
        expectedFilename: String,
        family: String,
        year: Int? = nil,
        paper: String? = nil,
        pageCount: Int? = nil,
        questionUnitCount: Int = 0,
        useRule: String? = nil,
        inventoryStatus: String? = nil,
        checksum: String? = nil,
        mediaKind: SolutionMediaKind? = nil,
        normalizedTextChecksum: String? = nil,
        semanticDocumentIdentity: String? = nil,
        duplicateReviewState: DuplicateReviewState? = nil,
        possibleDuplicateSourceIDs: [String]? = nil,
        localFilename: String? = nil,
        importRevision: String,
        isImportedActive: Bool = true,
        questions: [AdmissionsQuestion] = []
    ) {
        self.stableSourceID = stableSourceID
        self.displayName = displayName
        self.expectedFilename = expectedFilename
        self.family = family
        self.year = year
        self.paper = paper
        self.pageCount = pageCount
        self.questionUnitCount = questionUnitCount
        self.useRule = useRule
        self.inventoryStatus = inventoryStatus
        self.checksum = checksum
        self.mediaKindRawValue = mediaKind?.rawValue
        self.normalizedTextChecksum = normalizedTextChecksum
        self.semanticDocumentIdentity = semanticDocumentIdentity
        self.duplicateReviewStateRawValue = duplicateReviewState?.rawValue
        self.possibleDuplicateSourceIDsRawValue = possibleDuplicateSourceIDs.map(CanonicalStringArrayCodec.encode)
        self.localFilename = localFilename
        self.importRevision = importRevision
        self.isImportedActive = isImportedActive
        self.questions = questions
    }
}

@Model
final class AdmissionsQuestion {
    @Attribute(.unique) var externalQuestionID: String
    var admissionsTestRawValue: String
    var family: String
    var year: Int?
    var paper: String?
    var section: String?
    var questionLabel: String
    var page: Int?
    var primaryTopic: String
    var secondaryTopic: String?
    var reasoningSkill: String?
    var tmuaPaperFit: String?
    var difficulty: Int
    var difficultyLabel: String
    var tmuaRelevance: Double?
    var format: String?
    var recommendedUse: String?
    var scheduleEligible: Bool
    var classificationConfidence: String?
    var descriptor: String?
    var importRevision: String
    var isImportedActive: Bool
    var protectionRawValue: String
    var primaryPreparationStreamRawValue: String?
    var intendedUsesRawValue: String?
    var questionNumber: Int?
    var subpart: String?
    var difficultyProvenanceRawValue: String?
    var validityStateRawValue: String?
    var validityReason: String?
    var duplicateReviewStateRawValue: String?
    var possibleDuplicateQuestionIDsRawValue: String?
    var verifiedCanonicalQuestionID: String?

    // User-owned state. Reimport intentionally never writes these fields.
    var reviewStateRawValue: String
    var userNotes: String

    var sourceDocument: SourceDocument?

    @Relationship(deleteRule: .cascade, inverse: \QuestionAttempt.question)
    var attempts: [QuestionAttempt]

    @Relationship(deleteRule: .nullify, inverse: \ProgrammeAssignment.question)
    var programmeAssignments: [ProgrammeAssignment]

    var admissionsTest: AdmissionsTestKind {
        get { AdmissionsTestKind(rawValue: admissionsTestRawValue) ?? .tmua }
        set { admissionsTestRawValue = newValue.rawValue }
    }

    var protection: QuestionProtection {
        get { QuestionProtection(rawValue: protectionRawValue) ?? .none }
        set { protectionRawValue = newValue.rawValue }
    }

    var reviewState: QuestionReviewState {
        get { QuestionReviewState(rawValue: reviewStateRawValue) ?? .none }
        set { reviewStateRawValue = newValue.rawValue }
    }

    var primaryPreparationStream: PreparationStreamKind? {
        get { primaryPreparationStreamRawValue.flatMap(PreparationStreamKind.init(rawValue:)) }
        set { primaryPreparationStreamRawValue = newValue?.rawValue }
    }

    var intendedUses: Set<PreparationStreamKind> {
        get { PreparationStreamCompatibility.decode(intendedUsesRawValue) ?? [] }
        set { intendedUsesRawValue = PreparationStreamCompatibility.encode(newValue) }
    }

    /// True when an importer has supplied canonical classification, including
    /// an explicit empty intended-use array. Malformed canonical data never
    /// silently falls back to the known-inaccurate legacy TMUA value.
    var hasCanonicalPreparationClassification: Bool {
        primaryPreparationStreamRawValue != nil || intendedUsesRawValue != nil
    }

    var effectivePreparationStreams: Set<PreparationStreamKind> {
        if hasCanonicalPreparationClassification {
            var streams = intendedUses
            if let primaryPreparationStream { streams.insert(primaryPreparationStream) }
            return streams
        }
        return PreparationStreamCompatibility.legacyFallback(for: admissionsTest)
    }

    func isUsefulFor(_ stream: PreparationStreamKind) -> Bool {
        effectivePreparationStreams.contains(stream)
    }

    var isTMUAPracticeEligible: Bool {
        isImportedActive && scheduleEligible && isUsefulFor(.tmua) && validityState != .invalid
    }

    var difficultyProvenance: DifficultyProvenance? {
        get { difficultyProvenanceRawValue.flatMap(DifficultyProvenance.init(rawValue:)) }
        set { difficultyProvenanceRawValue = newValue?.rawValue }
    }

    var validityState: QuestionValidityState? {
        get { validityStateRawValue.flatMap(QuestionValidityState.init(rawValue:)) }
        set { validityStateRawValue = newValue?.rawValue }
    }

    var duplicateReviewState: DuplicateReviewState? {
        get { duplicateReviewStateRawValue.flatMap(DuplicateReviewState.init(rawValue:)) }
        set { duplicateReviewStateRawValue = newValue?.rawValue }
    }

    var possibleDuplicateQuestionIDs: [String] {
        get { CanonicalStringArrayCodec.decode(possibleDuplicateQuestionIDsRawValue) ?? [] }
        set { possibleDuplicateQuestionIDsRawValue = CanonicalStringArrayCodec.encode(newValue) }
    }

    var latestAttempt: QuestionAttempt? {
        attempts.max(by: { $0.attemptedAt < $1.attemptedAt })
    }

    var isScheduled: Bool { programmeAssignments.contains(where: \.isImportedActive) }
    var isStandby: Bool { !isScheduled && isTMUAPracticeEligible && protection == .none }

    init(
        externalQuestionID: String,
        admissionsTest: AdmissionsTestKind,
        family: String,
        year: Int? = nil,
        paper: String? = nil,
        section: String? = nil,
        questionLabel: String,
        page: Int? = nil,
        primaryTopic: String,
        secondaryTopic: String? = nil,
        reasoningSkill: String? = nil,
        tmuaPaperFit: String? = nil,
        difficulty: Int,
        difficultyLabel: String,
        tmuaRelevance: Double? = nil,
        format: String? = nil,
        recommendedUse: String? = nil,
        scheduleEligible: Bool,
        classificationConfidence: String? = nil,
        descriptor: String? = nil,
        importRevision: String,
        isImportedActive: Bool = true,
        protection: QuestionProtection = .none,
        primaryPreparationStream: PreparationStreamKind? = nil,
        intendedUses: Set<PreparationStreamKind>? = nil,
        questionNumber: Int? = nil,
        subpart: String? = nil,
        difficultyProvenance: DifficultyProvenance? = nil,
        validityState: QuestionValidityState? = nil,
        validityReason: String? = nil,
        duplicateReviewState: DuplicateReviewState? = nil,
        possibleDuplicateQuestionIDs: [String]? = nil,
        verifiedCanonicalQuestionID: String? = nil,
        reviewState: QuestionReviewState = .none,
        userNotes: String = "",
        sourceDocument: SourceDocument? = nil,
        attempts: [QuestionAttempt] = [],
        programmeAssignments: [ProgrammeAssignment] = []
    ) {
        self.externalQuestionID = externalQuestionID
        self.admissionsTestRawValue = admissionsTest.rawValue
        self.family = family
        self.year = year
        self.paper = paper
        self.section = section
        self.questionLabel = questionLabel
        self.page = page
        self.primaryTopic = primaryTopic
        self.secondaryTopic = secondaryTopic
        self.reasoningSkill = reasoningSkill
        self.tmuaPaperFit = tmuaPaperFit
        self.difficulty = difficulty
        self.difficultyLabel = difficultyLabel
        self.tmuaRelevance = tmuaRelevance
        self.format = format
        self.recommendedUse = recommendedUse
        self.scheduleEligible = scheduleEligible
        self.classificationConfidence = classificationConfidence
        self.descriptor = descriptor
        self.importRevision = importRevision
        self.isImportedActive = isImportedActive
        self.protectionRawValue = protection.rawValue
        self.primaryPreparationStreamRawValue = primaryPreparationStream?.rawValue
        self.intendedUsesRawValue = intendedUses.map(PreparationStreamCompatibility.encode)
        self.questionNumber = questionNumber
        self.subpart = subpart
        self.difficultyProvenanceRawValue = difficultyProvenance?.rawValue
        self.validityStateRawValue = validityState?.rawValue
        self.validityReason = validityReason
        self.duplicateReviewStateRawValue = duplicateReviewState?.rawValue
        self.possibleDuplicateQuestionIDsRawValue = possibleDuplicateQuestionIDs.map(CanonicalStringArrayCodec.encode)
        self.verifiedCanonicalQuestionID = verifiedCanonicalQuestionID
        self.reviewStateRawValue = reviewState.rawValue
        self.userNotes = userNotes
        self.sourceDocument = sourceDocument
        self.attempts = attempts
        self.programmeAssignments = programmeAssignments
    }
}

@Model
final class SolutionDocument {
    @Attribute(.unique) var stableSolutionID: String
    var displayName: String
    var solutionTypeRawValue: String
    var resourceName: String
    var resourceExtension: String
    var resourceContainerRawValue: String
    var family: String
    var year: Int?
    var paper: String?
    var provenanceOrganization: String
    var provenanceTitle: String
    var originalFilename: String
    var pageCount: Int?
    var checksum: String?
    var mediaKindRawValue: String?
    var additionalSourceIDsRawValue: String?
    var normalizedTextChecksum: String?
    var semanticDocumentIdentity: String?
    var duplicateReviewStateRawValue: String?
    var possibleDuplicateSolutionIDsRawValue: String?
    var availabilityRawValue: String
    var isVerified: Bool
    var importRevision: String
    var isImportedActive: Bool
    var relatedSource: SourceDocument?

    @Relationship(deleteRule: .cascade, inverse: \QuestionSolutionLink.solutionDocument)
    var links: [QuestionSolutionLink]

    var solutionType: SolutionDocumentType {
        get { SolutionDocumentType(rawValue: solutionTypeRawValue) ?? .workedSolution }
        set { solutionTypeRawValue = newValue.rawValue }
    }

    var resourceContainer: SolutionResourceContainer {
        get { SolutionResourceContainer(rawValue: resourceContainerRawValue) ?? .solutionBundle }
        set { resourceContainerRawValue = newValue.rawValue }
    }

    var availability: SolutionAvailability {
        get { SolutionAvailability(rawValue: availabilityRawValue) ?? .unavailable }
        set { availabilityRawValue = newValue.rawValue }
    }

    var mediaKind: SolutionMediaKind {
        get {
            mediaKindRawValue.flatMap(SolutionMediaKind.init(rawValue:))
                ?? (resourceExtension.lowercased() == "mp4" ? .video : .pdf)
        }
        set { mediaKindRawValue = newValue.rawValue }
    }

    var additionalRelatedSourceIDs: [String] {
        get { CanonicalStringArrayCodec.decode(additionalSourceIDsRawValue) ?? [] }
        set { additionalSourceIDsRawValue = CanonicalStringArrayCodec.encode(newValue) }
    }

    var effectiveRelatedSourceIDs: [String] {
        Array(Set([relatedSource?.stableSourceID].compactMap { $0 } + additionalRelatedSourceIDs)).sorted()
    }

    var duplicateReviewState: DuplicateReviewState? {
        get { duplicateReviewStateRawValue.flatMap(DuplicateReviewState.init(rawValue:)) }
        set { duplicateReviewStateRawValue = newValue?.rawValue }
    }

    var possibleDuplicateSolutionIDs: [String] {
        get { CanonicalStringArrayCodec.decode(possibleDuplicateSolutionIDsRawValue) ?? [] }
        set { possibleDuplicateSolutionIDsRawValue = CanonicalStringArrayCodec.encode(newValue) }
    }

    init(
        stableSolutionID: String,
        displayName: String,
        solutionType: SolutionDocumentType,
        resourceName: String,
        resourceExtension: String = "pdf",
        resourceContainer: SolutionResourceContainer,
        family: String,
        year: Int? = nil,
        paper: String? = nil,
        provenanceOrganization: String,
        provenanceTitle: String,
        originalFilename: String,
        pageCount: Int? = nil,
        checksum: String? = nil,
        mediaKind: SolutionMediaKind? = nil,
        additionalSourceIDs: [String]? = nil,
        normalizedTextChecksum: String? = nil,
        semanticDocumentIdentity: String? = nil,
        duplicateReviewState: DuplicateReviewState? = nil,
        possibleDuplicateSolutionIDs: [String]? = nil,
        availability: SolutionAvailability,
        isVerified: Bool,
        importRevision: String,
        isImportedActive: Bool = true,
        relatedSource: SourceDocument? = nil,
        links: [QuestionSolutionLink] = []
    ) {
        self.stableSolutionID = stableSolutionID
        self.displayName = displayName
        self.solutionTypeRawValue = solutionType.rawValue
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.resourceContainerRawValue = resourceContainer.rawValue
        self.family = family
        self.year = year
        self.paper = paper
        self.provenanceOrganization = provenanceOrganization
        self.provenanceTitle = provenanceTitle
        self.originalFilename = originalFilename
        self.pageCount = pageCount
        self.checksum = checksum
        self.mediaKindRawValue = mediaKind?.rawValue
        self.additionalSourceIDsRawValue = additionalSourceIDs.map(CanonicalStringArrayCodec.encode)
        self.normalizedTextChecksum = normalizedTextChecksum
        self.semanticDocumentIdentity = semanticDocumentIdentity
        self.duplicateReviewStateRawValue = duplicateReviewState?.rawValue
        self.possibleDuplicateSolutionIDsRawValue = possibleDuplicateSolutionIDs.map(CanonicalStringArrayCodec.encode)
        self.availabilityRawValue = availability.rawValue
        self.isVerified = isVerified
        self.importRevision = importRevision
        self.isImportedActive = isImportedActive
        self.relatedSource = relatedSource
        self.links = links
    }
}

@Model
final class QuestionSolutionLink {
    @Attribute(.unique) var stableLinkID: String
    var startPage: Int?
    var endPage: Int?
    var startTimeSeconds: Double?
    var endTimeSeconds: Double?
    var problemLabel: String?
    var mappingConfidenceRawValue: String
    var importRevision: String
    var isImportedActive: Bool
    var question: AdmissionsQuestion?
    var solutionDocument: SolutionDocument?

    var mappingConfidence: SolutionMappingConfidence {
        get { SolutionMappingConfidence(rawValue: mappingConfidenceRawValue) ?? .sourceSection }
        set { mappingConfidenceRawValue = newValue.rawValue }
    }

    init(
        stableLinkID: String,
        startPage: Int? = nil,
        endPage: Int? = nil,
        startTimeSeconds: Double? = nil,
        endTimeSeconds: Double? = nil,
        problemLabel: String? = nil,
        mappingConfidence: SolutionMappingConfidence,
        importRevision: String,
        isImportedActive: Bool = true,
        question: AdmissionsQuestion? = nil,
        solutionDocument: SolutionDocument? = nil
    ) {
        self.stableLinkID = stableLinkID
        self.startPage = startPage
        self.endPage = endPage
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.problemLabel = problemLabel
        self.mappingConfidenceRawValue = mappingConfidence.rawValue
        self.importRevision = importRevision
        self.isImportedActive = isImportedActive
        self.question = question
        self.solutionDocument = solutionDocument
    }
}

@Model
final class AdmissionsProgramme {
    @Attribute(.unique) var externalProgrammeID: String
    var admissionsTestRawValue: String
    var name: String
    var startDate: Date
    var importRevision: String
    var isImportedActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \ProgrammeDay.programme)
    var days: [ProgrammeDay]

    var admissionsTest: AdmissionsTestKind {
        get { AdmissionsTestKind(rawValue: admissionsTestRawValue) ?? .tmua }
        set { admissionsTestRawValue = newValue.rawValue }
    }

    init(
        externalProgrammeID: String,
        admissionsTest: AdmissionsTestKind,
        name: String,
        startDate: Date,
        importRevision: String,
        isImportedActive: Bool = true,
        days: [ProgrammeDay] = []
    ) {
        self.externalProgrammeID = externalProgrammeID
        self.admissionsTestRawValue = admissionsTest.rawValue
        self.name = name
        self.startDate = startDate
        self.importRevision = importRevision
        self.isImportedActive = isImportedActive
        self.days = days
    }

    func date(for dayNumber: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let offset = days.first(where: { $0.isImportedActive && $0.dayNumber == dayNumber })?
            .scheduleOffsetDays ?? (dayNumber - 1)
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: startDate))
            ?? startDate
    }

    func dayNumber(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        let activeDays = days.filter(\.isImportedActive)
        if activeDays.contains(where: { $0.scheduleOffsetDays != nil }) {
            let requested = calendar.startOfDay(for: date)
            return activeDays.first(where: {
                calendar.isDate(self.date(for: $0.dayNumber, calendar: calendar), inSameDayAs: requested)
            })?.dayNumber
        }
        let start = calendar.startOfDay(for: startDate)
        let requested = calendar.startOfDay(for: date)
        guard let difference = calendar.dateComponents([.day], from: start, to: requested).day else {
            return nil
        }
        let dayNumber = difference + 1
        return (1...30).contains(dayNumber) ? dayNumber : nil
    }

    func programmeDay(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> ProgrammeDay? {
        guard let number = dayNumber(for: date, calendar: calendar) else { return nil }
        return days.first { $0.isImportedActive && $0.dayNumber == number }
    }

    func isAvailable(
        _ day: ProgrammeDay,
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard calendar.isDate(self.date(for: day.dayNumber, calendar: calendar), inSameDayAs: date) else {
            return false
        }
        guard let earliestStartMinute = day.earliestStartMinute else { return true }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0) >= earliestStartMinute
    }
}

@Model
final class ProgrammeDay {
    @Attribute(.unique) var externalDayID: String
    var dayNumber: Int
    var focus: String
    var studyBrief: String
    var allocatedQuestionCount: Int
    var expectedQuestionMinutes: Int
    var expectedReviewMinutes: Int
    var dailyTarget: String?
    var notes: String?
    var scheduleOffsetDays: Int?
    var earliestStartMinute: Int?
    var isImportedActive: Bool
    var programme: AdmissionsProgramme?

    @Relationship(deleteRule: .cascade, inverse: \ProgrammeAssignment.programmeDay)
    var assignments: [ProgrammeAssignment]

    var expectedTotalMinutes: Int { expectedQuestionMinutes + expectedReviewMinutes }

    init(
        externalDayID: String,
        dayNumber: Int,
        focus: String,
        studyBrief: String,
        allocatedQuestionCount: Int,
        expectedQuestionMinutes: Int,
        expectedReviewMinutes: Int,
        dailyTarget: String? = nil,
        notes: String? = nil,
        scheduleOffsetDays: Int? = nil,
        earliestStartMinute: Int? = nil,
        isImportedActive: Bool = true,
        programme: AdmissionsProgramme? = nil,
        assignments: [ProgrammeAssignment] = []
    ) {
        self.externalDayID = externalDayID
        self.dayNumber = dayNumber
        self.focus = focus
        self.studyBrief = studyBrief
        self.allocatedQuestionCount = allocatedQuestionCount
        self.expectedQuestionMinutes = expectedQuestionMinutes
        self.expectedReviewMinutes = expectedReviewMinutes
        self.dailyTarget = dailyTarget
        self.notes = notes
        self.scheduleOffsetDays = scheduleOffsetDays
        self.earliestStartMinute = earliestStartMinute
        self.isImportedActive = isImportedActive
        self.programme = programme
        self.assignments = assignments
    }
}

@Model
final class ProgrammeAssignment {
    @Attribute(.unique) var externalAssignmentID: String
    var block: String?
    var purpose: String?
    var suggestedTimeCapMinutes: Int?
    var displayOrder: Int
    var isImportedActive: Bool
    var programmeDay: ProgrammeDay?
    var question: AdmissionsQuestion?

    @Relationship(deleteRule: .nullify, inverse: \QuestionAttempt.programmeAssignment)
    var attempts: [QuestionAttempt]

    var isComplete: Bool {
        attempts.contains(where: { $0.outcome != .skipped })
    }

    init(
        externalAssignmentID: String,
        block: String? = nil,
        purpose: String? = nil,
        suggestedTimeCapMinutes: Int? = nil,
        displayOrder: Int,
        isImportedActive: Bool = true,
        programmeDay: ProgrammeDay? = nil,
        question: AdmissionsQuestion? = nil,
        attempts: [QuestionAttempt] = []
    ) {
        self.externalAssignmentID = externalAssignmentID
        self.block = block
        self.purpose = purpose
        self.suggestedTimeCapMinutes = suggestedTimeCapMinutes
        self.displayOrder = displayOrder
        self.isImportedActive = isImportedActive
        self.programmeDay = programmeDay
        self.question = question
        self.attempts = attempts
    }
}

@Model
final class QuestionAttempt {
    @Attribute(.unique) var id: UUID
    var attemptedAt: Date
    var outcomeRawValue: String
    var timeTakenSeconds: Int
    var errorTypeRawValue: String?
    var notes: String
    var originRawValue: String
    var question: AdmissionsQuestion?
    var programmeAssignment: ProgrammeAssignment?

    var outcome: QuestionAttemptOutcome {
        get { QuestionAttemptOutcome(rawValue: outcomeRawValue) ?? .skipped }
        set { outcomeRawValue = newValue.rawValue }
    }

    var errorType: QuestionErrorType? {
        get { errorTypeRawValue.flatMap(QuestionErrorType.init(rawValue:)) }
        set { errorTypeRawValue = newValue?.rawValue }
    }

    var origin: QuestionAttemptOrigin {
        get { QuestionAttemptOrigin(rawValue: originRawValue) ?? .questionBank }
        set { originRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        attemptedAt: Date = .now,
        outcome: QuestionAttemptOutcome,
        timeTakenSeconds: Int,
        errorType: QuestionErrorType? = nil,
        notes: String = "",
        origin: QuestionAttemptOrigin,
        question: AdmissionsQuestion? = nil,
        programmeAssignment: ProgrammeAssignment? = nil
    ) {
        self.id = id
        self.attemptedAt = attemptedAt
        self.outcomeRawValue = outcome.rawValue
        self.timeTakenSeconds = max(0, timeTakenSeconds)
        self.errorTypeRawValue = errorType?.rawValue
        self.notes = notes
        self.originRawValue = origin.rawValue
        self.question = question
        self.programmeAssignment = programmeAssignment
    }
}

@Model
final class AdmissionsTopicState {
    @Attribute(.unique) var stableTopicID: String
    var admissionsTestRawValue: String
    var name: String
    var displayOrder: Int
    var manualStatusRawValue: String
    var needsReview: Bool
    var specificationCoverageRawValue: String
    var notes: String
    var isImportedActive: Bool

    var admissionsTest: AdmissionsTestKind {
        get { AdmissionsTestKind(rawValue: admissionsTestRawValue) ?? .tmua }
        set { admissionsTestRawValue = newValue.rawValue }
    }

    var manualStatus: TopicStatus {
        get { TopicStatus(rawValue: manualStatusRawValue) ?? .good }
        set { manualStatusRawValue = newValue.rawValue }
    }

    var specificationCoverage: SpecificationCoverageState {
        get { SpecificationCoverageState(rawValue: specificationCoverageRawValue) ?? .notStarted }
        set { specificationCoverageRawValue = newValue.rawValue }
    }

    init(
        stableTopicID: String,
        admissionsTest: AdmissionsTestKind,
        name: String,
        displayOrder: Int,
        manualStatus: TopicStatus = .good,
        needsReview: Bool = false,
        specificationCoverage: SpecificationCoverageState = .notStarted,
        notes: String = "",
        isImportedActive: Bool = true
    ) {
        self.stableTopicID = stableTopicID
        self.admissionsTestRawValue = admissionsTest.rawValue
        self.name = name
        self.displayOrder = displayOrder
        self.manualStatusRawValue = manualStatus.rawValue
        self.needsReview = needsReview
        self.specificationCoverageRawValue = specificationCoverage.rawValue
        self.notes = notes
        self.isImportedActive = isImportedActive
    }
}

@Model
final class QuestionAttemptTimerState {
    @Attribute(.unique) var singletonID: String
    var statusRawValue: String
    var startedAt: Date?
    var runningSince: Date?
    var accumulatedSeconds: TimeInterval
    var question: AdmissionsQuestion?
    var programmeAssignment: ProgrammeAssignment?

    var status: AttemptTimerStatus {
        get { AttemptTimerStatus(rawValue: statusRawValue) ?? .idle }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        singletonID: String = "question-attempt-timer",
        status: AttemptTimerStatus = .idle,
        startedAt: Date? = nil,
        runningSince: Date? = nil,
        accumulatedSeconds: TimeInterval = 0,
        question: AdmissionsQuestion? = nil,
        programmeAssignment: ProgrammeAssignment? = nil
    ) {
        self.singletonID = singletonID
        self.statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.runningSince = runningSince
        self.accumulatedSeconds = accumulatedSeconds
        self.question = question
        self.programmeAssignment = programmeAssignment
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        guard status == .running, let runningSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, date.timeIntervalSince(runningSince))
    }

    func start(question: AdmissionsQuestion, assignment: ProgrammeAssignment?, at date: Date = .now) {
        self.question = question
        self.programmeAssignment = assignment
        startedAt = date
        runningSince = date
        accumulatedSeconds = 0
        status = .running
    }

    func pause(at date: Date = .now) {
        accumulatedSeconds = elapsed(at: date)
        runningSince = nil
        status = .paused
    }

    func resume(at date: Date = .now) {
        runningSince = date
        status = .running
    }

    func reset() {
        status = .idle
        startedAt = nil
        runningSince = nil
        accumulatedSeconds = 0
        question = nil
        programmeAssignment = nil
    }
}

@Model
final class AdmissionsImportState {
    @Attribute(.unique) var singletonID: String
    var importRevision: String
    var questionCount: Int
    var assignmentCount: Int
    var sourceCount: Int
    var lastImportedAt: Date

    init(
        singletonID: String = "admissions-manifest",
        importRevision: String,
        questionCount: Int,
        assignmentCount: Int,
        sourceCount: Int,
        lastImportedAt: Date = .now
    ) {
        self.singletonID = singletonID
        self.importRevision = importRevision
        self.questionCount = questionCount
        self.assignmentCount = assignmentCount
        self.sourceCount = sourceCount
        self.lastImportedAt = lastImportedAt
    }
}
