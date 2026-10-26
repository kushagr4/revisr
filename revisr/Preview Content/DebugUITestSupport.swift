#if DEBUG
import Foundation
import SwiftData

/// Launch switches used only by the XCUITest target (`revisrUITests`).
/// Compiled out of Release builds.
///   --uitest-store <name>   open an isolated store, never the student's own
///   --uitest-reset          delete that isolated store first (a clean install)
///   --uitest-fixture-bank   use synthetic development fixtures instead of the bundled bank
enum DebugUITestSupport {
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func flag(_ name: String) -> Bool { ProcessInfo.processInfo.arguments.contains(name) }

    /// The isolated store for this UI test, or nil for a normal launch.
    static func isolatedStoreURL() throws -> URL? {
        guard let raw = value("--uitest-store") else { return nil }
        let name = String(raw.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(64))
        guard !name.isEmpty else { return nil }
        let directory = URL.applicationSupportDirectory.appending(path: "RevisrUITests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "uitest-\(name).store")
        if flag("--uitest-reset") {
            for suffix in ["", "-shm", "-wal"] {
                let file = URL(filePath: url.path(percentEncoded: false) + suffix)
                if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: file)
                }
            }
        }
        return url
    }

    @MainActor
    static func installFixtureBankIfRequested() {
        guard flag("--uitest-fixture-bank"), let syllabus = TMUASyllabus.load() else { return }
        let bank = TMUAContentBank(schemaVersion: 1, bankVersion: "uitest-fixtures-v1", distribution: .internal,
            taxonomyVersion: TMUASyllabus.currentVersion, contentPolicyVersion: TMUAContentPolicy.version,
            excludedItemCount: 0, items: fixtureItems(syllabus: syllabus))
        TMUAContentStore.install(TMUAContentContext(bank: bank, syllabus: syllabus,
                                                    allowsDevelopmentFixtures: true))
    }

    static let optionIDs = ["A", "B", "C", "D", "E"]

    /// Synthetic questions spread over every strand. Each stem states its own
    /// key so a UI test can answer deliberately right or wrong. Every fourth
    /// item uses long text and mathematical markup to exercise layout.
    static func fixtureItems(syllabus: TMUASyllabus, perPaper: Int = 40) -> [TMUAContentItem] {
        var result: [TMUAContentItem] = []
        for paper in [1, 2] {
            let topics = syllabus.topics.filter { paper == 1 ? $0.papers == [1, 2] : $0.papers.contains(2) }
                .sorted { paper == 2 ? ($0.papers.count, $0.key) < ($1.papers.count, $1.key) : $0.key < $1.key }
            let strands = topics.flatMap { topic in topic.strands.map { (topic.key, $0.key) } }
            for index in 0..<perPaper {
                let (topic, strand) = strands[index % strands.count]
                let id = "uix-p\(paper)-\(String(format: "%03d", index))"
                let key = optionIDs[(index * 3 + paper) % optionIDs.count]
                let rich = index % 4 == 3
                let stem = rich
                    ? "Synthetic fixture \(id). Suppose \\(f(x) = \\frac{x^2 + 1}{\\sqrt{x}}\\) for \\(x > 0\\), and consider a long statement that wraps over several lines so the layout of a long question can be checked. Fixture answer: \(key)."
                    : "Synthetic fixture \(id). Fixture answer: \(key)."
                let options = optionIDs.map { option in
                    TMUAOption(id: option, text: rich
                        ? "\\(x^{\(optionIDs.firstIndex(of: option)! + 2)} - 1\\) together with a deliberately long description of option \(option)"
                        : "Fixture option \(option)")
                }
                result.append(TMUAContentItem(
                    stableId: id, version: 1, paper: paper, category: .developmentFixture,
                    title: "Fixture \(paper)-\(index + 1)", stem: stem, options: options, correctOptionId: key,
                    solution: "Synthetic fixture solution: the stated answer is \(key).",
                    taxonomy: TMUATaxonomyMapping(topic: topic, strand: strand,
                        skill: paper == 2 && topic == "logic" ? "conditional-reasoning" : nil),
                    difficulty: [2, 3, 3, 4, 2][index % 5], estimatedMinutes: 4, source: nil,
                    rights: TMUAContentRights(copyrightHolder: "Synthetic fixture", licence: "fixture",
                        inAppUse: .notApplicable, redistribution: .notApplicable, commercialUse: .notApplicable,
                        answerKey: .notApplicable, solution: .notApplicable,
                        attribution: TMUAContentCategory.developmentFixture.attributionTitle),
                    review: TMUAContentReview(mathematical: .none, originality: .notApplicable,
                        publication: .notApproved, editorialStatus: "uitest-fixture")))
            }
        }
        return result
    }
}
#endif
