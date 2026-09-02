import Foundation
import SwiftData

@MainActor
enum AdmissionsProgrammeMigrationService {
    static let supportedFormatVersions = 1...1

    static func seedBundledMigrationIfNeeded(in context: ModelContext) throws {
        let manifest = try AdmissionsProgrammeMigrationManifest.bundled()
        let programmes = try context.fetch(FetchDescriptor<AdmissionsProgramme>())
        guard let programme = programmes.first(where: {
            $0.externalProgrammeID == manifest.programmeID
        }) else {
            throw AdmissionsProgrammeMigrationError.unresolvedProgramme(manifest.programmeID)
        }
        if programme.importRevision == manifest.migrationRevision { return }
        try upsert(manifest, in: context)
    }

    static func upsert(
        _ manifest: AdmissionsProgrammeMigrationManifest,
        in context: ModelContext
    ) throws {
        do {
            try performUpsert(manifest, in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func performUpsert(
        _ manifest: AdmissionsProgrammeMigrationManifest,
        in context: ModelContext
    ) throws {
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsProgrammeMigrationError.unsupportedFormat(manifest.formatVersion)
        }
        let programmes = try context.fetch(FetchDescriptor<AdmissionsProgramme>())
        guard let programme = programmes.first(where: {
            $0.externalProgrammeID == manifest.programmeID
        }) else {
            throw AdmissionsProgrammeMigrationError.unresolvedProgramme(manifest.programmeID)
        }
        let questions = try context.fetch(FetchDescriptor<AdmissionsQuestion>())
        let questionsByID = Dictionary(uniqueKeysWithValues: questions.map {
            ($0.externalQuestionID, $0)
        })
        try validate(manifest, questionsByID: questionsByID)

        let programmeDays = try context.fetch(FetchDescriptor<ProgrammeDay>()).filter {
            $0.programme?.externalProgrammeID == manifest.programmeID
        }
        programmeDays.forEach { $0.isImportedActive = false }
        var daysByID = Dictionary(uniqueKeysWithValues: programmeDays.map {
            ($0.externalDayID, $0)
        })
        var daysByNumber: [Int: ProgrammeDay] = [:]
        for record in manifest.days {
            let externalID = "\(manifest.programmeID)-D\(String(format: "%02d", record.dayNumber))"
            let day = daysByID[externalID] ?? ProgrammeDay(
                externalDayID: externalID,
                dayNumber: record.dayNumber,
                focus: record.focus,
                studyBrief: record.studyBrief,
                allocatedQuestionCount: record.allocatedQuestionCount,
                expectedQuestionMinutes: record.expectedQuestionMinutes,
                expectedReviewMinutes: record.expectedReviewMinutes,
                programme: programme
            )
            if daysByID[externalID] == nil {
                context.insert(day)
                daysByID[externalID] = day
            }
            day.dayNumber = record.dayNumber
            day.focus = record.focus
            day.studyBrief = record.studyBrief
            day.allocatedQuestionCount = record.allocatedQuestionCount
            day.expectedQuestionMinutes = record.expectedQuestionMinutes
            day.expectedReviewMinutes = record.expectedReviewMinutes
            day.dailyTarget = record.dailyTarget
            day.notes = record.notes
            day.scheduleOffsetDays = record.scheduleOffsetDays
            day.earliestStartMinute = record.earliestStartMinute
            day.programme = programme
            day.isImportedActive = true
            daysByNumber[record.dayNumber] = day
        }

        let programmeAssignments = try context.fetch(FetchDescriptor<ProgrammeAssignment>()).filter {
            $0.programmeDay?.programme?.externalProgrammeID == manifest.programmeID
        }
        for assignment in programmeAssignments where assignment.attempts.isEmpty {
            assignment.isImportedActive = false
        }
        var assignmentsByID = Dictionary(uniqueKeysWithValues: programmeAssignments.map {
            ($0.externalAssignmentID, $0)
        })
        let manifestAssignmentIDs = Set(manifest.assignments.map(\.externalAssignmentID))

        for record in manifest.assignments {
            guard let question = questionsByID[record.questionID] else {
                throw AdmissionsProgrammeMigrationError.unresolvedQuestion(record.questionID)
            }
            guard let day = daysByNumber[record.dayNumber] else {
                throw AdmissionsProgrammeMigrationError.unresolvedDay(record.dayNumber)
            }
            let assignment = assignmentsByID[record.externalAssignmentID] ?? ProgrammeAssignment(
                externalAssignmentID: record.externalAssignmentID,
                displayOrder: record.displayOrder,
                programmeDay: day,
                question: question
            )
            if assignmentsByID[record.externalAssignmentID] == nil {
                context.insert(assignment)
                assignmentsByID[record.externalAssignmentID] = assignment
            }
            if !assignment.attempts.isEmpty {
                guard assignment.question?.externalQuestionID == record.questionID,
                      assignment.programmeDay?.dayNumber == record.dayNumber else {
                    throw AdmissionsProgrammeMigrationError.historicalAssignmentConflict(
                        record.externalAssignmentID
                    )
                }
            } else {
                assignment.block = record.block
                assignment.purpose = record.purpose
                assignment.suggestedTimeCapMinutes = record.suggestedTimeCapMinutes
                assignment.displayOrder = record.displayOrder
                assignment.programmeDay = day
                assignment.question = question
            }
            if !day.assignments.contains(where: {
                $0.externalAssignmentID == assignment.externalAssignmentID
            }) {
                day.assignments.append(assignment)
            }
            if !question.programmeAssignments.contains(where: {
                $0.externalAssignmentID == assignment.externalAssignmentID
            }) {
                question.programmeAssignments.append(assignment)
            }
            assignment.isImportedActive = true
        }

        // An assignment with user activity is historical data, even when a newer
        // static plan no longer selects it. Keep its identity and relationship.
        for assignment in programmeAssignments
        where !assignment.attempts.isEmpty
            && !manifestAssignmentIDs.contains(assignment.externalAssignmentID) {
            assignment.isImportedActive = true
        }

        let manifestCounts = Dictionary(grouping: manifest.assignments, by: \.dayNumber)
            .mapValues(\.count)
        let historicalExtras = Dictionary(grouping: programmeAssignments.filter {
            !$0.attempts.isEmpty && !manifestAssignmentIDs.contains($0.externalAssignmentID)
        }, by: { $0.programmeDay?.dayNumber ?? -1 }).mapValues(\.count)
        for (number, day) in daysByNumber {
            day.allocatedQuestionCount = (manifestCounts[number] ?? 0) + (historicalExtras[number] ?? 0)
        }

        programme.importRevision = manifest.migrationRevision
        try context.save()
    }

    private static func validate(
        _ manifest: AdmissionsProgrammeMigrationManifest,
        questionsByID: [String: AdmissionsQuestion]
    ) throws {
        guard supportedFormatVersions.contains(manifest.formatVersion) else {
            throw AdmissionsProgrammeMigrationError.unsupportedFormat(manifest.formatVersion)
        }
        guard manifest.preserveHistoryThroughDay == 3 else {
            throw AdmissionsProgrammeMigrationError.invalidDay(manifest.preserveHistoryThroughDay)
        }
        try requireUnique(manifest.days.map(\.dayNumber)) {
            AdmissionsProgrammeMigrationError.duplicateDay($0)
        }
        try requireUnique(manifest.assignments.map(\.externalAssignmentID)) {
            AdmissionsProgrammeMigrationError.duplicateAssignment($0)
        }
        guard Set(manifest.days.map(\.dayNumber)) == Set(1...30) else {
            throw AdmissionsProgrammeMigrationError.invalidDay(0)
        }
        let dayNumbers = Set(manifest.days.map(\.dayNumber))
        var offsets = Set<Int>()
        for day in manifest.days {
            guard let offset = day.scheduleOffsetDays,
                  offset >= 0,
                  offsets.insert(offset).inserted,
                  day.earliestStartMinute.map({ (0..<1_440).contains($0) }) ?? true else {
                throw AdmissionsProgrammeMigrationError.invalidDay(day.dayNumber)
            }
        }
        for assignment in manifest.assignments {
            guard dayNumbers.contains(assignment.dayNumber) else {
                throw AdmissionsProgrammeMigrationError.unresolvedDay(assignment.dayNumber)
            }
            guard let question = questionsByID[assignment.questionID] else {
                throw AdmissionsProgrammeMigrationError.unresolvedQuestion(assignment.questionID)
            }
            guard question.protection == .none else {
                throw AdmissionsProgrammeMigrationError.protectedQuestion(assignment.questionID)
            }
        }
    }

    private static func requireUnique<T: Hashable>(
        _ values: [T],
        error: (T) -> Error
    ) throws {
        var seen = Set<T>()
        for value in values where !seen.insert(value).inserted { throw error(value) }
    }
}
