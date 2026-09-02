import CryptoKit
import SwiftData
import XCTest
@testable import revisr

@MainActor
final class AdmissionsInfrastructureV2Tests: XCTestCase {
    func testAllPreparationStreamsAndCanonicalCompatibilityRules() throws {
        XCTAssertEqual(Set(PreparationStreamKind.allCases), [
            .tmua, .csat, .smc, .bmo, .cambridgeCSInterview,
        ])
        let question = makeQuestion("Q-COMPAT")
        XCTAssertNil(question.primaryPreparationStreamRawValue)
        XCTAssertNil(question.intendedUsesRawValue)
        XCTAssertFalse(question.hasCanonicalPreparationClassification)
        XCTAssertEqual(question.effectivePreparationStreams, [.tmua])

        question.primaryPreparationStream = .smc
        question.intendedUses = [.tmua, .bmo, .smc, .tmua]
        XCTAssertEqual(question.intendedUsesRawValue, "[\"bmo\",\"smc\",\"tmua\"]")
        XCTAssertEqual(question.effectivePreparationStreams, [.tmua, .smc, .bmo])
        XCTAssertTrue(question.isUsefulFor(.bmo))
        XCTAssertFalse(question.isUsefulFor(.csat))

        question.primaryPreparationStreamRawValue = nil
        question.intendedUsesRawValue = "[]"
        XCTAssertTrue(question.hasCanonicalPreparationClassification)
        XCTAssertTrue(question.effectivePreparationStreams.isEmpty)

        question.intendedUsesRawValue = "not-json"
        XCTAssertTrue(question.effectivePreparationStreams.isEmpty)
    }

    func testBundledCatalogueUsesAuditedCanonicalClassificationWithLegacyFallback() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        try SeedDataService.seedIfNeeded(in: container.mainContext)
        let questions = try container.mainContext.fetch(FetchDescriptor<AdmissionsQuestion>())

        XCTAssertEqual(questions.count, 2_600)
        XCTAssertEqual(questions.filter { $0.primaryPreparationStream == .tmua }.count, 1_364)
        XCTAssertEqual(questions.filter { $0.primaryPreparationStream == .csat }.count, 80)
        XCTAssertEqual(questions.filter { $0.primaryPreparationStream == .smc }.count, 300)
        XCTAssertEqual(questions.filter { $0.primaryPreparationStream == .bmo }.count, 93)
        XCTAssertEqual(questions.filter { $0.primaryPreparationStreamRawValue == nil }.count, 763)
        XCTAssertTrue(questions.allSatisfy { !$0.effectivePreparationStreams.isEmpty })
    }

    func testManifestV2ImportIsIdempotentAndPreservesUserState() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let manifest = try admissionsManifest()
        try AdmissionsImportService.upsert(manifest, in: context)
        let question = try XCTUnwrap(context.fetch(FetchDescriptor<AdmissionsQuestion>()).first)
        question.userNotes = "Keep this"
        question.reviewState = .redo
        let attemptID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        context.insert(QuestionAttempt(
            id: attemptID,
            outcome: .incorrect,
            timeTakenSeconds: 90,
            origin: .questionBank,
            question: question
        ))
        try context.save()

        try AdmissionsImportService.upsert(manifest, in: context)
        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<AdmissionsQuestion>()).first)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocument>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 1)
        XCTAssertEqual(imported.externalQuestionID, "Q-V2")
        XCTAssertEqual(imported.userNotes, "Keep this")
        XCTAssertEqual(imported.reviewState, .redo)
        XCTAssertEqual(imported.attempts.map(\.id), [attemptID])
        XCTAssertEqual(imported.primaryPreparationStream, .smc)
        XCTAssertEqual(imported.intendedUses, [.tmua, .smc])
        XCTAssertEqual(imported.difficultyProvenance, .sourceProvided)
        XCTAssertEqual(imported.validityState, .usable)
        XCTAssertEqual(imported.possibleDuplicateQuestionIDs, [])
        XCTAssertFalse(context.hasChanges)
    }

    func testFullPreflightFailureLeavesNoCatalogueMutation() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        var object = admissionsManifestObject()
        var programme = object["programme"] as! [String: Any]
        var assignments = programme["assignments"] as! [[String: Any]]
        assignments.append([
            "externalAssignmentID": "A-LATE-BROKEN",
            "dayNumber": 1,
            "questionID": "MISSING-LATE-QUESTION",
            "displayOrder": 99,
        ])
        programme["assignments"] = assignments
        object["programme"] = programme
        let manifest = try decode(AdmissionsManifest.self, object)

        XCTAssertThrowsError(try AdmissionsImportService.upsert(manifest, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsQuestion>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocument>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgrammeAssignment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdmissionsImportState>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testMalformedStreamEncodingAndInvalidMediaRangesAreRejected() throws {
        var invalidStream = admissionsManifestObject()
        var questions = invalidStream["questions"] as! [[String: Any]]
        questions[0]["primaryPreparationStream"] = "invented-stream"
        invalidStream["questions"] = questions
        XCTAssertThrowsError(try decode(AdmissionsManifest.self, invalidStream))

        var invalidUses = admissionsManifestObject()
        questions = invalidUses["questions"] as! [[String: Any]]
        questions[0]["intendedUses"] = "tmua,smc"
        invalidUses["questions"] = questions
        XCTAssertThrowsError(try decode(AdmissionsManifest.self, invalidUses))

        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(makeSource("SRC-1"))
        context.insert(makeSource("SRC-2"))
        context.insert(makeQuestion("Q-1"))
        context.insert(makeQuestion("Q-2"))
        try context.save()
        let invalidVideoObject: [String: Any] = [
            "formatVersion": 2, "importRevision": "bad-video",
            "documents": [[
                "stableSolutionID": "SOL-BAD", "displayName": "Bad",
                "solutionType": "videoSolution", "resourceName": "bad",
                "resourceExtension": "mp4", "resourceContainer": "videoBundle",
                "family": "Test", "provenanceOrganization": "Local",
                "provenanceTitle": "Bad", "originalFilename": "bad.mp4",
                "availability": "available", "isVerified": true,
                "mediaKind": "video", "importRevision": "bad-video",
            ]],
            "links": [[
                "stableLinkID": "L-BAD", "solutionID": "SOL-BAD", "questionID": "Q-1",
                "startPage": 1, "mappingConfidence": "verifiedPage", "importRevision": "bad-video",
            ]],
        ]
        let invalidVideo = try decode(AdmissionsSolutionsManifest.self, invalidVideoObject)
        XCTAssertThrowsError(try AdmissionsSolutionsImportService.upsert(invalidVideo, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolutionDocument>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionSolutionLink>()), 0)

    }

    func testDeterministicDuplicateEvidenceAndPossibleDuplicateStorage() {
        let canonical = DuplicateIdentityRecord(
            stableID: "A", binaryChecksum: "ABC", normalizedTextChecksum: nil,
            verifiedSemanticIdentity: nil, verifiedQuestionIdentity: nil
        )
        let sameBytes = DuplicateIdentityRecord(
            stableID: "B", binaryChecksum: "abc", normalizedTextChecksum: nil,
            verifiedSemanticIdentity: nil, verifiedQuestionIdentity: nil
        )
        let ambiguous = DuplicateIdentityRecord(
            stableID: "C", binaryChecksum: nil, normalizedTextChecksum: nil,
            verifiedSemanticIdentity: nil, verifiedQuestionIdentity: nil
        )
        XCTAssertEqual(
            DuplicateIdentityResolver.canonicalRecord(for: sameBytes, among: [canonical]),
            canonical
        )
        XCTAssertNil(DuplicateIdentityResolver.canonicalRecord(for: ambiguous, among: [canonical]))

        let question = makeQuestion("Q-DUP")
        question.duplicateReviewState = .possibleDuplicate
        question.possibleDuplicateQuestionIDs = ["Q-Z", "Q-A", "Q-Z"]
        XCTAssertEqual(question.possibleDuplicateQuestionIDsRawValue, "[\"Q-A\",\"Q-Z\"]")
        XCTAssertEqual(question.possibleDuplicateQuestionIDs, ["Q-A", "Q-Z"])
    }

    func testVideoAndMultiSourceSolutionImportHasNoInventedMappingOrAttemptMutation() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source1 = makeSource("SRC-1")
        let source2 = makeSource("SRC-2")
        let question1 = makeQuestion("Q-1", source: source1)
        let question2 = makeQuestion("Q-2", source: source2)
        context.insert(source1)
        context.insert(source2)
        context.insert(question1)
        context.insert(question2)
        try context.save()

        let manifest = try solutionsManifest()
        try AdmissionsSolutionsImportService.upsert(manifest, in: context)
        try AdmissionsSolutionsImportService.upsert(manifest, in: context)
        let documents = try context.fetch(FetchDescriptor<SolutionDocument>())
        let links = try context.fetch(FetchDescriptor<QuestionSolutionLink>())
        let document = try XCTUnwrap(documents.first)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(document.solutionType, .videoSolution)
        XCTAssertEqual(document.mediaKind, .video)
        XCTAssertEqual(document.effectiveRelatedSourceIDs, ["SRC-1", "SRC-2"])
        XCTAssertTrue(links.allSatisfy { $0.startPage == nil && $0.endPage == nil })
        XCTAssertTrue(links.allSatisfy { $0.startTimeSeconds == nil && $0.endTimeSeconds == nil })

        let bundle = try makeVideoBundle()
        let attemptsBefore = try context.fetchCount(FetchDescriptor<QuestionAttempt>())
        let resolutions = SolutionLibraryService.resolutions(for: question1, links: links, in: bundle)
        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(resolutions.first?.document.mediaKind, .video)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionAttempt>()), attemptsBefore)
        XCTAssertFalse(context.hasChanges)
    }

    func testProgrammeSupportsFlexDatesEarliestStartAndCalendarProtection() {
        let calendar = DateUtilities.appCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let programme = AdmissionsProgramme(
            externalProgrammeID: "FLEX", admissionsTest: .tmua, name: "Flex",
            startDate: start, importRevision: "test"
        )
        let day1 = makeDay(1, offset: 0, programme: programme)
        let day2 = makeDay(2, offset: 1, earliest: 18 * 60, programme: programme)
        let day3 = makeDay(3, offset: 3, programme: programme)
        programme.days = [day1, day2, day3]

        let tuesday17 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 17))!
        let tuesday18 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 18))!
        let recoveryWednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12))!
        XCTAssertEqual(programme.dayNumber(for: tuesday17, calendar: calendar), 2)
        XCTAssertFalse(programme.isAvailable(day2, at: tuesday17, calendar: calendar))
        XCTAssertTrue(programme.isAvailable(day2, at: tuesday18, calendar: calendar))
        XCTAssertNil(programme.dayNumber(for: recoveryWednesday, calendar: calendar))
        XCTAssertNotEqual(programme.dayNumber(for: recoveryWednesday, calendar: calendar), 30)

        let benchmark = makeQuestion("BENCH")
        benchmark.family = "TMUA Actual"
        benchmark.programmeAssignments = [ProgrammeAssignment(
            externalAssignmentID: "BENCH-A", displayOrder: 0,
            programmeDay: day3, question: benchmark
        )]
        XCTAssertEqual(
            SolutionLibraryService.revealRequirement(
                for: benchmark, now: recoveryWednesday, calendar: calendar
            ),
            .protectedQuestion
        )
        let afterBenchmark = calendar.date(byAdding: .day, value: 4, to: start)!
        XCTAssertEqual(
            SolutionLibraryService.revealRequirement(
                for: benchmark, now: afterBenchmark, calendar: calendar
            ),
            .unattempted
        )
    }

    func testHistoricalDaysOneToThreeFingerprintRemainsExact() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AdmissionsManifest", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let programme = try XCTUnwrap(root["programme"] as? [String: Any])
        let days = try XCTUnwrap(programme["days"] as? [[String: Any]])
            .filter { ($0["dayNumber"] as? Int ?? 0) <= 3 }
        let assignments = try XCTUnwrap(programme["assignments"] as? [[String: Any]])
            .filter { ($0["dayNumber"] as? Int ?? 0) <= 3 }
        let payload = try JSONSerialization.data(
            withJSONObject: ["days": days, "assignments": assignments],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let canonicalPayload = Data(asciiEscapedJSON(String(decoding: payload, as: UTF8.self)).utf8)
        let fingerprint = SHA256.hash(data: canonicalPayload).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(fingerprint, "326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e")
        XCTAssertEqual(Dictionary(grouping: assignments, by: { $0["dayNumber"] as! Int }).mapValues(\.count), [
            1: 16, 2: 16, 3: 15,
        ])
    }

    func testPairedSnapshotCopyMigratesAdditivelyWithoutHistoryChanges() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".qa/data-audit/snapshot-before")
        let sourceStore = sourceRoot.appendingPathComponent("Revisr.store")
        guard FileManager.default.fileExists(atPath: sourceStore.path) else {
            throw XCTSkip("Local audited legacy-store fixture is unavailable")
        }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revisr-Legacy-Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["Revisr.store", "Revisr.store-wal", "Revisr.store-shm"] {
            let source = sourceRoot.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: temporary.appendingPathComponent(name))
            }
        }

        let auditURL = sourceRoot.deletingLastPathComponent().appendingPathComponent("REVISR_DATA_AUDIT.json")
        let audit = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: auditURL)) as? [String: Any])
        let attemptSection = try XCTUnwrap(audit["attempts"] as? [String: Any])
        let attemptRecords = try XCTUnwrap(attemptSection["records"] as? [[String: Any]])
        let expectedAttemptIDs = Set(attemptRecords.compactMap { ($0["id"] as? String)?.lowercased() })

        let container = try AppContainer.make(storeURL: temporary.appendingPathComponent("Revisr.store"))
        let context = container.mainContext
        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let attempts = try context.fetch(FetchDescriptor<QuestionAttempt>())
        let assignments = try context.fetch(FetchDescriptor<ProgrammeAssignment>())
        XCTAssertEqual(questions.count, 1_573)
        XCTAssertTrue(Set(questions.map(\.externalQuestionID)).isSubset(of: Set(try AdmissionsManifest.bundled().questions.map(\.externalQuestionID))))
        XCTAssertEqual(attempts.count, 48)
        XCTAssertEqual(Set(attempts.map { $0.id.uuidString.lowercased() }), expectedAttemptIDs)
        XCTAssertEqual(Set(attempts.compactMap { $0.question?.externalQuestionID }).count, 47)
        XCTAssertEqual(assignments.count, 530)
        XCTAssertTrue(questions.allSatisfy { $0.primaryPreparationStreamRawValue == nil })
        XCTAssertTrue(questions.allSatisfy { $0.intendedUsesRawValue == nil })
        XCTAssertEqual(questions.filter { $0.reviewState == .needsReview }.count, 5)
        XCTAssertEqual(questions.filter { $0.reviewState == .redo }.count, 2)
        XCTAssertEqual(questions.filter { $0.family == "TMUA Actual" && $0.year == 2022 && $0.protection != .none }.count, 40)

        let days = try context.fetch(FetchDescriptor<ProgrammeDay>())
        XCTAssertEqual(days.first(where: { $0.dayNumber == 1 })?.assignments.filter(\.isComplete).count, 16)
        XCTAssertEqual(days.first(where: { $0.dayNumber == 2 })?.assignments.filter(\.isComplete).count, 16)
        XCTAssertEqual(days.first(where: { $0.dayNumber == 3 })?.assignments.filter(\.isComplete).count, 15)
        let subjects = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Subject>()).map { ($0.name, $0.isActiveForStudy) })
        XCTAssertEqual(subjects["TMUA"], true)
        XCTAssertEqual(subjects["Mathematics"], false)
        XCTAssertEqual(subjects["Further Mathematics"], false)
    }

    private func admissionsManifest() throws -> AdmissionsManifest {
        try decode(AdmissionsManifest.self, admissionsManifestObject())
    }

    private func admissionsManifestObject() -> [String: Any] {
        [
            "formatVersion": 2,
            "importRevision": "v2-test",
            "profiles": [["kind": "tmua", "displayName": "TMUA", "isActive": true]],
            "sources": [[
                "stableSourceID": "SRC-V2", "displayName": "Synthetic",
                "expectedFilename": "synthetic.pdf", "family": "SMC",
                "questionUnitCount": 1, "mediaKind": "pdf",
            ]],
            "questions": [[
                "externalQuestionID": "Q-V2", "admissionsTest": "tmua", "family": "SMC",
                "questionLabel": "1", "primaryTopic": "Combinatorics", "difficulty": 3,
                "difficultyLabel": "Challenging", "scheduleEligible": true,
                "protection": "none", "sourceID": "SRC-V2", "importRevision": "v2-test",
                "primaryPreparationStream": "smc", "intendedUses": ["tmua", "smc"],
                "questionNumber": 1, "difficultyProvenance": "sourceProvided",
                "validityState": "usable", "duplicateReviewState": "none",
                "possibleDuplicateQuestionIDs": [],
            ]],
            "topics": [["stableTopicID": "T-1", "name": "Combinatorics", "displayOrder": 0]],
            "programme": [
                "externalProgrammeID": "P-V2", "admissionsTest": "tmua", "name": "V2",
                "startDate": "2026-09-01", "importRevision": "v2-test",
                "days": [[
                    "dayNumber": 1, "focus": "Start", "studyBrief": "Synthetic",
                    "allocatedQuestionCount": 1, "expectedQuestionMinutes": 10,
                    "expectedReviewMinutes": 5, "scheduleOffsetDays": 2,
                    "earliestStartMinute": 1080,
                ]],
                "assignments": [[
                    "externalAssignmentID": "A-V2", "dayNumber": 1,
                    "questionID": "Q-V2", "displayOrder": 0,
                ]],
            ],
        ]
    }

    private func solutionsManifest() throws -> AdmissionsSolutionsManifest {
        try decode(AdmissionsSolutionsManifest.self, [
            "formatVersion": 2, "importRevision": "solutions-v2",
            "documents": [[
                "stableSolutionID": "SOL-VIDEO", "displayName": "Shared Video",
                "solutionType": "videoSolution", "resourceName": "shared-video",
                "resourceExtension": "mp4", "resourceContainer": "videoBundle",
                "family": "Test", "provenanceOrganization": "Local",
                "provenanceTitle": "Shared Video", "originalFilename": "shared-video.mp4",
                "availability": "available", "isVerified": true, "sourceID": "SRC-1",
                "additionalSourceIDs": ["SRC-2"], "mediaKind": "video",
                "importRevision": "solutions-v2",
            ]],
            "links": [
                ["stableLinkID": "L-1", "solutionID": "SOL-VIDEO", "questionID": "Q-1", "mappingConfidence": "paperLevel", "importRevision": "solutions-v2"],
                ["stableLinkID": "L-2", "solutionID": "SOL-VIDEO", "questionID": "Q-2", "mappingConfidence": "paperLevel", "importRevision": "solutions-v2"],
            ],
        ])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    private func makeSource(_ id: String) -> SourceDocument {
        SourceDocument(
            stableSourceID: id, displayName: id, expectedFilename: "\(id).pdf",
            family: "Test", importRevision: "test"
        )
    }

    private func makeQuestion(_ id: String, source: SourceDocument? = nil) -> AdmissionsQuestion {
        AdmissionsQuestion(
            externalQuestionID: id, admissionsTest: .tmua, family: "Test",
            questionLabel: "1", primaryTopic: "Test", difficulty: 2,
            difficultyLabel: "Core", scheduleEligible: true,
            importRevision: "test", sourceDocument: source
        )
    }

    private func makeDay(
        _ number: Int,
        offset: Int,
        earliest: Int? = nil,
        programme: AdmissionsProgramme
    ) -> ProgrammeDay {
        ProgrammeDay(
            externalDayID: "FLEX-D\(number)", dayNumber: number, focus: "Day \(number)",
            studyBrief: "", allocatedQuestionCount: 0, expectedQuestionMinutes: 0,
            expectedReviewMinutes: 0, scheduleOffsetDays: offset,
            earliestStartMinute: earliest, programme: programme
        )
    }

    private func makeVideoBundle() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoFixture-\(UUID().uuidString).bundle")
        let videos = root.appendingPathComponent("AdmissionsVideos")
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.revisr.tests.video.\(UUID().uuidString)",
            "CFBundleName": "VideoFixture", "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        try Data([0, 0, 0, 0]).write(to: videos.appendingPathComponent("shared-video.mp4"))
        return try XCTUnwrap(Bundle(url: root))
    }

    private func asciiEscapedJSON(_ value: String) -> String {
        value.unicodeScalars.reduce(into: "") { result, scalar in
            let code = scalar.value
            if code < 128 {
                result.unicodeScalars.append(scalar)
            } else if code <= 0xFFFF {
                result += String(format: "\\u%04x", code)
            } else {
                let adjusted = code - 0x1_0000
                result += String(format: "\\u%04x\\u%04x", 0xD800 + adjusted / 0x400, 0xDC00 + adjusted % 0x400)
            }
        }
    }
}
