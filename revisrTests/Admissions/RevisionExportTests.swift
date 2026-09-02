import SwiftData
import XCTest
@testable import revisr

@MainActor
final class RevisionExportTests: XCTestCase {
    private let appInfo = ExportApplicationInfo(appName: "Revisr", version: "1.0-test", build: "99")

    private var calendar: Calendar {
        DateUtilities.appCalendar(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    private var exportDate: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 10,
            minute: 30
        ))!
    }

    func testSnapshotSchemaPreservesAttemptsReviewProgrammeCoverageAndProtection() throws {
        let fixture = try makeFixture()
        let dataSet = try RevisionExportService.buildDataSet(
            in: fixture.context,
            now: exportDate,
            calendar: calendar,
            applicationInfo: appInfo
        )
        let snapshot = dataSet.snapshot
        let encoded = try RevisionExportService.encodeJSON(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(snapshot.export.formatIdentifier, "revisr.export.revision.v2")
        XCTAssertEqual(snapshot.export.schemaVersion, 2)
        XCTAssertEqual(snapshot.export.exportedAt, "2026-08-22T10:30:00Z")
        XCTAssertEqual(
            Set(json.keys),
            Set([
                "export", "profile", "tmua", "programme", "performance", "needsReview",
                "specificationCoverage", "results", "standby", "recentActivity", "upcoming",
                "questionCatalog", "attemptHistory"
            ])
        )

        let history = try XCTUnwrap(snapshot.attemptHistory.first(where: { $0.questionID == fixture.questionID }))
        XCTAssertEqual(history.attempts.map(\.attemptNumber), [1, 2])
        XCTAssertEqual(history.attempts.map(\.outcome), ["incorrect", "correct"])
        XCTAssertEqual(history.attempts.map(\.timeTakenSeconds), [372, 241])
        XCTAssertEqual(history.attempts.first?.errorType, "approach")
        XCTAssertEqual(history.attempts.first?.notes, "Missed the constraint")
        XCTAssertEqual(history.attempts.first?.attemptedAt, "2026-08-20T09:15:00Z")
        XCTAssertEqual(history.attempts.last?.attemptedAt, "2026-08-21T09:15:00Z")
        XCTAssertEqual(snapshot.performance.overall.totalAttempts, 2)
        XCTAssertEqual(snapshot.performance.overall.uniqueQuestionsAttempted, 1)
        XCTAssertEqual(snapshot.performance.overall.latestCorrect, 1)

        let review = try XCTUnwrap(snapshot.needsReview.questions.first(where: {
            $0.question.questionID == fixture.questionID
        }))
        XCTAssertEqual(review.reviewState, "redo")
        XCTAssertEqual(review.latestOutcome, "correct")
        XCTAssertEqual(review.attemptCount, 2)
        XCTAssertTrue(snapshot.needsReview.topics.contains(where: { $0.topicID == fixture.topicID }))

        XCTAssertEqual(snapshot.programme.currentDayNumber, 6)
        XCTAssertEqual(snapshot.programme.currentDay?.dayNumber, 6)
        XCTAssertEqual(snapshot.programme.totalDays, 30)
        XCTAssertEqual(snapshot.programme.totalAssignments, 452)
        XCTAssertEqual(snapshot.upcoming.days.map(\.dayNumber), Array(6...13))
        XCTAssertTrue(snapshot.upcoming.days.flatMap(\.assignments).allSatisfy { !$0.questionID.isEmpty })

        let coverage = snapshot.specificationCoverage
        XCTAssertEqual(coverage.total, 21)
        XCTAssertEqual(coverage.covered + coverage.learning + coverage.notStarted, coverage.total)
        XCTAssertEqual(Set(coverage.items.map(\.stableID)).count, coverage.items.count)
        XCTAssertEqual(
            coverage.items.first(where: { $0.stableID == fixture.topicID })?.coverageStatus,
            "learning"
        )

        let protected2022 = snapshot.tmua.protectedQuestions.filter { $0.year == 2022 }
        XCTAssertEqual(protected2022.count, 40)
        XCTAssertTrue(protected2022.allSatisfy(\.manuallySelectable))
        XCTAssertTrue(protected2022.allSatisfy(\.excludedFromAutomaticPractice))
        XCTAssertTrue(protected2022.allSatisfy { $0.benchmarkState == "protectedOfficialTMUA2022" })

        XCTAssertEqual(dataSet.allQuestions.count, 1_949)
        XCTAssertTrue(dataSet.allQuestions.allSatisfy { $0.admissionsTest == "tmua" })
        XCTAssertEqual(dataSet.allQuestions.filter { $0.primaryPreparationStream == "tmua" }.count, 1_364)
        XCTAssertTrue(dataSet.allQuestions.allSatisfy { $0.preparationClassificationSource == "canonical" })
        XCTAssertEqual(dataSet.solutions.filter { $0.mediaType == "video" }.count, 8)
        XCTAssertEqual(dataSet.solutions.filter { $0.videoAvailable == true }.count, 8)
        XCTAssertEqual(Set(dataSet.allQuestions.map(\.questionID)).count, 1_949)
        XCTAssertEqual(snapshot.standby.totalQuestions, 1_488)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(fixture.legacySentinel))
    }

    func testFullArchiveContainsExpectedReadableFilesWithoutPDFsOrDevicePaths() throws {
        let fixture = try makeFixture()
        let dataSet = try RevisionExportService.buildDataSet(
            in: fixture.context,
            now: exportDate,
            calendar: calendar,
            applicationInfo: appInfo
        )
        let archive = try RevisionExportService.makeFullArchiveData(from: dataSet, now: exportDate)
        let entries = try ZIPArchiveWriter.entries(in: archive)
        let names = Set(entries.map(\.name))
        let expected: Set<String> = [
            "README.md", "manifest.json", "revision-summary.md", "revision-snapshot.json",
            "questions.json", "questions.csv", "attempts.json", "attempts.csv",
            "programme.json", "programme-assignments.csv", "specification-coverage.json",
            "specification-coverage.csv", "results.json", "results.csv", "topics.json",
            "settings.json", "sources.json", "solutions.json"
        ]

        XCTAssertEqual(names, expected)
        XCTAssertFalse(names.contains(where: { $0.lowercased().hasSuffix(".pdf") }))
        XCTAssertGreaterThan(archive.count, 1_000)

        for entry in entries where entry.name.hasSuffix(".json") {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: entry.data), entry.name)
        }
        let allText = entries.compactMap { String(data: $0.data, encoding: .utf8) }.joined(separator: "\n")
        XCTAssertFalse(allText.contains("/Users/"))
        XCTAssertFalse(allText.contains("/private/var/"))
        XCTAssertFalse(allText.contains("/var/mobile/Containers/"))
        XCTAssertFalse(allText.contains("file://"))
        XCTAssertFalse(allText.contains(fixture.legacySentinel))

        let manifestEntry = try XCTUnwrap(entries.first(where: { $0.name == "manifest.json" }))
        let manifest = try JSONDecoder().decode(FullExportManifestV1.self, from: manifestEntry.data)
        XCTAssertEqual(manifest.formatIdentifier, "revisr.export.full.v2")
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(Set(manifest.files), expected)
    }

    func testCreatingTwoExportsIsReadOnlyAndDeterministicForOneSnapshotTime() throws {
        let fixture = try makeFixture()
        let before = try modelCounts(in: fixture.context)
        XCTAssertFalse(fixture.context.hasChanges)

        let first = try RevisionExportService.createSnapshotFile(
            in: fixture.context,
            now: exportDate,
            calendar: calendar,
            applicationInfo: appInfo
        )
        let full = try RevisionExportService.createFullExportFile(
            in: fixture.context,
            now: exportDate,
            calendar: calendar,
            applicationInfo: appInfo
        )
        let second = try RevisionExportService.createSnapshotFile(
            in: fixture.context,
            now: exportDate,
            calendar: calendar,
            applicationInfo: appInfo
        )

        XCTAssertEqual(first.url.lastPathComponent, "Revisr-Revision-Snapshot-2026-08-22.json")
        XCTAssertEqual(full.url.lastPathComponent, "Revisr-Full-Export-2026-08-22.zip")
        XCTAssertEqual(try Data(contentsOf: first.url), try Data(contentsOf: second.url))
        XCTAssertEqual(try modelCounts(in: fixture.context), before)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testZIPWriterRejectsTraversalAndRoundTripsUnicodeStoreEntries() throws {
        XCTAssertThrowsError(try ZIPArchiveWriter.makeArchive(
            entries: [.init(name: "../private.json", data: Data())],
            modifiedAt: exportDate
        ))

        let payload = Data("Revisr — local only".utf8)
        let archive = try ZIPArchiveWriter.makeArchive(
            entries: [.init(name: "notes/revision-✓.txt", data: payload)],
            modifiedAt: exportDate
        )
        XCTAssertEqual(try ZIPArchiveWriter.entries(in: archive), [
            .init(name: "notes/revision-✓.txt", data: payload)
        ])
    }

    private func makeFixture() throws -> (
        container: ModelContainer,
        context: ModelContext,
        questionID: String,
        topicID: String,
        legacySentinel: String
    ) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)

        let programme = try XCTUnwrap(context.fetch(FetchDescriptor<AdmissionsProgramme>()).first)
        let daySixOffset = try XCTUnwrap(programme.days.first { $0.dayNumber == 6 }?.scheduleOffsetDays)
        programme.startDate = calendar.date(
            byAdding: .day,
            value: -daySixOffset,
            to: calendar.startOfDay(for: exportDate)
        )!
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
        settings.tmuaProgrammeStartDate = programme.startDate

        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let question = try XCTUnwrap(questions.first(where: \.isStandby))
        question.reviewState = .redo
        question.userNotes = "Revisit the constraint before solving"

        let firstDate = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 20, hour: 9, minute: 15
        ))!
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate)!
        context.insert(QuestionAttempt(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            attemptedAt: firstDate,
            outcome: .incorrect,
            timeTakenSeconds: 372,
            errorType: .approach,
            notes: "Missed the constraint",
            origin: .questionBank,
            question: question
        ))
        context.insert(QuestionAttempt(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            attemptedAt: secondDate,
            outcome: .correct,
            timeTakenSeconds: 241,
            notes: "Corrected approach",
            origin: .needsReview,
            question: question
        ))

        let topic = try XCTUnwrap(context.fetch(FetchDescriptor<AdmissionsTopicState>()).first)
        topic.needsReview = true
        topic.manualStatus = .needsWork
        topic.specificationCoverage = .learning
        topic.notes = "Review this topic"

        context.insert(StudyResult(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: firstDate,
            paperOrModuleLabel: "TMUA Paper 1 mock",
            rawScore: 14,
            maximumScore: 20,
            scaledScore: 6.8,
            notes: "Timed mock",
            subjectNameSnapshot: "TMUA",
            moduleNameSnapshot: "Paper 1"
        ))

        let legacySentinel = "LEGACY-FURTHER-MATHEMATICS-DO-NOT-EXPORT"
        context.insert(Subject(
            name: legacySentinel,
            targetPercentage: 0,
            displayOrder: 99,
            isActiveForStudy: false
        ))
        let source = try XCTUnwrap(context.fetch(FetchDescriptor<SourceDocument>()).first)
        source.localFilename = "/private/var/mobile/Containers/Data/Application/secret/source.pdf"
        try context.save()
        return (container, context, question.externalQuestionID, topic.stableTopicID, legacySentinel)
    }

    private func modelCounts(in context: ModelContext) throws -> [String: Int] {
        [
            "questions": try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()),
            "attempts": try context.fetchCount(FetchDescriptor<QuestionAttempt>()),
            "programmes": try context.fetchCount(FetchDescriptor<AdmissionsProgramme>()),
            "days": try context.fetchCount(FetchDescriptor<ProgrammeDay>()),
            "assignments": try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()),
            "topics": try context.fetchCount(FetchDescriptor<AdmissionsTopicState>()),
            "results": try context.fetchCount(FetchDescriptor<StudyResult>()),
            "settings": try context.fetchCount(FetchDescriptor<AppSettings>()),
            "sources": try context.fetchCount(FetchDescriptor<SourceDocument>())
        ]
    }
}
