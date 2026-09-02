#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DebugTopicsScenarioService {
    static func applyIfRequested(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--topics-demo") || arguments.contains("--topics-detail") else { return }
        let marker = "Revisr topics demo"
        let topics = try context.fetch(FetchDescriptor<Topic>())
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        for session in sessions where session.notes == marker {
            session.notes = "Practised the main method and noted one step to revisit."
        }
        guard !topics.contains(where: { $0.name == "Generating Functions Practice" && $0.isCustom }) else {
            if context.hasChanges { try context.save() }
            return
        }
        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let namesAndSessions: [(String, Int, Int, StudyActivity)] = [
            ("Complex Numbers", -3, 90, .questions),
            ("Complex Numbers", -8, 60, .revision),
            ("Probability", -2, 75, .questions),
            ("Integration", -5, 50, .recall),
            ("Momentum", -1, 45, .review)
        ]
        for (name, dayOffset, minutes, activity) in namesAndSessions {
            guard let topic = topics.first(where: { $0.name == name }),
                  let module = topic.module,
                  let subject = module.subject else { continue }
            context.insert(
                StudySession(
                    date: calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today,
                    duration: TimeInterval(minutes * 60),
                    activity: activity,
                    notes: name == "Complex Numbers" ? "Practised loci and modulus arguments." : "",
                    subject: subject,
                    module: module,
                    topic: topic,
                    subjectNameSnapshot: subject.name,
                    moduleNameSnapshot: module.name,
                    topicNameSnapshot: topic.name
                )
            )
        }

        if let complex = topics.first(where: { $0.name == "Complex Numbers" && $0.module?.name == "CP1" }) {
            complex.notes = "Revisit loci arguments and geometric interpretations."
        }

        if let fs1 = try context.fetch(FetchDescriptor<StudyModule>()).first(where: { $0.name == "FS1" }),
           !fs1.topics.contains(where: { $0.name == "Generating Functions Practice" }) {
            context.insert(
                Topic(
                    name: "Generating Functions Practice",
                    status: .good,
                    needsReview: false,
                    displayOrder: (fs1.topics.map(\.displayOrder).max() ?? -1) + 1,
                    isCustom: true,
                    module: fs1
                )
            )
        }
        try context.save()
    }
}
#endif
