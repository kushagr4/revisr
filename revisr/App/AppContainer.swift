import Foundation
import SwiftData

enum AppContainer {
    static let schema = Schema([
        Subject.self,
        StudyModule.self,
        Topic.self,
        PlannedStudyBlock.self,
        StudySession.self,
        StudyResult.self,
        WeeklyFocus.self,
        AppSettings.self,
        StudyTimerState.self,
        AdmissionsTestProfile.self,
        SourceDocument.self,
        AdmissionsQuestion.self,
        SolutionDocument.self,
        QuestionSolutionLink.self,
        AdmissionsProgramme.self,
        ProgrammeDay.self,
        ProgrammeAssignment.self,
        QuestionAttempt.self,
        AdmissionsTopicState.self,
        QuestionAttemptTimerState.self,
        AdmissionsImportState.self
    ])

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Revisr",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func make(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Revisr",
            schema: schema,
            url: storeURL
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
