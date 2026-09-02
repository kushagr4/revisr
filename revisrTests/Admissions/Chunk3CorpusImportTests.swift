import SwiftData
import XCTest
@testable import revisr

@MainActor
final class Chunk3CorpusImportTests: XCTestCase {
    func testStagedCorpusImportsIntoAuditedLegacyStoreWithoutChangingHistory() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let snapshot = root.appendingPathComponent(".qa/data-audit/snapshot-before")
        let sourceStore = snapshot.appendingPathComponent("Revisr.store")
        guard FileManager.default.fileExists(atPath: sourceStore.path) else {
            throw XCTSkip("Audited Chunk 2 store fixture is unavailable")
        }
        let candidate = try latestCandidate(in: root.appendingPathComponent(".qa/chunk3"))
        let manifest = try JSONDecoder().decode(
            AdmissionsManifest.self,
            from: Data(contentsOf: candidate.appendingPathComponent("AdmissionsManifest.json"))
        )
        let solutionsManifest = try JSONDecoder().decode(
            AdmissionsSolutionsManifest.self,
            from: Data(contentsOf: candidate.appendingPathComponent("AdmissionsSolutionsManifest.json"))
        )

        let retainedOutput = ProcessInfo.processInfo.environment["CHUNK3_SANDBOX_OUTPUT"]
            .map(URL.init(fileURLWithPath:))
        let temporary = retainedOutput ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Chunk3-Sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer {
            if retainedOutput == nil {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        for name in ["Revisr.store", "Revisr.store-wal", "Revisr.store-shm"] {
            let source = snapshot.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: temporary.appendingPathComponent(name))
            }
        }

        let container = try AppContainer.make(storeURL: temporary.appendingPathComponent("Revisr.store"))
        let context = container.mainContext
        let attemptsBefore = try attemptSignatures(in: context)
        let assignmentsBefore = try assignmentSignatures(in: context)
        let completionBefore = try completionCounts(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 1_573)
        XCTAssertEqual(attemptsBefore.count, 48)
        XCTAssertEqual(assignmentsBefore.count, 530)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocument>()), 80)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolutionDocument>()), 68)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()), 1_358)
        XCTAssertEqual(completionBefore, [1: 16, 2: 16, 3: 15])

        try AdmissionsImportService.upsert(manifest, in: context)
        try AdmissionsSolutionsImportService.upsert(solutionsManifest, in: context)
        try assertPostImportState(
            in: context,
            attemptsBefore: attemptsBefore,
            assignmentsBefore: assignmentsBefore,
            completionBefore: completionBefore
        )

        let firstCounts = try catalogueCounts(in: context)
        try AdmissionsImportService.upsert(manifest, in: context)
        try AdmissionsSolutionsImportService.upsert(solutionsManifest, in: context)
        XCTAssertEqual(try catalogueCounts(in: context), firstCounts)
        try assertPostImportState(
            in: context,
            attemptsBefore: attemptsBefore,
            assignmentsBefore: assignmentsBefore,
            completionBefore: completionBefore
        )
    }

    private func assertPostImportState(
        in context: ModelContext,
        attemptsBefore: Set<String>,
        assignmentsBefore: Set<String>,
        completionBefore: [Int: Int]
    ) throws {
        XCTAssertEqual(try catalogueCounts(in: context), [
            "questions": 2_600,
            "sources": 136,
            "solutions": 120,
            "links": 2_364,
            "attempts": 48,
            "assignments": 530,
        ])
        XCTAssertEqual(try attemptSignatures(in: context), attemptsBefore)
        XCTAssertEqual(try assignmentSignatures(in: context), assignmentsBefore)
        XCTAssertEqual(try completionCounts(in: context), completionBefore)

        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        XCTAssertEqual(questions.filter {
            $0.family == "TMUA Actual" && $0.year == 2022 && $0.protection != .none
        }.count, 40)
        XCTAssertEqual(questions.filter { $0.externalQuestionID.hasPrefix("YOTTA-P") }.count, 40)
        XCTAssertEqual(questions.filter { $0.family == "STEP" }.count, 163)
        XCTAssertFalse(questions.contains { $0.externalQuestionID.contains("REPORT") })
        let mioQ20 = try XCTUnwrap(questions.first { $0.externalQuestionID == "MIOMATH-2024-P2-Q20" })
        XCTAssertEqual(mioQ20.validityState, .usable)
        XCTAssertTrue(mioQ20.scheduleEligible)

        let subjects = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Subject>()).map { ($0.name, $0.isActiveForStudy) }
        )
        XCTAssertEqual(subjects["TMUA"], true)
        XCTAssertEqual(subjects["Mathematics"], false)
        XCTAssertEqual(subjects["Further Mathematics"], false)
    }

    private func latestCandidate(in directory: URL) throws -> URL {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("staging-v") }
        return try XCTUnwrap(candidates.max {
            Int($0.lastPathComponent.dropFirst("staging-v".count)) ?? 0
                < Int($1.lastPathComponent.dropFirst("staging-v".count)) ?? 0
        })
    }

    private func catalogueCounts(in context: ModelContext) throws -> [String: Int] {
        [
            "questions": try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()),
            "sources": try context.fetchCount(FetchDescriptor<SourceDocument>()),
            "solutions": try context.fetchCount(FetchDescriptor<SolutionDocument>()),
            "links": try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()),
            "attempts": try context.fetchCount(FetchDescriptor<QuestionAttempt>()),
            "assignments": try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()),
        ]
    }

    private func attemptSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<QuestionAttempt>()).map {
            [
                $0.id.uuidString,
                $0.question?.externalQuestionID ?? "nil",
                String($0.attemptedAt.timeIntervalSince1970),
                $0.outcome.rawValue,
                $0.errorType?.rawValue ?? "nil",
                $0.notes,
                String($0.timeTakenSeconds),
            ].joined(separator: "|")
        })
    }

    private func assignmentSignatures(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<ProgrammeAssignment>()).map {
            [
                $0.externalAssignmentID,
                $0.question?.externalQuestionID ?? "nil",
                String($0.programmeDay?.dayNumber ?? -1),
                String($0.isComplete),
                String($0.displayOrder),
            ].joined(separator: "|")
        })
    }

    private func completionCounts(in context: ModelContext) throws -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProgrammeDay>())
            .filter { (1...3).contains($0.dayNumber) }
            .map { ($0.dayNumber, $0.assignments.filter(\.isComplete).count) })
    }
}
