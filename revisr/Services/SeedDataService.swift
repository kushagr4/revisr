import Foundation
import SwiftData

@MainActor
enum SeedDataService {
    static let currentSeedVersion = 4

    /// App entry point. Historical stores retain the old seed/migration path;
    /// clean stores import the catalogue without the owner's personal plan.
    static func bootstrapForLaunch(in context: ModelContext) throws -> AppSettings {
        let records = try context.fetch(FetchDescriptor<AppSettings>())
        if let settings = canonicalSettings(from: records), settings.publicOnboardingStage != nil {
            // A public profile that never saved its setup has no diagnostic
            // history, so it can safely join the flexible TMUA journey.
            if settings.publicOnboardingStage == .profile && settings.publicFlowVersion == nil {
                settings.publicFlowVersion = 2
            }
            try seedNewInstallation(in: context, existingSettings: settings)
            return settings
        }

        var hasLegacyData = !records.isEmpty
        if !hasLegacyData {
            let programmeCount = try context.fetchCount(FetchDescriptor<AdmissionsProgramme>())
            let attemptCount = try context.fetchCount(FetchDescriptor<QuestionAttempt>())
            let sessionCount = try context.fetchCount(FetchDescriptor<StudySession>())
            let resultCount = try context.fetchCount(FetchDescriptor<StudyResult>())
            let subjectCount = try context.fetchCount(FetchDescriptor<Subject>())
            hasLegacyData = [programmeCount, attemptCount, sessionCount, resultCount, subjectCount]
                .contains(where: { $0 > 0 })
        }
        if hasLegacyData {
            try seedIfNeeded(in: context)
        } else {
            try seedNewInstallation(in: context, existingSettings: nil)
        }
        guard let settings = canonicalSettings(from: try context.fetch(FetchDescriptor<AppSettings>())) else {
            throw BootstrapError.missingSettings
        }
        return settings
    }

    private static func seedNewInstallation(
        in context: ModelContext,
        existingSettings: AppSettings?
    ) throws {
        if existingSettings == nil {
            let settings = AppSettings(
                tmuaExamDate: .now,
                availability: AppSettings.publicDefaultAvailability,
                weeklyTargetMinutes: 600,
                usesLegacyProgrammeStartDate: false,
                appliedSeedVersion: currentSeedVersion
            )
            settings.publicOnboardingStage = .profile
            settings.publicFlowVersion = 2
            context.insert(settings)
        }
        if try context.fetch(FetchDescriptor<StudyTimerState>()).isEmpty {
            context.insert(StudyTimerState())
        }
        if context.hasChanges { try context.save() }
        try AdmissionsImportService.seedBundledManifestIfNeeded(
            in: context,
            importPersonalProgramme: false
        )
        try AdmissionsSolutionsImportService.seedBundledManifestIfNeeded(in: context)
    }

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

private enum BootstrapError: Error {
    case missingSettings
}
