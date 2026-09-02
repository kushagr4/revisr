import SwiftData
import XCTest
@testable import revisr

@MainActor
final class TopicServiceTests: XCTestCase {
    func testAllFourStatusesPersistAndCanChange() throws {
        let fixture = try makeFixture()
        let topic = fixture.topic

        for status in TopicStatus.allCases {
            try TopicService.setStatus(status, for: topic, in: fixture.context)
            XCTAssertEqual(topic.status, status)
            XCTAssertEqual(topic.statusRawValue, status.rawValue)
        }
    }

    func testCreatingStudySessionDoesNotChangeStatusOrReviewFlag() throws {
        let fixture = try makeFixture()
        fixture.topic.status = .weak
        fixture.topic.needsReview = true
        fixture.context.insert(
            StudySession(
                date: .now,
                duration: 90 * 60,
                activity: .questions,
                subject: fixture.subject,
                module: fixture.module,
                topic: fixture.topic,
                subjectNameSnapshot: fixture.subject.name,
                moduleNameSnapshot: fixture.module.name,
                topicNameSnapshot: fixture.topic.name
            )
        )
        try fixture.context.save()

        XCTAssertEqual(fixture.topic.status, .weak)
        XCTAssertTrue(fixture.topic.needsReview)
    }

    func testMarkAndUnmarkNeedsReviewUpdatesCollection() throws {
        let fixture = try makeFixture()

        try TopicService.setNeedsReview(true, for: fixture.topic, in: fixture.context)
        XCTAssertEqual(TopicAnalytics.needsReview(topics: [fixture.topic], lastStudied: [:]).map(\.id), [fixture.topic.id])

        try TopicService.setNeedsReview(false, for: fixture.topic, in: fixture.context)
        XCTAssertTrue(TopicAnalytics.needsReview(topics: [fixture.topic], lastStudied: [:]).isEmpty)
    }

    func testCreatesCustomTopicInSelectedModuleWithStableOrder() throws {
        let fixture = try makeFixture()
        let created = try TopicService.create(
            from: TopicDraft(
                name: "  New   Topic ",
                status: .needsWork,
                needsReview: true,
                notes: " Reminder ",
                module: fixture.module
            ),
            existingTopics: try fixture.context.fetch(FetchDescriptor<Topic>()),
            in: fixture.context
        )

        XCTAssertEqual(created.name, "New Topic")
        XCTAssertTrue(created.isCustom)
        XCTAssertEqual(created.module?.id, fixture.module.id)
        XCTAssertEqual(created.status, .needsWork)
        XCTAssertTrue(created.needsReview)
        XCTAssertTrue(fixture.module.topics.contains(where: { $0.id == created.id }))
    }

    func testDuplicateNormalizedNameRejectedWithinSameModule() throws {
        let fixture = try makeFixture()
        let draft = TopicDraft(
            name: "  COMPLEX   numbers ",
            status: .good,
            needsReview: false,
            notes: "",
            module: fixture.module
        )

        XCTAssertThrowsError(
            try TopicService.create(
                from: draft,
                existingTopics: try fixture.context.fetch(FetchDescriptor<Topic>()),
                in: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? TopicError, .duplicateName)
        }
    }

    func testSameTopicNameAllowedInDifferentModule() throws {
        let fixture = try makeFixture()
        let otherModule = StudyModule(name: "CP2", displayOrder: 1, subject: fixture.subject)
        fixture.context.insert(otherModule)

        let created = try TopicService.create(
            from: TopicDraft(
                name: fixture.topic.name,
                status: .good,
                needsReview: false,
                notes: "",
                module: otherModule
            ),
            existingTopics: try fixture.context.fetch(FetchDescriptor<Topic>()),
            in: fixture.context
        )

        XCTAssertEqual(created.module?.id, otherModule.id)
    }

    func testSeededTopicCannotMoveOrDelete() throws {
        let fixture = try makeFixture()
        let otherModule = StudyModule(name: "CP2", displayOrder: 1, subject: fixture.subject)
        fixture.context.insert(otherModule)

        XCTAssertThrowsError(
            try TopicService.update(
                fixture.topic,
                from: TopicDraft(
                    name: fixture.topic.name,
                    status: .good,
                    needsReview: false,
                    notes: "",
                    module: otherModule
                ),
                existingTopics: try fixture.context.fetch(FetchDescriptor<Topic>()),
                in: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? TopicError, .cannotMoveSeeded)
        }
        XCTAssertThrowsError(try TopicService.delete(fixture.topic, in: fixture.context)) { error in
            XCTAssertEqual(error as? TopicError, .cannotDeleteSeeded)
        }
    }

    func testDeletingCustomTopicPreservesHistoricalSessionAndPlanSnapshots() throws {
        let fixture = try makeFixture()
        let custom = try TopicService.create(
            from: TopicDraft(
                name: "Custom Topic",
                status: .good,
                needsReview: false,
                notes: "",
                module: fixture.module
            ),
            existingTopics: try fixture.context.fetch(FetchDescriptor<Topic>()),
            in: fixture.context
        )
        let session = StudySession(
            date: .now,
            duration: 60 * 60,
            activity: .revision,
            subject: fixture.subject,
            module: fixture.module,
            topic: custom,
            subjectNameSnapshot: fixture.subject.name,
            moduleNameSnapshot: fixture.module.name,
            topicNameSnapshot: custom.name
        )
        let block = PlannedStudyBlock(
            day: .now,
            duration: 60 * 60,
            activity: .revision,
            subject: fixture.subject,
            module: fixture.module,
            topic: custom
        )
        fixture.context.insert(session)
        fixture.context.insert(block)
        try fixture.context.save()

        try TopicService.delete(custom, in: fixture.context)

        XCTAssertNil(session.topic)
        XCTAssertEqual(session.topicNameSnapshot, "Custom Topic")
        XCTAssertNil(block.topic)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<StudySession>()).count, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<PlannedStudyBlock>()).count, 1)
    }

    func testFreshSeedUsesAdmissionsTopicStateWithoutSchoolTopicHierarchy() throws {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(in: context)
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        XCTAssertNil(subjects.first(where: { $0.name == "Mathematics" }))
        XCTAssertNil(subjects.first(where: { $0.name == "Further Mathematics" }))
        XCTAssertTrue(try context.fetch(FetchDescriptor<Topic>()).isEmpty)
        let admissionsTopics = try context.fetch(FetchDescriptor<AdmissionsTopicState>())
        XCTAssertEqual(admissionsTopics.count, 21)
        XCTAssertTrue(admissionsTopics.allSatisfy { $0.admissionsTest == .tmua })
    }

    private func makeFixture() throws -> (
        container: ModelContainer,
        context: ModelContext,
        subject: Subject,
        module: StudyModule,
        topic: Topic
    ) {
        let container = try AppContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let subject = Subject(name: "Further Mathematics", targetPercentage: 1, displayOrder: 0)
        let module = StudyModule(name: "CP1", displayOrder: 0, subject: subject)
        let topic = Topic(name: "Complex Numbers", status: .needsWork, needsReview: true, displayOrder: 0, module: module)
        context.insert(subject)
        context.insert(module)
        context.insert(topic)
        try context.save()
        return (container, context, subject, module, topic)
    }
}
