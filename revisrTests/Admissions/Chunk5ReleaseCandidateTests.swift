import SwiftData
import XCTest
@testable import revisr

@MainActor
final class Chunk5ReleaseCandidateTests: XCTestCase {
    private let calendar = DateUtilities.appCalendar(
        locale: Locale(identifier: "en_GB"),
        timeZone: TimeZone(identifier: "Europe/London")!
    )

    func testDateBoundariesFlexUnavailableAndExamDateNeverFallBack() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        try SeedDataService.seedIfNeeded(in: container.mainContext)
        let programme = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<AdmissionsProgramme>()).first)

        let expected: [(String, Int?)] = [
            ("2026-08-30", nil), ("2026-08-31", 4),
            ("2026-09-02", 6), ("2026-09-03", nil), ("2026-09-04", 7),
            ("2026-09-14", 12), ("2026-09-15", 13),
            ("2026-09-27", nil), ("2026-09-28", 21),
            ("2026-10-11", nil), ("2026-10-12", 29),
            ("2026-10-13", nil), ("2026-10-14", 30),
            ("2026-10-15", nil), ("2026-10-16", nil), ("2026-10-17", nil),
        ]
        for (value, day) in expected {
            let date = try date(value, hour: 15)
            XCTAssertEqual(programme.dayNumber(for: date, calendar: calendar), day, value)
            XCTAssertEqual(programme.programmeDay(for: date, calendar: calendar)?.dayNumber, day, value)
        }
    }

    func testTuesdayRestrictionAtBoundaryAndPermanentProtectionAcrossProgramme() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let programme = try XCTUnwrap(try context.fetch(FetchDescriptor<AdmissionsProgramme>()).first)
        let days = try context.fetch(FetchDescriptor<ProgrammeDay>())
        for number in [5, 9, 13, 18, 22, 26] {
            let day = try XCTUnwrap(days.first { $0.dayNumber == number })
            let scheduledDate = programme.date(for: number, calendar: calendar)
            let before = try XCTUnwrap(calendar.date(bySettingHour: 13, minute: 59, second: 59, of: scheduledDate))
            let atBoundary = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 0, second: 0, of: scheduledDate))
            XCTAssertFalse(programme.isAvailable(day, at: before, calendar: calendar))
            XCTAssertTrue(programme.isAvailable(day, at: atBoundary, calendar: calendar))
        }

        let tmua2022 = try context.fetch(FetchDescriptor<AdmissionsQuestion>()).filter {
            $0.family == "TMUA Actual" && $0.year == 2022
        }
        XCTAssertEqual(tmua2022.count, 40)
        for value in ["2026-08-30", "2026-09-05", "2026-10-14", "2026-10-16", "2026-11-16"] {
            XCTAssertTrue(ExtraPracticeSelector.select(
                from: tmua2022,
                filter: ExtraPracticeFilter(),
                programme: programme,
                on: try date(value, hour: 15),
                limit: 40,
                calendar: calendar
            ).isEmpty, value)
        }
    }

    func testActiveProgrammeHasOnlyDocumentedRepairRepeatsAndNoSameDayDuplicates() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let active = try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter(\.isImportedActive)
        XCTAssertEqual(active.count, 452)

        let dayQuestionPairs = active.compactMap { assignment -> String? in
            guard let day = assignment.programmeDay?.dayNumber,
                  let questionID = assignment.question?.externalQuestionID else { return nil }
            return "\(day)|\(questionID)"
        }
        XCTAssertEqual(dayQuestionPairs.count, 452)
        XCTAssertEqual(Set(dayQuestionPairs).count, 452)

        let byQuestion = Dictionary(grouping: active, by: { $0.question?.externalQuestionID ?? "missing" })
        let repeatDays = byQuestion.filter { $0.value.count > 1 }.mapValues { assignments in
            assignments.compactMap { $0.programmeDay?.dayNumber }.sorted()
        }
        XCTAssertEqual(repeatDays, [
            "MAT-2017-Q1F": [3, 10, 17, 30],
            "MAT-2018-Q1G": [2, 4],
            "MAT-2019-Q1D": [1, 4, 22, 29],
            "MAT-2020-Q1E": [2, 5, 22, 29],
            "TPRA-P2-Q03": [3, 10, 27, 29],
            "TSPEC-P1-Q09": [1, 27],
            "TSPEC-P1-Q18": [3, 10, 17, 30],
            "TSPEC-P1-Q19": [2, 22, 29],
            "TYLER-B-P2-Q09": [3, 17, 30],
            "TYLER-C-P1-Q05": [2, 17],
            "TYLER-C-P1-Q07": [2, 17, 22, 30],
            "YOTTA-P1-Q08": [3, 10],
            "YOTTA-P1-Q11": [1, 17, 30],
            "YOTTA-P2-Q08": [3, 10, 17, 30],
        ])
    }

    func testPersistentCleanSeedSurvivesReopenAndRepeatedLaunchSeeding() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Chunk5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")

        var container: ModelContainer? = try AppContainer.make(storeURL: store)
        try SeedDataService.seedIfNeeded(in: try XCTUnwrap(container).mainContext)
        container = nil

        container = try AppContainer.make(storeURL: store)
        let reopened = try XCTUnwrap(container).mainContext
        try SeedDataService.seedIfNeeded(in: reopened)
        try SeedDataService.seedIfNeeded(in: reopened)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 2_600)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<SourceDocument>()), 136)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<SolutionDocument>()), 120)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<QuestionSolutionLink>()), 2_364)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<ProgrammeDay>()), 30)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 894)
        XCTAssertEqual(
            try reopened.fetch(FetchDescriptor<ProgrammeAssignment>()).filter(\.isImportedActive).count,
            452
        )
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<QuestionAttempt>()), 0)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<StudySession>()), 0)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<StudyResult>()), 0)
    }

    func testReleaseCandidateStoreReimportIsIdempotent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent(".qa/chunk5/release-candidate-snapshot")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("Revisr.store").path) else {
            throw XCTSkip("Chunk 5 release-candidate fixture is unavailable")
        }
        let retained = ProcessInfo.processInfo.environment["CHUNK5_IDEMPOTENCY_OUTPUT"]
            .map(URL.init(fileURLWithPath:))
        let destination = retained ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Chunk5-Idempotency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["Revisr.store", "Revisr.store-wal", "Revisr.store-shm"] {
            let input = source.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: input.path) {
                try FileManager.default.copyItem(at: input, to: destination.appendingPathComponent(name))
            }
        }
        defer { if retained == nil { try? FileManager.default.removeItem(at: destination) } }

        let container = try AppContainer.make(storeURL: destination.appendingPathComponent("Revisr.store"))
        let context = container.mainContext
        let before = try releaseCandidateSignature(context)
        try SeedDataService.seedIfNeeded(in: context)
        XCTAssertEqual(try releaseCandidateSignature(context), before)
        try SeedDataService.seedIfNeeded(in: context)
        XCTAssertEqual(try releaseCandidateSignature(context), before)
    }

    func testLegacyChunk2StoreRunsCompleteReleaseCandidateMigrationChain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent(".qa/data-audit/snapshot-before")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("Revisr.store").path) else {
            throw XCTSkip("Audited Chunk 2 legacy-store fixture is unavailable")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Chunk5-Legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        for name in ["Revisr.store", "Revisr.store-wal", "Revisr.store-shm"] {
            let input = source.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: input.path) {
                try FileManager.default.copyItem(at: input, to: destination.appendingPathComponent(name))
            }
        }

        let container = try AppContainer.make(storeURL: destination.appendingPathComponent("Revisr.store"))
        let context = container.mainContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 1_573)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), 48)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StudySession>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StudyResult>()), 0)
        let historyBefore = try userHistorySignature(context)

        try SeedDataService.seedIfNeeded(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 2_600)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocument>()), 136)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolutionDocument>()), 120)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()), 2_364)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 894)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter(\.isImportedActive).count,
            452
        )
        XCTAssertEqual(try userHistorySignature(context), historyBefore)

        let firstReleaseCandidate = try releaseCandidateSignature(context)
        try SeedDataService.seedIfNeeded(in: context)
        XCTAssertEqual(try releaseCandidateSignature(context), firstReleaseCandidate)
        XCTAssertEqual(try userHistorySignature(context), historyBefore)
    }

    private func date(_ value: String, hour: Int) throws -> Date {
        let pieces = value.split(separator: "-").compactMap { Int($0) }
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: pieces[0], month: pieces[1], day: pieces[2], hour: hour
        )))
    }

    private func releaseCandidateSignature(_ context: ModelContext) throws -> [String] {
        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
            .map { "Q|\($0.externalQuestionID)|\($0.importRevision)|\($0.reviewStateRawValue)|\($0.userNotes ?? "")" }
        let sources = try context.fetch(FetchDescriptor<SourceDocument>())
            .map { "S|\($0.stableSourceID)|\($0.importRevision)|\($0.checksum ?? "")" }
        let solutions = try context.fetch(FetchDescriptor<SolutionDocument>())
            .map { "D|\($0.stableSolutionID)|\($0.importRevision)|\($0.checksum ?? "")" }
        let links = try context.fetch(FetchDescriptor<QuestionSolutionLink>())
            .map { "L|\($0.stableLinkID)|\($0.importRevision)" }
        let days = try context.fetch(FetchDescriptor<ProgrammeDay>())
            .map { "P|\($0.externalDayID)|\($0.scheduleOffsetDays.map(String.init) ?? "nil")|\($0.importedActiveString)" }
        let assignments = try context.fetch(FetchDescriptor<ProgrammeAssignment>())
            .map { "A|\($0.externalAssignmentID)|\($0.isImportedActive)|\($0.programmeDay?.dayNumber ?? -1)|\($0.question?.externalQuestionID ?? "nil")" }
        let attempts = try context.fetch(FetchDescriptor<QuestionAttempt>())
            .map { "T|\($0.id.uuidString)|\($0.attemptedAt.timeIntervalSinceReferenceDate)|\($0.outcomeRawValue)|\($0.timeTakenSeconds)" }
        return (questions + sources + solutions + links + days + assignments + attempts).sorted()
    }

    private func userHistorySignature(_ context: ModelContext) throws -> [String] {
        let attempts = try context.fetch(FetchDescriptor<QuestionAttempt>()).map {
            [
                "attempt", $0.id.uuidString, $0.question?.externalQuestionID ?? "nil",
                $0.programmeAssignment?.externalAssignmentID ?? "nil",
                String($0.attemptedAt.timeIntervalSinceReferenceDate), $0.outcomeRawValue,
                $0.errorTypeRawValue ?? "nil", $0.notes, String($0.timeTakenSeconds),
            ].joined(separator: "|")
        }
        let sessions = try context.fetch(FetchDescriptor<StudySession>()).map {
            [
                "session", $0.id.uuidString, String($0.date.timeIntervalSinceReferenceDate),
                String($0.actualStartDate?.timeIntervalSinceReferenceDate ?? -1),
                String($0.endDate?.timeIntervalSinceReferenceDate ?? -1), String($0.duration),
                $0.activityRawValue, $0.notes, $0.subjectNameSnapshot,
                $0.moduleNameSnapshot ?? "nil", $0.topicNameSnapshot ?? "nil",
            ].joined(separator: "|")
        }
        let results = try context.fetch(FetchDescriptor<StudyResult>()).map {
            [
                "result", $0.id.uuidString, String($0.date.timeIntervalSinceReferenceDate),
                $0.paperOrModuleLabel, String($0.rawScore ?? -1),
                String($0.maximumScore ?? -1), String($0.scaledScore ?? -1), $0.notes,
            ].joined(separator: "|")
        }
        let d1D3 = try context.fetch(FetchDescriptor<ProgrammeAssignment>()).compactMap { assignment -> String? in
            guard let day = assignment.programmeDay?.dayNumber, day <= 3 else { return nil }
            return [
                "assignment", String(day), assignment.externalAssignmentID,
                assignment.question?.externalQuestionID ?? "nil", String(assignment.isImportedActive),
                String(assignment.isComplete),
            ].joined(separator: "|")
        }
        return (attempts + sessions + results + d1D3).sorted()
    }
}

private extension ProgrammeDay {
    var importedActiveString: String { String(isImportedActive) }
}
