import Foundation
import SwiftData

@MainActor
enum SeedDataService {
    static let currentSeedVersion = 4

    static func seedIfNeeded(in context: ModelContext) throws {
        let settingsRecords = try context.fetch(FetchDescriptor<AppSettings>())
        let settings: AppSettings
        if let existing = canonicalSettings(from: settingsRecords) {
            settings = existing
            for duplicate in settingsRecords where duplicate.id != existing.id {
                context.delete(duplicate)
            }
        } else {
            settings = AppSettings(
                activeAdmissionsTest: .tmua,
                tmuaProgrammeStartDate: AppSettings.makeDefaultProgrammeStartDate(),
                appliedSeedVersion: currentSeedVersion
            )
            context.insert(settings)
        }

        try migrateLegacySubjectsIfNeeded(
            after: settings.appliedSeedVersion,
            settings: settings,
            context: context
        )
        try ensureTMUAResultCompatibilitySubject(in: context)

        if try context.fetch(FetchDescriptor<StudyTimerState>()).isEmpty {
            context.insert(StudyTimerState())
        }

        if context.hasChanges { try context.save() }
        try AdmissionsImportService.seedBundledManifestIfNeeded(in: context)
        try AdmissionsSolutionsImportService.seedBundledManifestIfNeeded(in: context)
        try AdmissionsProgrammeMigrationService.seedBundledMigrationIfNeeded(in: context)
    }

    private static func canonicalSettings(from records: [AppSettings]) -> AppSettings? {
        records.sorted { lhs, rhs in
            if lhs.appliedSeedVersion != rhs.appliedSeedVersion {
                return lhs.appliedSeedVersion > rhs.appliedSeedVersion
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first
    }

    private static func migrateLegacySubjectsIfNeeded(
        after version: Int,
        settings: AppSettings,
        context: ModelContext
    ) throws {
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        for subject in subjects {
            switch subject.name {
            case "Mathematics", "Further Mathematics":
                // Relationships, sessions, results, plans, snapshots, notes, and
                // topics remain untouched. Only active selection is retired.
                subject.isActiveForStudy = false
            case "TMUA":
                subject.isActiveForStudy = true
            default:
                // Unknown historical subjects remain preserved but cannot become
                // admissions domains implicitly.
                if version < currentSeedVersion { subject.isActiveForStudy = false }
            }
        }

        settings.activeAdmissionsTest = .tmua
        if settings.tmuaProgrammeStartDate == nil {
            settings.tmuaProgrammeStartDate = AppSettings.makeDefaultProgrammeStartDate()
        }
        settings.appliedSeedVersion = currentSeedVersion
    }

    /// StudyResult is retained for TMUA scaled/mock history. A lightweight TMUA
    /// Subject keeps that proven relationship compatible without making the new
    /// admissions UI depend on the old school-subject planner.
    private static func ensureTMUAResultCompatibilitySubject(in context: ModelContext) throws {
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let tmua: Subject
        if let existing = subjects.first(where: { $0.name == "TMUA" }) {
            tmua = existing
            tmua.isActiveForStudy = true
            tmua.targetPercentage = 1
            tmua.displayOrder = 0
            tmua.accentIdentifier = .tmua
        } else {
            tmua = Subject(
                name: "TMUA",
                targetPercentage: 1,
                displayOrder: 0,
                accentIdentifier: .tmua,
                isActiveForStudy: true
            )
            context.insert(tmua)
        }

        if !tmua.modules.contains(where: { $0.name == "Paper 1" }) {
            context.insert(StudyModule(name: "Paper 1", displayOrder: 0, subject: tmua))
        }
        if !tmua.modules.contains(where: { $0.name == "Paper 2" }) {
            context.insert(StudyModule(name: "Paper 2", displayOrder: 1, subject: tmua))
        }
    }
}
