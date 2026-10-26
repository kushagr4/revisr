#if DEBUG
import Foundation
import SwiftData

/// Launch-argument scenarios for screenshot QA of the flexible TMUA journey.
/// Applied only to a fresh public profile, using the bundled development bank.
///   --tmua-scenario session|results|programme
///   --tmua-length starter|quick|balanced|comprehensive
///   --tmua-tab today|plan|progress|topics|questions|settings
///   --tmua-step examDate|availability|length
///   --tmua-open session|overview|results|practice
@MainActor
enum DebugTMUAScenarioService {
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func applyIfRequested(in context: ModelContext) throws {
        guard let scenario = value("--tmua-scenario"),
              let settings = try context.fetch(FetchDescriptor<AppSettings>()).first,
              settings.publicFlowVersion == 2,
              try TMUADiagnosticService.load(settings: settings, in: context) == nil,
              let content = TMUAContentStore.context() else { return }
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -3, to: today) ?? today
        try PublicPreparationService.saveFlexibleTMUAProfile(
            examDate: calendar.date(byAdding: .day, value: 47, to: today) ?? today, weeklyMinutes: 300,
            availability: AppSettings.publicDefaultAvailability.map { day in
                var day = day
                day.isAvailable = day.weekday != .sunday
                return day
            }, sessionMinutes: nil, settings: settings, in: context)
        let length = value("--tmua-length").flatMap(TMUADiagnosticLength.init(rawValue:)) ?? .balanced
        let snapshot = try TMUADiagnosticService.create(settings: settings, length: length, content: content,
                                                        at: start, in: context)
        let sections = snapshot.sections.sorted { $0.paperRawValue < $1.paperRawValue }
        if scenario == "session" {
            let paperOne = sections[0]
            try TMUADiagnosticService.start(paperOne, in: snapshot, at: start, in: context)
            for item in snapshot.items(in: paperOne).prefix(3) {
                try TMUADiagnosticService.select(item.content?.options.last?.id, for: item, in: paperOne,
                                                 at: start.addingTimeInterval(400), in: context)
            }
            try TMUADiagnosticService.setFlag(true, for: snapshot.items(in: paperOne)[1], in: paperOne, in: context)
            try TMUADiagnosticService.move(paperOne, to: 3, count: snapshot.items(in: paperOne).count, in: context)
            try TMUADiagnosticService.pause(paperOne, at: start.addingTimeInterval(640), in: context)
            return
        }
        // Answer with a deterministic pattern: correct on most Paper 1 items,
        // weaker on logic, some skipped.
        for section in sections {
            try TMUADiagnosticService.start(section, in: snapshot, at: start, in: context)
            for item in snapshot.items(in: section) {
                guard let content = item.content else { continue }
                if item.ordinal % 7 == 6 { continue }
                let wrong = content.options.first { $0.id != content.correctOptionId }?.id
                let missed = item.topicKey == "logic" || item.ordinal % 3 == 2
                try TMUADiagnosticService.select(missed ? wrong : content.correctOptionId, for: item, in: section,
                                                 at: start.addingTimeInterval(300), in: context)
            }
            try TMUADiagnosticService.submit(section, in: snapshot,
                at: start.addingTimeInterval(Double(section.paperRawValue) * 2_400), in: context)
        }
        guard scenario == "programme" else { return }
        try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, today: start, in: context)
        let tasks = try TMUAProgrammeService.tasks(settings: settings, in: context)
            .filter { $0.isActive && $0.questionID != nil && $0.scheduledDate < today }
        for (offset, task) in tasks.prefix(5).enumerated() {
            guard let item = content.eligibleItems.first(where: { $0.stableId == task.questionID }) else { continue }
            let choice = offset % 2 == 0 ? item.correctOptionId : (item.options.first { $0.id != item.correctOptionId }?.id ?? "A")
            try TMUAProgrammeService.recordPractice(item: item, selectedOptionID: choice, seconds: 300, task: task,
                                                    settings: settings, at: task.scheduledDate.addingTimeInterval(64_800),
                                                    in: context)
        }
    }
}
#endif
