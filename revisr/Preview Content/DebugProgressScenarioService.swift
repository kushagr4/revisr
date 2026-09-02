#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DebugProgressScenarioService {
    static func applyIfRequested(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--progress-demo") else { return }
        let marker = "Revisr progress demo"
        guard try context.fetch(FetchDescriptor<StudyResult>()).allSatisfy({ $0.notes != marker }) else {
            return
        }

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        guard
            let tmua = subjects.first(where: { $0.name == "TMUA" }),
            let further = subjects.first(where: { $0.name == "Further Mathematics" }),
            let maths = subjects.first(where: { $0.name == "Mathematics" })
        else { return }

        let calendar = DateUtilities.appCalendar()
        let today = calendar.startOfDay(for: .now)
        let sessionSeeds: [(Subject, Int, Int)] = [
            (tmua, -5, 100), (further, -4, 65), (tmua, -3, 85),
            (maths, -2, 55), (further, -1, 70), (tmua, 0, 80)
        ]
        for (subject, offset, minutes) in sessionSeeds {
            context.insert(
                StudySession(
                    date: calendar.date(byAdding: .day, value: offset, to: today) ?? today,
                    duration: TimeInterval(minutes * 60),
                    activity: .revision,
                    notes: marker,
                    subject: subject,
                    subjectNameSnapshot: subject.name
                )
            )
        }

        for index in 0..<6 {
            let paper = index.isMultiple(of: 2) ? "Paper 1" : "Paper 2"
            context.insert(
                StudyResult(
                    date: calendar.date(byAdding: .day, value: -(6 - index), to: today) ?? today,
                    paperOrModuleLabel: paper,
                    rawScore: Double(11 + index),
                    maximumScore: 20,
                    scaledScore: 5.5 + Double(index) * 0.4,
                    notes: marker,
                    subject: tmua,
                    module: tmua.modules.first(where: { $0.name == paper }),
                    subjectNameSnapshot: tmua.name,
                    moduleNameSnapshot: paper
                )
            )
        }

        let aLevelSeeds: [(Subject, String, Double, Double, Int)] = [
            (maths, "Pure mock", 61, 75, -4),
            (further, "CP1 assessment", 53, 75, -2),
            (maths, "Statistics test", 42, 50, -1)
        ]
        for (subject, label, raw, maximum, offset) in aLevelSeeds {
            context.insert(
                StudyResult(
                    date: calendar.date(byAdding: .day, value: offset, to: today) ?? today,
                    paperOrModuleLabel: label,
                    rawScore: raw,
                    maximumScore: maximum,
                    notes: marker,
                    subject: subject,
                    subjectNameSnapshot: subject.name
                )
            )
        }
        try context.save()
    }
}
#endif
