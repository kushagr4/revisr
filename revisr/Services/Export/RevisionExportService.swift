import Foundation
import SwiftData

enum RevisionExportError: LocalizedError {
    case missingSettings
    case duplicateQuestionID(String)
    case unresolvedAttemptQuestion
    case unresolvedProgrammeQuestion(String)
    case duplicateSpecificationID(String)
    case invalidMetadata
    case unsafeOutput
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .missingSettings: "Unable to create export because Revisr settings are unavailable."
        case let .duplicateQuestionID(id): "Unable to create export because Question ID \(id) is duplicated."
        case .unresolvedAttemptQuestion: "Unable to create export because an attempt has no Question ID."
        case let .unresolvedProgrammeQuestion(id): "Unable to create export because assignment \(id) has no Question ID."
        case let .duplicateSpecificationID(id): "Unable to create export because specification ID \(id) is duplicated."
        case .invalidMetadata: "Unable to create export because required export metadata is missing."
        case .unsafeOutput: "Unable to create export because it contains an internal device path."
        case .invalidArchive: "Unable to create a complete Full Data Export."
        }
    }
}

struct ExportApplicationInfo: Equatable, Sendable {
    let appName: String
    let version: String
    let build: String

    static var current: ExportApplicationInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return ExportApplicationInfo(
            appName: (info["CFBundleDisplayName"] as? String) ?? "Revisr",
            version: (info["CFBundleShortVersionString"] as? String) ?? "Unknown",
            build: (info["CFBundleVersion"] as? String) ?? "Unknown"
        )
    }
}

enum RevisionExportKind: String, Sendable {
    case snapshot
    case full
}

struct RevisionExportArtifact: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: RevisionExportKind
    let url: URL
}

struct RevisionExportDataSet {
    let snapshot: RevisionExportV1
    let allQuestions: [QuestionExportV1]
    let allAttemptHistory: [QuestionAttemptHistoryExportV1]
    let fullProgramme: FullProgrammeExportV1?
    let topics: [TopicExportV1]
    let settings: SettingsExportV1
    let sources: [SourceExportV1]
    let solutions: [SolutionDocumentExportV1]
}

@MainActor
enum RevisionExportService {
    static let formatIdentifier = "revisr.export.revision.v2"
    static let fullFormatIdentifier = "revisr.export.full.v2"
    static let schemaVersion = 2
    static let suggestedPrompt = "I've attached my Revisr revision export. Analyse my TMUA progress, unfinished programme work, specification coverage, Question performance, timing, error types and Needs Review backlog. Then create a revision plan that prioritises my weaknesses while respecting protected Question papers and my existing programme."

    static func createSnapshotFile(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar(),
        applicationInfo: ExportApplicationInfo = .current
    ) throws -> RevisionExportArtifact {
        let dataSet = try buildDataSet(
            in: context,
            now: now,
            calendar: calendar,
            applicationInfo: applicationInfo
        )
        let data = try encodeJSON(dataSet.snapshot)
        try validate(snapshot: dataSet.snapshot, encodedData: data)
        let directory = try makeTemporaryExportDirectory()
        let url = directory.appendingPathComponent("Revisr-Revision-Snapshot-\(dayString(now, calendar: calendar)).json")
        try data.write(to: url, options: .atomic)
        return RevisionExportArtifact(kind: .snapshot, url: url)
    }

    static func createFullExportFile(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar(),
        applicationInfo: ExportApplicationInfo = .current
    ) throws -> RevisionExportArtifact {
        let dataSet = try buildDataSet(
            in: context,
            now: now,
            calendar: calendar,
            applicationInfo: applicationInfo
        )
        let archive = try makeFullArchiveData(from: dataSet, now: now)
        let directory = try makeTemporaryExportDirectory()
        let url = directory.appendingPathComponent("Revisr-Full-Export-\(dayString(now, calendar: calendar)).zip")
        try archive.write(to: url, options: .atomic)
        return RevisionExportArtifact(kind: .full, url: url)
    }

    static func buildDataSet(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = DateUtilities.appCalendar(),
        applicationInfo: ExportApplicationInfo = .current
    ) throws -> RevisionExportDataSet {
        let snapshotContext = ModelContext(context.container)
        return try buildDataSetFromSnapshot(
            in: snapshotContext,
            now: now,
            calendar: calendar,
            applicationInfo: applicationInfo
        )
    }

    private static func buildDataSetFromSnapshot(
        in context: ModelContext,
        now: Date,
        calendar: Calendar,
        applicationInfo: ExportApplicationInfo
    ) throws -> RevisionExportDataSet {
        let activeAssignments = try context.fetch(FetchDescriptor<ProgrammeAssignment>())
            .filter(\.isImportedActive)
        let bundledProgramme = try? AdmissionsProgrammeMigrationManifest.bundled()
        var assignmentQuestionIDs = Dictionary(uniqueKeysWithValues:
            (bundledProgramme?.assignments ?? []).map {
                ($0.externalAssignmentID, $0.questionID)
            }
        )
        for assignment in activeAssignments {
            if let question = assignment.question {
                assignmentQuestionIDs[assignment.externalAssignmentID] = question.externalQuestionID
            } else if assignmentQuestionIDs[assignment.externalAssignmentID] == nil {
                throw RevisionExportError.unresolvedProgrammeQuestion(assignment.externalAssignmentID)
            }
        }
        let scheduledQuestionIDs = Set(assignmentQuestionIDs.values)

        let allQuestions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
            .filter {
                $0.isImportedActive
                    && ($0.isUsefulFor(.tmua) || scheduledQuestionIDs.contains($0.externalQuestionID))
            }
            .sorted { $0.externalQuestionID < $1.externalQuestionID }
        try validateUniqueQuestionModels(allQuestions)
        let questionIDs = Set(allQuestions.map(\.externalQuestionID))
        let questionNeedsReview = Dictionary(uniqueKeysWithValues: allQuestions.map {
            ($0.externalQuestionID, $0.reviewState != .none)
        })
        let attempts = try context.fetch(FetchDescriptor<QuestionAttempt>())
            .filter { attempt in
                guard let question = attempt.question else { return true }
                return question.isImportedActive && question.isUsefulFor(.tmua)
            }
            .sorted(by: attemptSort)
        guard attempts.allSatisfy({ $0.question.map { questionIDs.contains($0.externalQuestionID) } == true }) else {
            throw RevisionExportError.unresolvedAttemptQuestion
        }

        let programmes = try context.fetch(FetchDescriptor<AdmissionsProgramme>())
            .filter { $0.isImportedActive && $0.admissionsTest == .tmua }
            .sorted { $0.externalProgrammeID < $1.externalProgrammeID }
        let programme = programmes.first
        let settingsRecords = try context.fetch(FetchDescriptor<AppSettings>())
        guard let settings = settingsRecords.first else { throw RevisionExportError.missingSettings }
        let profiles = try context.fetch(FetchDescriptor<AdmissionsTestProfile>())
        let topics = try context.fetch(FetchDescriptor<AdmissionsTopicState>())
            .filter { $0.isImportedActive && $0.admissionsTest == .tmua }
            .sorted {
                if $0.displayOrder != $1.displayOrder { return $0.displayOrder < $1.displayOrder }
                return $0.stableTopicID < $1.stableTopicID
            }
        let results = try context.fetch(FetchDescriptor<StudyResult>())
            .filter { $0.subjectNameSnapshot == "TMUA" }
            .sorted { $0.date < $1.date }
        let sources = try context.fetch(FetchDescriptor<SourceDocument>())
            .filter(\.isImportedActive)
            .sorted { $0.stableSourceID < $1.stableSourceID }
        let solutionDocuments = try context.fetch(FetchDescriptor<SolutionDocument>())
            .filter(\.isImportedActive)
            .sorted { $0.stableSolutionID < $1.stableSolutionID }
        let solutionLinks = try context.fetch(FetchDescriptor<QuestionSolutionLink>())
            .filter(\.isImportedActive)

        let currentDay = programme?.dayNumber(for: now, calendar: calendar)
        let questionDTOs = Dictionary(uniqueKeysWithValues: try allQuestions.map { question in
            (question.externalQuestionID, try makeQuestionExport(
                question,
                now: now,
                calendar: calendar,
                solutionLinks: solutionLinks
            ))
        })
        let dayDTOs = try makeProgrammeDays(
            programme,
            assignmentQuestionIDs: assignmentQuestionIDs,
            questionNeedsReview: questionNeedsReview,
            calendar: calendar
        )
        let allAssignments = dayDTOs.flatMap(\.assignments)
        guard allAssignments.allSatisfy({ questionIDs.contains($0.questionID) }) else {
            let broken = allAssignments.first(where: { !questionIDs.contains($0.questionID) })?.assignmentID ?? "unknown"
            throw RevisionExportError.unresolvedProgrammeQuestion(broken)
        }

        let allAttemptHistory = makeAttemptHistory(attempts, calendar: calendar)
        let standbyQuestions = allQuestions.filter(\.isStandby)
        let standbyIDs = Set(standbyQuestions.map(\.externalQuestionID))
        let referencedIDs = Set(attempts.compactMap { $0.question?.externalQuestionID })
            .union(allQuestions.filter { $0.reviewState != .none }.map(\.externalQuestionID))
            .union(allAssignments.map(\.questionID))
        let catalogIDs = referencedIDs.subtracting(standbyIDs)
        let catalog = catalogIDs.sorted().compactMap { questionDTOs[$0] }

        let metadata = RevisionExportMetadataV1(
            formatIdentifier: formatIdentifier,
            schemaVersion: schemaVersion,
            exportedAt: timestampString(now, calendar: calendar),
            appName: applicationInfo.appName,
            appVersion: applicationInfo.version,
            appBuild: applicationInfo.build
        )
        let csatStatus = profiles.first(where: { $0.kind == .csat })?.status == .active ? "active" : "notStarted"
        let profile = RevisionProfileExportV1(
            activeAdmissionsTest: settings.activeAdmissionsTest.rawValue,
            programmeName: programme?.name,
            programmeStartDate: programme.map { dayString($0.startDate, calendar: calendar) },
            currentProgrammeDay: currentDay,
            tmuaExamDate: dayString(settings.tmuaExamDate, calendar: calendar),
            csatStatus: csatStatus
        )

        let protected = allQuestions.compactMap { question -> ProtectedQuestionExportV1? in
            guard let dto = questionDTOs[question.externalQuestionID],
                  dto.protection.excludedFromAutomaticPractice else { return nil }
            return ProtectedQuestionExportV1(
                questionID: dto.questionID,
                sourceID: dto.sourceID,
                sourceDisplayName: dto.sourceDisplayName,
                family: dto.family,
                year: dto.year,
                paper: dto.paper,
                policy: dto.protection.policy,
                manuallySelectable: dto.protection.manuallySelectable,
                excludedFromAutomaticPractice: dto.protection.excludedFromAutomaticPractice,
                benchmarkState: dto.protection.benchmarkState,
                futureProgrammeDay: dto.protection.futureProgrammeDay
            )
        }
        let tmua = TMUAContextExportV1(
            status: profiles.first(where: { $0.kind == .tmua })?.status.rawValue ?? "active",
            examDate: dayString(settings.tmuaExamDate, calendar: calendar),
            paper1Target: settings.tmuaPaper1Target,
            paper2Target: settings.tmuaPaper2Target,
            protectionPolicy: "Protected questions remain manually selectable but are excluded from automatic Extra Practice. Official TMUA 2022 material is always protected; future scheduled official benchmark papers remain protected until their programme day.",
            protectedQuestions: protected.sorted { $0.questionID < $1.questionID }
        )

        let programmeSnapshot = makeProgrammeSnapshot(
            programme: programme,
            days: dayDTOs,
            currentDay: currentDay,
            now: now,
            calendar: calendar
        )
        let upcoming = makeUpcoming(days: dayDTOs, programme: programme, currentDay: currentDay, now: now, calendar: calendar)
        let performance = makePerformance(questions: allQuestions, attempts: attempts)
        let needsReview = NeedsReviewExportV1(
            questions: allQuestions
                .filter { $0.reviewState != .none }
                .compactMap { question in
                    guard let dto = questionDTOs[question.externalQuestionID] else { return nil }
                    let latest = question.attempts.max(by: attemptSort)
                    return QuestionReviewExportV1(
                        question: dto,
                        latestOutcome: latest?.outcome.rawValue,
                        latestErrorType: latest?.errorType?.rawValue,
                        attemptCount: question.attempts.count,
                        latestAttemptAt: latest.map { timestampString($0.attemptedAt, calendar: calendar) },
                        reviewState: question.reviewState.rawValue,
                        notes: question.userNotes.nilIfBlank
                    )
                }
                .sorted { $0.question.questionID < $1.question.questionID },
            topics: topics.filter(\.needsReview).map { topic in
                TopicReviewExportV1(
                    topicID: topic.stableTopicID,
                    name: topic.name,
                    manualStatus: topic.manualStatus.rawValue,
                    reviewState: "needsReview",
                    specificationCoverage: topic.specificationCoverage.rawValue,
                    notes: topic.notes.nilIfBlank
                )
            }
        )
        let specification = try makeSpecificationCoverage(topics, calendar: calendar)
        let resultDTOs = results.map { result in
            ResultExportV1(
                resultID: result.id.uuidString.lowercased(),
                date: dayString(result.date, calendar: calendar),
                testOrPaper: result.paperOrModuleLabel,
                rawScore: result.rawScore,
                maximumScore: result.maximumScore,
                scaledScore: result.scaledScore,
                percentage: result.rawPercentage,
                notes: result.notes.nilIfBlank
            )
        }
        let standby = makeStandby(standbyQuestions, questionDTOs: questionDTOs)
        let recent = RecentActivityExportV1(
            selectionDefinition: "Latest 50 attempts, newest first.",
            attempts: attempts.suffix(50).reversed().compactMap { attempt in
                guard let question = attempt.question else { return nil }
                return RecentAttemptExportV1(
                    attemptedAt: timestampString(attempt.attemptedAt, calendar: calendar),
                    questionID: question.externalQuestionID,
                    outcome: attempt.outcome.rawValue,
                    timeTakenSeconds: attempt.timeTakenSeconds,
                    errorType: attempt.errorType?.rawValue,
                    reviewState: question.reviewState.rawValue
                )
            }
        )
        let snapshot = RevisionExportV1(
            export: metadata,
            profile: profile,
            tmua: tmua,
            programme: programmeSnapshot,
            performance: performance,
            needsReview: needsReview,
            specificationCoverage: specification,
            results: resultDTOs,
            standby: standby,
            recentActivity: recent,
            upcoming: upcoming,
            questionCatalog: catalog,
            attemptHistory: allAttemptHistory
        )
        let topicDTOs = topics.map {
            TopicExportV1(
                topicID: $0.stableTopicID,
                admissionsTest: $0.admissionsTest.rawValue,
                name: $0.name,
                manualStatus: $0.manualStatus.rawValue,
                needsReview: $0.needsReview,
                specificationCoverage: $0.specificationCoverage.rawValue,
                notes: $0.notes.nilIfBlank
            )
        }
        let settingsDTO = SettingsExportV1(
            activeAdmissionsTest: settings.activeAdmissionsTest.rawValue,
            tmuaExamDate: dayString(settings.tmuaExamDate, calendar: calendar),
            tmuaProgrammeStartDate: dayString(settings.effectiveTMUAProgrammeStartDate, calendar: calendar),
            tmuaPaper1Target: settings.tmuaPaper1Target,
            tmuaPaper2Target: settings.tmuaPaper2Target,
            csatStatus: csatStatus
        )
        let sourceDTOs = sources.map { source in
            let relatedSolutions = solutionDocuments.filter {
                $0.effectiveRelatedSourceIDs.contains(source.stableSourceID)
            }
            return SourceExportV1(
                sourceID: source.stableSourceID,
                displayName: source.displayName,
                filename: source.expectedFilename,
                family: source.family,
                year: source.year,
                paper: source.paper,
                pageCount: source.pageCount,
                questionUnitCount: source.questionUnitCount,
                availability: SourceLibraryService.bundledURL(for: source) == nil ? "unavailable" : "availableBundledOffline",
                containsProtectedQuestions: source.questions.contains { $0.protection != .none },
                solutionStatus: SolutionLibraryService.availability(
                    for: source,
                    documents: solutionDocuments,
                    links: solutionLinks
                ).rawValue,
                solutionDocumentIDs: relatedSolutions.map(\.stableSolutionID).sorted()
            )
        }
        let solutionDTOs = solutionDocuments.map { document in
            let documentLinks = solutionLinks.filter {
                $0.solutionDocument?.stableSolutionID == document.stableSolutionID
            }
            return SolutionDocumentExportV1(
                solutionID: document.stableSolutionID,
                displayName: document.displayName,
                solutionType: document.solutionType.rawValue,
                family: document.family,
                year: document.year,
                paper: document.paper,
                provenanceOrganization: document.provenanceOrganization,
                provenanceTitle: document.provenanceTitle,
                originalFilename: document.originalFilename,
                availability: document.availability.rawValue,
                verifiedSourceMatch: document.isVerified,
                sourceID: document.relatedSource?.stableSourceID,
                additionalSourceIDs: document.additionalRelatedSourceIDs,
                mediaType: document.mediaKind.rawValue,
                videoAvailable: document.mediaKind == .video,
                directQuestionMappings: documentLinks.filter { $0.mappingConfidence == .verifiedPage }.count,
                sourceLevelMappings: documentLinks.filter { $0.mappingConfidence == .sourceSection }.count
            )
        }
        let fullProgramme = programme.map {
            FullProgrammeExportV1(
                programmeID: $0.externalProgrammeID,
                name: $0.name,
                admissionsTest: $0.admissionsTest.rawValue,
                startDate: dayString($0.startDate, calendar: calendar),
                days: dayDTOs
            )
        }
        let dataSet = RevisionExportDataSet(
            snapshot: snapshot,
            allQuestions: allQuestions.compactMap { questionDTOs[$0.externalQuestionID] },
            allAttemptHistory: allAttemptHistory,
            fullProgramme: fullProgramme,
            topics: topicDTOs,
            settings: settingsDTO,
            sources: sourceDTOs,
            solutions: solutionDTOs
        )
        let encoded = try encodeJSON(snapshot)
        try validate(snapshot: snapshot, encodedData: encoded)
        return dataSet
    }

    static func makeFullArchiveData(from dataSet: RevisionExportDataSet, now: Date) throws -> Data {
        var files: [String: Data] = [:]
        files["README.md"] = Data(fullExportReadme(dataSet.snapshot).utf8)
        files["revision-summary.md"] = Data(revisionSummary(dataSet.snapshot).utf8)
        files["revision-snapshot.json"] = try encodeJSON(dataSet.snapshot)
        files["questions.json"] = try encodeJSON(dataSet.allQuestions)
        files["specification-coverage.json"] = try encodeJSON(dataSet.snapshot.specificationCoverage)
        files["topics.json"] = try encodeJSON(dataSet.topics)
        files["settings.json"] = try encodeJSON(dataSet.settings)
        files["sources.json"] = try encodeJSON(dataSet.sources)
        files["solutions.json"] = try encodeJSON(dataSet.solutions)
        if let programme = dataSet.fullProgramme {
            files["programme.json"] = try encodeJSON(programme)
            files["programme-assignments.csv"] = CSVWriter.data(
                headers: ["assignmentID", "dayNumber", "questionID", "status", "latestOutcome", "needsReview", "suggestedTimeCapMinutes"],
                rows: programme.days.flatMap(\.assignments).map {
                    [$0.assignmentID, String($0.dayNumber), $0.questionID, $0.status, $0.latestOutcome ?? "", String($0.needsReview), $0.suggestedTimeCapMinutes.map(String.init) ?? ""]
                }
            )
        }
        if !dataSet.allAttemptHistory.isEmpty {
            files["attempts.json"] = try encodeJSON(dataSet.allAttemptHistory)
            files["attempts.csv"] = CSVWriter.data(
                headers: ["attemptID", "attemptNumber", "questionID", "attemptedAt", "outcome", "timeTakenSeconds", "errorType", "notes", "origin", "programmeDay", "programmeAssignmentID"],
                rows: dataSet.allAttemptHistory.flatMap(\.attempts).map {
                    [$0.attemptID, String($0.attemptNumber), $0.questionID, $0.attemptedAt, $0.outcome, String($0.timeTakenSeconds), $0.errorType ?? "", $0.notes ?? "", $0.origin, $0.programmeDay.map(String.init) ?? "", $0.programmeAssignmentID ?? ""]
                }
            )
        }
        if !dataSet.snapshot.results.isEmpty {
            files["results.json"] = try encodeJSON(dataSet.snapshot.results)
            files["results.csv"] = CSVWriter.data(
                headers: ["resultID", "date", "testOrPaper", "rawScore", "maximumScore", "scaledScore", "percentage", "notes"],
                rows: dataSet.snapshot.results.map {
                    [$0.resultID, $0.date, $0.testOrPaper, number($0.rawScore), number($0.maximumScore), number($0.scaledScore), number($0.percentage), $0.notes ?? ""]
                }
            )
        }
        files["questions.csv"] = CSVWriter.data(
            headers: ["questionID", "family", "year", "paper", "section", "questionLabel", "primaryTopic", "secondaryTopic", "reasoningSkill", "tmuaPaperFit", "difficulty", "difficultyLabel", "reviewState", "standby", "protection", "sourceID", "solutionAvailable", "solutionType", "solutionStatus", "solutionSourceID"],
            rows: dataSet.allQuestions.map {
                [$0.questionID, $0.family, $0.year.map(String.init) ?? "", $0.paper ?? "", $0.section ?? "", $0.questionLabel, $0.primaryTopic, $0.secondaryTopic ?? "", $0.reasoningSkill ?? "", $0.tmuaPaperFit ?? "", String($0.difficulty), $0.difficultyLabel, $0.reviewState, String($0.standby), $0.protection.policy, $0.sourceID ?? "", String($0.solutionAvailable), $0.solutionType ?? "", $0.solutionStatus, $0.solutionSourceID ?? ""]
            }
        )
        files["specification-coverage.csv"] = CSVWriter.data(
            headers: ["stableID", "officialCode", "section", "title", "coverageStatus", "lastReviewedAt", "linkedTopic", "notes"],
            rows: dataSet.snapshot.specificationCoverage.items.map {
                [$0.stableID, $0.officialCode ?? "", $0.section ?? "", $0.title, $0.coverageStatus, $0.lastReviewedAt ?? "", $0.linkedTopic ?? "", $0.notes ?? ""]
            }
        )
        let allFiles = (Array(files.keys) + ["manifest.json"]).sorted()
        let manifest = FullExportManifestV1(
            formatIdentifier: fullFormatIdentifier,
            schemaVersion: schemaVersion,
            exportedAt: dataSet.snapshot.export.exportedAt,
            appName: dataSet.snapshot.export.appName,
            appVersion: dataSet.snapshot.export.appVersion,
            appBuild: dataSet.snapshot.export.appBuild,
            activeAdmissionsTest: dataSet.snapshot.profile.activeAdmissionsTest,
            files: allFiles,
            exclusions: [
                "Question-paper and solution PDF binaries, full solution text, and copyrighted Question wording",
                "Absolute local file paths",
                "Debug logs and migration diagnostics",
                "Inactive legacy Mathematics and Further Mathematics data"
            ]
        )
        files["manifest.json"] = try encodeJSON(manifest)
        try validateFilePayloads(files)
        let archive = try ZIPArchiveWriter.makeArchive(
            entries: files.map { ZIPArchiveWriter.Entry(name: $0.key, data: $0.value) },
            modifiedAt: now
        )
        let names = try ZIPArchiveWriter.entryNames(in: archive).sorted()
        guard names == allFiles,
              !names.contains(where: { $0.lowercased().hasSuffix(".pdf") }) else {
            throw RevisionExportError.invalidArchive
        }
        return archive
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func validate(snapshot: RevisionExportV1, encodedData: Data) throws {
        guard snapshot.export.schemaVersion == schemaVersion,
              snapshot.export.formatIdentifier == formatIdentifier,
              !snapshot.export.exportedAt.isEmpty,
              !snapshot.export.appName.isEmpty else {
            throw RevisionExportError.invalidMetadata
        }
        let questions = snapshot.questionCatalog + snapshot.standby.questions
        var seen = Set<String>()
        for question in questions {
            guard seen.insert(question.questionID).inserted else {
                throw RevisionExportError.duplicateQuestionID(question.questionID)
            }
        }
        let known = seen
        guard snapshot.attemptHistory.allSatisfy({ known.contains($0.questionID) }),
              snapshot.attemptHistory.flatMap(\.attempts).allSatisfy({ known.contains($0.questionID) }),
              snapshot.programme.currentDay?.assignments.allSatisfy({ known.contains($0.questionID) }) ?? true,
              snapshot.upcoming.days.flatMap(\.assignments).allSatisfy({ known.contains($0.questionID) }),
              snapshot.programme.overdueIncompleteAssignments.allSatisfy({ known.contains($0.questionID) }) else {
            throw RevisionExportError.unresolvedAttemptQuestion
        }
        var specIDs = Set<String>()
        for item in snapshot.specificationCoverage.items {
            guard specIDs.insert(item.stableID).inserted else {
                throw RevisionExportError.duplicateSpecificationID(item.stableID)
            }
        }
        guard let output = String(data: encodedData, encoding: .utf8),
              !containsUnsafePath(output) else { throw RevisionExportError.unsafeOutput }
    }

    static func cleanupTemporaryExports(olderThan age: TimeInterval = 86_400) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Revisr Exports", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in contents {
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if (date ?? .distantPast) < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func validateUniqueQuestionModels(_ questions: [AdmissionsQuestion]) throws {
        var ids = Set<String>()
        for question in questions where !ids.insert(question.externalQuestionID).inserted {
            throw RevisionExportError.duplicateQuestionID(question.externalQuestionID)
        }
    }

    private static func makeQuestionExport(
        _ question: AdmissionsQuestion,
        now: Date,
        calendar: Calendar,
        solutionLinks: [QuestionSolutionLink]
    ) throws -> QuestionExportV1 {
        let futureAssignment = question.programmeAssignments
            .filter { $0.isImportedActive }
            .compactMap { assignment -> (ProgrammeDay, Date)? in
                guard let day = assignment.programmeDay, let programme = day.programme else { return nil }
                return (day, programme.date(for: day.dayNumber, calendar: calendar))
            }
            .filter { calendar.startOfDay(for: $0.1) > calendar.startOfDay(for: now) }
            .min { $0.1 < $1.1 }
        let futureDay = futureAssignment?.0.dayNumber
        let futureBenchmark = question.family == "TMUA Actual" && futureAssignment != nil
        let fixedProtection = question.protection != .none
        let benchmarkState: String
        if fixedProtection && question.family == "TMUA Actual" && question.year == 2022 {
            benchmarkState = "protectedOfficialTMUA2022"
        } else if fixedProtection {
            benchmarkState = "protected"
        } else if futureBenchmark {
            benchmarkState = "futureProtectedBenchmark"
        } else {
            benchmarkState = "available"
        }
        let policy = fixedProtection
            ? question.protection.rawValue
            : (futureBenchmark ? "protectedUntilProgrammeDay" : "none")
        let mappedLinks = solutionLinks.filter {
            $0.question?.externalQuestionID == question.externalQuestionID
        }.sorted {
            ($0.solutionDocument?.solutionType.preferenceOrder ?? .max)
                < ($1.solutionDocument?.solutionType.preferenceOrder ?? .max)
        }
        let preferredLink = mappedLinks.first
        let preferredSolution = preferredLink?.solutionDocument
        return QuestionExportV1(
            questionID: question.externalQuestionID,
            admissionsTest: question.admissionsTest.rawValue,
            primaryPreparationStream: question.primaryPreparationStream?.rawValue,
            intendedUses: question.hasCanonicalPreparationClassification
                ? question.intendedUses.map(\.rawValue).sorted()
                : nil,
            effectivePreparationStreams: question.effectivePreparationStreams.map(\.rawValue).sorted(),
            preparationClassificationSource: question.hasCanonicalPreparationClassification
                ? "canonical"
                : "legacyFallback",
            family: question.family,
            year: question.year,
            paper: question.paper,
            section: question.section,
            questionLabel: question.questionLabel,
            page: question.page,
            primaryTopic: question.primaryTopic,
            secondaryTopic: question.secondaryTopic,
            reasoningSkill: question.reasoningSkill,
            tmuaPaperFit: question.tmuaPaperFit,
            difficulty: question.difficulty,
            difficultyLabel: question.difficultyLabel,
            difficultyProvenance: question.difficultyProvenance?.rawValue,
            validityState: question.validityState?.rawValue,
            validityReason: question.validityReason,
            duplicateReviewState: question.duplicateReviewState?.rawValue,
            possibleDuplicateQuestionIDs: question.possibleDuplicateQuestionIDs,
            tmuaRelevance: question.tmuaRelevance,
            format: question.format,
            recommendedUse: question.recommendedUse,
            classificationConfidence: question.classificationConfidence,
            descriptor: question.descriptor,
            sourceID: question.sourceDocument?.stableSourceID,
            sourceDisplayName: question.sourceDocument?.displayName,
            sourceFilename: question.sourceDocument?.expectedFilename,
            solutionAvailable: preferredSolution != nil,
            solutionType: preferredSolution?.solutionType.rawValue,
            solutionStatus: preferredSolution == nil
                ? "pendingSource"
                : (preferredLink?.mappingConfidence == .verifiedPage ? "available" : "partial"),
            solutionSourceID: preferredSolution?.stableSolutionID,
            solutionMediaType: preferredSolution?.mediaKind.rawValue,
            videoAvailable: mappedLinks.contains { $0.solutionDocument?.mediaKind == .video },
            reviewState: question.reviewState.rawValue,
            notes: question.userNotes.nilIfBlank,
            scheduled: question.isScheduled,
            standby: question.isStandby,
            protection: QuestionProtectionExportV1(
                policy: policy,
                manuallySelectable: true,
                excludedFromAutomaticPractice: fixedProtection || futureBenchmark,
                benchmarkState: benchmarkState,
                futureProgrammeDay: futureBenchmark ? futureDay : nil
            )
        )
    }

    private static func makeProgrammeDays(
        _ programme: AdmissionsProgramme?,
        assignmentQuestionIDs: [String: String],
        questionNeedsReview: [String: Bool],
        calendar: Calendar
    ) throws -> [ProgrammeDayExportV1] {
        guard let programme else { return [] }
        return try programme.days
            .filter(\.isImportedActive)
            .sorted { $0.dayNumber < $1.dayNumber }
            .map { day in
                let assignments = try day.assignments
                    .filter(\.isImportedActive)
                    .sorted {
                        if $0.displayOrder != $1.displayOrder { return $0.displayOrder < $1.displayOrder }
                        return $0.externalAssignmentID < $1.externalAssignmentID
                    }
                    .map { assignment -> ProgrammeAssignmentExportV1 in
                        guard let questionID = assignmentQuestionIDs[assignment.externalAssignmentID] else {
                            throw RevisionExportError.unresolvedProgrammeQuestion(assignment.externalAssignmentID)
                        }
                        let latest = assignment.attempts.max(by: attemptSort)
                        return ProgrammeAssignmentExportV1(
                            assignmentID: assignment.externalAssignmentID,
                            dayNumber: day.dayNumber,
                            questionID: questionID,
                            status: assignment.isComplete ? "completed" : "incomplete",
                            latestOutcome: latest?.outcome.rawValue,
                            needsReview: questionNeedsReview[questionID] ?? false,
                            block: assignment.block,
                            purpose: assignment.purpose,
                            suggestedTimeCapMinutes: assignment.suggestedTimeCapMinutes,
                            displayOrder: assignment.displayOrder
                        )
                    }
                return ProgrammeDayExportV1(
                    dayID: day.externalDayID,
                    dayNumber: day.dayNumber,
                    date: dayString(programme.date(for: day.dayNumber, calendar: calendar), calendar: calendar),
                    focus: day.focus,
                    studyBrief: day.studyBrief,
                    dailyTarget: day.dailyTarget,
                    notes: day.notes?.nilIfBlank,
                    expectedQuestionMinutes: day.expectedQuestionMinutes,
                    expectedReviewMinutes: day.expectedReviewMinutes,
                    expectedTotalMinutes: day.expectedTotalMinutes,
                    allocatedQuestionCount: day.allocatedQuestionCount,
                    completedAssignmentCount: assignments.filter { $0.status == "completed" }.count,
                    assignments: assignments,
                    scheduleOffsetDays: day.scheduleOffsetDays,
                    earliestStartMinute: day.earliestStartMinute
                )
            }
    }

    private static func makeProgrammeSnapshot(
        programme: AdmissionsProgramme?,
        days: [ProgrammeDayExportV1],
        currentDay: Int?,
        now: Date,
        calendar: Calendar
    ) -> ProgrammeSnapshotExportV1 {
        let today = dayString(now, calendar: calendar)
        let overdue = days
            .filter { $0.date < today }
            .flatMap(\.assignments)
            .filter { $0.status != "completed" }
        let completedDays = days
            .filter { !$0.assignments.isEmpty && $0.completedAssignmentCount == $0.assignments.count }
            .map(\.dayNumber)
        return ProgrammeSnapshotExportV1(
            programmeID: programme?.externalProgrammeID,
            name: programme?.name,
            totalDays: days.count,
            currentDayNumber: currentDay,
            completedDayNumbers: completedDays,
            completedAssignments: days.reduce(0) { $0 + $1.completedAssignmentCount },
            totalAssignments: days.reduce(0) { $0 + $1.assignments.count },
            overdueIncompleteAssignments: overdue,
            currentDay: currentDay.flatMap { number in days.first(where: { $0.dayNumber == number }) }
        )
    }

    private static func makeUpcoming(
        days: [ProgrammeDayExportV1],
        programme: AdmissionsProgramme?,
        currentDay: Int?,
        now: Date,
        calendar: Calendar
    ) -> UpcomingExportV1 {
        guard let programme else {
            return UpcomingExportV1(windowDefinition: "No active programme.", days: [])
        }
        let startDay: Int
        let limit: Int
        if let currentDay {
            startDay = currentDay
            limit = 8
        } else if calendar.startOfDay(for: now) < calendar.startOfDay(for: programme.startDate) {
            startDay = 1
            limit = 7
        } else {
            startDay = Int.max
            limit = 0
        }
        let selected = days
            .filter { $0.dayNumber >= startDay }
            .prefix(limit)
            .map { day in
                ProgrammeDayExportV1(
                    dayID: day.dayID,
                    dayNumber: day.dayNumber,
                    date: day.date,
                    focus: day.focus,
                    studyBrief: day.studyBrief,
                    dailyTarget: day.dailyTarget,
                    notes: day.notes,
                    expectedQuestionMinutes: day.expectedQuestionMinutes,
                    expectedReviewMinutes: day.expectedReviewMinutes,
                    expectedTotalMinutes: day.expectedTotalMinutes,
                    allocatedQuestionCount: day.allocatedQuestionCount,
                    completedAssignmentCount: day.completedAssignmentCount,
                    assignments: day.assignments.filter { $0.status != "completed" },
                    scheduleOffsetDays: day.scheduleOffsetDays,
                    earliestStartMinute: day.earliestStartMinute
                )
            }
        return UpcomingExportV1(
            windowDefinition: currentDay == nil ? "Next 7 programme days." : "Current programme day plus the next 7 days.",
            days: selected
        )
    }

    private static func makeAttemptHistory(
        _ attempts: [QuestionAttempt],
        calendar: Calendar
    ) -> [QuestionAttemptHistoryExportV1] {
        let grouped = Dictionary(grouping: attempts) { $0.question?.externalQuestionID ?? "" }
        return grouped.keys.sorted().compactMap { questionID in
            guard !questionID.isEmpty else { return nil }
            let ordered = (grouped[questionID] ?? []).sorted(by: attemptSort)
            return QuestionAttemptHistoryExportV1(
                questionID: questionID,
                attempts: ordered.enumerated().map { index, attempt in
                    AttemptExportV1(
                        attemptID: attempt.id.uuidString.lowercased(),
                        attemptNumber: index + 1,
                        questionID: questionID,
                        attemptedAt: timestampString(attempt.attemptedAt, calendar: calendar),
                        outcome: attempt.outcome.rawValue,
                        timeTakenSeconds: attempt.timeTakenSeconds,
                        errorType: attempt.errorType?.rawValue,
                        notes: attempt.notes.nilIfBlank,
                        origin: attempt.origin.rawValue,
                        programmeDay: attempt.programmeAssignment?.programmeDay?.dayNumber,
                        programmeAssignmentID: attempt.programmeAssignment?.externalAssignmentID
                    )
                }
            )
        }
    }

    private static func makePerformance(
        questions: [AdmissionsQuestion],
        attempts: [QuestionAttempt]
    ) -> PerformanceExportV1 {
        let all = AdmissionsAnalytics.attemptSummary(attempts)
        let latest = AdmissionsAnalytics.latestQuestionSummary(questions)
        let timed = attempts.map(\.timeTakenSeconds).filter { $0 > 0 }.sorted()
        let paperFit = ["Paper 1", "Paper 2"].map { key in
            makeMetric(key: key, questions: questions.filter { normalizedPaperFit($0.tmuaPaperFit) == key })
        }
        let difficulty = (1...5).map { level in
            makeMetric(key: String(level), questions: questions.filter { $0.difficulty == level })
        }
        let topicGroups = Dictionary(grouping: questions, by: \.primaryTopic)
        let topics = topicGroups.keys.sorted().compactMap { topic -> TopicPerformanceExportV1? in
            let group = topicGroups[topic] ?? []
            let summary = AdmissionsAnalytics.latestQuestionSummary(group)
            let review = group.filter { $0.reviewState != .none }.count
            guard summary.uniqueQuestionCount > 0 || review > 0 else { return nil }
            return TopicPerformanceExportV1(
                topic: topic,
                questionsAttempted: summary.uniqueQuestionCount,
                latestCorrect: summary.correctCount,
                latestIncorrect: summary.incorrectCount,
                latestPartial: summary.partialCount,
                accuracy: summary.accuracy,
                averageTimeSeconds: summary.averageSeconds,
                needsReviewCount: review
            )
        }
        let errorCounts = AdmissionsAnalytics.errorDistribution(attempts)
        return PerformanceExportV1(
            accuracyDefinition: "Correct / (Correct + Incorrect + Partial). Skipped attempts are counted separately and excluded from accuracy. Latest-result metrics use the most recent non-skipped attempt per unique Question.",
            percentageScale: "Decimal from 0 to 1; for example 0.742 means 74.2%.",
            overall: OverallPerformanceExportV1(
                uniqueQuestionsAttempted: latest.uniqueQuestionCount,
                totalAttempts: all.attemptCount,
                correctAttempts: all.correctCount,
                incorrectAttempts: all.incorrectCount,
                partialAttempts: all.partialCount,
                skippedAttempts: all.skippedCount,
                latestCorrect: latest.correctCount,
                latestIncorrect: latest.incorrectCount,
                latestPartial: latest.partialCount,
                latestResultAccuracy: latest.accuracy,
                attemptLevelAccuracy: all.accuracy,
                averageTimeSeconds: all.averageSeconds,
                medianTimeSeconds: median(timed)
            ),
            paperFit: paperFit,
            difficulty: difficulty,
            topics: topics,
            errorTypes: QuestionErrorType.allCases.map { CountExportV1(key: $0.rawValue, count: errorCounts[$0] ?? 0) }
        )
    }

    private static func makeMetric(key: String, questions: [AdmissionsQuestion]) -> MetricBreakdownExportV1 {
        let summary = AdmissionsAnalytics.latestQuestionSummary(questions)
        return MetricBreakdownExportV1(
            key: key,
            questionsAttempted: summary.uniqueQuestionCount,
            latestCorrect: summary.correctCount,
            latestIncorrect: summary.incorrectCount,
            latestPartial: summary.partialCount,
            accuracy: summary.accuracy,
            averageTimeSeconds: summary.averageSeconds
        )
    }

    private static func makeSpecificationCoverage(
        _ topics: [AdmissionsTopicState],
        calendar: Calendar
    ) throws -> SpecificationCoverageExportV1 {
        var ids = Set<String>()
        for topic in topics where !ids.insert(topic.stableTopicID).inserted {
            throw RevisionExportError.duplicateSpecificationID(topic.stableTopicID)
        }
        let covered = topics.filter { $0.specificationCoverage == .covered }.count
        let learning = topics.filter { $0.specificationCoverage == .learning }.count
        let notStarted = topics.filter { $0.specificationCoverage == .notStarted }.count
        return SpecificationCoverageExportV1(
            scope: "TMUA only",
            total: topics.count,
            covered: covered,
            learning: learning,
            notStarted: notStarted,
            coveragePercentage: topics.isEmpty ? nil : Double(covered) / Double(topics.count),
            items: topics.map { topic in
                SpecificationItemExportV1(
                    stableID: topic.stableTopicID,
                    officialCode: topic.stableTopicID,
                    section: topic.name.split(separator: ":", maxSplits: 1).count > 1
                        ? String(topic.name.split(separator: ":", maxSplits: 1)[0])
                        : nil,
                    title: topic.name,
                    coverageStatus: topic.specificationCoverage.rawValue,
                    lastReviewedAt: nil,
                    linkedTopic: topic.name,
                    notes: topic.notes.nilIfBlank
                )
            }
        )
    }

    private static func makeStandby(
        _ questions: [AdmissionsQuestion],
        questionDTOs: [String: QuestionExportV1]
    ) -> StandbyExportV1 {
        let byTopic = Dictionary(grouping: questions, by: \.primaryTopic)
        let byDifficulty = Dictionary(grouping: questions, by: { String($0.difficulty) })
        let byPaper = Dictionary(grouping: questions, by: { normalizedPaperFit($0.tmuaPaperFit) ?? "Unspecified" })
        return StandbyExportV1(
            totalQuestions: questions.count,
            unattemptedQuestions: questions.filter { $0.attempts.isEmpty }.count,
            needsReviewCount: questions.filter { $0.reviewState != .none }.count,
            byPrimaryTopic: byTopic.keys.sorted().map { CountExportV1(key: $0, count: byTopic[$0]?.count ?? 0) },
            byDifficulty: byDifficulty.keys.sorted().map { CountExportV1(key: $0, count: byDifficulty[$0]?.count ?? 0) },
            byPaperFit: byPaper.keys.sorted().map { CountExportV1(key: $0, count: byPaper[$0]?.count ?? 0) },
            questions: questions.compactMap { questionDTOs[$0.externalQuestionID] }
        )
    }

    private static func fullExportReadme(_ snapshot: RevisionExportV1) -> String {
        """
        # Revisr Full Data Export

        Exported: \(snapshot.export.exportedAt)
        Active admissions test: \(snapshot.profile.activeAdmissionsTest.uppercased())
        Format: \(fullFormatIdentifier), schema version \(schemaVersion)

        Revisr is a private, local-first admissions-preparation app. JSON files are authoritative; CSV files are convenient tabular views. `revision-snapshot.json` is the recommended starting point for revision planning, while the other files provide complete exported TMUA records.

        Outcomes: correct, incorrect, partial, skipped.
        Error types: knowledge, approach, algebra, misread, logic, slow, careless.
        Coverage values: notStarted, learning, covered.
        Review values: none, needsReview, redo.

        Accuracy = Correct / (Correct + Incorrect + Partial); Skipped is excluded. Latest-result metrics use the most recent non-skipped attempt per unique Question. Percentages are decimals from 0 to 1. Durations are integer seconds.

        Protected questions may be selected manually but are excluded from automatic practice. Official TMUA 2022 material is always protected; scheduled future official benchmark papers remain protected until their programme day.

        Source PDFs, copyrighted Question wording, internal file paths, debug logs, migration diagnostics, and inactive legacy school-subject data are not included. Nothing was uploaded automatically.
        """
    }

    private static func revisionSummary(_ snapshot: RevisionExportV1) -> String {
        let overall = snapshot.performance.overall
        let accuracy = overall.latestResultAccuracy.map { String(format: "%.1f%%", $0 * 100) } ?? "No scorable attempts"
        let errors = snapshot.performance.errorTypes
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { "- \($0.key.capitalized): \($0.count)" }
            .joined(separator: "\n")
        let upcoming = snapshot.upcoming.days.prefix(8).map {
            "- Day \($0.dayNumber) (\($0.date)): \($0.focus) — \($0.assignments.count) incomplete Questions, \($0.expectedTotalMinutes) min expected"
        }.joined(separator: "\n")
        return """
        # Revisr Revision Snapshot

        Exported: \(snapshot.export.exportedAt)

        ## Current programme
        \(snapshot.profile.programmeName ?? "No active programme")
        \(snapshot.profile.currentProgrammeDay.map { "Day \($0) of \(snapshot.programme.totalDays)" } ?? "Outside the active programme date range")
        Completed assignments: \(snapshot.programme.completedAssignments) / \(snapshot.programme.totalAssignments)

        ## Question performance
        Unique Questions attempted: \(overall.uniqueQuestionsAttempted)
        Total attempts: \(overall.totalAttempts)
        Latest-result accuracy: \(accuracy)

        ## Needs Review
        \(snapshot.needsReview.questions.count) Questions
        \(snapshot.needsReview.topics.count) topics

        ## Main error types
        \(errors.isEmpty ? "No recorded errors" : errors)

        ## Specification coverage
        Covered: \(snapshot.specificationCoverage.covered) / \(snapshot.specificationCoverage.total)
        Learning: \(snapshot.specificationCoverage.learning)
        Not started: \(snapshot.specificationCoverage.notStarted)

        ## Upcoming
        \(upcoming.isEmpty ? "No upcoming programme days" : upcoming)
        """
    }

    private static func validateFilePayloads(_ files: [String: Data]) throws {
        guard !files.isEmpty,
              !files.keys.contains(where: { $0.lowercased().hasSuffix(".pdf") }) else {
            throw RevisionExportError.invalidArchive
        }
        for (name, data) in files {
            guard !name.hasPrefix("/"), !name.contains("..") else {
                throw RevisionExportError.invalidArchive
            }
            if let text = String(data: data, encoding: .utf8), containsUnsafePath(text) {
                throw RevisionExportError.unsafeOutput
            }
        }
    }

    private static func makeTemporaryExportDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Revisr Exports", isDirectory: true)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func containsUnsafePath(_ value: String) -> Bool {
        value.contains("/private/var/")
            || value.contains("/var/mobile/Containers/")
            || value.contains("/Users/")
            || value.contains("file://")
    }

    private static func normalizedPaperFit(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.localizedCaseInsensitiveContains("paper 1") || value == "P1" { return "Paper 1" }
        if value.localizedCaseInsensitiveContains("paper 2") || value == "P2" { return "Paper 2" }
        return value.nilIfBlank
    }

    private static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return Double(values[middle - 1] + values[middle]) / 2
        }
        return Double(values[middle])
    }

    private static func attemptSort(_ lhs: QuestionAttempt, _ rhs: QuestionAttempt) -> Bool {
        if lhs.attemptedAt != rhs.attemptedAt { return lhs.attemptedAt < rhs.attemptedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func timestampString(_ date: Date, calendar: Calendar = DateUtilities.appCalendar()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter.string(from: date)
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.8g", $0) } ?? ""
    }
}

private enum CSVWriter {
    static func data(headers: [String], rows: [[String]]) -> Data {
        let lines = ([headers] + rows).map { $0.map(escape).joined(separator: ",") }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
