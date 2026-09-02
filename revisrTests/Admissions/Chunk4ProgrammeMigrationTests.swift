import SwiftData
import XCTest
@testable import revisr

@MainActor
final class Chunk4ProgrammeMigrationTests: XCTestCase {
    func testFreshSeedLeavesEveryActiveAssignmentFullyResolved() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)

        let active = try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter(\.isImportedActive)
        XCTAssertEqual(active.count, 452)
        XCTAssertEqual(active.filter { $0.programmeDay == nil }.map(\.externalAssignmentID), [])
        XCTAssertEqual(active.filter { $0.question == nil }.map(\.externalAssignmentID), [])
        let activeFromDays = try context.fetch(FetchDescriptor<ProgrammeDay>())
            .flatMap(\.assignments).filter(\.isImportedActive)
        XCTAssertEqual(activeFromDays.count, 452)
        XCTAssertEqual(activeFromDays.filter { $0.question == nil }.map(\.externalAssignmentID), [])
        let forwardQuestionIDs = Set(active.compactMap { $0.question?.externalQuestionID })
        let inverseQuestionIDs = Set(try context.fetch(FetchDescriptor<AdmissionsQuestion>()).filter {
            $0.programmeAssignments.contains(where: \.isImportedActive)
        }.map(\.externalQuestionID))
        XCTAssertEqual(inverseQuestionIDs, forwardQuestionIDs)

        let reopened = ModelContext(container)
        let persistedActive = try reopened.fetch(FetchDescriptor<ProgrammeAssignment>())
            .filter(\.isImportedActive)
        XCTAssertEqual(persistedActive.count, 452)
        XCTAssertEqual(persistedActive.filter { $0.question == nil }.map(\.externalAssignmentID), [])

        _ = try reopened.fetch(FetchDescriptor<AdmissionsQuestion>())
        _ = try reopened.fetch(FetchDescriptor<QuestionSolutionLink>())
        let refaultedActive = try reopened.fetch(FetchDescriptor<ProgrammeAssignment>())
            .filter(\.isImportedActive)
        XCTAssertEqual(refaultedActive.filter { $0.question == nil }.map(\.externalAssignmentID), [])
    }

    func testProductionPathMigratesCurrentDeviceStoreWithoutChangingHistory() throws {
        let temporary = try copiedCurrentDeviceStore(retainEnvironmentKey: "CHUNK4_SANDBOX_OUTPUT")
        let retained = ProcessInfo.processInfo.environment["CHUNK4_SANDBOX_OUTPUT"] != nil
        defer { if !retained { try? FileManager.default.removeItem(at: temporary) } }

        let container = try AppContainer.make(storeURL: temporary.appendingPathComponent("Revisr.store"))
        let context = container.mainContext
        let attemptsBefore = try attemptSignatures(in: context)
        let sessionsBefore = try sessionSignatures(in: context)
        let resultsBefore = try resultSignatures(in: context)
        let historicalBefore = try historicalSignatures(in: context)
        let reviewBefore = try reviewSignatures(in: context)

        XCTAssertEqual(attemptsBefore.count, 48)
        XCTAssertEqual(sessionsBefore.count, 3)
        XCTAssertEqual(resultsBefore.count, 0)
        XCTAssertEqual(try d4PlusActivity(in: context).count, 0)
        XCTAssertEqual(try completionCounts(in: context), [1: 16, 2: 16, 3: 15])

        try runProductionSeed(in: context)
        try assertFinalProgramme(
            in: context,
            attemptsBefore: attemptsBefore,
            sessionsBefore: sessionsBefore,
            resultsBefore: resultsBefore,
            historicalBefore: historicalBefore,
            reviewBefore: reviewBefore
        )

        let firstCatalogue = try catalogueSignature(in: context)
        let firstAssignments = try allAssignmentSignatures(in: context)
        try runProductionSeed(in: context)
        XCTAssertEqual(try catalogueSignature(in: context), firstCatalogue)
        XCTAssertEqual(try allAssignmentSignatures(in: context), firstAssignments)
        try assertFinalProgramme(
            in: context,
            attemptsBefore: attemptsBefore,
            sessionsBefore: sessionsBefore,
            resultsBefore: resultsBefore,
            historicalBefore: historicalBefore,
            reviewBefore: reviewBefore
        )
    }

    func testAttemptedAndCompletedD4PlusAssignmentsSurviveReplacement() throws {
        let temporary = try copiedCurrentDeviceStore(retainEnvironmentKey: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let container = try AppContainer.make(storeURL: temporary.appendingPathComponent("Revisr.store"))
        let context = container.mainContext
        try AdmissionsImportService.upsert(AdmissionsManifest.bundled(), in: context)

        let migration = try AdmissionsProgrammeMigrationManifest.bundled()
        let selectedIDs = Set(migration.assignments.map(\.externalAssignmentID))
        let obsoleteD4 = try context.fetch(FetchDescriptor<ProgrammeAssignment>())
            .filter {
                $0.programmeDay?.dayNumber == 4
                    && !selectedIDs.contains($0.externalAssignmentID)
                    && $0.attempts.isEmpty
            }
            .sorted { $0.externalAssignmentID < $1.externalAssignmentID }
        let completed = try XCTUnwrap(obsoleteD4.first)
        let skipped = try XCTUnwrap(obsoleteD4.dropFirst().first)
        let completedIdentity = identity(completed)
        let skippedIdentity = identity(skipped)
        context.insert(QuestionAttempt(
            outcome: .correct,
            timeTakenSeconds: 240,
            notes: "Synthetic preservation fixture",
            origin: .programme,
            question: completed.question,
            programmeAssignment: completed
        ))
        context.insert(QuestionAttempt(
            outcome: .skipped,
            timeTakenSeconds: 0,
            notes: "Synthetic preservation fixture",
            origin: .programme,
            question: skipped.question,
            programmeAssignment: skipped
        ))
        try context.save()

        try AdmissionsProgrammeMigrationService.upsert(migration, in: context)
        XCTAssertTrue(completed.isImportedActive)
        XCTAssertTrue(skipped.isImportedActive)
        XCTAssertEqual(identity(completed), completedIdentity)
        XCTAssertEqual(identity(skipped), skippedIdentity)
        XCTAssertEqual(completed.attempts.count, 1)
        XCTAssertEqual(skipped.attempts.count, 1)
        XCTAssertTrue(completed.isComplete)
        XCTAssertFalse(skipped.isComplete)
        XCTAssertEqual(try activeAssignmentCount(in: context), 454)
        XCTAssertEqual(completed.programmeDay?.allocatedQuestionCount, 14)

        let signatures = try allAssignmentSignatures(in: context)
        try AdmissionsProgrammeMigrationService.upsert(migration, in: context)
        XCTAssertEqual(try allAssignmentSignatures(in: context), signatures)
        XCTAssertEqual(try activeAssignmentCount(in: context), 454)
    }

    private func runProductionSeed(in context: ModelContext) throws {
        try AdmissionsImportService.seedBundledManifestIfNeeded(in: context)
        try AdmissionsSolutionsImportService.seedBundledManifestIfNeeded(in: context)
        try AdmissionsProgrammeMigrationService.seedBundledMigrationIfNeeded(in: context)
    }

    private func assertFinalProgramme(
        in context: ModelContext,
        attemptsBefore: Set<String>,
        sessionsBefore: Set<String>,
        resultsBefore: Set<String>,
        historicalBefore: Set<String>,
        reviewBefore: Set<String>
    ) throws {
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 2_600)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocument>()), 136)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolutionDocument>()), 120)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()), 2_364)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 894)
        XCTAssertEqual(try activeAssignmentCount(in: context), 452)
        XCTAssertEqual(try attemptSignatures(in: context), attemptsBefore)
        XCTAssertEqual(try sessionSignatures(in: context), sessionsBefore)
        XCTAssertEqual(try resultSignatures(in: context), resultsBefore)
        XCTAssertEqual(try historicalSignatures(in: context), historicalBefore)
        XCTAssertTrue(reviewBefore.isSubset(of: try reviewSignatures(in: context)))
        XCTAssertEqual(try completionCounts(in: context), [1: 16, 2: 16, 3: 15])

        let programme = try XCTUnwrap(try context.fetch(FetchDescriptor<AdmissionsProgramme>()).first {
            $0.externalProgrammeID == "TMUA-30-DAY-2026"
        })
        let calendar = DateUtilities.appCalendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let expectedDates: [Int: DateComponents] = [
            4: .init(year: 2026, month: 8, day: 31), 5: .init(year: 2026, month: 9, day: 1),
            6: .init(year: 2026, month: 9, day: 2), 7: .init(year: 2026, month: 9, day: 4),
            8: .init(year: 2026, month: 9, day: 7), 9: .init(year: 2026, month: 9, day: 8),
            10: .init(year: 2026, month: 9, day: 9), 11: .init(year: 2026, month: 9, day: 11),
            12: .init(year: 2026, month: 9, day: 14), 13: .init(year: 2026, month: 9, day: 15),
            14: .init(year: 2026, month: 9, day: 16), 15: .init(year: 2026, month: 9, day: 18),
            16: .init(year: 2026, month: 9, day: 19), 17: .init(year: 2026, month: 9, day: 21),
            18: .init(year: 2026, month: 9, day: 22), 19: .init(year: 2026, month: 9, day: 23),
            20: .init(year: 2026, month: 9, day: 25), 21: .init(year: 2026, month: 9, day: 28),
            22: .init(year: 2026, month: 9, day: 29), 23: .init(year: 2026, month: 9, day: 30),
            24: .init(year: 2026, month: 10, day: 2), 25: .init(year: 2026, month: 10, day: 5),
            26: .init(year: 2026, month: 10, day: 6), 27: .init(year: 2026, month: 10, day: 7),
            28: .init(year: 2026, month: 10, day: 9), 29: .init(year: 2026, month: 10, day: 12),
            30: .init(year: 2026, month: 10, day: 14),
        ]
        for (number, components) in expectedDates {
            let expected = try XCTUnwrap(calendar.date(from: components))
            XCTAssertTrue(calendar.isDate(programme.date(for: number, calendar: calendar), inSameDayAs: expected))
        }
        for number in [5, 9, 13, 18, 22, 26] {
            XCTAssertEqual(programme.days.first { $0.dayNumber == number }?.earliestStartMinute, 840)
        }
        for components in [
            DateComponents(year: 2026, month: 9, day: 5), DateComponents(year: 2026, month: 9, day: 12),
            DateComponents(year: 2026, month: 9, day: 26), DateComponents(year: 2026, month: 10, day: 3),
            DateComponents(year: 2026, month: 10, day: 10), DateComponents(year: 2026, month: 10, day: 13),
            DateComponents(year: 2026, month: 10, day: 15),
        ] {
            XCTAssertNil(programme.dayNumber(for: try XCTUnwrap(calendar.date(from: components)), calendar: calendar))
        }

        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        XCTAssertEqual(questions.filter { $0.family == "TMUA Actual" && $0.year == 2022 && $0.protection != .none }.count, 40)
        XCTAssertFalse(questions.contains { question in
            question.family == "TMUA Actual" && question.year == 2022
                && question.programmeAssignments.contains(where: \.isImportedActive)
        })
        try assertBenchmarkProtection(programme: programme, questions: questions, calendar: calendar)

        let subjects = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Subject>()).map {
            ($0.name, $0.isActiveForStudy)
        })
        XCTAssertEqual(subjects["TMUA"], true)
        XCTAssertEqual(subjects["Mathematics"], false)
        XCTAssertEqual(subjects["Further Mathematics"], false)
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(settings.tmuaExamDate), inSameDayAs: try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 16)))))
    }

    private func assertBenchmarkProtection(
        programme: AdmissionsProgramme,
        questions: [AdmissionsQuestion],
        calendar: Calendar
    ) throws {
        let checkpoints: [(Int, Int, String)] = [
            (2017, 15, "Paper 1"), (2017, 16, "Paper 2"),
            (2018, 19, "Paper 1"), (2018, 20, "Paper 2"),
            (2019, 21, "Paper 1"), (2019, 21, "Paper 2"),
            (2020, 25, "Paper 1"), (2020, 26, "Paper 2"),
            (2021, 28, "Paper 1"), (2021, 28, "Paper 2"),
        ]
        for (year, day, paper) in checkpoints {
            let question = try XCTUnwrap(questions.first {
                $0.family == "TMUA Actual" && $0.year == year && $0.paper == paper
            })
            let scheduled = programme.date(for: day, calendar: calendar)
            let before = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: scheduled))
            XCTAssertTrue(ExtraPracticeSelector.select(
                from: [question], filter: ExtraPracticeFilter(), programme: programme,
                on: before, limit: 1, calendar: calendar
            ).isEmpty)
            XCTAssertEqual(ExtraPracticeSelector.select(
                from: [question], filter: ExtraPracticeFilter(), programme: programme,
                on: scheduled, limit: 1, calendar: calendar
            ).map(\.externalQuestionID), [question.externalQuestionID])
        }
    }

    private func copiedCurrentDeviceStore(retainEnvironmentKey: String?) throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let snapshot = root.appendingPathComponent(".qa/chunk4/pre-migration-device")
        let sourceStore = snapshot.appendingPathComponent("Revisr.store")
        guard FileManager.default.fileExists(atPath: sourceStore.path) else {
            throw XCTSkip("Current paired-device store fixture is unavailable")
        }
        let retained = retainEnvironmentKey.flatMap { ProcessInfo.processInfo.environment[$0] }
            .map(URL.init(fileURLWithPath:))
        let destination = retained ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Chunk4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["Revisr.store", "Revisr.store-wal", "Revisr.store-shm"] {
            let source = snapshot.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent(name))
            }
        }
        return destination
    }

    private func identity(_ assignment: ProgrammeAssignment) -> String {
        "\(assignment.externalAssignmentID)|\(assignment.programmeDay?.dayNumber ?? -1)|\(assignment.question?.externalQuestionID ?? "nil")"
    }

    private func activeAssignmentCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter(\.isImportedActive).count
    }

    private func d4PlusActivity(in context: ModelContext) throws -> [ProgrammeAssignment] {
        try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter {
            ($0.programmeDay?.dayNumber ?? 0) >= 4 && !$0.attempts.isEmpty
        }
    }

    private func completionCounts(in context: ModelContext) throws -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProgrammeDay>())
            .filter { (1...3).contains($0.dayNumber) }
            .map { ($0.dayNumber, $0.assignments.filter { $0.isImportedActive && $0.isComplete }.count) })
    }

    private func attemptSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<QuestionAttempt>()).map {
            [$0.id.uuidString, $0.question?.externalQuestionID ?? "nil", $0.programmeAssignment?.externalAssignmentID ?? "nil", String($0.attemptedAt.timeIntervalSince1970), $0.outcome.rawValue, $0.errorType?.rawValue ?? "nil", $0.notes, String($0.timeTakenSeconds)].joined(separator: "|")
        })
    }

    private func sessionSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<StudySession>()).map {
            [$0.id.uuidString, String($0.date.timeIntervalSince1970), String($0.duration), $0.notes, $0.subjectNameSnapshot, $0.moduleNameSnapshot ?? "nil"].joined(separator: "|")
        })
    }

    private func resultSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<StudyResult>()).map {
            [$0.id.uuidString, String($0.date.timeIntervalSince1970), $0.paperOrModuleLabel, $0.notes].joined(separator: "|")
        })
    }

    private func historicalSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter {
            ($0.programmeDay?.dayNumber ?? 31) <= 3
        }.map(identity))
    }

    private func reviewSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<AdmissionsQuestion>()).map {
            "\($0.externalQuestionID)|\($0.reviewStateRawValue)|\($0.userNotes)"
        })
    }

    private func allAssignmentSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<ProgrammeAssignment>()).map {
            [identity($0), $0.block ?? "nil", $0.purpose ?? "nil", String($0.suggestedTimeCapMinutes ?? -1), String($0.displayOrder), String($0.isImportedActive), $0.attempts.map(\.id.uuidString).sorted().joined(separator: ",")].joined(separator: "|")
        })
    }

    private func catalogueSignature(in context: ModelContext) throws -> [String: Int] {
        [
            "questions": try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()),
            "sources": try context.fetchCount(FetchDescriptor<SourceDocument>()),
            "solutions": try context.fetchCount(FetchDescriptor<SolutionDocument>()),
            "links": try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()),
            "assignments": try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()),
            "activeAssignments": try activeAssignmentCount(in: context),
            "attempts": try context.fetchCount(FetchDescriptor<QuestionAttempt>()),
            "sessions": try context.fetchCount(FetchDescriptor<StudySession>()),
            "results": try context.fetchCount(FetchDescriptor<StudyResult>()),
        ]
    }
}
