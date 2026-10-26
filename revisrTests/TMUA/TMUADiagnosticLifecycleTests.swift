import SwiftData
import XCTest
@testable import revisr

@MainActor
final class TMUADiagnosticLifecycleTests: XCTestCase {
    private let today = TMUAFixtures.date(2026, 10, 26)

    func testCreationPinsVersionsForEveryLength() throws {
        let content = try TMUAFixtures.standardContext()
        for length in TMUADiagnosticLength.allCases {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let settings = try TMUAFixtures.profile(in: context, today: today)
            let snapshot = try TMUADiagnosticService.create(settings: settings, length: length,
                                                            content: content, at: today, in: context)
            XCTAssertEqual(snapshot.sections.count, 2)
            XCTAssertEqual(snapshot.items.filter { $0.paperRawValue == 1 }.count, length.paperOneQuestions)
            XCTAssertEqual(snapshot.items.filter { $0.paperRawValue == 2 }.count, length.paperTwoQuestions)
            XCTAssertTrue(snapshot.items.allSatisfy { $0.content?.versionKey == $0.versionKey })
            XCTAssertEqual(snapshot.diagnostic.bankVersion, content.bank.bankVersion)
            XCTAssertEqual(snapshot.diagnostic.selectorVersion, TMUADiagnosticSelector.version)
            XCTAssertEqual(settings.publicDiagnosticLength, length)
            XCTAssertEqual(Set(snapshot.items.map(\.itemStableID)).count, length.totalQuestions)
        }
    }

    func testLengthChangesOnlyBeforeStarting() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let content = try TMUAFixtures.standardContext()
        let settings = try TMUAFixtures.profile(in: context, today: today)
        var snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content, in: context)
        snapshot = try TMUADiagnosticService.changeLength(snapshot, to: .balanced, settings: settings,
                                                          content: content, in: context)
        XCTAssertEqual(snapshot.items.count, 20)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TMUADiagnosticItem>()), 20)
        let first = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        try TMUADiagnosticService.start(first, in: snapshot, in: context)
        XCTAssertThrowsError(try TMUADiagnosticService.changeLength(snapshot, to: .starter, settings: settings,
                                                                    content: content, in: context)) {
            XCTAssertEqual($0 as? TMUADiagnosticError, .alreadyStarted)
        }
        XCTAssertEqual(try TMUADiagnosticService.load(settings: settings, in: context)?.items.count, 20,
                       "a started diagnostic is never silently altered")
    }

    func testAnswersNavigationFlagsAndPausedTimeArePreserved() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .quick,
                                                        content: TMUAFixtures.standardContext(), in: context)
        let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        let paperTwo = try XCTUnwrap(snapshot.sections.first { $0.paper == .two })
        XCTAssertThrowsError(try TMUADiagnosticService.start(paperTwo, in: snapshot, in: context)) {
            XCTAssertEqual($0 as? TMUADiagnosticError, .sectionLocked)
        }
        try TMUADiagnosticService.start(paperOne, in: snapshot, at: today, in: context)
        let items = snapshot.items(in: paperOne)
        try TMUADiagnosticService.select("C", for: items[0], in: paperOne, at: today.addingTimeInterval(30), in: context)
        try TMUADiagnosticService.setFlag(true, for: items[1], in: paperOne, in: context)
        XCTAssertThrowsError(try TMUADiagnosticService.select("Z", for: items[2], in: paperOne, in: context))
        XCTAssertThrowsError(try TMUADiagnosticService.select("A", for: snapshot.items(in: paperTwo)[0],
                                                              in: paperOne, in: context))
        try TMUADiagnosticService.move(paperOne, to: 6, count: items.count, in: context)
        try TMUADiagnosticService.pause(paperOne, at: today.addingTimeInterval(120), in: context)
        XCTAssertEqual(paperOne.accumulatedSeconds, 120, accuracy: 0.001)
        // A whole day away while paused adds nothing.
        try TMUADiagnosticService.resume(paperOne, at: today.addingTimeInterval(86_400), in: context)
        try TMUADiagnosticService.pause(paperOne, at: today.addingTimeInterval(86_460), in: context)
        XCTAssertEqual(paperOne.accumulatedSeconds, 180, accuracy: 0.001)
        XCTAssertEqual(paperOne.pauseCount, 2)
        XCTAssertEqual(paperOne.currentIndex, 6)
        XCTAssertEqual(items[0].selectedOptionID, "C")
        XCTAssertTrue(items[1].isFlagged)
        XCTAssertEqual(paperOne.status, .inProgress, "pausing never submits")
    }

    func testTerminationAndRelaunchResumeTheSameQuestionSet() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Revisr-TMUA-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Revisr.store")
        let content = try TMUAFixtures.standardContext()
        var versionKeys: [String] = []
        do {
            let container = try AppContainer.make(storeURL: store)
            let context = container.mainContext
            let settings = try TMUAFixtures.profile(in: context, today: today)
            let snapshot = try TMUADiagnosticService.create(settings: settings, length: .comprehensive,
                                                            content: content, at: today, in: context)
            versionKeys = snapshot.items.map(\.stableID).sorted()
            let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
            try TMUADiagnosticService.start(paperOne, in: snapshot, at: today, in: context)
            let items = snapshot.items(in: paperOne)
            for item in items.prefix(7) {
                try TMUADiagnosticService.select("B", for: item, in: paperOne, at: today.addingTimeInterval(300), in: context)
            }
            try TMUADiagnosticService.move(paperOne, to: 6, count: items.count, at: today.addingTimeInterval(300), in: context)
            // Process ends here with the timer still running.
        }
        let reopened = try AppContainer.make(storeURL: store)
        let context = reopened.mainContext
        let settings = try SeedDataService.bootstrapForLaunch(in: context)
        XCTAssertEqual(settings.publicFlowVersion, 2)
        let snapshot = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
        // Re-creating returns the saved diagnostic rather than a new question set.
        let again = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content, in: context)
        XCTAssertEqual(again.diagnostic.stableID, snapshot.diagnostic.stableID)
        XCTAssertEqual(snapshot.items.map(\.stableID).sorted(), versionKeys)
        let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        XCTAssertEqual(paperOne.currentIndex, 6)
        XCTAssertEqual(snapshot.items(in: paperOne).prefix(7).compactMap(\.selectedOptionID), Array(repeating: "B", count: 7))
        try TMUADiagnosticService.recoverInterruptedTimers(snapshot, in: context)
        XCTAssertNil(paperOne.runningSince)
        XCTAssertEqual(paperOne.accumulatedSeconds, 300, accuracy: 0.001,
                       "only time up to the last saved interaction counts after termination")
        XCTAssertEqual(paperOne.recoveredInterruptionCount, 1)
        try TMUADiagnosticService.resume(paperOne, at: today.addingTimeInterval(90_000), in: context)
        try TMUAFixtures.answerAndSubmit(paperOne, snapshot: snapshot, at: today.addingTimeInterval(90_060), in: context)
        XCTAssertEqual(paperOne.status, .submitted)
    }

    func testSubmissionMarksLocksAndRejectsDuplicates() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter,
                                                        content: TMUAFixtures.standardContext(), in: context)
        let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        try TMUAFixtures.answerAndSubmit(paperOne, snapshot: snapshot, skip: 1, at: today, in: context)
        let items = snapshot.items(in: paperOne)
        XCTAssertEqual(items.map(\.marking), [.correct, .incorrect, .correct, .incorrect, .unanswered])
        XCTAssertThrowsError(try TMUADiagnosticService.submit(paperOne, in: snapshot, in: context))
        XCTAssertThrowsError(try TMUADiagnosticService.select("A", for: items[4], in: paperOne, in: context))
        XCTAssertThrowsError(try TMUADiagnosticService.setFlag(true, for: items[0], in: paperOne, in: context))
        XCTAssertNil(snapshot.diagnostic.initialCompletedAt, "Paper 2 is still outstanding")
        XCTAssertNotNil(paperOne.submittedAt)
        let paperTwo = try XCTUnwrap(snapshot.sections.first { $0.paper == .two })
        try TMUAFixtures.answerAndSubmit(paperTwo, snapshot: snapshot, at: today.addingTimeInterval(86_400), in: context)
        XCTAssertNotNil(snapshot.diagnostic.initialCompletedAt)
    }

    func testRawScoresUseSubmittedLengthOnlyAndNeverClaimScaledScore() throws {
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let content = try TMUAFixtures.standardContext()
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .quick, content: content, in: context)
        let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        let paperTwo = try XCTUnwrap(snapshot.sections.first { $0.paper == .two })
        try TMUAFixtures.answerAndSubmit(paperOne, snapshot: snapshot, skip: 2, at: today, in: context)
        try TMUAFixtures.answerAndSubmit(paperTwo, snapshot: snapshot, allCorrect: true, at: today, in: context)
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        XCTAssertEqual(report.questionCount, 15)
        XCTAssertEqual(report.papers[0].rawScore, "3 / 8")
        XCTAssertEqual(report.papers[0].skipped, 2)
        XCTAssertEqual(report.papers[1].rawScore, "7 / 7")
        XCTAssertEqual(report.combinedScore, "10 / 15")
        XCTAssertEqual(report.activeSeconds, 1_200)
        XCTAssertTrue(report.scoreDisclaimer.contains("not a TMUA score"))
        XCTAssertTrue(report.scoreDisclaimer.contains("abbreviated"))
        XCTAssertFalse(report.combinedScore.contains("9"), "no 1–9 conversion appears in the score")
        XCTAssertEqual(report.sampledTopicKeys.count + report.unassessedTopicKeys.count, content.syllabus.topics.count)
        XCTAssertFalse(report.unassessedTopicKeys.isEmpty, "15 questions cannot sample every topic")
        // Skipped answers are not evidence of difficulty.
        let skippedTopics = snapshot.items(in: paperOne).filter { $0.marking == .unanswered }
            .map { content.syllabus.topicTitle($0.topicKey) }
        for result in report.topics where skippedTopics.contains(result.name) {
            XCTAssertGreaterThan(result.unansweredCount, 0)
            XCTAssertEqual(result.assessedCount + result.unansweredCount >= 1, true)
        }
    }

    func testEvidenceConfidenceDiffersByLengthAndPaperTwoTopicsCanBeClassified() throws {
        // Ten logic questions all missed: possible with a single paper only
        // because logic is examinable only in Paper 2.
        let logic = (0..<10).map {
            TMUAFixtures.item("logic-\($0)", paper: 2, topic: "logic", strand: "implication",
                              skill: "conditional-reasoning", difficulty: 2)
        }
        let algebra = (0..<20).map {
            TMUAFixtures.item("alg-\($0)", paper: 1, topic: "algebra", strand: "polynomials", difficulty: 2)
        }
        let others = try TMUAFixtures.items(paperOne: 0, paperTwo: 12, prefix: "other")
        let content = try TMUAFixtures.context(logic + algebra + others)
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .comprehensive,
                                                        content: content, in: context)
        for section in snapshot.sections.sorted(by: { $0.paperRawValue < $1.paperRawValue }) {
            try TMUADiagnosticService.start(section, in: snapshot, in: context)
            for item in snapshot.items(in: section) {
                let key = try XCTUnwrap(item.content?.correctOptionId)
                try TMUADiagnosticService.select(item.topicKey == "logic" ? "E" : key, for: item, in: section, in: context)
            }
            try TMUADiagnosticService.submit(section, in: snapshot, in: context)
        }
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        let logicResult = try XCTUnwrap(report.topics.first { $0.name == "Logic of arguments" })
        XCTAssertGreaterThanOrEqual(logicResult.assessedCount, 4)
        XCTAssertEqual(logicResult.level, .strongDifficulty)
        XCTAssertTrue(logicResult.explanation.contains("in the paper that assesses it"))
        let algebraResult = try XCTUnwrap(report.topics.first { $0.name == "Algebra" })
        XCTAssertEqual(algebraResult.level, .relativeStrength)
        XCTAssertEqual(report.length.confidenceTitle, "Broadest available")
        XCTAssertNotEqual(TMUADiagnosticLength.starter.confidenceExplanation,
                          TMUADiagnosticLength.comprehensive.confidenceExplanation)
    }

    func testStarterEvidenceStaysConservative() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content, in: context)
        for section in snapshot.sections.sorted(by: { $0.paperRawValue < $1.paperRawValue }) {
            try TMUADiagnosticService.start(section, in: snapshot, in: context)
            for item in snapshot.items(in: section) {
                try TMUADiagnosticService.select("E", for: item, in: section, in: context) // every answer wrong
            }
            try TMUADiagnosticService.submit(section, in: snapshot, in: context)
        }
        let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: content.syllabus)
        XCTAssertEqual(report.correct, 0)
        XCTAssertFalse(report.topics.contains { $0.level == .strongDifficulty },
                       "one question per topic never establishes strong difficulty")
        XCTAssertEqual(report.length.confidenceTitle, "Provisional")
    }

    // MARK: Expansion

    func testEveryExpansionPathKeepsEarlierWorkAndAddsOnlyTheDifference() throws {
        let pairs: [(TMUADiagnosticLength, TMUADiagnosticLength)] = [
            (.starter, .quick), (.starter, .balanced), (.starter, .comprehensive),
            (.quick, .balanced), (.quick, .comprehensive), (.balanced, .comprehensive)
        ]
        let content = try TMUAFixtures.standardContext()
        for (from, to) in pairs {
            let container = try TMUAFixtures.memoryContainer()
            let context = container.mainContext
            let settings = try TMUAFixtures.profile(in: context, today: today)
            let initial = try TMUADiagnosticService.create(settings: settings, length: from, content: content, in: context)
            XCTAssertThrowsError(try TMUADiagnosticService.expand(initial, to: to, settings: settings,
                                                                  content: content, in: context),
                                 "cannot expand before the initial diagnostic is complete")
            try TMUAFixtures.completeAll(initial, at: today, in: context)
            let before = initial.items.map { ($0.stableID, $0.selectedOptionID, $0.markingRawValue) }
            let beforeSeconds = initial.sections.map(\.accumulatedSeconds)
            let expanded = try TMUADiagnosticService.expand(initial, to: to, settings: settings,
                                                            content: content, in: context)
            let added = expanded.items.filter { item in !initial.items.contains { $0.stableID == item.stableID } }
            XCTAssertEqual(added.filter { $0.paperRawValue == 1 }.count, to.paperOneQuestions - from.paperOneQuestions)
            XCTAssertEqual(added.filter { $0.paperRawValue == 2 }.count, to.paperTwoQuestions - from.paperTwoQuestions)
            XCTAssertTrue(Set(added.map(\.itemStableID)).isDisjoint(with: initial.items.map(\.itemStableID)))
            XCTAssertEqual(expanded.items.count, to.totalQuestions)
            for (id, option, marking) in before {
                let item = try XCTUnwrap(expanded.items.first { $0.stableID == id })
                XCTAssertEqual(item.selectedOptionID, option)
                XCTAssertEqual(item.markingRawValue, marking)
            }
            XCTAssertEqual(initial.sections.map(\.accumulatedSeconds), beforeSeconds)
            XCTAssertEqual(expanded.diagnostic.targetLength, to)
            XCTAssertEqual(expanded.diagnostic.initialLength, from)
            XCTAssertEqual(expanded.sections.filter { $0.round == 1 }.count, 2, "separate sessions for added questions")
            XCTAssertThrowsError(try TMUADiagnosticService.expand(expanded, to: .comprehensive, settings: settings,
                                                                  content: content, in: context),
                                 "another round waits until the added questions are submitted")
            // Report keeps the earlier length label until the added round is submitted.
            XCTAssertEqual(TMUADiagnosticReportBuilder.build(snapshot: expanded, syllabus: content.syllabus).length, from)
            try TMUAFixtures.completeAll(expanded, at: today.addingTimeInterval(86_400), in: context)
            let report = TMUADiagnosticReportBuilder.build(snapshot: expanded, syllabus: content.syllabus)
            XCTAssertEqual(report.length, to)
            XCTAssertEqual(report.questionCount, to.totalQuestions)
            XCTAssertTrue(report.wasExpanded)
            XCTAssertTrue(report.timingNote.contains("separate sessions"))
        }
    }

    func testPractisedQuestionsAreNotReusedAsDiagnosticEvidence() throws {
        let content = try TMUAFixtures.context(TMUAFixtures.items(paperOne: 13, paperTwo: 12))
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let initial = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content, in: context)
        try TMUAFixtures.completeAll(initial, at: today, in: context)
        // Practise every remaining Paper 2 question except four.
        let seen = Set(initial.items.map(\.itemStableID))
        let unseenTwo = content.eligibleItems(for: .two).filter { !seen.contains($0.stableId) }
        for item in unseenTwo.dropLast(4) {
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: "A", seconds: 60, task: nil,
                                                    settings: settings, in: context)
        }
        XCTAssertTrue(TMUADiagnosticService.canExpand(initial, to: .quick, settings: settings, content: content, in: context))
        XCTAssertFalse(TMUADiagnosticService.canExpand(initial, to: .balanced, settings: settings, content: content, in: context))
        XCTAssertThrowsError(try TMUADiagnosticService.expand(initial, to: .balanced, settings: settings,
                                                              content: content, in: context))
        let expanded = try TMUADiagnosticService.expand(initial, to: .quick, settings: settings, content: content, in: context)
        let practised = Set(unseenTwo.dropLast(4).map(\.stableId))
        XCTAssertTrue(expanded.items.allSatisfy { !practised.contains($0.itemStableID) })
    }

    func testRepeatedIdentityAddsNoIndependentEvidence() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content, in: context)
        try TMUAFixtures.completeAll(snapshot, at: today, in: context)
        // Simulate a corrupted duplicate row of an already-answered identity.
        let original = try XCTUnwrap(snapshot.items.first)
        let section = try XCTUnwrap(snapshot.sections.first { $0.stableID == original.sectionID })
        let duplicate = TMUADiagnosticItem(sectionID: section.stableID, diagnosticID: snapshot.diagnostic.stableID,
                                           ordinal: 99, item: try XCTUnwrap(original.content))
        duplicate.stableID += "-duplicate"
        duplicate.selectedOptionID = original.selectedOptionID
        duplicate.markingRawValue = original.markingRawValue
        context.insert(duplicate)
        try context.save()
        let reloaded = try XCTUnwrap(TMUADiagnosticService.load(settings: settings, in: context))
        let report = TMUADiagnosticReportBuilder.build(snapshot: reloaded, syllabus: content.syllabus)
        XCTAssertEqual(report.questionCount, 10)
    }

    func testDraftsSurviveABankThatDropsTheirVersion() throws {
        let content = try TMUAFixtures.standardContext()
        let container = try TMUAFixtures.memoryContainer()
        let context = container.mainContext
        let settings = try TMUAFixtures.profile(in: context, today: today)
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: .starter, content: content, in: context)
        let empty = try TMUAFixtures.context([])
        XCTAssertTrue(empty.eligibleItems.isEmpty)
        let paperOne = try XCTUnwrap(snapshot.sections.first { $0.paper == .one })
        try TMUADiagnosticService.start(paperOne, in: snapshot, in: context)
        let item = snapshot.items(in: paperOne)[0]
        let key = try XCTUnwrap(item.content?.correctOptionId)
        try TMUADiagnosticService.select(key, for: item, in: paperOne, in: context)
        try TMUADiagnosticService.submit(paperOne, in: snapshot, in: context)
        XCTAssertEqual(item.marking, .correct, "marked from the pinned snapshot, not the current bank")
    }
}
