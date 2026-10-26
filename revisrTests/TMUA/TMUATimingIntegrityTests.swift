import SwiftData
import XCTest
@testable import revisr

/// R1 Stage C: timing semantics, checkpoints and save failures.
@MainActor
final class TMUATimingIntegrityTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)

    private struct SimulatedDiskFull: LocalizedError {
        var errorDescription: String? { "The disk is full." }
    }

    override func tearDown() async throws {
        TMUADiagnosticService.injectedSaveFailure = nil
    }

    private func startedQuick(in context: ModelContext) throws
        -> (TMUADiagnosticSnapshot, TMUADiagnosticSection, [TMUADiagnosticItem]) {
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .quick,
                                                        content: TMUAFixtures.standardContext(), at: today, in: context)
        let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        try TMUADiagnosticService.start(paperOne, in: snapshot, at: today, in: context)
        return (snapshot, paperOne, snapshot.items(in: paperOne))
    }

    /// Reading for minutes without tapping no longer loses that time after a
    /// crash: checkpoints bound the loss to one interval.
    func testCheckpointsBoundLostTimeAfterAbnormalTermination() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (snapshot, paperOne, items) = try startedQuick(in: context)
        try TMUADiagnosticService.select("B", for: items[0], in: paperOne, at: today.addingTimeInterval(30), in: context)
        // Eight minutes of reading with no interaction, checkpointed each minute.
        for minute in 1...8 {
            try TMUADiagnosticService.checkpoint(paperOne, at: today.addingTimeInterval(30 + Double(minute) * 60), in: context)
        }
        // The process dies at +540s; relaunch a week later.
        try TMUADiagnosticService.recoverInterruptedTimers(snapshot, in: context)
        XCTAssertEqual(paperOne.accumulatedSeconds, 510, accuracy: 0.001,
                       "time counts to the last checkpoint (≤ \(TMUADiagnosticService.checkpointInterval)s lost), never the week away")
        XCTAssertNil(paperOne.runningSince)
        XCTAssertEqual(paperOne.recoveredInterruptionCount, 1)
        XCTAssertEqual(items[0].selectedOptionID, "B", "recovery never touches answers")
        XCTAssertEqual(paperOne.status, .inProgress)
    }

    func testWithoutCheckpointsOnlyTheLastInteractionCounts() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (snapshot, paperOne, items) = try startedQuick(in: context)
        try TMUADiagnosticService.select("A", for: items[0], in: paperOne, at: today.addingTimeInterval(45), in: context)
        try TMUADiagnosticService.recoverInterruptedTimers(snapshot, in: context)
        XCTAssertEqual(paperOne.accumulatedSeconds, 45, accuracy: 0.001)
    }

    func testCheckpointDoesNothingWhilePausedOrSubmitted() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (snapshot, paperOne, _) = try startedQuick(in: context)
        try TMUADiagnosticService.pause(paperOne, at: today.addingTimeInterval(100), in: context)
        try TMUADiagnosticService.checkpoint(paperOne, at: today.addingTimeInterval(5_000), in: context)
        XCTAssertEqual(paperOne.lastSavedAt, today.addingTimeInterval(100))
        // A week later, still paused: nothing to recover and no time added.
        try TMUADiagnosticService.recoverInterruptedTimers(snapshot, in: context)
        XCTAssertEqual(paperOne.accumulatedSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(paperOne.recoveredInterruptionCount, 0)
        try TMUADiagnosticService.resume(paperOne, at: today.addingTimeInterval(7 * 86_400), in: context)
        try TMUADiagnosticService.submit(paperOne, in: snapshot, at: today.addingTimeInterval(7 * 86_400 + 60), in: context)
        let submittedAt = paperOne.lastSavedAt
        try TMUADiagnosticService.checkpoint(paperOne, at: today.addingTimeInterval(8 * 86_400), in: context)
        XCTAssertEqual(paperOne.lastSavedAt, submittedAt)
        XCTAssertEqual(paperOne.accumulatedSeconds, 160, accuracy: 0.001)
    }

    /// A failed save (for example a full disk) keeps the last stored answer on
    /// screen and in the store, and a timer change never discards answers.
    func testSaveFailuresKeepStoredAnswersAndTimerState() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tmua-save-failure-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + suffix) } }
        let container = try AppContainer.make(storeURL: url)
        let context = container.mainContext
        let (snapshot, paperOne, items) = try startedQuick(in: context)
        try TMUADiagnosticService.select("C", for: items[0], in: paperOne, at: today.addingTimeInterval(20), in: context)

        TMUADiagnosticService.injectedSaveFailure = SimulatedDiskFull()
        XCTAssertThrowsError(try TMUADiagnosticService.select("D", for: items[0], in: paperOne,
                                                              at: today.addingTimeInterval(40), in: context))
        XCTAssertEqual(items[0].selectedOptionID, "C", "the screen shows the answer that is actually saved")

        TMUADiagnosticService.injectedSaveFailure = SimulatedDiskFull()
        XCTAssertThrowsError(try TMUADiagnosticService.pause(paperOne, at: today.addingTimeInterval(60), in: context))
        XCTAssertNotNil(paperOne.runningSince, "a failed pause leaves the timer as stored")
        XCTAssertEqual(paperOne.accumulatedSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(items[0].selectedOptionID, "C", "a timer change never discards a saved answer")

        TMUADiagnosticService.injectedSaveFailure = SimulatedDiskFull()
        XCTAssertThrowsError(try TMUADiagnosticService.submit(paperOne, in: snapshot, at: today.addingTimeInterval(80), in: context))
        XCTAssertEqual(paperOne.status, .inProgress, "a failed submission stays open, unmarked")
        XCTAssertTrue(items.allSatisfy { $0.marking == nil })

        // The stored state, read through a fresh context, matches.
        let fresh = ModelContext(container)
        let sectionID = paperOne.stableID
        let stored = try XCTUnwrap(fresh.fetch(FetchDescriptor<TMUADiagnosticSection>(
            predicate: #Predicate { $0.stableID == sectionID })).first)
        XCTAssertEqual(stored.statusRawValue, TMUASectionStatus.inProgress.rawValue)
        let itemID = items[0].stableID
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<TMUADiagnosticItem>(
            predicate: #Predicate { $0.stableID == itemID })).first?.selectedOptionID, "C")

        // Once space is available, the same submission succeeds exactly once.
        try TMUADiagnosticService.submit(paperOne, in: snapshot, at: today.addingTimeInterval(90), in: context)
        XCTAssertEqual(paperOne.status, .submitted)
        XCTAssertThrowsError(try TMUADiagnosticService.submit(paperOne, in: snapshot, in: context))
        XCTAssertThrowsError(try TMUADiagnosticService.select("A", for: items[0], in: paperOne, in: context),
                             "a submitted answer never changes")
    }

    func testSwitchingPapersKeepsEachSectionsStateSeparate() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let (snapshot, paperOne, itemsOne) = try startedQuick(in: context)
        let paperTwo = try XCTUnwrap(snapshot.sections.first { $0.paper == .two })
        try TMUADiagnosticService.select("A", for: itemsOne[0], in: paperOne, at: today.addingTimeInterval(10), in: context)
        try TMUADiagnosticService.submit(paperOne, in: snapshot, at: today.addingTimeInterval(300), in: context)
        try TMUADiagnosticService.start(paperTwo, in: snapshot, at: today.addingTimeInterval(400), in: context)
        let itemsTwo = snapshot.items(in: paperTwo)
        XCTAssertThrowsError(try TMUADiagnosticService.select("B", for: itemsOne[1], in: paperTwo, in: context)) {
            XCTAssertEqual($0 as? TMUADiagnosticError, .wrongSection)
        }
        XCTAssertThrowsError(try TMUADiagnosticService.resume(paperOne, in: context), "a submitted paper cannot reopen")
        try TMUADiagnosticService.select("B", for: itemsTwo[0], in: paperTwo, at: today.addingTimeInterval(430), in: context)
        try TMUADiagnosticService.pause(paperTwo, at: today.addingTimeInterval(460), in: context)
        XCTAssertEqual(paperOne.accumulatedSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(paperTwo.accumulatedSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(itemsOne[0].selectedOptionID, "A")
    }
}
